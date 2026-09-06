import QtQuick
import Quickshell.Io
import qs.Commons

SharedService {
  id: root

  property string updateExecutable: "desktop-agent-usage-update"
  property string compactExecutable: "desktop-shell-status"
  property string compactProvider: "codex"
  property string compactText: ""
  property string compactTooltip: ""
  property bool compactMuted: false
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
  readonly property bool compactRunning: !!compactWorker && compactWorker.running
  readonly property var retryAgentIds: usage.retryAgentIds
  property var compactWorker: null

  function compactClassHas(value, expected) {
    if (Array.isArray(value)) return value.indexOf(expected) !== -1
    return String(value || "") === expected
  }

  function applyCompactStatus(raw) {
    var data = Util.parseModuleJson(raw)
    if (!Util.isPlainObject(data) || typeof data.text !== "string" || typeof data.tooltip !== "string") return false
    compactText = data.text
    compactTooltip = data.tooltip
    compactMuted = compactClassHas(data.class !== undefined ? data.class : data.alt, "muted")
    return true
  }

  function refreshCompactStatus() {
    if (!root.collecting) return false
    if (root.compactWorker) {
      compactQueued = true
      return true
    }
    compactGeneration++
    var worker = compactComponent.createObject(root, { generation: compactGeneration })
    if (!worker) return false
    root.compactWorker = worker
    worker.running = true
    return true
  }

  function destroyCompactWorker(worker) {
    if (!worker) return
    worker.running = false
    var staleWorker = worker
    Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
  }

  function finishCompact(worker, exitCode, raw) {
    if (worker !== root.compactWorker || worker.generation !== root.compactGeneration) {
      root.destroyCompactWorker(worker)
      return
    }

    if (root.collecting && Number(exitCode) === 0)
      root.applyCompactStatus(raw)

    var queued = root.compactQueued
    root.compactQueued = false
    root.compactWorker = null
    root.destroyCompactWorker(worker)
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
    if (!root.collecting) {
      root.compactGeneration++
      root.compactQueued = false
      var oldCompactWorker = root.compactWorker
      root.compactWorker = null
      root.destroyCompactWorker(oldCompactWorker)
    }
  }

  Component.onDestruction: {
    root.compactQueued = false
    root.compactGeneration++
    var oldCompactWorker = root.compactWorker
    root.compactWorker = null
    root.destroyCompactWorker(oldCompactWorker)
  }

  Component {
    id: compactComponent

    Process {
      id: process
      property int generation: 0
      command: [root.compactExecutable, root.compactProvider]
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
