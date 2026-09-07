import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons

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
  readonly property string sourceHost: config ? String(config.sourceHost || "") : ""
  readonly property var targets: {
    var configured = config && Array.isArray(config.targets) ? config.targets
      : (config && config.target ? [config.target] : [])
    var result = []
    var seen = ({})
    for (var i = 0; i < configured.length; i++) {
      var host = String(configured[i] || "")
      var key = host.toLowerCase()
      if (key !== "" && key !== sourceHost.toLowerCase() && !seen[key]) {
        seen[key] = true
        result.push(host)
      }
    }
    return result
  }
  readonly property string targetsKey: JSON.stringify(targets)
  readonly property bool sourceEnabled: targets.length > 0 && !!shell && !shell.previewMode

  property var detectedScreens: []
  property var sourcesByHost: ({})
  property var localOverrides: ({})
  property int modeRevision: 0
  property string publishError: ""
  property bool publishDirectoryReady: false
  property bool snapshotWritePending: false
  property bool snapshotWriteQueued: false
  property bool detectQueued: false
  property int detectionGeneration: 0

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

  function applyDetection(raw, success, requestGeneration) {
    if (!sourceEnabled || requestGeneration !== detectionGeneration) return
    var nextScreens = []
    if (success) {
      try {
        var result = JSON.parse(String(raw || ""))
        if (Array.isArray(result.screens)) {
          nextScreens = result.screens.filter(function(entry) {
            return entry && typeof entry.screen === "string" && entry.screen !== ""
              && root.targets.indexOf(entry.host) !== -1
              && typeof entry.sshTarget === "string" && entry.sshTarget !== ""
          })
        }
      } catch (_) {
        nextScreens = []
      }
    }
    if (JSON.stringify(nextScreens) === JSON.stringify(detectedScreens)) return
    var nextOverrides = ({})
    for (var i = 0; i < nextScreens.length; i++) {
      var screen = nextScreens[i].screen
      if (localOverrides[screen] === true) nextOverrides[screen] = true
    }
    detectedScreens = nextScreens
    localOverrides = nextOverrides
    modeRevision++
  }

  function connectionForHost(host) {
    // Detection is focus-ranked; one publisher account per host is shared across monitors.
    for (var i = 0; i < detectedScreens.length; i++) {
      var entry = detectedScreens[i]
      if (entry.host === host && localOverrides[entry.screen] !== true) return entry.sshTarget
    }
    return ""
  }

  function detectNow() {
    if (!sourceEnabled) return
    if (detectProcess.running) {
      detectQueued = true
      return
    }
    detectProcess.requestGeneration = detectionGeneration
    detectProcess.command = ["desktop-remote-bar", "detect"].concat(targets)
    detectProcess.running = true
  }

  function screenEligible(screenName) {
    var revision = modeRevision
    return detectedScreens.some(function(entry) { return entry.screen === String(screenName || "") })
  }

  function sourceForScreen(screenName) {
    var revision = modeRevision
    for (var i = 0; i < detectedScreens.length; i++) {
      if (detectedScreens[i].screen === String(screenName || ""))
        return sourcesByHost[detectedScreens[i].host] || null
    }
    return null
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
  }

  function modeTooltip(screenName) {
    var selected = screenRemoteSelected(screenName)
    var source = sourceForScreen(screenName)
    var host = selected && source ? source.host : (sourceHost !== "" ? sourceHost : "local computer")
    var lines = [host]
    if (selected && source && source.health !== "fresh") {
      lines.push(source.health === "stale" ? "Remote data is stale" : "Remote data is offline")
      if (source.snapshotAgeSeconds >= 0) lines.push("Snapshot age: " + source.snapshotAgeSeconds + "s")
      if (source.lastError !== "") lines.push(source.lastError)
    }
    return lines.join("\n")
  }

  onPublisherEnabledChanged: {
    if (publisherActive) publishDirectoryProcess.running = true
  }
  onPublisherActiveChanged: {
    if (publisherActive && !publishDirectoryReady) publishDirectoryProcess.running = true
  }
  onTargetsKeyChanged: {
    detectionGeneration++
    detectQueued = false
    detectedScreens = []
    localOverrides = ({})
    modeRevision++
    Qt.callLater(root.detectNow)
  }
  onSourceEnabledChanged: {
    detectionGeneration++
    if (sourceEnabled) Qt.callLater(root.detectNow)
    else {
      detectedScreens = []
      localOverrides = ({})
      modeRevision++
    }
  }

  Component.onCompleted: {
    if (publisherActive) publishDirectoryProcess.running = true
    detectNow()
  }

  property Instantiator sources: Instantiator {
    model: root.targets
    delegate: RemoteBarSource {
      required property var modelData
      host: String(modelData)
      connectionTarget: root.connectionForHost(host)
      active: root.sourceEnabled && connectionTarget !== ""
    }
    onObjectAdded: function(index, object) {
      var next = Object.assign({}, root.sourcesByHost)
      next[object.host] = object
      root.sourcesByHost = next
      root.modeRevision++
    }
    onObjectRemoved: function(index, object) {
      if (root.sourcesByHost[object.host] !== object) return
      var next = Object.assign({}, root.sourcesByHost)
      delete next[object.host]
      root.sourcesByHost = next
      root.modeRevision++
    }
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
    property int requestGeneration: -1
    stdout: StdioCollector {
      id: detectStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.applyDetection(detectStdout.text, Number(exitCode) === 0, requestGeneration)
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
          || name === "activespecial" || name === "activespecialv2"
          || name === "focusedmon" || name === "focusedmonv2"
          || name === "moveworkspace" || name === "moveworkspacev2"
          || name === "openwindow" || name === "closewindow"
          || name === "windowtitle" || name === "windowtitlev2"
          || name === "activewindow" || name === "activewindowv2" || name === "fullscreen"
          || name === "movewindow" || name === "movewindowv2") root.detectNow()
    }
  }

  property Timer detectTimer: Timer {
    interval: 30000
    running: root.sourceEnabled
    repeat: true
    onTriggered: root.detectNow()
  }
}
