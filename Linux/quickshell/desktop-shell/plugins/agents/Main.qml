import QtQuick
import Quickshell
import Quickshell.Io

// The panel reads two repository-owned records. Provider credentials and all
// provider-specific parsing remain in the shell helpers.
Item {
  id: root
  visible: false

  property var settings: ({})
  property bool loaded: true
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/desktop-shell/agents/usage"
  readonly property var agentIds: ["codex", "claude"]

  property var agents: []
  property int dataRevision: 0
  property var retryAgentIds: []
  property string pendingUpdateKind: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function rebuildAgents() {
    var result = []
    for (var i = 0; i < agentInstantiator.count; i++) {
      var agent = agentInstantiator.objectAt(i)
      if (agent) result.push(agent)
    }
    agents = result
    recordsChanged()
  }

  function recordsChanged() {
    dataRevision++
    scheduleLimitsRetry()
  }

  function scheduleLimitsRetry() {
    var advising = []
    for (var i = 0; i < agents.length; i++) {
      var record = agents[i] ? agents[i].record : null
      if (record && record.retryAdvised === true && providerEnabled(String(record.id || "")))
        advising.push(String(record.id))
    }
    retryAgentIds = advising
    if (advising.length > 0) limitsRetry.restart()
    else limitsRetry.stop()
  }

  function providerEnabled(id) {
    if (id !== "codex" && id !== "claude") return false
    if (!settings || !settings.providers || !settings.providers[id]) return true
    return settings.providers[id].enabled !== false
  }

  function numberValue(value) {
    var n = Number(value || 0)
    return isFinite(n) ? Math.round(n) : 0
  }

  function providerHasData(record) {
    if (!record || !providerEnabled(String(record.id || ""))) return false
    return true
  }

  function displayProvider(record) {
    return {
      providerId: String(record.id),
      providerName: String(record.name || record.id),
      ready: record.ready === true,
      stale: record.stale === true,
      error: String(record.error || ""),
      updatedAt: String(record.updatedAt || ""),
      usageStatusText: String(record.usageStatusText || ""),
      authHelpText: String(record.authHelpText || ""),
      limits: Array.isArray(record.limits) ? record.limits : [],
      tierLabel: String(record.tierLabel || ""),
      dailyUsage: Array.isArray(record.dailyUsage) ? record.dailyUsage : [],
      todayPrompts: numberValue(record.todayPrompts),
      todaySessions: numberValue(record.todaySessions),
      todayTotalTokens: numberValue(record.todayTotalTokens),
      todayTokensByModel: record.todayTokensByModel || ({}),
      totalPrompts: numberValue(record.totalPrompts),
      totalSessions: numberValue(record.totalSessions),
      activeDays: numberValue(record.activeDays),
      modelUsage: record.modelUsage || ({})
    }
  }

  readonly property var enabledProviders: {
    var revision = dataRevision
    var result = []
    for (var i = 0; i < agents.length; i++) {
      var record = agents[i] ? agents[i].record : null
      if (providerHasData(record)) result.push(displayProvider(record))
    }
    return result
  }

  Instantiator {
    id: agentInstantiator
    model: root.agentIds

    delegate: Agent {
      required property string modelData
      agentId: modelData
      path: root.usageDir + "/" + modelData + ".json"
      onRecordChanged: root.recordsChanged()
    }

    onObjectAdded: root.rebuildAgents()
    onObjectRemoved: root.rebuildAgents()
  }

  Timer {
    id: limitsRetry
    interval: 30000
    repeat: false
    running: root.loaded
    onTriggered: root.runUpdate("limits", root.retryAgentIds)
  }

  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 900)))

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.loaded
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runUpdate("normal")
  }

  Process {
    id: updateProcess
    running: false

    onExited: {
      if (root.pendingUpdateKind !== "") {
        var kind = root.pendingUpdateKind
        root.pendingUpdateKind = ""
        root.runUpdate(kind)
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("agents", text.trim())
    }
  }

  function updateCommand(kind, providerIds) {
    var command = ["desktop-agent-usage-update"]
    if (kind === "force") command.push("--force")
    if (kind === "limits") command.push("--limits-only")
    if (providerIds) {
      for (var i = 0; i < providerIds.length; i++) command.push(providerIds[i])
    }
    return command
  }

  function runUpdate(kind, providerIds) {
    if (!root.loaded) return
    if (updateProcess.running) {
      if (kind === "force" || root.pendingUpdateKind === "") root.pendingUpdateKind = kind
      return
    }
    updateProcess.command = updateCommand(kind, providerIds)
    updateProcess.running = true
  }

  function refresh() { refreshAll(true) }
  function refreshAll(force) { runUpdate(force === true ? "force" : "normal") }
  function refreshLimits() { runUpdate("limits") }

  function formatTokenCount(value) {
    var n = numberValue(value)
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(n)
  }

  function modelWordCase(word) {
    if (word === "gpt") return "GPT"
    if (word === "deepseek") return "DeepSeek"
    return word.charAt(0).toUpperCase() + word.slice(1)
  }

  function friendlyModelName(id) {
    if (!id) return "Unknown"
    var name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "")
    var parts = name.split("-")
    var words = []
    var version = []
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i]
      if (part === "") continue
      if (/^\d/.test(part)) {
        version.push(part)
        continue
      }
      if (version.length > 0) {
        words.push(version.join("."))
        version = []
      }
      words.push(modelWordCase(part))
    }
    if (version.length > 0) words.push(version.join("."))
    return words.length > 0 ? words.join(" ") : "Unknown"
  }

  Component.onDestruction: {
    loaded = false
    limitsRetry.stop()
  }
}
