import QtQuick
import Quickshell.Io
import qs.Commons

SharedService {
  id: root

  property string batteryStatusOutput: ""
  property string actionError: ""
  property string actionExecutable: "desktop-hardware-action"
  property string batteryStatusExecutable: "battery-status"
  property var batteryAvailableOverride: null
  property int processStartGraceInterval: 100
  property int collectionGeneration: 0
  property int batteryGeneration: 0
  property int batteryDemandGeneration: 0
  property int actionGeneration: 0
  property int actionFinalizedGeneration: 0
  property var batteryWorker: null
  property var actionWorker: null

  readonly property bool batteryAvailable: root.batteryAvailableOverride === null
    ? PowerState.batteryAvailable : root.batteryAvailableOverride === true

  function refreshBatteryStatus() {
    if (!root.collecting || !root.detailed || !root.batteryAvailable || root.batteryWorker) return false
    root.batteryGeneration++
    var worker = batteryComponent.createObject(root, {
      generation: root.batteryGeneration,
      demandGeneration: root.batteryDemandGeneration,
      collectionGeneration: root.collectionGeneration
    })
    if (!worker) return false
    root.batteryWorker = worker
    worker.running = true
    return true
  }

  function handleBatteryRunningChanged(worker) {
    if (worker.running || worker !== root.batteryWorker || !root.collecting
        || worker.generation !== root.batteryGeneration
        || worker.demandGeneration !== root.batteryDemandGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    batteryStartCheck.worker = worker
    batteryStartCheck.generation = worker.generation
    batteryStartCheck.demandGeneration = worker.demandGeneration
    batteryStartCheck.collectionGeneration = worker.collectionGeneration
    batteryStartCheck.start()
  }

  function finishBatteryStatus(worker, exitCode, failedStart) {
    if (worker !== null && worker !== root.batteryWorker) return
    if (worker && (worker.generation !== root.batteryGeneration
        || worker.demandGeneration !== root.batteryDemandGeneration
        || worker.collectionGeneration !== root.collectionGeneration)) return
    batteryStartCheck.stop()
    batteryStartCheck.worker = null
    if (worker && root.batteryWorker === worker) root.batteryWorker = null
    if (worker && !failedStart && Number(exitCode) === 0 && root.detailed) {
      var output = String(worker.stdoutOutput.text || "").trim()
      if (output !== "") root.batteryStatusOutput = output
    }
    root.destroyWorker(worker)
  }

  function stopBatteryStatus() {
    root.batteryDemandGeneration++
    batteryStartCheck.stop()
    batteryStartCheck.worker = null
    var oldWorker = root.batteryWorker
    root.batteryWorker = null
    root.destroyWorker(oldWorker)
  }

  function setProfile(profileName) {
    var name = String(profileName || "")
    if (name === "" || root.actionWorker) return false
    root.actionError = ""
    root.actionGeneration++
    root.operationPending = true
    var worker = actionComponent.createObject(root, {
      generation: root.actionGeneration,
      collectionGeneration: root.collectionGeneration
    })
    if (!worker) {
      root.finishAction(null, 1, true)
      return true
    }
    worker.profileName = name
    worker.command = [root.actionExecutable, "power", "set-profile", name]
    root.actionWorker = worker
    worker.running = true
    return true
  }

  function handleActionRunningChanged(worker) {
    if (worker.running || worker !== root.actionWorker || !root.collecting
        || worker.generation !== root.actionGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    actionStartCheck.worker = worker
    actionStartCheck.generation = worker.generation
    actionStartCheck.collectionGeneration = worker.collectionGeneration
    actionStartCheck.start()
  }

  function finishAction(worker, exitCode, failedStart) {
    if (worker !== null && worker !== root.actionWorker) return
    if (worker && (worker.generation !== root.actionGeneration
        || worker.collectionGeneration !== root.collectionGeneration)) return
    if (root.actionFinalizedGeneration === root.actionGeneration) return

    root.actionFinalizedGeneration = root.actionGeneration
    actionStartCheck.stop()
    actionStartCheck.worker = null
    if (worker && root.actionWorker === worker) root.actionWorker = null
    var ok = !failedStart && Number(exitCode) === 0
    if (ok) {
      root.actionError = ""
      PowerState.reconcile()
    } else {
      root.actionError = failedStart
        ? "Power profile action failed to start"
        : String(worker && worker.stderrOutput.text || "").trim() || "Power profile action failed"
      PowerState.markProfileActionFailed(root.actionError)
    }
    root.destroyWorker(worker)
    root.operationPending = false
  }

  function destroyWorker(worker) {
    if (!worker) return
    worker.running = false
    var staleWorker = worker
    Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
  }

  function stopCollection() {
    root.collectionGeneration++
    root.stopBatteryStatus()
    actionStartCheck.stop()
    actionStartCheck.worker = null
    var oldWorker = root.actionWorker
    root.actionWorker = null
    root.destroyWorker(oldWorker)
    root.operationPending = false
  }

  onCollectingChanged: {
    if (!root.collecting) {
      root.stopCollection()
      return
    }
    root.refreshBatteryStatus()
  }
  onDetailedChanged: {
    if (root.detailed) root.refreshBatteryStatus()
    else root.stopBatteryStatus()
  }
  onBatteryAvailableChanged: if (root.batteryAvailable) root.refreshBatteryStatus()

  Timer {
    interval: 5000
    repeat: true
    running: root.collecting && root.detailed && root.batteryAvailable
    onTriggered: root.refreshBatteryStatus()
  }

  Timer {
    id: batteryStartCheck
    property int generation: 0
    property int demandGeneration: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.batteryWorker
          && worker.generation === generation && worker.demandGeneration === demandGeneration
          && worker.collectionGeneration === collectionGeneration && !worker.running)
        root.finishBatteryStatus(worker, 1, true)
    }
  }

  Timer {
    id: actionStartCheck
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.actionWorker
          && worker.generation === generation && worker.collectionGeneration === collectionGeneration
          && !worker.running)
        root.finishAction(worker, 1, true)
    }
  }

  Component {
    id: batteryComponent
    Process {
      id: process
      property int generation: 0
      property int demandGeneration: 0
      property int collectionGeneration: 0
      command: [root.batteryStatusExecutable]
      stdout: StdioCollector {
        id: stdoutCollector
        waitForEnd: true
      }
      stderr: StdioCollector { waitForEnd: true }
      property alias stdoutOutput: stdoutCollector
      onExited: function(exitCode) { root.finishBatteryStatus(process, Number(exitCode), false) }
      onRunningChanged: root.handleBatteryRunningChanged(process)
    }
  }

  Component {
    id: actionComponent
    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      property string profileName: ""
      command: []
      stdout: StdioCollector { waitForEnd: true }
      stderr: StdioCollector {
        id: stderrCollector
        waitForEnd: true
      }
      property alias stderrOutput: stderrCollector
      onExited: function(exitCode) { root.finishAction(process, Number(exitCode), false) }
      onRunningChanged: root.handleActionRunningChanged(process)
    }
  }

  Component.onDestruction: {
    root.stopCollection()
  }
}
