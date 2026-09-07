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
  property var _brightnessSnapshot: ({ version: 1, topology: "", monitors: ({}) })
  property var _brightnessPending: ({})
  property var _brightnessErrors: ({})
  property var _stickyBrightnessErrors: ({})
  property var activeTarget: null
  property string pendingConfirmationConnector: ""
  property var pendingConfirmationRecord: null
  property string pendingConfirmationError: ""
  property string queuedReconciliationConnector: ""
  property bool queuedFullReconciliation: false
  property bool topologyRefreshPending: false
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
  property int processTimeoutInterval: 30000
  property int stateProcessTimeoutInterval: 0
  property int stateDiscoveryTimeoutInterval: 16000
  property int stateMonitorTimeoutInterval: 6000
  property int stateMonitorCountLimit: 8
  property var stateWorker: null
  property var actionWorker: null

  readonly property var stateData: hardwareState && hardwareState.data ? hardwareState.data : ({})
  readonly property var brightness: stateData.brightness || ({ available: false, percent: 1 })
  readonly property var keyboardBrightness: stateData.keyboardBrightness || ({ available: false, percent: 0 })
  readonly property var brightnessSnapshot: root._brightnessSnapshot
  readonly property var brightnessByMonitor: root._brightnessSnapshot && root._brightnessSnapshot.monitors
    ? root._brightnessSnapshot.monitors : ({})
  readonly property var activeActionTarget: root.activeTarget

  function copyJson(value) {
    try {
      return JSON.parse(JSON.stringify(value))
    } catch (error) {
      return value
    }
  }

  function capturedStateTargetCount(connector) {
    if (Model.isValidConnector(connector) && connector !== "") return 1
    var stateCount = Model.normalizeMonitors(root.stateData && root.stateData.monitors
      ? root.stateData.monitors : [], null).monitors.length
    var nativeCount = Model.normalizeMonitors(
      Hyprland.monitors ? Hyprland.monitors.values : [], Hyprland.focusedMonitor).monitors.length
    return Math.max(1, stateCount, nativeCount)
  }

  function stateTimeoutFor(worker) {
    var configured = Number(root.stateProcessTimeoutInterval)
    if (isFinite(configured) && configured > 0) return Math.max(1, Math.round(configured))
    var discovery = Number(root.stateDiscoveryTimeoutInterval)
    var perMonitor = Number(root.stateMonitorTimeoutInterval)
    if (!isFinite(discovery) || discovery < 1) discovery = 16000
    if (!isFinite(perMonitor) || perMonitor < 1) perMonitor = 6000
    var targetCount = worker && Number(worker.targetCount) > 0 ? Number(worker.targetCount) : 1
    var fullSnapshot = !worker || !Model.isValidConnector(worker.requestedConnector)
      || worker.requestedConnector === ""
    var monitorLimit = Number(root.stateMonitorCountLimit)
    if (fullSnapshot && isFinite(monitorLimit) && monitorLimit > 0)
      targetCount = Math.max(targetCount, Math.round(monitorLimit))
    return Math.max(1, Math.round(discovery + targetCount * perMonitor))
  }

  function connectedMonitor(connector) {
    var monitors = root.stateData && Array.isArray(root.stateData.monitors) ? root.stateData.monitors : []
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i] && monitors[i].name === connector && monitors[i].enabled !== false) return true
    }
    return false
  }

  function setBrightnessPendingFor(connector, pending) {
    if (!Model.isValidConnector(connector)) return
    var next = Object.assign({}, root._brightnessPending)
    if (pending) next[connector] = true
    else delete next[connector]
    root._brightnessPending = next
  }

  function setBrightnessErrorFor(connector, message, sticky) {
    if (!Model.isValidConnector(connector)) return
    var next = Object.assign({}, root._brightnessErrors)
    var stickyErrors = Object.assign({}, root._stickyBrightnessErrors)
    if (message) {
      next[connector] = String(message)
      if (sticky === true) stickyErrors[connector] = true
      else if (sticky === false) delete stickyErrors[connector]
    } else {
      delete next[connector]
      delete stickyErrors[connector]
    }
    root._brightnessErrors = next
    root._stickyBrightnessErrors = stickyErrors
  }

  function hasQueuedBrightness(connector) {
    var queue = root.operationState && Array.isArray(root.operationState.actionQueue)
      ? root.operationState.actionQueue : []
    for (var i = 0; i < queue.length; i++) {
      var target = Model.brightnessActionTarget(queue[i])
      if (target && target.connector === connector) return true
    }
    return false
  }

  function releaseBrightnessReservation(connector) {
    if (!Model.isValidConnector(connector)) return
    if (root.activeTarget && root.activeTarget.connector === connector) return
    if (root.hasQueuedBrightness(connector)) return
    root.setBrightnessPendingFor(connector, false)
  }

  function brightnessFor(connector) {
    return Model.brightnessFor(root._brightnessSnapshot, connector)
  }

  function brightnessPending(connector) {
    return Model.isValidConnector(connector) && root._brightnessPending[connector] === true
  }

  function brightnessError(connector) {
    if (!Model.isValidConnector(connector)) return "Brightness unavailable"
    if (root._brightnessErrors[connector]) return String(root._brightnessErrors[connector])
    var record = root.brightnessFor(connector)
    return record && typeof record.error === "string" ? record.error : "Brightness unavailable"
  }

  function updateSnapshotRecord(connector, record) {
    if (!Model.isValidConnector(connector)) return
    var snapshot = root.copyJson(root._brightnessSnapshot)
    if (!snapshot || typeof snapshot !== "object") return
    if (!snapshot.monitors || typeof snapshot.monitors !== "object") snapshot.monitors = ({})
    snapshot.monitors[connector] = root.copyJson(record)
    root._brightnessSnapshot = snapshot
  }

  function markBrightnessUnavailable(connector, message, sticky) {
    if (!Model.isValidConnector(connector)) return
    var current = root.brightnessFor(connector)
    var stale = root.copyJson(current)
    stale.connector = connector
    stale.available = false
    stale.stale = true
    stale.error = String(message || "Brightness unavailable")
    root.updateSnapshotRecord(connector, stale)
    root.setBrightnessErrorFor(connector, stale.error, sticky === true)
  }

  function markStateFailure(message, requestedConnector) {
    var error = String(message || "Monitor state refresh failed")
    var connector = Model.isValidConnector(requestedConnector) ? requestedConnector : ""
    var previousState = root.hardwareState && typeof root.hardwareState === "object"
      ? root.hardwareState : ({})

    root.invalidateQueuedBrightness(error, connector)
    if (connector !== "") {
      root.markBrightnessUnavailable(connector, error, false)
      root.hardwareState = {
        available: previousState.available === true,
        stale: previousState.stale === true,
        error: previousState.error || "",
        data: Object.assign({}, root.stateData, { brightnessSnapshot: root._brightnessSnapshot })
      }
      return false
    }

    root._brightnessSnapshot = Model.invalidateBrightnessSnapshot(root._brightnessSnapshot, error)
    root.hardwareState = {
      available: false,
      stale: true,
      error: error,
      data: Object.assign({}, root.stateData, { brightnessSnapshot: root._brightnessSnapshot })
    }
    return false
  }

  function clearRecoveredBrightnessErrors(snapshot, requestedConnector) {
    if (!snapshot || typeof snapshot !== "object" || !snapshot.monitors) return
    var keys = Model.isValidConnector(requestedConnector) && requestedConnector !== ""
      ? [requestedConnector] : Object.keys(snapshot.monitors)
    for (var i = 0; i < keys.length; i++) {
      var connector = keys[i]
      var record = snapshot.monitors[connector]
      if (Model.isValidBrightnessTarget(record) && root._stickyBrightnessErrors[connector] !== true)
        root.setBrightnessErrorFor(connector, "")
    }
  }

  function validateCurrentTarget(connector) {
    if (!Model.isValidConnector(connector)) return { valid: false, error: "Connector is malformed" }
    if (root.hardwareState.available !== true || root.hardwareState.stale === true)
      return { valid: false, error: "Monitor state is unavailable or stale" }
    if (!root.connectedMonitor(connector)) return { valid: false, error: "Monitor is disconnected" }
    var target = root.brightnessFor(connector)
    if (!Model.isValidBrightnessTarget(target))
      return { valid: false, error: root.brightnessError(connector) || "Brightness is unavailable" }
    if (target.topology === "" || target.topology !== root._brightnessSnapshot.topology)
      return { valid: false, error: "Monitor topology changed; refresh is required" }
    return { valid: true, target: root.copyJson(target) }
  }

  function validateBrightnessAction(args) {
    if (!Array.isArray(args) || args.length < 2
        || args[0] !== "monitor" || args[1] !== "set-display-brightness")
      return { valid: true, args: Array.isArray(args) ? args.slice() : args, target: null }
    var parsed = Model.brightnessActionTarget(args)
    if (!parsed) return {
      valid: false,
      error: "Brightness action requires a valid target record",
      connector: Model.brightnessActionConnector(args)
    }
    var current = root.validateCurrentTarget(parsed.connector)
    if (!current.valid) return { valid: false, error: current.error, connector: parsed.connector }
    if (parsed.identity !== current.target.identity || parsed.topology !== current.target.topology)
      return { valid: false, error: "Brightness target identity changed; refresh is required", connector: parsed.connector }
    var prepared = args.slice()
    prepared[2] = String(args[2])
    prepared[3] = JSON.stringify(root.copyJson(current.target))
    return { valid: true, args: prepared, target: current.target }
  }

  function invalidateQueuedBrightness(message) {
    var requestedConnector = arguments.length > 1 ? arguments[1] : ""
    var restrictToConnector = Model.isValidConnector(requestedConnector) && requestedConnector !== ""
    var queue = root.operationState && Array.isArray(root.operationState.actionQueue)
      ? root.operationState.actionQueue : []
    var kept = []
    for (var i = 0; i < queue.length; i++) {
      var target = Model.brightnessActionTarget(queue[i])
      if (!target) {
        kept.push(queue[i])
        continue
      }
      if (restrictToConnector && target.connector !== requestedConnector) {
        kept.push(queue[i])
        continue
      }
      root.setBrightnessErrorFor(target.connector, message || "Monitor topology changed", true)
      root.setBrightnessPendingFor(target.connector, true)
    }
    var next = Object.assign({}, root.operationState)
    next.actionQueue = kept
    root.operationState = next
    var keys = Object.keys(root._brightnessPending)
    for (var k = 0; k < keys.length; k++) root.releaseBrightnessReservation(keys[k])
  }

  function queueFullReconciliation() {
    root.queuedFullReconciliation = true
    root.queuedReconciliationConnector = ""
  }

  function consumeReconciliationConnector() {
    var connector = root.queuedFullReconciliation ? "" : root.queuedReconciliationConnector
    root.queuedFullReconciliation = false
    root.queuedReconciliationConnector = ""
    return connector
  }

  function syncOperationPending() {
    var state = root.operationState
    root.operationPending = root.postActionPending || !!state.actionRunning
      || (Array.isArray(state.actionQueue) && state.actionQueue.length > 0)
  }

  function applyState(raw, requestedConnector) {
    var parsed = Model.parseState(raw)
    if (!parsed || typeof parsed.available !== "boolean" || typeof parsed.stale !== "boolean") {
      return root.markStateFailure("Invalid hardware state", requestedConnector)
    }

    if (parsed.available !== true || parsed.stale === true)
      return root.markStateFailure(parsed.error || "Monitor state is stale or unavailable", requestedConnector)

    var previousData = root.hardwareState && root.hardwareState.data ? root.hardwareState.data : {}
    var incomingSnapshot = parsed.data.brightnessSnapshot
    var snapshotResult = Model.normalizeBrightnessSnapshot(incomingSnapshot, root._brightnessSnapshot,
      Model.isValidConnector(requestedConnector) ? requestedConnector : "")
    if (!snapshotResult || snapshotResult.valid !== true)
      return root.markStateFailure("Invalid brightness snapshot", requestedConnector)
    root._brightnessSnapshot = snapshotResult.snapshot
    if (snapshotResult.topologyChanged) {
      root.invalidateQueuedBrightness("Monitor topology changed; refresh is required")
      root.topologyRefreshPending = true
    }
    var reconciled = Model.brightnessState({
      brightnessPercent: root.brightnessPercent,
      lastConfirmedBrightnessPercent: root.lastConfirmedBrightnessPercent,
      brightness: previousData.brightness,
      keyboardBrightness: previousData.keyboardBrightness
    }, parsed.data.brightness, parsed.data.keyboardBrightness)
    root.brightnessPercent = reconciled.brightnessPercent
    root.lastConfirmedBrightnessPercent = reconciled.lastConfirmedBrightnessPercent
    var nextData = Object.assign({}, parsed.data)
    nextData.brightness = reconciled.brightness
    nextData.keyboardBrightness = reconciled.keyboardBrightness
    nextData.brightnessSnapshot = root._brightnessSnapshot
    root.hardwareState = {
      available: parsed.available === true,
      stale: parsed.stale === true,
      error: parsed.error || "",
      data: nextData
    }
    root.clearRecoveredBrightnessErrors(root._brightnessSnapshot, requestedConnector)
    return true
  }

  function applyStateFromWorker(worker, raw) {
    if (!worker || worker !== root.stateWorker || !root.collecting
        || worker.generation !== root.reconciliationGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    worker.stateApplied = true
    worker.stateFresh = root.applyState(raw, worker.requestedConnector) === true
  }

  function refresh(connector) {
    if (!root.collecting || !root.collectorLoaded) return false
    var requestedConnector = Model.isValidConnector(connector) ? connector : ""
    if (requestedConnector !== "") {
      if (!root.queuedFullReconciliation) root.queuedReconciliationConnector = requestedConnector
    } else {
      root.queueFullReconciliation()
    }
    var transition = Model.monitorOperationTransition(root.operationState, "reconcile-request")
    root.operationState = transition.state
    root.syncOperationPending()
    if (transition.startReconciliation && !root.stateWorker)
      root.startStateProcess(root.consumeReconciliationConnector())
    return true
  }

  function refreshNativeMonitors(delayed) {
    Hyprland.refreshMonitors()
    if (delayed === true) monitorRefreshTimer.restart()
    return true
  }

  function startStateProcess(connector) {
    if (!root.collecting || root.stateWorker) return
    root.reconciliationGeneration++
    var worker = stateComponent.createObject(root, {
      generation: root.reconciliationGeneration,
      collectionGeneration: root.collectionGeneration,
      previousBrightnessSnapshot: root.copyJson(root._brightnessSnapshot),
      requestedConnector: Model.isValidConnector(connector) ? connector : "",
      targetCount: root.capturedStateTargetCount(connector),
      confirmation: Model.isValidConnector(connector) && connector !== "",
      postActionConfirmation: root.postActionReconciliationPending
    })
    if (!worker) {
      root.finishReconciliation(null, 1, true, connector)
      return
    }
    root.stateWorker = worker
    worker.running = true
    stateTimeoutTimer.worker = worker
    stateTimeoutTimer.generation = worker.generation
    stateTimeoutTimer.collectionGeneration = worker.collectionGeneration
    stateTimeoutTimer.interval = root.stateTimeoutFor(worker)
    stateTimeoutTimer.start()
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

  function cancelRoutineReconciliation() {
    var worker = root.stateWorker
    var queue = root.operationState && Array.isArray(root.operationState.actionQueue)
      ? root.operationState.actionQueue : []
    if (root.consumerCount !== 0 || !root.postActionPending || !worker
        || worker.postActionConfirmation === true || queue.length === 0) return

    root.reconciliationFinalizedGeneration = root.reconciliationGeneration
    stateStartCheckTimer.stop()
    stateTimeoutTimer.stop()
    stateStartCheckTimer.worker = null
    stateTimeoutTimer.worker = null
    root.stateWorker = null
    root.destroyWorker(worker)

    var transition = Model.monitorOperationTransition(root.operationState, "reconcile-cancelled")
    root.operationState = transition.state
    root.syncOperationPending()
    if (transition.startAction) root.startAction(transition.startAction)
    else if (transition.startReconciliation && root.collecting && !root.stateWorker)
      root.startStateProcess(root.consumeReconciliationConnector())
  }

  function finishBrightnessConfirmation(worker, success) {
    var connector = root.pendingConfirmationConnector
      || (worker && worker.requestedConnector ? worker.requestedConnector : "")
    if (!Model.isValidConnector(connector)) return
    var deliveryError = root.pendingConfirmationError
    var confirmed = root.brightnessFor(connector)
    var expected = root.pendingConfirmationRecord
    var expectedValid = Model.isValidBrightnessTarget(expected)
    var confirmedValid = Model.isValidBrightnessTarget(confirmed)
    var matchesExpected = expectedValid && confirmedValid
      && (confirmed.current === expected.current
        && confirmed.maximum === expected.maximum
        && confirmed.percent === expected.percent
        && confirmed.identity === expected.identity
        && confirmed.topology === expected.topology)
    if (success && matchesExpected) {
      root.setBrightnessErrorFor(connector, deliveryError, Boolean(deliveryError))
    } else if (confirmedValid) {
      root.setBrightnessErrorFor(connector, deliveryError
        || (expectedValid ? "Targeted brightness confirmation did not match action result"
          : "Targeted brightness confirmation failed"), true)
    } else {
      var confirmationError = deliveryError || "Targeted brightness confirmation failed"
      root.markBrightnessUnavailable(connector, confirmationError, deliveryError !== "")
    }
    root.releaseBrightnessReservation(connector)
    root.pendingConfirmationConnector = ""
    root.pendingConfirmationRecord = null
    root.pendingConfirmationError = ""
  }

  function finishReconciliation(worker, exitCode, failedStart, failedConnector) {
    if (worker !== null && worker !== root.stateWorker) return
    if (worker && (worker.generation !== root.reconciliationGeneration
        || worker.collectionGeneration !== root.collectionGeneration)) return
    if (root.reconciliationFinalizedGeneration === root.reconciliationGeneration) return

    root.reconciliationFinalizedGeneration = root.reconciliationGeneration
    stateStartCheckTimer.stop()
    stateTimeoutTimer.stop()
    stateStartCheckTimer.worker = null
    stateTimeoutTimer.worker = null
    if (worker && root.stateWorker === worker) root.stateWorker = null
    if (worker && !failedStart && Number(exitCode) === 0 && !worker.stateApplied) {
      worker.stateApplied = true
      worker.stateFresh = root.applyState(worker.stdoutOutput.text || "", worker.requestedConnector) === true
    }
    var reconciliationConnector = worker ? worker.requestedConnector : (failedConnector || "")
    var stateFresh = worker && !failedStart && Number(exitCode) === 0 && worker.stateFresh === true
    var postActionWorker = (worker && worker.postActionConfirmation === true)
      || (!worker && failedStart && root.postActionReconciliationPending)
    if (!stateFresh) {
      var failureMessage = "Monitor state refresh failed"
      if (failedStart) failureMessage = "Monitor state failed to start"
      else if (Number(exitCode) === 124) failureMessage = "Monitor state refresh timed out"
      else if (worker && worker.stateApplied && root.hardwareState.error)
        failureMessage = String(root.hardwareState.error)
      root.markStateFailure(failureMessage, reconciliationConnector)
    }
    var postActionTargetWorker = postActionWorker && root.pendingConfirmationConnector !== ""
    var confirmationSuccess = postActionTargetWorker && !failedStart
      && Number(exitCode) === 0 && worker.stateFresh === true
    if (postActionTargetWorker) root.finishBrightnessConfirmation(worker, confirmationSuccess)
    else if (postActionWorker && (failedStart || Number(exitCode) !== 0)) {
      if (root.pendingConfirmationConnector)
        root.markBrightnessUnavailable(root.pendingConfirmationConnector, "Monitor confirmation failed", true)
      root.pendingConfirmationConnector = ""
      root.pendingConfirmationRecord = null
      root.pendingConfirmationError = ""
    }
    root.destroyWorker(worker)

    var transition = Model.monitorOperationTransition(root.operationState, "reconcile-finished")
    root.operationState = transition.state
    if (postActionWorker) {
      root.postActionReconciliationPending = false
      if (!transition.state.actionRunning
          && (!Array.isArray(transition.state.actionQueue) || transition.state.actionQueue.length === 0)
          && !root.topologyRefreshPending)
        root.postActionPending = false
    }
    var topologyQueued = root.topologyRefreshPending
    if (topologyQueued) {
      root.topologyRefreshPending = false
      root.queueFullReconciliation()
      if (root.postActionPending) root.postActionReconciliationPending = true
    }
    root.syncOperationPending()
    if (transition.startAction) root.startAction(transition.startAction)
    else if (transition.startReconciliation && root.collecting && !root.stateWorker)
      root.startStateProcess(root.consumeReconciliationConnector())
    else if (topologyQueued && root.collecting) Qt.callLater(function() { root.refresh() })
  }

  function startAction(args) {
    if (!Array.isArray(args)) return
    var prepared = root.validateBrightnessAction(args)
    if (!prepared.valid) {
      var rejectedTarget = Model.brightnessActionTarget(args)
      if (rejectedTarget) root.setBrightnessErrorFor(rejectedTarget.connector, prepared.error, true)
      root.actionName = String(args[1] || "")
      root.activeTarget = rejectedTarget ? root.copyJson(rejectedTarget.record) : null
      root.actionGeneration++
      root.finishAction(null, 2, true)
      return
    }
    args = prepared.args
    root.activeTarget = prepared.target ? root.copyJson(prepared.target) : null
    if (root.activeTarget) root.setBrightnessErrorFor(root.activeTarget.connector, "")
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
    actionTimeoutTimer.worker = worker
    actionTimeoutTimer.generation = worker.generation
    actionTimeoutTimer.collectionGeneration = worker.collectionGeneration
    actionTimeoutTimer.start()
  }

  function handleActionRunningChanged(worker) {
    if (worker.running || worker !== root.actionWorker || !root.collecting
        || worker.generation !== root.actionGeneration
        || worker.collectionGeneration !== root.collectionGeneration
        || worker.processStarted || worker.actionExited) return
    actionStartCheckTimer.worker = worker
    actionStartCheckTimer.generation = worker.generation
    actionStartCheckTimer.collectionGeneration = worker.collectionGeneration
    actionStartCheckTimer.start()
  }

  function handleActionExited(worker, exitCode) {
    if (!worker || worker !== root.actionWorker
        || worker.generation !== root.actionGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    worker.actionExited = true
    worker.receivedExitCode = Number(exitCode)
    if (worker.stdoutFinished) root.finishAction(worker, worker.receivedExitCode, false)
  }

  function handleActionOutputFinished(worker, output) {
    if (!worker || worker !== root.actionWorker
        || worker.generation !== root.actionGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    worker.actionOutput = String(output || "")
    worker.stdoutFinished = true
    if (worker.actionExited) root.finishAction(worker, worker.receivedExitCode, false)
  }

  function finishAction(worker, exitCode, failedStart) {
    if (worker !== null && worker !== root.actionWorker) return
    if (worker && (worker.generation !== root.actionGeneration
        || worker.collectionGeneration !== root.collectionGeneration)) return
    if (root.actionFinalizedGeneration === root.actionGeneration) return

    root.actionFinalizedGeneration = root.actionGeneration
    actionStartCheckTimer.stop()
    actionTimeoutTimer.stop()
    actionStartCheckTimer.worker = null
    actionTimeoutTimer.worker = null
    if (worker && root.actionWorker === worker) root.actionWorker = null
    var action = root.actionName
    var target = root.activeTarget ? root.copyJson(root.activeTarget) : null
    var status = Number(exitCode)
    var confirmed = null
    var deliveryError = ""
    if (target && !failedStart && (status === 0 || status === 3)) {
      try {
        confirmed = JSON.parse(String(worker
          ? worker.actionOutput || (worker.stdoutOutput ? worker.stdoutOutput.text || "" : "") : ""))
      } catch (error) {
        confirmed = null
      }
      if (!Model.isValidBrightnessTarget(confirmed)
          || confirmed.connector !== target.connector
          || confirmed.identity !== target.identity
          || confirmed.topology !== target.topology) confirmed = null
      else if (status === 3) deliveryError = "OSD delivery failed"
    }
    if (!failedStart && Number(exitCode) === 0 && Model.shouldRefreshNativeMonitors(action))
      root.refreshNativeMonitors(action === "set-scale")
    root.destroyWorker(worker)
    root.actionName = ""

    var transition = Model.monitorOperationTransition(root.operationState, "action-finished")
    root.operationState = transition.state
    if (target) {
      if (confirmed) {
        root.pendingConfirmationConnector = target.connector
        root.pendingConfirmationRecord = confirmed
        root.pendingConfirmationError = deliveryError
        root.postActionReconciliationPending = true
        root.postActionPending = true
      } else {
        root.markBrightnessUnavailable(target.connector,
          failedStart ? "Brightness action failed to start"
            : status === 3 ? "OSD delivery failed without confirmation"
            : status === 0 ? "Invalid brightness confirmation" : "Brightness action failed", true)
        root.postActionReconciliationPending = false
        root.postActionPending = Array.isArray(transition.state.actionQueue)
          && transition.state.actionQueue.length > 0
      }
    } else {
      root.postActionPending = true
      root.postActionReconciliationPending = true
    }
    root.activeTarget = null
    if (target && !confirmed) root.releaseBrightnessReservation(target.connector)
    root.syncOperationPending()
    Qt.callLater(function() {
      if (confirmed) root.refresh(target.connector)
      else root.refresh()
    })
  }

  function runAction(args) {
    if (!Array.isArray(args)) return false
    var prepared = root.validateBrightnessAction(args)
    if (!prepared.valid) {
      if (prepared.connector) root.setBrightnessErrorFor(prepared.connector, prepared.error, true)
      return false
    }
    args = prepared.args
    if (prepared.target) {
      root.setBrightnessPendingFor(prepared.target.connector, true)
      root.setBrightnessErrorFor(prepared.target.connector, "")
    }
    var transition = Model.monitorOperationTransition(root.operationState, "action-request", args)
    root.operationState = transition.state
    root.postActionPending = true
    root.syncOperationPending()
    if (transition.startAction && !root.actionWorker) root.startAction(transition.startAction)
    return true
  }

  function setBrightness(connector, percent) {
    if (typeof percent !== "number" || !isFinite(percent) || Math.floor(percent) !== percent
        || percent < 1 || percent > 100) {
      if (Model.isValidConnector(connector))
        root.setBrightnessErrorFor(connector, "Brightness percent is out of range", true)
      return false
    }
    var current = root.validateCurrentTarget(connector)
    if (!current.valid) {
      root.setBrightnessErrorFor(connector, current.error,
        root._stickyBrightnessErrors[connector] === true)
      return false
    }
    var target = root.copyJson(current.target)
    return root.runAction(["monitor", "set-display-brightness", String(percent), JSON.stringify(target)])
  }

  function setKeyboardBrightness(action) {
    return root.runAction(["monitor", "set-keyboard-brightness", String(action)])
  }

  function setScale(monitorName, scale) {
    if (!monitorName) return false
    return root.runAction(["monitor", "set-scale", monitorName, String(scale)])
  }

  function setLayout(mode, monitorName) {
    var args = ["monitor", "set-layout", mode]
    if (mode === "single") {
      if (!monitorName) return false
      args.push(monitorName)
    }
    return root.runAction(args)
  }

  function destroyWorker(worker) {
    if (!worker) return
    worker.running = false
    var staleWorker = worker
    Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
  }

  function handleNativeTopologyChanged() {
    var snapshot = root._brightnessSnapshot
    var hasRecords = snapshot && snapshot.monitors && Object.keys(snapshot.monitors).length > 0
    if (!hasRecords && (!snapshot || snapshot.topology === "")) return
    root._brightnessSnapshot = Model.invalidateBrightnessSnapshot(
      snapshot, "Monitor topology changed; refresh is required")
    root.invalidateQueuedBrightness("Monitor topology changed; refresh is required")
    root.queueFullReconciliation()
    if (root.collecting) root.refresh()
  }

  function stopCollection() {
    root.collectionGeneration++
    stateStartCheckTimer.stop()
    actionStartCheckTimer.stop()
    stateTimeoutTimer.stop()
    actionTimeoutTimer.stop()
    stateStartCheckTimer.worker = null
    actionStartCheckTimer.worker = null
    stateTimeoutTimer.worker = null
    actionTimeoutTimer.worker = null
    var oldStateWorker = root.stateWorker
    root.stateWorker = null
    root.destroyWorker(oldStateWorker)
    var oldActionWorker = root.actionWorker
    root.actionWorker = null
    root.destroyWorker(oldActionWorker)
    root.actionName = ""
    root.activeTarget = null
    root.pendingConfirmationConnector = ""
    root.pendingConfirmationRecord = null
    root.pendingConfirmationError = ""
    root.queuedReconciliationConnector = ""
    root.queuedFullReconciliation = false
    root.topologyRefreshPending = false
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

  onConsumerCountChanged: root.cancelRoutineReconciliation()

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
    id: stateTimeoutTimer
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: Math.max(1, root.processTimeoutInterval)
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.stateWorker
          && worker.generation === generation && worker.collectionGeneration === collectionGeneration
          && worker.running)
        root.finishReconciliation(worker, 124, false)
    }
  }

  Timer {
    id: actionTimeoutTimer
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: Math.max(1, root.processTimeoutInterval)
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.actionWorker
          && worker.generation === generation && worker.collectionGeneration === collectionGeneration
          && worker.running)
        root.finishAction(worker, 124, false)
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
      property bool stateFresh: false
      property var previousBrightnessSnapshot: ({})
      property string requestedConnector: ""
      property int targetCount: 1
      property bool confirmation: false
      property bool postActionConfirmation: false
      command: {
        var args = [root.stateExecutable, "monitor", JSON.stringify(previousBrightnessSnapshot)]
        if (requestedConnector !== "") args.push(requestedConnector)
        return args
      }
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
      property bool processStarted: false
      property bool actionExited: false
      property bool stdoutFinished: false
      property int receivedExitCode: 1
      property string actionOutput: ""
      command: []
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: root.handleActionOutputFinished(process, text)
      }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) { root.handleActionExited(process, Number(exitCode)) }
      onRunningChanged: {
        if (process.running) process.processStarted = true
        root.handleActionRunningChanged(process)
      }
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

  Connections {
    target: Hyprland.monitors
    function onValuesChanged() { root.handleNativeTopologyChanged() }
  }

  Component.onDestruction: {
    root.collectorLoaded = false
    startupTimer.stop()
    monitorRefreshTimer.stop()
    root.stopCollection()
  }
}
