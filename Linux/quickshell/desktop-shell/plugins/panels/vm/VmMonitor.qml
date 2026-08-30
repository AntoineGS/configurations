import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var state: Model.emptyState()
  property var monitorState: Model.vmMonitorState()
  property string virshExecutable: "virsh"
  property string stateHelperExecutable: "desktop-hardware-state"
  property int capabilityProbeInterval: 60000
  property int startupReconciliationInterval: 45000
  property int steadyReconciliationInterval: 60000
  property int stabilityInterval: 10000
  property int utilizationInterval: 5000
  property int processStartGraceInterval: 100
  readonly property bool capabilityAvailable: monitorState.capabilityAvailable
  readonly property bool watcherRunning: watcherProcess.running
  readonly property bool utilizationRunning: utilizationTimer.running
  readonly property int backoffSeconds: monitorState.backoffSeconds
  readonly property bool reconciliationRunning: monitorState.reconciliationRunning

  function transition(event, argument) {
    var next = Model.vmMonitorTransition(monitorState, event, argument)
    monitorState = next.state
    return next
  }

  function refreshNow() {
    if (!capabilityAvailable) return
    startReconciliation(transition("reconcile-request", monitorState.watcherGeneration))
  }

  function probeNow() {
    if (!virshProbeProcess.running) virshProbeProcess.running = true
  }

  function startReconciliation(next) {
    if (next.startReconciliation) {
      stateProcess.running = true
    }
  }

  function applyState(raw, processError) {
    var nextState = Model.stateFromRaw(root.state, raw, processError)
    root.state = nextState
    transition("state-applied", nextState.confirmedRunning === true)
  }

  function startWatcher() {
    if (!capabilityAvailable || watcherProcess.running) return
    var next = transition("watcher-start")
    if (!next.startWatcher) return
    watcherProcess.running = true
  }

  function startInitialSnapshot() {
    var next = transition("capability-found")
    if (next.startWatcher) {
      watcherProcess.running = true
    }
    startReconciliation(next)
  }

  function handleWatcherStopped(generation) {
    if (!root.capabilityAvailable || watcherProcess.running) return
    if (generation !== monitorState.watcherGeneration) return
    var wasStarted = monitorState.watcherStartedGeneration === generation
    var next = transition("watcher-stopped", generation)
    if (!wasStarted) {
      transition("capability-missing")
      capabilityProbeTimer.start()
    } else if (next.retryWatcher) retryTimer.start()
  }

  function handleWatcherExit(code) {
    root.handleWatcherStopped(root.monitorState.watcherGeneration)
  }

  Process {
    id: virshProbeProcess
    command: ["sh", "-c", "command -v -- \"$1\" >/dev/null 2>&1", "vm-virsh-probe", root.virshExecutable]
    onExited: function(code) {
      if (Number(code) === 0) {
        capabilityProbeTimer.stop()
        root.startInitialSnapshot()
      } else {
        root.transition("capability-missing")
      }
    }
  }

  Process {
    id: watcherProcess
    command: [root.virshExecutable, "--connect", "qemu:///system", "event", "--all", "--loop"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: root.refreshNow()
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) { root.handleWatcherExit(code) }
    onRunningChanged: {
      if (!watcherProcess.running) {
        var generation = root.monitorState.watcherGeneration
        Qt.callLater(function() { root.handleWatcherStopped(generation) })
      }
    }
    onStarted: {
      root.transition("watcher-started", root.monitorState.watcherGeneration)
    }
  }

  Process {
    id: stateProcess
    command: [root.stateHelperExecutable, "vm"]
    stdout: StdioCollector {
      id: stateStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: stateStderr
      waitForEnd: true
    }
    onExited: function(code) {
      stateStartCheckTimer.stop()
      var processError = ""
      if (Number(code) !== 0) {
        processError = String(stateStderr.text || "").trim()
        if (!processError) processError = "desktop-hardware-state exited with code " + String(code)
      }
      var generation = root.monitorState.reconciliationGeneration
      root.applyState(stateStdout.text || "", processError)
      var next = root.transition("reconcile-finished", {
        generation: generation,
        watcherGeneration: root.monitorState.reconciliationWatcherGeneration,
        fresh: Number(code) === 0 && !root.state.stale && !root.state.malformed,
        stable: root.monitorState.stableGeneration === root.monitorState.reconciliationWatcherGeneration
          && watcherProcess.running
      })
      root.startReconciliation(next)
    }
    onRunningChanged: {
      if (!stateProcess.running) {
        stateStartCheckTimer.generation = root.monitorState.reconciliationGeneration
        stateStartCheckTimer.start()
      }
    }
  }

  Timer {
    id: startupTimer
    interval: root.monitorState.startupPhase
      ? root.startupReconciliationInterval : root.steadyReconciliationInterval
    repeat: true
    running: root.capabilityAvailable
    triggeredOnStart: false
    onTriggered: {
      root.startReconciliation(root.transition("schedule-tick"))
    }
  }

  Timer {
    id: utilizationTimer
    interval: root.utilizationInterval
    repeat: true
    running: root.monitorState.runningConfirmed === true
    triggeredOnStart: false
    onTriggered: root.refreshNow()
  }

  Timer {
    id: watcherStabilityTimer
    interval: root.stabilityInterval
    repeat: false
    running: root.monitorState.stabilityGeneration === root.monitorState.watcherGeneration
      && root.monitorState.stabilityGeneration !== 0
    onTriggered: root.transition("watcher-stable", {
      generation: root.monitorState.watcherGeneration,
      running: watcherProcess.running
    })
  }

  Timer {
    id: stateStartCheckTimer
    property int generation: 0
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (!stateProcess.running) {
        var next = root.transition("reconcile-process-stopped", { generation: generation })
        root.startReconciliation(next)
      }
    }
  }

  Timer {
    id: capabilityProbeTimer
    interval: root.capabilityProbeInterval
    repeat: true
    running: !root.capabilityAvailable
    triggeredOnStart: false
    onTriggered: if (!virshProbeProcess.running) virshProbeProcess.running = true
  }

  Timer {
    id: retryTimer
    interval: Math.max(1, root.backoffSeconds) * 1000
    repeat: false
    onTriggered: {
      if (root.capabilityAvailable) {
        root.startWatcher()
        root.refreshNow()
      }
    }
  }

  Component.onCompleted: virshProbeProcess.running = true
  Component.onDestruction: {
    retryTimer.stop()
    startupTimer.stop()
    utilizationTimer.stop()
    capabilityProbeTimer.stop()
    watcherStabilityTimer.stop()
    stateStartCheckTimer.stop()
  }
}
