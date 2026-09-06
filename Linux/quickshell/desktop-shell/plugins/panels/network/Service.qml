import QtQuick
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

SharedService {
  id: root

  property bool iwdAvailable: false
  property string iwdDevice: ""
  property string stationPath: ""
  property string connectionState: ""
  property string connectedSsid: ""
  property int iwdSignal: 0
  property var iwdNetworks: []
  property bool initialProbeCompleted: false
  property bool initialProbeHadStation: false

  property var wifiNetworks: []
  property string dnsProvider: "DHCP"
  property string pendingDnsProvider: ""
  property string actionKind: ""
  property string actionDevice: ""
  property string actionProfile: ""
  property string actionPassword: ""
  property string queuedActionKind: ""
  property string queuedActionDevice: ""
  property string queuedActionProfile: ""
  property string queuedActionPassword: ""
  property string queuedDnsProvider: ""
  property bool pendingStateRefresh: false
  property bool pendingScan: false
  property string healthError: ""
  property string actionError: ""
  property bool initialProbeRequested: false

  property string stateExecutable: "desktop-iwd-state"
  property string actionExecutable: "desktop-connectivity-action"
  property int processStartGraceInterval: 100
  property var stateWorker: null
  property var actionWorker: null
  property int collectionGeneration: 0
  property int actionGeneration: 0
  property int actionFinalizedGeneration: 0
  property bool actionReconciliationPending: false

  readonly property bool actionReserved: actionKind !== "" || queuedActionKind !== ""
    || actionReconciliationPending || queuedActionState.consumedToken !== null
  readonly property bool busy: !!stateWorker || !!actionWorker || actionReserved
  readonly property bool capabilityAvailable: iwdAvailable || stationPath !== ""

  QtObject {
    id: queuedActionState
    objectName: "networkQueuedActionState"
    property var token: null
    property var consumedToken: null
    property var starter: null
    property var clearSecret: null
  }

  function reportHealth() {
    if (!pluginRegistry) return
    var scope = "capability:service:desktop.network"
    if (healthError === "") pluginRegistry.clearPluginError("desktop.network", scope)
    else pluginRegistry.recordPluginError("desktop.network", healthError, scope)
  }

  function setHealthError(message) {
    healthError = String(message || "")
    reportHealth()
  }

  function syncWifiNetworks() {
    var rows = []
    for (var i = 0; i < iwdNetworks.length; i++) {
      var row = Model.wifiRow(iwdNetworks[i])
      if (row && row.ssid !== "") rows.push(row)
    }
    wifiNetworks = Model.sortWifiRows(rows)
  }

  function applyState(raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (error) {
      setHealthError("iwd state query failed")
      return false
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)
        || typeof parsed.available !== "boolean" || !Array.isArray(parsed.networks)) {
      setHealthError("iwd state query failed")
      return false
    }
    if (!parsed.available
        && (parsed.device !== null || parsed.stationPath !== null || parsed.state !== "disconnected"
            || parsed.connectedSsid !== null || parsed.signal !== 0 || parsed.networks.length !== 0)) {
      setHealthError("iwd state query failed")
      return false
    }
    var previousSession = Model.connectionSessionKey(iwdDevice, connectionState, connectedSsid)
    var nextDevice = parsed.device === null ? "" : String(parsed.device || "")
    var nextState = String(parsed.state || "")
    var nextSsid = parsed.connectedSsid === null ? "" : String(parsed.connectedSsid || "")
    if (previousSession !== Model.connectionSessionKey(nextDevice, nextState, nextSsid)) dnsProvider = "DHCP"
    iwdAvailable = parsed.available
    iwdDevice = nextDevice
    stationPath = parsed.stationPath === null ? "" : String(parsed.stationPath || "")
    connectionState = nextState
    connectedSsid = nextSsid
    iwdSignal = Math.max(0, Math.min(100, Math.round(Number(parsed.signal || 0))))
    iwdNetworks = parsed.networks
    syncWifiNetworks()
    if (!initialProbeCompleted) {
      initialProbeCompleted = true
      initialProbeHadStation = parsed.available
    }
    setHealthError("")
    return true
  }

  function requestRefresh(scan) {
    pendingStateRefresh = true
    if (scan) pendingScan = true
    schedule()
  }

  function runConnect(ssid, password) {
    if (!ssid) return false
    return queueOrStartAction("connect", iwdDevice, ssid, password, "")
  }

  function runNetworkAction(kindName, profile) {
    if (!profile) return false
    return queueOrStartAction(kindName, iwdDevice, profile, "", "")
  }

  function setDns(provider) {
    if (connectedSsid === "") return false
    return queueOrStartAction("set-dns", iwdDevice, "", "", provider)
  }

  function queueOrStartAction(kindName, device, profile, password, dnsProvider) {
    if (actionReserved) return false
    operationPending = true
    if (stateWorker) {
      queuedActionKind = String(kindName || "")
      queuedActionDevice = String(device || "")
      queuedActionProfile = String(profile || "")
      queuedActionPassword = ""
      var requestToken = {}
      queuedActionState.token = requestToken
      queuedActionState.consumedToken = null
      var secret = String(password || "")
      var consumed = false
      queuedActionState.starter = function(authorization) {
        if (authorization !== requestToken || queuedActionState.consumedToken !== requestToken || consumed) return
        if (!root.collecting || root.stateWorker || root.actionWorker) {
          secret = ""
          queuedActionState.consumedToken = null
          return
        }
        consumed = true
        var value = secret
        secret = ""
        startAction(kindName, device, profile, value, dnsProvider)
        queuedActionState.consumedToken = null
      }
      queuedActionState.clearSecret = function() { secret = "" }
      queuedDnsProvider = String(dnsProvider || "")
      return true
    }
    return startAction(kindName, device, profile, password, dnsProvider)
  }

  function actionCommand(kindName, device, profile, dnsProvider) {
    if (kindName === "connect")
      return [root.actionExecutable, "network", "connect", device, profile]
    if (kindName === "disconnect")
      return [root.actionExecutable, "network", "disconnect", device]
    if (kindName === "forget")
      return [root.actionExecutable, "network", "forget", profile]
    if (kindName === "set-dns")
      return [root.actionExecutable, "network", "set-dns", device, dnsProvider]
    if (kindName === "scan")
      return [root.actionExecutable, "network", "scan", device]
    return []
  }

  function startAction(kindName, device, profile, password, dnsProvider) {
    var command = actionCommand(kindName, String(device || ""), String(profile || ""), String(dnsProvider || ""))
    if (command.length === 0) {
      operationPending = false
      return false
    }
    actionKind = String(kindName || "")
    actionDevice = String(device || "")
    actionProfile = String(profile || "")
    pendingDnsProvider = String(dnsProvider || "")
    actionError = ""
    actionGeneration++
    var secret = String(password || "")
    var worker = actionComponent.createObject(root, { generation: actionGeneration })
    if (!worker) {
      secret = ""
      finishAction(null, 1, true)
      return true
    }
    worker.command = command
    actionWorker = worker
    var clearSecret = function() { secret = "" }
    worker.started.connect(function() {
      if (root.actionWorker !== worker || root.actionKind !== "connect") {
        clearSecret()
        return
      }
      var value = secret
      clearSecret()
      worker.write(value + "\n")
    })
    worker.exited.connect(function(exitCode) {
      root.finishAction(worker, Number(exitCode), false, clearSecret)
    })
    worker.runningChanged.connect(function() {
      root.handleActionRunningChanged(worker, clearSecret)
    })
    worker.running = true
    return true
  }

  function clearQueuedAction() {
    var clearSecret = queuedActionState.clearSecret
    queuedActionState.starter = null
    queuedActionState.clearSecret = null
    queuedActionState.token = null
    queuedActionState.consumedToken = null
    if (clearSecret) clearSecret()
    queuedActionKind = ""
    queuedActionDevice = ""
    queuedActionProfile = ""
    queuedActionPassword = ""
    queuedDnsProvider = ""
  }

  function dequeueQueuedAction() {
    if (!collecting || stateWorker || actionWorker) return false
    var token = queuedActionState.token
    var starter = queuedActionState.starter
    var clearSecret = queuedActionState.clearSecret
    queuedActionState.token = null
    queuedActionState.consumedToken = token
    queuedActionState.starter = null
    queuedActionState.clearSecret = null
    queuedActionKind = ""
    queuedActionDevice = ""
    queuedActionProfile = ""
    queuedActionPassword = ""
    queuedDnsProvider = ""
    if (starter) starter(token)
    else if (clearSecret) clearSecret()
    return true
  }

  function clearActiveAction() {
    actionKind = ""
    actionDevice = ""
    actionProfile = ""
    pendingDnsProvider = ""
  }

  function destroyWorker(worker) {
    if (!worker) return
    worker.running = false
    var staleWorker = worker
    Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
  }

  function handleStateRunningChanged(worker) {
    if (worker.running || worker !== stateWorker || !collecting
        || worker.collectionGeneration !== collectionGeneration) return
    stateStartCheckTimer.worker = worker
    stateStartCheckTimer.generation = worker.generation
    stateStartCheckTimer.collectionGeneration = worker.collectionGeneration
    stateStartCheckTimer.start()
  }

  function finishState(worker, exitCode, failedStart) {
    if (worker !== stateWorker || !collecting
        || worker.collectionGeneration !== collectionGeneration) return
    stateStartCheckTimer.stop()
    stateStartCheckTimer.worker = null
    var ok = !failedStart && Number(exitCode) === 0
    if (ok) applyState(worker.stdoutOutput.text || "")
    else setHealthError(failedStart ? "iwd state query failed to start" : "iwd state query failed")
    stateWorker = null
    destroyWorker(worker)
    if (actionReconciliationPending) {
      actionReconciliationPending = false
      operationPending = false
    }
    schedule()
  }

  function finishAction(worker, exitCode, failedStart, clearSecret) {
    if (worker !== null && worker !== actionWorker) {
      if (clearSecret) clearSecret()
      return
    }
    if (actionFinalizedGeneration === actionGeneration) {
      if (clearSecret) clearSecret()
      return
    }
    actionFinalizedGeneration = actionGeneration
    var timerCleanup = actionStartCheckTimer.cleanup
    actionStartCheckTimer.cleanup = null
    actionStartCheckTimer.stop()
    actionStartCheckTimer.worker = null
    if (timerCleanup) timerCleanup()
    if (clearSecret) clearSecret()
    var kindName = actionKind
    var ok = !failedStart && Number(exitCode) === 0
    if (actionWorker === worker) actionWorker = null
    if (worker) {
      destroyWorker(worker)
    }
    if (!ok) {
      actionError = failedStart ? "Network action failed to start" : "Network action failed"
      setHealthError(actionError)
      clearActiveAction()
      clearQueuedAction()
      if (!failedStart) {
        actionReconciliationPending = true
        pendingStateRefresh = true
      } else {
        actionReconciliationPending = false
        operationPending = false
      }
      schedule()
      return
    }
    if (kindName === "connect" || kindName === "disconnect") dnsProvider = "DHCP"
    if (kindName === "set-dns") dnsProvider = pendingDnsProvider
    actionError = ""
    clearActiveAction()
    actionReconciliationPending = true
    pendingStateRefresh = true
    schedule()
  }

  function handleActionRunningChanged(worker, clearSecret) {
    if (worker.running) return
    if (worker !== actionWorker || worker.generation !== actionGeneration || !collecting) {
      if (clearSecret) clearSecret()
      return
    }
    actionStartCheckTimer.worker = worker
    actionStartCheckTimer.generation = worker.generation
    actionStartCheckTimer.cleanup = clearSecret
    actionStartCheckTimer.start()
  }

  function schedule() {
    if (!collecting || stateWorker || actionWorker) return
    if (queuedActionKind !== "") {
      dequeueQueuedAction()
      return
    }
    if (pendingScan && iwdDevice === "") {
      if (pendingStateRefresh) {
        pendingStateRefresh = false
        startState()
      }
      return
    }
    if (pendingScan) {
      pendingScan = false
      startAction("scan", iwdDevice, "", "", "")
      return
    }
    if (pendingStateRefresh) {
      pendingStateRefresh = false
      startState()
    }
  }

  function startState() {
    if (!collecting || stateWorker) return
    if (consumerCount > 0 && !initialProbeCompleted) initialProbeRequested = true
    var worker = stateComponent.createObject(root, {
      collectionGeneration: collectionGeneration,
      generation: collectionGeneration
    })
    if (!worker) {
      setHealthError("iwd state query failed to start")
      return
    }
    stateWorker = worker
    worker.running = true
  }

  function stopCollection() {
    collectionGeneration++
    pendingStateRefresh = false
    pendingScan = false
    stateStartCheckTimer.stop()
    var actionCleanup = actionStartCheckTimer.cleanup
    actionStartCheckTimer.cleanup = null
    actionStartCheckTimer.stop()
    if (actionCleanup) actionCleanup()
    stateStartCheckTimer.worker = null
    actionStartCheckTimer.worker = null
    var oldStateWorker = stateWorker
    stateWorker = null
    destroyWorker(oldStateWorker)
    var oldActionWorker = actionWorker
    actionWorker = null
    destroyWorker(oldActionWorker)
    clearActiveAction()
    clearQueuedAction()
    actionReconciliationPending = false
    operationPending = false
    initialProbeRequested = false
    initialProbeCompleted = false
    initialProbeHadStation = false
  }

  onCollectingChanged: {
    if (!collecting) {
      stopCollection()
      return
    }
  }

  onDetailedChanged: if (detailed && collecting) requestRefresh(true)

  Timer {
    interval: 20
    repeat: true
    running: root.collecting && root.consumerCount > 0 && !root.initialProbeRequested
    onTriggered: if (root.consumerCount > 0 && !root.initialProbeRequested) root.requestRefresh(false)
  }

  onActionExecutableChanged: if (actionWorker) actionWorker.command = actionCommand(
    actionKind, actionDevice, actionProfile, pendingDnsProvider)

  Timer {
    interval: root.detailed ? 3000 : 60000
    repeat: true
    running: root.collecting && (!root.initialProbeCompleted || root.initialProbeHadStation)
    onTriggered: root.requestRefresh(false)
  }

  Timer {
    id: stateStartCheckTimer
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && collectionGeneration === root.collectionGeneration
          && worker && worker === root.stateWorker && worker.generation === generation && !worker.running)
        root.finishState(worker, 1, true)
    }
  }

  Timer {
    id: actionStartCheckTimer
    property int generation: 0
    property var worker: null
    property var cleanup: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      var clearSecret = cleanup
      cleanup = null
      if (worker && worker === root.actionWorker
          && worker.generation === generation && !worker.running)
        root.finishAction(worker, 1, true, clearSecret)
      else if (clearSecret) clearSecret()
    }
  }

  Component {
    id: stateComponent

    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      command: [root.stateExecutable]
      stdout: StdioCollector {
        id: stdoutCollector
        waitForEnd: true
      }
      stderr: StdioCollector { waitForEnd: true }
      property alias stdoutOutput: stdoutCollector
      onExited: function(exitCode) { root.finishState(process, Number(exitCode), false) }
      onRunningChanged: root.handleStateRunningChanged(process)
    }
  }

  Component {
    id: actionComponent

    Process {
      id: process
      property int generation: 0
      command: []
      stdinEnabled: true
      stdout: StdioCollector { waitForEnd: true }
      stderr: StdioCollector { waitForEnd: true }
    }
  }

  Component.onDestruction: stopCollection()
}
