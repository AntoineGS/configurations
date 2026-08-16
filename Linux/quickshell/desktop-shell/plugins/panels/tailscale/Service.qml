import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property var pluginRegistry: null
  property bool loaded: true
  property bool available: false
  property bool running: false
  property bool needsLogin: false
  property string backendState: "Unknown"
  property string statusText: "Unavailable"
  property string lastError: ""
  property string actionStatus: ""
  property var self: ({})
  property var peers: []
  property string pendingClipboard: ""

  readonly property bool active: available && running
  readonly property bool busy: stateProcess.running || actionProcess.running || copyProcess.running
  readonly property string selfName: String(self.name || "")
  readonly property string selfDnsName: String(self.dnsName || "")
  readonly property var selfAddresses: Array.isArray(self.addresses) ? self.addresses : []
  readonly property bool selfExitNode: self.exitNode === true

  function reportCapability() {
    if (!pluginRegistry) return
    if (available) pluginRegistry.clearPluginError("desktop.tailscale")
    else pluginRegistry.recordPluginError("desktop.tailscale", "Tailscale unavailable or logged out")
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
      return
    }

    available = parsed.available
    running = parsed.running
    needsLogin = parsed.needsLogin
    backendState = parsed.backendState
    self = parsed.self || ({})
    peers = parsed.peers || []
    lastError = parsed.error
    if (needsLogin) statusText = "Needs login"
    else if (running) statusText = parsed.stale ? "Connected (stale)" : "Connected"
    else if (backendState === "Stopped") statusText = "Disconnected"
    else statusText = backendState
    reportCapability()
  }

  function refresh() {
    if (!stateProcess.running) stateProcess.running = true
  }

  function runAction(args, label) {
    if (actionProcess.running || !Array.isArray(args)) return
    actionStatus = label || ""
    actionProcess.command = ["desktop-hardware-action"].concat(args)
    actionProcess.running = true
  }

  function toggleTailscale() {
    if (active) runAction(["tailscale", "down"], "Stopping Tailscale")
    else runAction(["tailscale", "up"], "Starting Tailscale")
  }

  function up() {
    runAction(["tailscale", "up"], "Starting Tailscale")
  }

  function down() {
    runAction(["tailscale", "down"], "Stopping Tailscale")
  }

  function logout() {
    runAction(["tailscale", "logout"], "Logging out")
  }

  function switchAccount(id) {
    var accountId = String(id || "")
    if (accountId !== "") runAction(["tailscale", "switch-account", accountId], "Switching account")
  }

  function setExitNode(peer) {
    if (!peer) return
    if (peer.exitNode === true) {
      runAction(["tailscale", "clear-exit-node"], "Clearing exit node")
      return
    }
    var target = Model.peerAddress(peer)
    if (target !== "") runAction(["tailscale", "set-exit-node", target], "Setting exit node")
  }

  function copyToClipboard(value) {
    var text = String(value || "")
    if (text === "" || copyProcess.running) return
    pendingClipboard = text
    copyProcess.command = ["wl-copy"]
    copyProcess.running = true
  }

  function copyPeerName(peer) {
    copyToClipboard(Model.peerLabel(peer))
  }

  function copyPeerAddress(peer) {
    copyToClipboard(Model.peerAddress(peer))
  }

  Component.onCompleted: refresh()
  Component.onDestruction: {
    loaded = false
    refreshTimer.stop()
  }

  Timer {
    id: refreshTimer
    interval: 15000
    running: root.loaded
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProcess
    command: ["desktop-hardware-state", "tailscale"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      if (exitCode !== 0) root.lastError = root.actionStatus || "Tailscale action failed"
      else root.actionStatus = ""
      root.refresh()
    }
  }

  Process {
    id: copyProcess
    command: []
    stdinEnabled: true
    onStarted: write(root.pendingClipboard)
    onExited: root.pendingClipboard = ""
  }
}
