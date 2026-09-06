import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

SharedService {
  id: root

  property bool available: false
  property bool running: false
  property bool needsLogin: false
  property string backendState: "Unknown"
  property string statusText: "Unavailable"
  property string lastError: ""
  property string actionError: ""
  property string actionStatus: ""
  property var self: ({})
  property var peers: []

  property string stateExecutable: "desktop-hardware-state"
  property string actionExecutable: "desktop-hardware-action"
  property int processStartGraceInterval: 100
  property var stateWorker: null
  property var actionWorker: null
  property var queuedActionArgs: []
  property string queuedActionStatus: ""
  property bool pendingRefresh: false
  property bool initialRefreshRequested: false
  property bool actionReconciliationPending: false
  property int collectionGeneration: 0
  property int actionGeneration: 0
  property int actionFinalizedGeneration: 0

  readonly property bool active: available && running
  readonly property bool actionReserved: !!actionWorker || queuedActionArgs.length > 0
    || actionReconciliationPending
  readonly property bool busy: !!stateWorker || actionReserved
  readonly property string selfName: String(self.name || "")
  readonly property string selfDnsName: String(self.dnsName || "")
  readonly property var selfAddresses: Array.isArray(self.addresses) ? self.addresses : []
  readonly property bool selfExitNode: self.exitNode === true

  function reportCapability() {
    if (!pluginRegistry) return
    var scope = "capability:service:desktop.tailscale"
    if (available) pluginRegistry.clearPluginError("desktop.tailscale", scope)
    else pluginRegistry.recordPluginError("desktop.tailscale", "Tailscale unavailable or logged out", scope)
  }

  function applyState(raw) {
    var parsed = Model.parseState(raw)
    if (!parsed) {
      available = false
      running = false
      needsLogin = false
      backendState = "Invalid"
      statusText = "Status unavailable"
      lastError = "Invalid hardware state"
      self = ({})
      peers = []
      reportCapability()
      return false
    }

    available = parsed.available
    running = parsed.running
    needsLogin = parsed.needsLogin
    backendState = parsed.backendState
    self = parsed.self || ({})
    peers = parsed.peers || []
    lastError = actionError !== "" ? actionError : parsed.error
    if (needsLogin) statusText = "Needs login"
    else if (running) statusText = parsed.stale ? "Connected (stale)" : "Connected"
    else if (backendState === "Stopped") statusText = "Disconnected"
    else statusText = backendState
    reportCapability()
    return true
  }

  function refresh() {
    pendingRefresh = true
    schedule()
    return true
  }

  function runAction(args, label) {
    if (!Array.isArray(args) || args.length === 0 || actionReserved) return false
    operationPending = true
    if (stateWorker) {
      queuedActionArgs = args.slice()
      queuedActionStatus = label || ""
      return true
    }
    return startAction(args, label)
  }

  function startAction(args, label) {
    actionStatus = label || ""
    actionError = ""
    actionGeneration++
    var worker = actionComponent.createObject(root, { generation: actionGeneration })
    if (!worker) {
      finishAction(null, 1, true)
      return true
    }
    worker.actionArgs = args.slice()
    worker.command = [root.actionExecutable].concat(args)
    actionWorker = worker
    worker.running = true
    return true
  }

  function toggleTailscale() {
    return active ? runAction(["tailscale", "down"], "Stopping Tailscale")
      : runAction(["tailscale", "up"], "Starting Tailscale")
  }

  function up() {
    return runAction(["tailscale", "up"], "Starting Tailscale")
  }

  function down() {
    return runAction(["tailscale", "down"], "Stopping Tailscale")
  }

  function logout() {
    return runAction(["tailscale", "logout"], "Logging out")
  }

  function switchAccount(id) {
    var accountId = String(id || "")
    return accountId !== "" && runAction(["tailscale", "switch-account", accountId], "Switching account")
  }

  function setExitNode(peer) {
    if (!peer) return false
    if (peer.exitNode === true) return runAction(["tailscale", "clear-exit-node"], "Clearing exit node")
    var target = Model.peerAddress(peer)
    return target !== "" && runAction(["tailscale", "set-exit-node", target], "Setting exit node")
  }

  function copyToClipboard(value) {
    var text = String(value || "")
    if (text !== "") Quickshell.execDetached(["wl-copy", "--", text])
  }

  function copyPeerName(peer) {
    copyToClipboard(Model.peerLabel(peer))
  }

  function copyPeerAddress(peer) {
    copyToClipboard(Model.peerAddress(peer))
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
    var reconciliationError = actionReconciliationPending ? actionError : ""
    var ok = !failedStart && Number(exitCode) === 0
    if (ok) applyState(worker.stdoutOutput.text || "")
    else {
      available = false
      running = false
      lastError = reconciliationError !== "" ? reconciliationError
        : (failedStart ? "Tailscale state query failed to start" : "Tailscale state query failed")
      reportCapability()
    }
    stateWorker = null
    destroyWorker(worker)
    if (actionReconciliationPending) {
      actionReconciliationPending = false
      operationPending = false
      actionError = ""
      if (reconciliationError !== "") lastError = reconciliationError
    }
    schedule()
  }

  function finishAction(worker, exitCode, failedStart) {
    if (worker !== null && worker !== actionWorker) return
    if (actionFinalizedGeneration === actionGeneration) return
    actionFinalizedGeneration = actionGeneration
    actionStartCheckTimer.stop()
    actionStartCheckTimer.worker = null
    var ok = !failedStart && Number(exitCode) === 0
    if (actionWorker === worker) actionWorker = null
    if (worker) destroyWorker(worker)
    if (!ok) {
      lastError = failedStart ? "Tailscale action failed to start" : "Tailscale action failed"
      actionStatus = ""
      if (failedStart) {
        operationPending = false
        actionReconciliationPending = false
      } else {
        actionError = lastError
        actionReconciliationPending = true
        pendingRefresh = true
      }
      queuedActionArgs = []
      queuedActionStatus = ""
      schedule()
      return
    }
    actionStatus = ""
    actionReconciliationPending = true
    pendingRefresh = true
    schedule()
  }

  function handleActionRunningChanged(worker) {
    if (worker.running || worker !== actionWorker || worker.generation !== actionGeneration) return
    actionStartCheckTimer.worker = worker
    actionStartCheckTimer.generation = worker.generation
    actionStartCheckTimer.start()
  }

  function schedule() {
    if (!collecting || stateWorker || actionWorker) return
    if (queuedActionArgs.length > 0) {
      var args = queuedActionArgs
      var label = queuedActionStatus
      queuedActionArgs = []
      queuedActionStatus = ""
      startAction(args, label)
      return
    }
    if (pendingRefresh) {
      pendingRefresh = false
      startState()
    }
  }

  function startState() {
    if (!collecting || stateWorker) return
    if (consumerCount > 0) initialRefreshRequested = true
    var worker = stateComponent.createObject(root, {
      collectionGeneration: collectionGeneration,
      generation: collectionGeneration
    })
    if (!worker) {
      available = false
      running = false
      lastError = "Tailscale state query failed to start"
      reportCapability()
      return
    }
    stateWorker = worker
    worker.running = true
  }

  function stopCollection() {
    collectionGeneration++
    pendingRefresh = false
    stateStartCheckTimer.stop()
    actionStartCheckTimer.stop()
    stateStartCheckTimer.worker = null
    actionStartCheckTimer.worker = null
    var oldStateWorker = stateWorker
    stateWorker = null
    destroyWorker(oldStateWorker)
    var oldActionWorker = actionWorker
    actionWorker = null
    destroyWorker(oldActionWorker)
    queuedActionArgs = []
    queuedActionStatus = ""
    actionReconciliationPending = false
    operationPending = false
    initialRefreshRequested = false
  }

  onCollectingChanged: {
    if (!collecting) {
      stopCollection()
      return
    }
  }

  Timer {
    interval: 20
    repeat: true
    running: root.collecting && root.consumerCount > 0 && !root.initialRefreshRequested
    onTriggered: if (root.consumerCount > 0 && !root.initialRefreshRequested) root.refresh()
  }

  onDetailedChanged: if (detailed && collecting) refresh()
  onActionExecutableChanged: if (actionWorker)
    actionWorker.command = [root.actionExecutable].concat(actionWorker.actionArgs || [])

  Timer {
    interval: root.detailed ? 15000 : 60000
    repeat: true
    running: root.collecting
    onTriggered: root.refresh()
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
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: if (worker && worker === root.actionWorker
      && worker.generation === generation && !worker.running)
      root.finishAction(worker, 1, true)
  }

  Component {
    id: stateComponent

    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      command: [root.stateExecutable, "tailscale"]
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
      property var actionArgs: []
      command: []
      stdout: StdioCollector { waitForEnd: true }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) { root.finishAction(process, Number(exitCode), false) }
      onRunningChanged: root.handleActionRunningChanged(process)
    }
  }

  Component.onDestruction: stopCollection()
}
