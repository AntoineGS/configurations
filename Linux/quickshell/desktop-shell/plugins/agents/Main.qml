import QtQuick
import Quickshell
import Quickshell.Io

// The service reads two repository-owned records. Provider credentials and all
// provider-specific parsing remain in the shell helpers.
Item {
  id: root
  visible: false

  property var settings: ({})
  property bool collecting: false
  property bool loaded: false
  property string updateExecutable: "desktop-agent-usage-update"
  property int limitsRetryInterval: 30000
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/desktop-shell/agents/usage"
  readonly property var agentIds: ["codex", "claude"]

  property var agents: []
  property var cachedRecords: ({})
  property int dataRevision: 0
  property var retryAgentIds: []
  property var pendingUpdate: null
  property int collectionGeneration: 0
  property int updateGeneration: 0
  property bool updateRunning: updateProcess.running

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function rebuildAgents() {
    var result = []
    for (var i = 0; i < agentInstantiator.count; i++) {
      var agent = agentInstantiator.objectAt(i)
      if (agent) {
        result.push(agent)
        cacheRecord(agent)
      }
    }
    agents = result
    recordsChanged()
  }

  function isRecord(value) {
    return !!value && typeof value === "object" && !Array.isArray(value)
  }

  function isValidRecord(agent, value) {
    return !!agent && isRecord(value) && typeof value.id === "string"
      && value.id === String(agent.agentId || "")
  }

  function cacheRecord(agent) {
    if (!root.collecting || !agent || agent.generation !== root.collectionGeneration) return
    if (!isValidRecord(agent, agent.record)) return
    var id = String(agent.agentId)
    var next = Object.assign({}, root.cachedRecords)
    next[id] = agent.record
    root.cachedRecords = next
  }

  function recordChanged(agent) {
    cacheRecord(agent)
    dataRevision++
    scheduleLimitsRetry()
  }

  function recordsChanged() {
    dataRevision++
    scheduleLimitsRetry()
  }

  function scheduleLimitsRetry() {
    var advising = []
    for (var i = 0; i < root.agentIds.length; i++) {
      var id = String(root.agentIds[i])
      var record = recordFor(id)
      if (record && record.retryAdvised === true && providerEnabled(id)) advising.push(id)
    }
    retryAgentIds = advising
    if (advising.length > 0 && root.loaded) limitsRetry.restart()
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

  function recordFor(id) {
    var target = String(id || "")
    for (var i = 0; i < agents.length; i++) {
      var current = agents[i] ? agents[i].record : null
      if (isValidRecord(agents[i], current) && current.id === target) return current
    }
    return cachedRecords[target] || null
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
    for (var i = 0; i < agentIds.length; i++) {
      var record = recordFor(agentIds[i])
      if (providerHasData(record)) result.push(displayProvider(record))
    }
    return result
  }

  Instantiator {
    id: agentInstantiator
    model: root.agentIds
    active: root.collecting

    delegate: Agent {
      id: agent
      required property string modelData
      agentId: modelData
      path: root.usageDir + "/" + modelData + ".json"
      active: root.collecting
      Component.onCompleted: agent.generation = root.collectionGeneration
      onRecordChanged: root.recordChanged(agent)
    }

    onObjectAdded: root.rebuildAgents()
    onObjectRemoved: root.rebuildAgents()
  }

  Timer {
    id: limitsRetry
    interval: root.limitsRetryInterval
    repeat: false
    running: root.loaded === true && root.retryAgentIds.length > 0
    onTriggered: root.runUpdate("limits", root.retryAgentIds.slice())
  }

  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 900)))

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.loaded === true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runUpdate("normal")
  }

  Process {
    id: updateProcess
    running: false
    property var request: null

    onExited: {
      var next = root.pendingUpdate
      root.pendingUpdate = null
      if (next && root.loaded) Qt.callLater(function() {
        if (root.loaded) root.startUpdate(next)
      })
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("agents", text.trim())
    }
  }

  function updateCommand(request) {
    var command = [root.updateExecutable]
    if (request.kind === "force") command.push("--force")
    if (request.kind === "limits") command.push("--limits-only")
    var providerIds = Array.isArray(request.providerIds) ? request.providerIds : []
    if (request.kind === "limits") {
      for (var i = 0; i < providerIds.length; i++) command.push(providerIds[i])
    }
    return command
  }

  function normalizedProviderIds(providerIds) {
    if (!Array.isArray(providerIds)) return []
    var result = []
    for (var i = 0; i < providerIds.length; i++) {
      var id = String(providerIds[i] || "")
      if ((id === "codex" || id === "claude") && result.indexOf(id) === -1) result.push(id)
    }
    return result
  }

  function requestFor(kind, providerIds) {
    var requestKind = kind === "force" || kind === "limits" ? kind : "normal"
    return { kind: requestKind, providerIds: normalizedProviderIds(providerIds) }
  }

  function queueUpdate(request) {
    var current = root.pendingUpdate
    if (!current || request.kind === "force"
        || (current.kind !== "force" && request.kind === "limits"))
      root.pendingUpdate = request
  }

  function startUpdate(request) {
    if (!root.loaded || !request || updateProcess.running) return false
    root.updateGeneration++
    updateProcess.request = request
    updateProcess.command = root.updateCommand(request)
    updateProcess.running = true
    return true
  }

  function cancelQueuedUpdate() {
    pendingUpdate = null
    limitsRetry.stop()
  }

  function runUpdate(kind, providerIds) {
    if (!root.loaded) return false
    var request = requestFor(kind, providerIds)
    if (updateProcess.running) {
      queueUpdate(request)
      return true
    }
    return startUpdate(request)
  }

  function refresh() { return refreshAll(true) }
  function refreshAll(force) { return runUpdate(force === true ? "force" : "normal") }
  function refreshLimits() { return runUpdate("limits") }

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
    collecting = false
    pendingUpdate = null
    limitsRetry.stop()
  }

  onCollectingChanged: {
    collectionGeneration++
    if (!root.collecting) {
      pendingUpdate = null
      limitsRetry.stop()
    }
  }

  onLoadedChanged: {
    if (!root.loaded) {
      pendingUpdate = null
      limitsRetry.stop()
    } else {
      scheduleLimitsRetry()
    }
  }
}
