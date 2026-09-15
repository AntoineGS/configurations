import QtQuick
import Quickshell.Io
import qs.Commons

SharedService {
  id: root

  property string updateExecutable: "desktop-agent-usage-update"
  property string compactExecutable: "desktop-shell-status"
  // The provider polled when the widget entry names none. The `compactProviders`
  // setting extends the bar text with more adapters, in the order listed.
  property string compactProvider: "codex"
  readonly property var compactProviders: {
    var configured = root.settings ? root.settings.compactProviders : undefined
    var result = []
    if (Array.isArray(configured)) {
      for (var i = 0; i < configured.length; i++) {
        var id = String(configured[i] || "")
        if (id !== "" && result.indexOf(id) === -1) result.push(id)
      }
    }
    return result.length > 0 ? result : [root.compactProvider]
  }
  readonly property string compactProvidersKey: JSON.stringify(compactProviders)
  // Last accepted status per provider: { text, tooltip, muted }. Kept across
  // collection stops so a rebind shows the last-good text immediately.
  property var compactResults: ({})
  readonly property string compactText: {
    var parts = []
    for (var i = 0; i < root.compactProviders.length; i++) {
      var result = root.compactResults[root.compactProviders[i]]
      if (result && result.text !== "") parts.push(result.text)
    }
    return parts.join(" · ")
  }
  readonly property string compactTooltip: {
    var parts = []
    for (var i = 0; i < root.compactProviders.length; i++) {
      var result = root.compactResults[root.compactProviders[i]]
      if (result && result.tooltip !== "") parts.push(result.tooltip)
    }
    return parts.join("\n\n")
  }
  readonly property bool compactMuted: {
    var seen = false
    for (var i = 0; i < root.compactProviders.length; i++) {
      var result = root.compactResults[root.compactProviders[i]]
      if (!result || result.text === "") continue
      seen = true
      if (!result.muted) return false
    }
    return seen
  }
  property bool compactQueued: false
  property int compactGeneration: 0
  property alias limitsRetryInterval: usage.limitsRetryInterval

  readonly property var enabledProviders: usage.enabledProviders
  readonly property string displayText: root.compactText !== ""
    ? root.compactText : (root.enabledProviders.length > 0 ? "󱚣" : "")
  readonly property var remoteSummary: ({
    available: root.displayText !== "",
    text: root.displayText,
    tooltip: root.compactTooltip,
    muted: root.compactMuted
  })
  readonly property bool updateRunning: usage.updateRunning
  readonly property bool compactRunning: compactWorkers.length > 0
  readonly property var retryAgentIds: usage.retryAgentIds
  property var compactWorkers: []

  function compactClassHas(value, expected) {
    if (Array.isArray(value)) return value.indexOf(expected) !== -1
    return String(value || "") === expected
  }

  function applyCompactStatus(provider, raw) {
    var data = Util.parseModuleJson(raw)
    if (!Util.isPlainObject(data) || typeof data.text !== "string" || typeof data.tooltip !== "string") return false
    var next = Object.assign({}, root.compactResults)
    next[provider] = {
      text: data.text,
      tooltip: data.tooltip,
      muted: compactClassHas(data.class !== undefined ? data.class : data.alt, "muted")
    }
    root.compactResults = next
    return true
  }

  function refreshCompactStatus() {
    if (!root.collecting) return false
    if (root.compactWorkers.length > 0) {
      compactQueued = true
      return true
    }
    compactGeneration++
    var started = []
    for (var i = 0; i < root.compactProviders.length; i++) {
      var worker = compactComponent.createObject(root, {
        generation: compactGeneration,
        provider: root.compactProviders[i]
      })
      if (worker) started.push(worker)
    }
    if (started.length === 0) return false
    root.compactWorkers = started
    for (var j = 0; j < started.length; j++) started[j].running = true
    return true
  }

  function destroyCompactWorker(worker) {
    if (!worker) return
    worker.running = false
    var staleWorker = worker
    Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
  }

  function destroyCompactWorkers() {
    root.compactGeneration++
    root.compactQueued = false
    var oldWorkers = root.compactWorkers
    root.compactWorkers = []
    for (var i = 0; i < oldWorkers.length; i++) root.destroyCompactWorker(oldWorkers[i])
  }

  function finishCompact(worker, exitCode, raw) {
    if (root.compactWorkers.indexOf(worker) === -1 || worker.generation !== root.compactGeneration) {
      root.destroyCompactWorker(worker)
      return
    }

    if (root.collecting && Number(exitCode) === 0)
      root.applyCompactStatus(worker.provider, raw)

    root.compactWorkers = root.compactWorkers.filter(function(entry) { return entry !== worker })
    root.destroyCompactWorker(worker)
    if (root.compactWorkers.length > 0) return

    var queued = root.compactQueued
    root.compactQueued = false
    if (queued && root.collecting) Qt.callLater(root.refreshCompactStatus)
  }

  function refresh() {
    var compactStarted = root.refreshCompactStatus()
    var updateStarted = root.collecting && root.detailed ? usage.refresh() : false
    return compactStarted || updateStarted
  }

  function refreshLimits() {
    return root.collecting && root.detailed ? usage.refreshLimits() : false
  }

  function refreshAll(force) {
    return root.collecting && root.detailed ? usage.refreshAll(force) : false
  }

  function formatTokenCount(value) { return usage.formatTokenCount(value) }
  function friendlyModelName(id) { return usage.friendlyModelName(id) }

  Main {
    id: usage
    settings: root.settings
    updateExecutable: root.updateExecutable
    collecting: root.collecting
    loaded: root.collecting && root.detailed
  }

  Timer {
    interval: 300000
    running: root.collecting
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshCompactStatus()
  }

  onDetailedChanged: {
    if (!root.detailed) usage.cancelQueuedUpdate()
  }

  onCollectingChanged: {
    if (!root.collecting) root.destroyCompactWorkers()
  }

  // A provider list change (settings edit) drops text for providers no longer
  // shown and polls the new set right away.
  onCompactProvidersKeyChanged: {
    root.destroyCompactWorkers()
    if (root.collecting) Qt.callLater(root.refreshCompactStatus)
  }

  Component.onDestruction: root.destroyCompactWorkers()

  Component {
    id: compactComponent

    Process {
      id: process
      property int generation: 0
      property string provider: ""
      command: [root.compactExecutable, provider]
      stdout: StdioCollector {
        id: compactStdout
        waitForEnd: true
      }
      stderr: StdioCollector {
        waitForEnd: true
        onStreamFinished: if (text.trim() !== "") console.warn("agents", text.trim())
      }
      onExited: function(exitCode) {
        root.finishCompact(process, Number(exitCode), compactStdout.text || "")
      }
    }
  }
}
