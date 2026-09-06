import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "RemoteBarModel.js" as RemoteBarModel

QtObject {
  id: root

  required property var shell
  property var config: ({})
  readonly property string home: Quickshell.env("HOME") || ""
  // Keep the transport path stable between the graphical service and non-interactive SSH shells.
  readonly property string stateHome: home + "/.local/state"
  property string snapshotPath: stateHome + "/desktop-shell/remote-bar.json"
  readonly property string snapshotDirectory: {
    var path = String(root.snapshotPath || "")
    var separator = path.lastIndexOf("/")
    return separator > 0 ? path.slice(0, separator) : "."
  }
  readonly property bool publisherEnabled: config && config.publish === true
  readonly property bool publisherActive: publisherEnabled && !!shell && !shell.previewMode
  readonly property string publisherHost: publisherEnabled ? String(config.host || "") : ""
  readonly property string target: config ? String(config.target || "") : ""
  readonly property string sourceHost: config ? String(config.sourceHost || "") : ""
  readonly property bool sourceEnabled: target !== ""
  readonly property int staleAfterSeconds: 30
  readonly property int offlineAfterSeconds: 60

  property var eligibleScreens: []
  property var localOverrides: ({})
  property int modeRevision: 0
  property var snapshot: null
  property double snapshotReceivedAt: 0
  property string connectionTarget: ""
  property string lastError: ""
  property string publishError: ""
  property double nowSeconds: Math.floor(Date.now() / 1000)
  property bool publishDirectoryReady: false
  property bool snapshotWritePending: false
  property bool snapshotWriteQueued: false
  property bool detectQueued: false

  readonly property var freshness: RemoteBarModel.freshness(
    snapshot, nowSeconds, snapshotReceivedAt, staleAfterSeconds, offlineAfterSeconds)
  readonly property string health: freshness.state
  readonly property int snapshotAgeSeconds: freshness.ageSeconds
  readonly property bool eligible: eligibleScreens.length > 0
  readonly property bool anyRemoteSelected: {
    var revision = modeRevision
    for (var i = 0; i < eligibleScreens.length; i++)
      if (localOverrides[String(eligibleScreens[i])] !== true) return true
    return false
  }
  readonly property bool warning: anyRemoteSelected && health !== "fresh"
  readonly property var agents: RemoteBarModel.widget(snapshot, "agents")
  readonly property var audio: RemoteBarModel.widget(snapshot, "audio")
  readonly property var disk: RemoteBarModel.widget(snapshot, "disk")
  readonly property var vm: RemoteBarModel.widget(snapshot, "vm")

  readonly property var agentsService: shell ? shell.serviceFor("desktop.agents") : null
  readonly property var audioService: shell ? shell.serviceFor("desktop.audio") : null
  readonly property var diskService: shell ? shell.serviceFor("desktop.disk") : null
  readonly property var vmService: shell ? shell.serviceFor("desktop.vm") : null

  property ServiceConsumer agentsConsumer: ServiceConsumer {
    service: root.agentsService
    active: root.publisherEnabled && root.shell
      && !root.shell.previewMode && root.shell.serviceConfigured("desktop.agents")
    details: false
  }

  property ServiceConsumer audioConsumer: ServiceConsumer {
    service: root.audioService
    active: root.publisherEnabled && root.shell
      && !root.shell.previewMode && root.shell.serviceConfigured("desktop.audio")
    details: false
  }

  property ServiceConsumer diskConsumer: ServiceConsumer {
    service: root.diskService
    active: root.publisherEnabled && root.shell
      && !root.shell.previewMode && root.shell.serviceConfigured("desktop.disk")
    details: false
  }

  property ServiceConsumer vmConsumer: ServiceConsumer {
    service: root.vmService
    active: root.publisherEnabled && root.shell
      && !root.shell.previewMode && root.shell.serviceConfigured("desktop.vm")
    details: false
  }

  function plainCopy(value, fallback) {
    try {
      return JSON.parse(JSON.stringify(value))
    } catch (_) {
      return fallback
    }
  }

  function publishSnapshot() {
    if (!publisherActive || !publishDirectoryReady || publisherHost === "") return
    if (snapshotWritePending) {
      snapshotWriteQueued = true
      return
    }
    var payload = {
      schemaVersion: 1,
      host: publisherHost,
      publishedAt: Math.floor(Date.now() / 1000),
      widgets: {
        agents: agentsConsumer.active && agentsService
          ? plainCopy(agentsService.remoteSummary, {}) : {},
        audio: audioConsumer.active && audioService
          ? plainCopy(audioService.remoteSummary, {}) : {},
        disk: diskConsumer.active && diskService
          ? plainCopy(diskService.remoteSummary, {}) : {},
        vm: vmConsumer.active && vmService
          ? plainCopy(vmService.remoteSummary, {}) : {}
      }
    }
    snapshotWritePending = true
    snapshotFile.setText(JSON.stringify(payload) + "\n")
  }

  function applyDetection(raw, success, requestTarget) {
    if (!sourceEnabled || requestTarget !== target) return
    var detectedTarget = ""
    var detectedScreens = []
    if (success) {
      try {
        var result = JSON.parse(String(raw || ""))
        if (result.eligible === true && Array.isArray(result.screens)) {
          detectedTarget = String(result.sshTarget || "")
          detectedScreens = result.screens.map(function(screen) { return String(screen || "") }).filter(Boolean)
        }
      } catch (_) {
        detectedTarget = ""
        detectedScreens = []
      }
    }
    var connectionChanged = connectionTarget !== detectedTarget
    connectionTarget = detectedTarget
    var screensChanged = detectedScreens.length !== eligibleScreens.length
    if (!screensChanged) {
      for (var i = 0; i < detectedScreens.length; i++) {
        if (detectedScreens[i] !== eligibleScreens[i]) {
          screensChanged = true
          break
        }
      }
    }
    if (screensChanged) {
      var nextOverrides = ({})
      for (var j = 0; j < detectedScreens.length; j++) {
        var screen = detectedScreens[j]
        if (localOverrides[screen] === true) nextOverrides[screen] = true
      }
      eligibleScreens = detectedScreens
      localOverrides = nextOverrides
      modeRevision++
    }
    if (anyRemoteSelected && (screensChanged || connectionChanged)) fetchNow()
    if (!eligible) lastError = ""
  }

  function fetchNow() {
    if (!sourceEnabled || !anyRemoteSelected || fetchProcess.running) return
    if (connectionTarget === "") return
    fetchProcess.requestTarget = connectionTarget
    fetchProcess.requestHost = target
    fetchProcess.command = ["desktop-remote-bar", "fetch", connectionTarget]
    fetchProcess.running = true
  }

  function detectNow() {
    if (!sourceEnabled) return
    if (detectProcess.running) {
      detectQueued = true
      return
    }
    detectProcess.requestTarget = target
    detectProcess.command = ["desktop-remote-bar", "detect", target]
    detectProcess.running = true
  }

  function screenEligible(screenName) {
    var revision = modeRevision
    return eligibleScreens.indexOf(String(screenName || "")) !== -1
  }

  function screenRemoteSelected(screenName) {
    var screen = String(screenName || "")
    return screenEligible(screen) && localOverrides[screen] !== true
  }

  function setRemoteSelected(screenName, selected) {
    var screen = String(screenName || "")
    if (!screenEligible(screen)) return
    var next = Object.assign({}, localOverrides)
    if (selected === true) delete next[screen]
    else next[screen] = true
    localOverrides = next
    modeRevision++
    if (selected === true) fetchNow()
  }

  function modeTooltip(screenName) {
    var selected = screenRemoteSelected(screenName)
    var host = selected ? target : (sourceHost !== "" ? sourceHost : "local computer")
    var lines = [host]
    if (selected && health !== "fresh") {
      lines.push(health === "stale" ? "Remote data is stale" : "Remote data is offline")
      if (snapshotAgeSeconds >= 0) lines.push("Snapshot age: " + snapshotAgeSeconds + "s")
      if (lastError !== "") lines.push(lastError)
    }
    return lines.join("\n")
  }

  onPublisherEnabledChanged: {
    if (publisherActive) publishDirectoryProcess.running = true
  }
  onPublisherActiveChanged: {
    if (publisherActive && !publishDirectoryReady) publishDirectoryProcess.running = true
  }
  onTargetChanged: {
    snapshot = null
    snapshotReceivedAt = 0
    connectionTarget = ""
    detectQueued = false
    lastError = ""
    eligibleScreens = []
    localOverrides = ({})
    modeRevision++
    if (!sourceEnabled) {
      return
    } else detectNow()
  }

  Component.onCompleted: {
    if (publisherActive) publishDirectoryProcess.running = true
    detectNow()
  }

  property FileView snapshotFile: FileView {
    path: root.snapshotPath
    atomicWrites: true
    blockWrites: false
    printErrors: false
    onSaved: {
      root.snapshotWritePending = false
      root.publishError = ""
      if (root.snapshotWriteQueued) {
        root.snapshotWriteQueued = false
        Qt.callLater(root.publishSnapshot)
      }
    }
    onSaveFailed: function(error) {
      root.snapshotWritePending = false
      root.snapshotWriteQueued = false
      root.publishDirectoryReady = false
      root.publishError = String(error || "Remote snapshot write failed")
    }
  }

  property Process publishDirectoryProcess: Process {
    command: ["mkdir", "-p", root.snapshotDirectory]
    onExited: function(exitCode) {
      root.publishDirectoryReady = Number(exitCode) === 0
      if (root.publishDirectoryReady) root.publishSnapshot()
    }
  }

  property Timer publishTimer: Timer {
    interval: 10000
    running: root.publisherActive
    repeat: true
    onTriggered: {
      if (!root.publishDirectoryReady) {
        if (!root.publishDirectoryProcess.running) root.publishDirectoryProcess.running = true
        return
      }
      root.publishSnapshot()
    }
  }

  property Process detectProcess: Process {
    property string requestTarget: ""
    stdout: StdioCollector {
      id: detectStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.applyDetection(detectStdout.text, Number(exitCode) === 0, requestTarget)
      if (root.detectQueued) {
        root.detectQueued = false
        Qt.callLater(root.detectNow)
      }
    }
  }

  property Connections hyprlandEvents: Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event.name || "")
      if (name === "workspace" || name === "workspacev2"
          || name === "focusedmon" || name === "focusedmonv2"
          || name === "moveworkspace" || name === "moveworkspacev2"
          || name === "openwindow" || name === "closewindow"
          || name === "movewindow" || name === "movewindowv2") root.detectNow()
    }
  }

  property Timer detectTimer: Timer {
    interval: 30000
    running: root.sourceEnabled
    repeat: true
    onTriggered: root.detectNow()
  }

  property Process fetchProcess: Process {
    property string requestTarget: ""
    property string requestHost: ""
    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: fetchStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (!root.sourceEnabled || requestTarget !== root.connectionTarget || requestHost !== root.target) return
      if (Number(exitCode) !== 0) {
        root.lastError = String(fetchStderr.text || "Remote snapshot read failed").trim().slice(0, 240)
        return
      }
      var parsed = RemoteBarModel.parseSnapshot(fetchStdout.text, requestHost)
      if (!parsed) {
        root.lastError = "Remote snapshot is invalid"
        return
      }
      root.snapshot = parsed
      root.snapshotReceivedAt = Math.floor(Date.now() / 1000)
      root.lastError = ""
      root.nowSeconds = Math.floor(Date.now() / 1000)
    }
  }

  property Timer fetchTimer: Timer {
    interval: 10000
    running: root.sourceEnabled && root.anyRemoteSelected
    repeat: true
    onTriggered: root.fetchNow()
  }

  property Timer clockTimer: Timer {
    interval: 1000
    running: root.sourceEnabled && root.eligible
    repeat: true
    onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
  }
}
