import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/agents" as Agents

Item {
  id: root

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || ""
  readonly property string statusModePath: Quickshell.env("AGENTS_FIXTURE_STATUS_MODE") || ""
  readonly property string statusLogPath: Quickshell.env("AGENTS_FIXTURE_STATUS_LOG") || ""
  readonly property string statusOldReleasePath: Quickshell.env("AGENTS_FIXTURE_STATUS_OLD_RELEASE") || ""
  readonly property string statusNewReleasePath: Quickshell.env("AGENTS_FIXTURE_STATUS_NEW_RELEASE") || ""
  readonly property string statusOldEnteredPath: Quickshell.env("AGENTS_FIXTURE_STATUS_OLD_ENTERED") || ""
  readonly property string statusNewReadPath: Quickshell.env("AGENTS_FIXTURE_STATUS_NEW_READ") || ""
  readonly property string updateLogPath: Quickshell.env("AGENTS_FIXTURE_UPDATE_LOG") || ""
  readonly property string activePath: Quickshell.env("AGENTS_FIXTURE_UPDATE_ACTIVE") || ""
  readonly property string overlapPath: Quickshell.env("AGENTS_FIXTURE_UPDATE_OVERLAP") || ""
  readonly property string normalReleasePath: Quickshell.env("AGENTS_FIXTURE_NORMAL_RELEASE") || ""
  readonly property string forceReleasePath: Quickshell.env("AGENTS_FIXTURE_FORCE_RELEASE") || ""
  readonly property string recordDir: root.stateHome + "/desktop-shell/agents/usage"
  readonly property string fakeStatus: Qt.resolvedUrl("tests/fixtures/agents/fake-status")
    .toString().replace("file://", "")
  readonly property string fakeUpdate: Qt.resolvedUrl("tests/fixtures/agents/fake-update")
    .toString().replace("file://", "")

  property var secondConsumer: null
  property int phase: 0
  property int checks: 0
  property int stableUpdateCount: 0
  property int stableStatusCount: 0
  property string statusLogText: ""
  property string statusOldEnteredText: ""
  property string statusNewReadText: ""
  property string updateLogText: ""
  property string overlapText: ""
  property string codexRecordText: ""
  property string claudeRecordText: ""
  property bool statusOldModeSaved: false

  QtObject {
    id: fakeShell
    property bool previewMode: false

    function widgetSettingsFor(pluginId) {
      return String(pluginId) === "desktop.agents" ? ({
        refreshIntervalSec: 3600,
        providers: {
          codex: { enabled: true },
          claude: { enabled: false }
        }
      }) : ({})
    }
  }

  Agents.Service {
    id: service
    shell: fakeShell
    manifest: ({ id: "desktop.agents" })
    compactExecutable: root.fakeStatus
    updateExecutable: root.fakeUpdate
    compactProvider: "codex"
    limitsRetryInterval: 100
  }

  ServiceConsumer {
    id: firstConsumer
    service: service
    active: true
    details: false
  }

  Component {
    id: consumerComponent
    ServiceConsumer { }
  }

  QtObject {
    id: firstView
    readonly property var providers: service.enabledProviders
  }

  QtObject {
    id: secondView
    readonly property var providers: service.enabledProviders
  }

  FileView {
    id: statusModeFile
    path: root.statusModePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: statusLogFile
    path: root.statusLogPath
    preload: true
    blockWrites: true
    printErrors: false
    onLoaded: root.statusLogText = text()
    onLoadFailed: root.statusLogText = ""
    onFileChanged: reload()
  }

  FileView {
    id: updateLogFile
    path: root.updateLogPath
    preload: true
    blockWrites: true
    printErrors: false
    onLoaded: root.updateLogText = text()
    onLoadFailed: root.updateLogText = ""
    onFileChanged: reload()
  }

  FileView {
    id: overlapFile
    path: root.overlapPath
    preload: true
    blockWrites: true
    printErrors: false
    onLoaded: root.overlapText = text()
    onLoadFailed: root.overlapText = ""
    onFileChanged: reload()
  }

  FileView {
    id: codexRecordFile
    path: root.recordDir + "/codex.json"
    preload: true
    watchChanges: true
    blockWrites: false
    printErrors: false
    onLoaded: root.codexRecordText = text()
    onLoadFailed: root.codexRecordText = ""
    onFileChanged: reload()
  }

  FileView {
    id: claudeRecordFile
    path: root.recordDir + "/claude.json"
    preload: true
    watchChanges: true
    blockWrites: false
    printErrors: false
    onLoaded: root.claudeRecordText = text()
    onLoadFailed: root.claudeRecordText = ""
    onFileChanged: reload()
  }

  FileView {
    id: statusOldEnteredFile
    path: root.statusOldEnteredPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.statusOldEnteredText = text()
    onLoadFailed: root.statusOldEnteredText = ""
    onFileChanged: reload()
  }

  FileView {
    id: statusNewReadFile
    path: root.statusNewReadPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.statusNewReadText = text()
    onLoadFailed: root.statusNewReadText = ""
    onFileChanged: reload()
  }

  FileView {
    id: codexRecordWriter
    path: root.recordDir + "/codex.json"
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: claudeRecordWriter
    path: root.recordDir + "/claude.json"
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: normalReleaseFile
    path: root.normalReleasePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: forceReleaseFile
    path: root.forceReleasePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: statusOldReleaseFile
    path: root.statusOldReleasePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: statusNewReleaseFile
    path: root.statusNewReleasePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: statusOldModeFile
    path: root.statusModePath
    preload: false
    atomicWrites: true
    blockWrites: false
    printErrors: false
    onSaved: root.statusOldModeSaved = true
    onSaveFailed: function(error) { root.fail("old status mode write failed: " + String(error || "")) }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      root.advance()
      if (root.checks >= 450) {
        console.error("Agents service fixture timed out", root.phase,
          service.consumerCount, service.collecting, service.detailed,
          service.enabledProviders.length, root.updateLogText, root.statusLogText)
        Qt.exit(1)
      }
    }
  }

  function lines(text) {
    return String(text || "").split("\n").filter(function(line) { return line !== "" })
  }

  function hasProvider(list, id, updatedAt) {
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].providerId === id && String(list[i].updatedAt) === updatedAt) return true
    }
    return false
  }

  function recordJson(id, updatedAt, retryAdvised) {
    return JSON.stringify({
      id: id,
      name: id === "codex" ? "Codex" : "Claude",
      ready: true,
      stale: false,
      updatedAt: updatedAt,
      retryAdvised: retryAdvised
    }) + "\n"
  }

  function recordHasUpdatedAt(raw, updatedAt) {
    try {
      return JSON.parse(String(raw || "")).updatedAt === updatedAt
    } catch (_) {
      return false
    }
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  function fail(message) {
    console.error("agents-service-runtime-test: " + String(message))
    Qt.exit(1)
  }

  function finish() {
    check(lines(root.updateLogText).length === root.stableUpdateCount,
      "no updates are launched after the detail demand ends")
    check(lines(root.statusLogText).length >= root.stableStatusCount,
      "compact polling remains safe after rebind")
    overlapFile.reload()
    check(root.overlapText === "", "fake update workers do not overlap")
    check(!service.updateRunning, "fake update worker is not still running")
    console.log("Agents shared lifecycle fixture passed", lines(root.updateLogText).length,
      lines(root.statusLogText).length, service.enabledProviders.length)
    Qt.exit(0)
  }

  function advance() {
    try {
      if (!firstConsumer.ready) return
      statusLogFile.reload()
      updateLogFile.reload()
      overlapFile.reload()
      var statusLines = lines(root.statusLogText)
      var updateLines = lines(root.updateLogText)

      if (root.phase === 0) {
        check(service.collecting, "baseline consumer starts record collection")
        if (service.enabledProviders.length !== 1 || service.compactText !== "AI") return
        check(hasProvider(service.enabledProviders, "codex", "initial-codex"),
          "enabled provider is observed")
        check(!hasProvider(service.enabledProviders, "claude", "initial-claude"),
          "disabled provider is filtered from data")
        check(service.retryAgentIds.length === 1 && service.retryAgentIds[0] === "codex",
          "automatic limits retry is restricted to the enabled provider")
        check(updateLines.length === 0, "baseline collection does not start detail updates")
        check(service.remoteSummary.available && service.remoteSummary.text === "AI",
          "compact summary is published from the service")
        root.secondConsumer = consumerComponent.createObject(root, {
          service: service,
          active: true,
          details: false
        })
        check(root.secondConsumer !== null, "second consumer is created")
        root.phase = 1
        return
      }

      if (root.phase === 1) {
        if (!root.secondConsumer.ready || service.consumerCount !== 2) return
        check(updateLines.length === 0, "adding a baseline consumer does not query details")
        check(root.overlapText === "", "adding a consumer does not overlap update workers")
        firstConsumer.details = true
        root.secondConsumer.details = true
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (updateLines.length < 1) return
        check(updateLines[0] === "request=", "detail demand starts one normal update")
        service.refreshLimits()
        service.refreshAll(true)
        firstConsumer.active = false
        check(service.detailed, "remaining detailed consumer keeps updates enabled")
        normalReleaseFile.setText("release\n")
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        if (updateLines.length < 2) return
        check(updateLines[1] === "request=--force", "forced refresh has pending priority")
        service.refreshLimits()
        forceReleaseFile.setText("release\n")
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        if (updateLines.length < 3) return
        check(updateLines[2] === "request=--limits-only",
          "public limits refresh queries all providers")
        if (!hasProvider(firstView.providers, "codex", "latest-codex")
            || !hasProvider(secondView.providers, "codex", "latest-codex")
            || !recordHasUpdatedAt(root.claudeRecordText, "latest-claude")) return
        check(service.enabledProviders.length === 1, "disabled provider remains filtered after refresh")
        check(secondView.providers.length === 1, "shared provider data remains filtered in the second view")
        claudeRecordWriter.setText(root.recordJson("claude", "before-auto-claude", true))
        root.phase = 41
        return
      }

      if (root.phase === 41) {
        if (updateLines.length < 4) return
        check(updateLines[3] === "request=--limits-only codex",
          "automatic limits retry keeps its provider restriction")
        if (!recordHasUpdatedAt(root.claudeRecordText, "before-auto-claude")) return
        check(service.enabledProviders.length === 1, "automatic retry does not expose disabled data")
        forceReleaseFile.setText("wait\n")
        service.refreshAll(true)
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (updateLines.length < 5) return
        check(updateLines[4] === "request=--force", "second forced refresh starts")
        service.refreshLimits()
        root.secondConsumer.details = false
        check(!service.detailed && service.collecting,
          "last detail release leaves baseline collection running")
        statusModeFile.setText("invalid\n")
        service.refresh()
        forceReleaseFile.setText("release\n")
        root.phase = 6
        return
      }

      if (root.phase === 6) {
        if (updateLines.length < 5 || service.updateRunning) return
        if (statusLines.length < 2 || service.compactText !== "AI") return
        check(updateLines.length === 5, "queued limits update stops with the last detail consumer")
        root.stableUpdateCount = updateLines.length
        root.stableStatusCount = statusLines.length
        var removed = root.secondConsumer
        root.secondConsumer = null
        removed.destroy()
        root.phase = 7
        return
      }

      if (root.phase === 7) {
        if (service.consumerCount !== 0 || service.collecting) return
        check(service.enabledProviders.length === 1,
          "cached provider records survive collection shutdown")
        check(hasProvider(service.enabledProviders, "codex", "latest-codex"),
          "last-good enabled record is cached")
        codexRecordWriter.setText("{}\n")
        claudeRecordWriter.setText(root.recordJson("claude", "restart-claude", false))
        root.statusOldModeSaved = false
        root.statusOldEnteredText = ""
        statusOldModeFile.setText("hold-old\n")
        statusOldReleaseFile.setText("wait\n")
        statusNewReleaseFile.setText("wait\n")
        root.phase = 70
        return
      }

      if (root.phase === 70) {
        if (!root.statusOldModeSaved) return
        firstConsumer.details = false
        firstConsumer.service = null
        firstConsumer.service = service
        firstConsumer.active = true
        root.phase = 71
        return
      }

      if (root.phase === 71) {
        if (statusLines.length < root.stableStatusCount + 1
            || String(root.statusOldEnteredText).trim() !== "old-blocked") return
        check(service.compactText === "AI", "old compact sample is blocked before restart")
        firstConsumer.active = false
        firstConsumer.service = null
        root.phase = 72
        return
      }

      if (root.phase === 72) {
        if (service.consumerCount !== 0 || service.collecting) return
        check(!service.compactRunning, "last consumer cancels the held compact query")
        statusModeFile.setText("hold-new\n")
        firstConsumer.service = service
        firstConsumer.active = true
        statusOldReleaseFile.setText("release\n")
        root.phase = 8
        return
      }

      if (root.phase === 8) {
        if (service.consumerCount !== 1 || !service.collecting || service.detailed) return
        if (statusLines.length < root.stableStatusCount + 2 || !service.compactRunning) return
        check(service.compactText === "AI", "stale compact callback is ignored after restart")
        check(hasProvider(service.enabledProviders, "codex", "latest-codex"),
          "malformed restart record does not replace last-good cache")
        codexRecordWriter.setText(root.recordJson("codex", "restart-codex", true))
        root.phase = 9
        return
      }

      if (root.phase === 9) {
        if (!hasProvider(service.enabledProviders, "codex", "restart-codex")) return
        statusNewReleaseFile.setText("release\n")
        root.phase = 10
        return
      }

      if (root.phase === 10) {
        if (service.compactRunning || String(root.statusNewReadText).trim() !== "new-read") return
        check(statusLines.length === root.stableStatusCount + 2,
          "restart starts exactly one fresh compact read")
        check(service.compactText === "AI", "fresh compact sample is published after restart")
        check(service.enabledProviders.length === 1
            && hasProvider(service.enabledProviders, "codex", "restart-codex"),
          "restart publishes the fresh valid record")
        check(service.consumerCount === 1 && service.collecting && !service.detailed,
          "consumer rebind restarts baseline collection without detail demand")
        finish()
      }
    } catch (error) {
      fail(error && error.message ? error.message : error)
    }
  }
}
