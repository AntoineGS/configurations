import QtQuick
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

SharedService {
  id: root

  property bool resizePending: false
  property string actionError: ""
  property int actionGeneration: 0
  property int actionFinalizedGeneration: 0
  property int actionReconciliationGeneration: 0
  property bool reconciliationReleasePending: false
  property bool actionReconciliationStarted: false
  property string actionExecutable: "desktop-hardware-action"

  property alias virshExecutable: monitor.virshExecutable
  property alias stateHelperExecutable: monitor.stateHelperExecutable
  property alias capabilityProbeInterval: monitor.capabilityProbeInterval
  property alias startupReconciliationInterval: monitor.startupReconciliationInterval
  property alias steadyReconciliationInterval: monitor.steadyReconciliationInterval
  property alias stabilityInterval: monitor.stabilityInterval
  property alias utilizationInterval: monitor.utilizationInterval
  property alias processStartGraceInterval: monitor.processStartGraceInterval

  readonly property var state: monitor.state
  readonly property var host: shell ? shell.serviceFor("desktop.host-metrics") : null
  readonly property var hostCpuState: host ? host.cpuState : Model.emptyHostStat()
  readonly property var hostMemoryState: host ? host.memoryState : Model.emptyHostStat()
  readonly property bool watcherRunning: monitor.watcherRunning
  readonly property bool reconciliationRunning: monitor.reconciliationRunning
  readonly property var remoteSummary: ({
    available: root.hostMemoryState.available || root.hostCpuState.available || root.state.visible,
    hostMemory: root.hostMemoryState,
    hostCpu: root.hostCpuState,
    runningVmCount: root.state.visible ? 1 : 0,
    vm: {
      visible: root.state.visible,
      name: root.state.name,
      stale: root.state.stale,
      error: root.state.error,
      cpuPercent: root.state.cpuPercent,
      memoryPercent: root.state.memoryPercent,
      showMemoryUsage: root.state.showMemoryUsage
    }
  })

  operationPending: resizePending

  ServiceConsumer {
    id: hostConsumer
    service: root.host
    active: root.collecting
  }

  onHostChanged: hostConsumer.service = root.host

  VmMonitor {
    id: monitor
    collecting: root.collecting
    popupOpen: root.detailed
  }

  function requestMemory(gib) {
    var requested = Number(gib)
    if (!isFinite(requested)) return false
    var value = Math.round(requested)
    if (!root.collecting || resizePending || actionProcess.running || !monitor.capabilityAvailable
        || !monitor.watcherRunning || !monitor.lastReconciliationFresh
        || monitor.lastReconciliationWatcherGeneration !== monitor.monitorState.watcherGeneration
        || !root.state.canResize
        || value < Model.minimumGiB() || value > Model.maximumGiB(root.state)) return false

    resizePending = true
    actionError = ""
    actionGeneration++
    actionProcess.command = [root.actionExecutable, "vm", "set-memory", String(value)]
    actionProcess.running = true
    return true
  }

  function refreshNow() {
    monitor.refreshNow()
  }

  function releaseResizeAfterReconciliation() {
    var monitorState = monitor.monitorState
    if (!reconciliationReleasePending) return
    if (!actionReconciliationStarted && monitorState.reconciliationGeneration >= actionReconciliationGeneration)
      actionReconciliationStarted = true
    if (!actionReconciliationStarted || !monitor.capabilityAvailable || monitor.reconciliationRunning
        || monitorState.reconciliationQueued
        || monitorState.reconciliationFinishedGeneration < actionReconciliationGeneration
        || !monitor.lastReconciliationFresh
        || monitor.lastReconciliationWatcherGeneration !== monitorState.watcherGeneration)
      return
    reconciliationReleasePending = false
    actionReconciliationStarted = false
    resizePending = false
  }

  function finishMemoryAction(exitCode, failedStart) {
    if (actionFinalizedGeneration === actionGeneration) return
    actionFinalizedGeneration = actionGeneration
    actionStartCheckTimer.stop()
    if (failedStart || Number(exitCode) !== 0) {
      resizePending = false
      reconciliationReleasePending = false
      actionReconciliationStarted = false
      actionError = failedStart ? "VM memory action failed to start" : String(actionStderr.text || "").trim()
      return
    }

    actionError = ""
    reconciliationReleasePending = true
    actionReconciliationGeneration = monitor.monitorState.reconciliationGeneration + 1
    actionReconciliationStarted = false
    monitor.refreshNow()
    actionReconciliationStarted = monitor.monitorState.reconciliationGeneration >= actionReconciliationGeneration
    releaseResizeAfterReconciliation()
  }

  Connections {
    target: monitor
    function onReconciliationRunningChanged() { root.releaseResizeAfterReconciliation() }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
    }
    onExited: function(exitCode) { root.finishMemoryAction(exitCode, false) }
    onStarted: actionStartCheckTimer.stop()
    onRunningChanged: {
      if (!actionProcess.running && actionGeneration > actionFinalizedGeneration) {
        actionStartCheckTimer.generation = actionGeneration
        actionStartCheckTimer.start()
      }
    }
  }

  Timer {
    id: actionStartCheckTimer
    property int generation: 0
    interval: 100
    repeat: false
    onTriggered: if (!actionProcess.running && generation === root.actionGeneration)
      root.finishMemoryAction(1, true)
  }
}
