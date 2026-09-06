import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

SharedService {
  id: root

  property var hardwareState: ({ available: false, stale: false, data: {} })
  property int brightnessPercent: 1
  property int lastConfirmedBrightnessPercent: 1
  property string hostname: ""
  property string actionName: ""
  property var operationState: Model.monitorOperationState()
  property int collectionGeneration: 0
  property int reconciliationGeneration: 0
  property int reconciliationFinalizedGeneration: 0
  property int actionGeneration: 0
  property int actionFinalizedGeneration: 0
  property bool postActionPending: false
  property bool postActionReconciliationPending: false
  property bool collectorLoaded: true
  property string stateExecutable: "desktop-hardware-state"
  property string actionExecutable: "desktop-hardware-action"
  property string hostnameExecutable: "hostname"
  property int processStartGraceInterval: 100
  property var stateWorker: null
  property var actionWorker: null

  readonly property var stateData: hardwareState && hardwareState.data ? hardwareState.data : ({})
  readonly property var brightness: stateData.brightness || ({ available: false, percent: 1 })
  readonly property var keyboardBrightness: stateData.keyboardBrightness || ({ available: false, percent: 0 })

  function syncOperationPending() {
    var state = root.operationState
    root.operationPending = root.postActionPending || !!state.actionRunning
      || (Array.isArray(state.actionQueue) && state.actionQueue.length > 0)
  }

  function applyState(raw) {
    var parsed = Model.parseState(raw)
    if (!parsed) {
      root.brightnessPercent = root.lastConfirmedBrightnessPercent
      root.hardwareState = {
        available: false,
        stale: true,
        error: "Invalid hardware state",
        data: root.hardwareState && root.hardwareState.data ? root.hardwareState.data : {}
      }
      return
    }

    var previousData = root.hardwareState && root.hardwareState.data ? root.hardwareState.data : {}
    var reconciled = Model.brightnessState({
      brightnessPercent: root.brightnessPercent,
      lastConfirmedBrightnessPercent: root.lastConfirmedBrightnessPercent,
      brightness: previousData.brightness,
      keyboardBrightness: previousData.keyboardBrightness
    }, parsed.stale === true ? null : parsed.data.brightness,
    parsed.stale === true ? null : parsed.data.keyboardBrightness)
    root.brightnessPercent = reconciled.brightnessPercent
    root.lastConfirmedBrightnessPercent = reconciled.lastConfirmedBrightnessPercent
    root.hardwareState = {
      available: parsed.available === true,
      stale: parsed.stale === true,
      error: parsed.error || "",
      data: {
        brightness: reconciled.brightness,
        keyboardBrightness: reconciled.keyboardBrightness
      }
    }
  }

  function applyStateFromWorker(worker, raw) {
    if (!worker || worker !== root.stateWorker || !root.collecting
        || worker.generation !== root.reconciliationGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    worker.stateApplied = true
    root.applyState(raw)
  }

  function refresh() {
    if (!root.collecting || !root.collectorLoaded) return false
    var transition = Model.monitorOperationTransition(root.operationState, "reconcile-request")
    root.operationState = transition.state
    root.syncOperationPending()
    if (transition.startReconciliation && !root.stateWorker) root.startStateProcess()
    return true
  }

  function refreshNativeMonitors(delayed) {
    Hyprland.refreshMonitors()
    if (delayed === true) monitorRefreshTimer.restart()
    return true
  }

  function startStateProcess() {
    if (!root.collecting || root.stateWorker) return
    root.reconciliationGeneration++
    var worker = stateComponent.createObject(root, {
      generation: root.reconciliationGeneration,
      collectionGeneration: root.collectionGeneration
    })
    if (!worker) {
      root.finishReconciliation(null, 1, true)
      return
    }
    root.stateWorker = worker
    worker.running = true
  }

  function handleStateRunningChanged(worker) {
    if (worker.running || worker !== root.stateWorker || !root.collecting
        || worker.generation !== root.reconciliationGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    stateStartCheckTimer.worker = worker
    stateStartCheckTimer.generation = worker.generation
    stateStartCheckTimer.collectionGeneration = worker.collectionGeneration
    stateStartCheckTimer.start()
  }

  function finishReconciliation(worker, exitCode, failedStart) {
    if (worker !== null && worker !== root.stateWorker) return
    if (worker && (worker.generation !== root.reconciliationGeneration
        || worker.collectionGeneration !== root.collectionGeneration)) return
    if (root.reconciliationFinalizedGeneration === root.reconciliationGeneration) return

    root.reconciliationFinalizedGeneration = root.reconciliationGeneration
    stateStartCheckTimer.stop()
    stateStartCheckTimer.worker = null
    if (worker && root.stateWorker === worker) root.stateWorker = null
    if (worker && !failedStart && Number(exitCode) === 0 && !worker.stateApplied)
      root.applyState(worker.stdoutOutput.text || "")
    root.destroyWorker(worker)

    var transition = Model.monitorOperationTransition(root.operationState, "reconcile-finished")
    root.operationState = transition.state
    if (root.postActionReconciliationPending) {
      root.postActionReconciliationPending = false
      if (!transition.state.actionRunning
          && (!Array.isArray(transition.state.actionQueue) || transition.state.actionQueue.length === 0))
        root.postActionPending = false
    }
    root.syncOperationPending()
    if (transition.startAction) root.startAction(transition.startAction)
    else if (transition.startReconciliation && root.collecting && !root.stateWorker) root.startStateProcess()
  }

  function startAction(args) {
    if (!Array.isArray(args)) return
    root.actionName = String(args[1] || "")
    root.actionGeneration++
    var worker = actionComponent.createObject(root, {
      generation: root.actionGeneration,
      collectionGeneration: root.collectionGeneration
    })
    if (!worker) {
      root.finishAction(null, 1, true)
      return
    }
    worker.command = [root.actionExecutable].concat(args)
    root.actionWorker = worker
    worker.running = true
  }

  function handleActionRunningChanged(worker) {
    if (worker.running || worker !== root.actionWorker || !root.collecting
        || worker.generation !== root.actionGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    actionStartCheckTimer.worker = worker
    actionStartCheckTimer.generation = worker.generation
    actionStartCheckTimer.collectionGeneration = worker.collectionGeneration
    actionStartCheckTimer.start()
  }

  function finishAction(worker, exitCode, failedStart) {
    if (worker !== null && worker !== root.actionWorker) return
    if (worker && (worker.generation !== root.actionGeneration
        || worker.collectionGeneration !== root.collectionGeneration)) return
    if (root.actionFinalizedGeneration === root.actionGeneration) return

    root.actionFinalizedGeneration = root.actionGeneration
    actionStartCheckTimer.stop()
    actionStartCheckTimer.worker = null
    if (worker && root.actionWorker === worker) root.actionWorker = null
    var action = root.actionName
    if (!failedStart && Number(exitCode) === 0 && Model.shouldRefreshNativeMonitors(action))
      root.refreshNativeMonitors(action === "set-scale")
    root.destroyWorker(worker)
    root.actionName = ""

    var transition = Model.monitorOperationTransition(root.operationState, "action-finished")
    root.operationState = transition.state
    root.postActionPending = true
    root.postActionReconciliationPending = true
    root.syncOperationPending()
    Qt.callLater(root.refresh)
  }

  function runAction(args) {
    if (!Array.isArray(args)) return false
    var transition = Model.monitorOperationTransition(root.operationState, "action-request", args)
    root.operationState = transition.state
    root.postActionPending = true
    root.syncOperationPending()
    if (transition.startAction && !root.actionWorker) root.startAction(transition.startAction)
    return true
  }

  function setBrightness(value) {
    var next = Model.clampBrightness(value)
    root.runAction(["monitor", "set-display-brightness", String(next)])
  }

  function setKeyboardBrightness(action) {
    root.runAction(["monitor", "set-keyboard-brightness", String(action)])
  }

  function setScale(monitorName, scale) {
    if (!monitorName) return
    root.runAction(["monitor", "set-scale", monitorName, String(scale)])
  }

  function setLayout(mode, monitorName) {
    var args = ["monitor", "set-layout", mode]
    if (mode === "single") {
      if (!monitorName) return
      args.push(monitorName)
    }
    root.runAction(args)
  }

  function destroyWorker(worker) {
    if (!worker) return
    worker.running = false
    var staleWorker = worker
    Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
  }

  function stopCollection() {
    root.collectionGeneration++
    stateStartCheckTimer.stop()
    actionStartCheckTimer.stop()
    stateStartCheckTimer.worker = null
    actionStartCheckTimer.worker = null
    var oldStateWorker = root.stateWorker
    root.stateWorker = null
    root.destroyWorker(oldStateWorker)
    var oldActionWorker = root.actionWorker
    root.actionWorker = null
    root.destroyWorker(oldActionWorker)
    root.actionName = ""
    root.operationState = Model.monitorOperationState()
    root.postActionPending = false
    root.postActionReconciliationPending = false
    root.operationPending = false
  }

  onCollectingChanged: {
    if (!root.collecting) {
      root.stopCollection()
      return
    }
    startupTimer.start()
    root.refresh()
  }

  Timer {
    id: startupTimer
    property bool startupPhase: true
    interval: startupPhase ? 30000 : 60000
    repeat: true
    running: root.collecting
    onTriggered: {
      root.refresh()
      startupPhase = false
    }
  }

  Timer {
    id: stateStartCheckTimer
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.stateWorker
          && worker.generation === generation && worker.collectionGeneration === collectionGeneration
          && !worker.running)
        root.finishReconciliation(worker, 1, true)
    }
  }

  Timer {
    id: actionStartCheckTimer
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

  Timer {
    id: monitorRefreshTimer
    interval: 150
    repeat: false
    onTriggered: Hyprland.refreshMonitors()
  }

  Component {
    id: stateComponent
    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      property bool stateApplied: false
      command: [root.stateExecutable, "monitor"]
      stdout: StdioCollector {
        id: stdoutCollector
        waitForEnd: true
        onStreamFinished: root.applyStateFromWorker(process, text)
      }
      stderr: StdioCollector { waitForEnd: true }
      property alias stdoutOutput: stdoutCollector
      onExited: function(exitCode) { root.finishReconciliation(process, Number(exitCode), false) }
      onRunningChanged: root.handleStateRunningChanged(process)
    }
  }

  Component {
    id: actionComponent
    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      command: []
      stdout: StdioCollector { waitForEnd: true }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) { root.finishAction(process, Number(exitCode), false) }
      onRunningChanged: root.handleActionRunningChanged(process)
    }
  }

  Process {
    id: hostnameProcess
    command: [root.hostnameExecutable]
    running: root.collecting
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (root.hostname === "" && value !== "") root.hostname = value
      }
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Component.onDestruction: {
    root.collectorLoaded = false
    startupTimer.stop()
    monitorRefreshTimer.stop()
    root.stopCollection()
  }
}
