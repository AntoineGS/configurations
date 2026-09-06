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
  property bool popupOpen: false
  property int closedUtilizationInterval: 15000
  property int openUtilizationInterval: 5000
  property int utilizationInterval: popupOpen ? openUtilizationInterval : closedUtilizationInterval
  property int processStartGraceInterval: 100
  property bool collecting: false
  property int collectionGeneration: 0
  property int activeCollectionGeneration: 0
  property var virshProbeProcess: null
  property var watcherProcess: null
  property var stateProcess: null
  property bool lastReconciliationFresh: false
  property int lastReconciliationWatcherGeneration: 0
  property bool reconciliationActive: false
  readonly property bool capabilityAvailable: monitorState.capabilityAvailable
  readonly property bool watcherRunning: !!watcherProcess && watcherProcess.running
  readonly property bool utilizationRunning: utilizationTimer.running
  readonly property int backoffSeconds: monitorState.backoffSeconds
  readonly property bool reconciliationRunning: reconciliationActive

  onPopupOpenChanged: {
    if (Model.popupOpenRefreshRequested(!popupOpen, popupOpen)) root.refreshNow()
  }

  onCollectingChanged: {
    if (!collecting) {
      collectionGeneration += 1
      activeCollectionGeneration = 0
      retryTimer.stop()
      startupTimer.stop()
      utilizationTimer.stop()
      capabilityProbeTimer.stop()
      watcherStabilityTimer.stop()
      stateStartCheckTimer.stop()
      stateStartCheckTimer.worker = null
      monitorState = Model.vmMonitorState()
      reconciliationActive = false
      lastReconciliationFresh = false
      lastReconciliationWatcherGeneration = 0
      var oldProbe = virshProbeProcess
      virshProbeProcess = null
      destroyWorker(oldProbe, true)
      var oldWatcher = watcherProcess
      watcherProcess = null
      destroyWorker(oldWatcher, true)
      var oldState = stateProcess
      stateProcess = null
      destroyWorker(oldState, true)
      return
    }

    collectionGeneration += 1
    activeCollectionGeneration = collectionGeneration
    monitorState = Model.vmMonitorState()
    reconciliationActive = false
    lastReconciliationFresh = false
    lastReconciliationWatcherGeneration = 0
    Qt.callLater(function() {
      if (root.collecting && root.activeCollectionGeneration === root.collectionGeneration)
        root.probeNow()
    })
  }

  function transition(event, argument) {
    var next = Model.vmMonitorTransition(monitorState, event, argument)
    monitorState = next.state
    reconciliationActive = next.state.reconciliationRunning
    if (event === "capability-found" || event === "capability-missing"
        || event === "watcher-start" || event === "watcher-stopped") {
      lastReconciliationFresh = false
      lastReconciliationWatcherGeneration = 0
    }
    return next
  }

  function refreshNow() {
    if (!collecting) return
    if (!capabilityAvailable) {
      probeNow()
      return
    }
    startReconciliation(transition("reconcile-request", monitorState.watcherGeneration))
  }

  function destroyWorker(worker, defer) {
    if (!worker) return
    worker.running = false
    if (defer) {
      var staleWorker = worker
      Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
    } else worker.destroy()
  }

  function probeNow() {
    if (!collecting || virshProbeProcess) return
    virshProbeProcess = probeComponent.createObject(root, {
      collectionGeneration: activeCollectionGeneration
    })
    if (virshProbeProcess) virshProbeProcess.running = true
  }

  function startReconciliation(next) {
    if (!collecting) return
    if (!next.startReconciliation || stateProcess) return
    stateProcess = stateComponent.createObject(root, {
      collectionGeneration: activeCollectionGeneration,
      reconciliationGeneration: monitorState.reconciliationGeneration,
      watcherGeneration: monitorState.reconciliationWatcherGeneration
    })
    if (stateProcess) stateProcess.running = true
  }

  function applyState(raw, processError, generation, worker) {
    if (!collecting || generation !== undefined && generation !== activeCollectionGeneration) return
    if (worker !== undefined && worker !== stateProcess) return
    var nextState = Model.stateFromRaw(root.state, raw, processError)
    root.state = nextState
    transition("state-applied", nextState.confirmedRunning === true)
  }

  function startWatcher() {
    if (!collecting || !capabilityAvailable || watcherProcess) return
    var next = transition("watcher-start")
    if (next.startWatcher) createWatcher(next.generation)
  }

  function startInitialSnapshot() {
    if (!collecting) return
    var next = transition("capability-found")
    if (next.startWatcher) createWatcher(monitorState.watcherGeneration)
    startReconciliation(next)
  }

  function createWatcher(generation) {
    if (!collecting || !capabilityAvailable || watcherProcess) return
    watcherProcess = watcherComponent.createObject(root, {
      collectionGeneration: activeCollectionGeneration,
      watcherGeneration: generation,
      owner: root
    })
    if (watcherProcess) watcherProcess.running = true
  }

  function handleProbeExit(worker, code) {
    if (worker !== virshProbeProcess || !collecting
        || worker.collectionGeneration !== activeCollectionGeneration) return
    virshProbeProcess = null
    destroyWorker(worker)
    if (Number(code) === 0) {
      capabilityProbeTimer.stop()
      startInitialSnapshot()
    } else {
      transition("capability-missing")
    }
  }

  function handleWatcherStopped(worker) {
    if (worker !== watcherProcess || !collecting
        || worker.collectionGeneration !== activeCollectionGeneration || worker.running) return
    var generation = worker.watcherGeneration
    if (!root.capabilityAvailable || generation !== monitorState.watcherGeneration) {
      watcherProcess = null
      destroyWorker(worker)
      return
    }
    var wasStarted = monitorState.watcherStartedGeneration === generation
    var next = transition("watcher-stopped", generation)
    watcherProcess = null
    destroyWorker(worker)
    if (!wasStarted) {
      transition("capability-missing")
      capabilityProbeTimer.start()
    } else if (next.retryWatcher) retryTimer.start()
  }

  function handleWatcherExit(worker) {
    handleWatcherStopped(worker)
  }

  function handleWatcherLine(worker) {
    if (worker === watcherProcess && collecting
        && worker.collectionGeneration === activeCollectionGeneration) root.refreshNow()
  }

  function handleStateExit(worker, code) {
    if (worker !== stateProcess || !collecting
        || worker.collectionGeneration !== activeCollectionGeneration) return
    stateStartCheckTimer.stop()
    stateStartCheckTimer.worker = null
    var processError = ""
    if (Number(code) !== 0) {
      processError = String(worker.stderrOutput.text || "").trim()
      if (!processError) processError = "desktop-hardware-state exited with code " + String(code)
    }
    var generation = worker.reconciliationGeneration
    var watcherGeneration = worker.watcherGeneration
    root.applyState(worker.stdoutOutput.text || "", processError, worker.collectionGeneration, worker)
    lastReconciliationFresh = Number(code) === 0 && !root.state.stale && !root.state.malformed
    lastReconciliationWatcherGeneration = lastReconciliationFresh ? watcherGeneration : 0
    stateProcess = null
    destroyWorker(worker)
    var next = root.transition("reconcile-finished", {
      generation: generation,
      watcherGeneration: watcherGeneration,
      fresh: Number(code) === 0 && !root.state.stale && !root.state.malformed,
      stable: root.monitorState.stableGeneration === watcherGeneration
        && root.watcherProcess && root.watcherProcess.running
    })
    root.startReconciliation(next)
  }

  function handleStateRunningChanged(worker) {
    if (worker.running || worker !== stateProcess || !root.collecting
        || worker.collectionGeneration !== root.activeCollectionGeneration) return
    stateStartCheckTimer.generation = worker.reconciliationGeneration
    stateStartCheckTimer.collectionGeneration = worker.collectionGeneration
    stateStartCheckTimer.worker = worker
    stateStartCheckTimer.start()
  }

  Component {
    id: probeComponent

    Process {
      id: process
      property int collectionGeneration: 0
      command: ["sh", "-c", "command -v -- \"$1\" >/dev/null 2>&1", "vm-virsh-probe", root.virshExecutable]
      onExited: function(code) { root.handleProbeExit(process, code) }
    }
  }

  Component {
    id: watcherComponent

    Process {
      id: process
      property var owner: null
      property int collectionGeneration: 0
      property int watcherGeneration: 0
      command: [owner.virshExecutable, "--connect", "qemu:///system", "event", "--all", "--loop"]
      stdout: SplitParser {
        splitMarker: "\n"
        onRead: process.owner.handleWatcherLine(process)
      }
      stderr: StdioCollector { waitForEnd: true }
      onExited: process.owner.handleWatcherExit(process)
      onRunningChanged: if (!process.running) process.owner.handleWatcherStopped(process)
      onStarted: {
        if (process.owner.collecting && process === process.owner.watcherProcess
            && process.collectionGeneration === process.owner.activeCollectionGeneration)
          process.owner.transition("watcher-started", process.watcherGeneration)
      }
    }
  }

  Component {
    id: stateComponent

    Process {
      id: process
      property int collectionGeneration: 0
      property int reconciliationGeneration: 0
      property int watcherGeneration: 0
      command: [root.stateHelperExecutable, "vm"]
      stdout: StdioCollector {
        id: stdoutCollector
        waitForEnd: true
      }
      stderr: StdioCollector {
        id: stderrCollector
        waitForEnd: true
      }
      property alias stdoutOutput: stdoutCollector
      property alias stderrOutput: stderrCollector
      onExited: function(code) { root.handleStateExit(process, code) }
      onRunningChanged: root.handleStateRunningChanged(process)
    }
  }

  Timer {
    id: startupTimer
    interval: root.monitorState.startupPhase
      ? root.startupReconciliationInterval : root.steadyReconciliationInterval
    repeat: true
    running: root.collecting && root.capabilityAvailable
    triggeredOnStart: false
    onTriggered: if (root.collecting) {
      root.startReconciliation(root.transition("schedule-tick"))
    }
  }

  Timer {
    id: utilizationTimer
    interval: root.utilizationInterval
    repeat: true
    running: root.collecting && root.monitorState.runningConfirmed === true
    triggeredOnStart: false
    onTriggered: if (root.collecting) root.refreshNow()
  }

  Timer {
    id: watcherStabilityTimer
    interval: root.stabilityInterval
    repeat: false
    running: root.collecting && root.monitorState.stabilityGeneration === root.monitorState.watcherGeneration
      && root.monitorState.stabilityGeneration !== 0
    onTriggered: if (root.collecting) root.transition("watcher-stable", {
      generation: root.monitorState.watcherGeneration,
      running: !!root.watcherProcess && root.watcherProcess.running
    })
  }

  Timer {
    id: stateStartCheckTimer
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && collectionGeneration === root.activeCollectionGeneration
          && worker && worker === root.stateProcess && !worker.running) {
        root.lastReconciliationFresh = false
        root.lastReconciliationWatcherGeneration = 0
        var next = root.transition("reconcile-process-stopped", { generation: generation })
        root.stateProcess = null
        root.destroyWorker(worker)
        worker = null
        root.startReconciliation(next)
      }
    }
  }

  Timer {
    id: capabilityProbeTimer
    interval: root.capabilityProbeInterval
    repeat: true
    running: root.collecting && !root.capabilityAvailable
    triggeredOnStart: false
    onTriggered: if (root.collecting) root.probeNow()
  }

  Timer {
    id: retryTimer
    interval: Math.max(1, root.backoffSeconds) * 1000
    repeat: false
    onTriggered: {
      if (root.collecting && root.capabilityAvailable) {
        root.startWatcher()
        root.refreshNow()
      }
    }
  }

  Component.onCompleted: if (collecting) probeNow()
  Component.onDestruction: {
    retryTimer.stop()
    startupTimer.stop()
    utilizationTimer.stop()
    capabilityProbeTimer.stop()
    watcherStabilityTimer.stop()
    stateStartCheckTimer.stop()
    var oldProbe = virshProbeProcess
    virshProbeProcess = null
    destroyWorker(oldProbe)
    var oldWatcher = watcherProcess
    watcherProcess = null
    destroyWorker(oldWatcher)
    var oldState = stateProcess
    stateProcess = null
    destroyWorker(oldState)
  }
}
