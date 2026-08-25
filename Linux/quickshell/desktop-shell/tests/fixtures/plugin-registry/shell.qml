import QtQuick
import Quickshell
import Quickshell.Io

import "services"
import "services/PluginState.js" as PluginState

ShellRoot {
  id: root

  property string resultPath: Quickshell.env("PLUGIN_REGISTRY_RESULT")
  property string firstPartyRoot: Quickshell.shellDir + "/firstparty"
  property bool rescanChecked: false
  property string changedId: ""
  property string pluginsRoot: Quickshell.env("PLUGIN_REGISTRY_PLUGINS_DIR")
  property string externalReleasePath: Quickshell.env("PLUGIN_REGISTRY_RELEASE_EXTERNAL")
  property string watcherFifoPath: Quickshell.env("PLUGIN_REGISTRY_WATCH_FIFO")
  property bool fifoMode: Quickshell.env("DESKTOP_SHELL_WATCH_FIFO_TEST") === "1"
  property bool watcherLifecycleMode: Quickshell.env("DESKTOP_SHELL_WATCHER_LIFECYCLE_TEST") === "1"
  property string watcherModePath: Quickshell.env("PLUGIN_REGISTRY_WATCHER_MODE")
  property string watcherCountPath: Quickshell.env("PLUGIN_REGISTRY_WATCHER_COUNT")
  property int watcherLifecyclePhase: 0
  property int watchReloadReadyCount: 0
  property int scanFinishedCount: 0
  property var observedVersions: []
  property bool guardAssertionsStarted: false
  property bool finishStarted: false
  property var observedIds: ({})
  property PluginRegistry registry: PluginRegistry { }
  property var state: PluginState.emptyState()
  property var config: ({
    version: 1,
    bar: {
      id: "desktop.bar",
      layout: {
        left: [{ id: "desktop.menu" }],
        center: [{ id: "desktop.clock" }],
        right: [{ id: "desktop.tray" }]
      }
    },
    plugins: [],
    disabledPlugins: []
  })

  FileView {
    id: resultFile
    path: root.resultPath
    atomicWrites: false
    blockWrites: false
    printErrors: false
  }

  Process {
    id: externalReleaseProcess
    command: ["bash", "-c", "touch -- \"$0\"", root.externalReleasePath]
  }

  Process {
    id: swapProcess
  }

  Process {
    id: watcherReadyProcess
    command: ["bash", "-c", "printf 'ready\\n' >\"$0\"", root.watcherModePath]
    onExited: {
      registry.pluginWatchEnabled = true
      registry.initProcess()
      root.watcherLifecyclePhase = 3
    }
  }

  Timer {
    id: firstSwapTimer
    interval: 500
    repeat: false
    running: true
    onTriggered: if (root.fifoMode) root.swapPlugin("2.0.0")
  }


  function manifest(id, kinds, entryPoints, options) {
    var result = {
      schemaVersion: 1,
      id: id,
      name: id,
      version: "1.0.0",
      kinds: kinds,
      entryPoints: entryPoints
    }
    if (options) {
      for (var key in options) result[key] = options[key]
    }
    return result
  }

  function block(kind, source, value) {
    return "===" + kind + "::" + source + "===\n" + JSON.stringify(value) + "\n=== EOM ===\n"
  }

  function fail(message) {
    resultFile.setText(JSON.stringify({ ok: false, error: message }))
    Qt.exit(1)
  }

  function check(condition, message) {
    if (!condition) fail(message)
  }

  function swapPlugin(version) {
    var value = JSON.stringify(manifest("acme.widget", ["bar-widget"], { barWidget: "Widget.qml" }, {
      version: version
    }))
    swapProcess.command = ["bash", "-c",
      "set -e; stage=\"$1/.stage.acme.widget\"; old=\"$1/.old.acme.widget\"; "
      + "rm -rf -- \"$stage\" \"$old\"; mkdir -p -- \"$stage\"; "
      + "printf '%s\\n' \"$4\" >\"$stage/manifest.json\"; "
      + "printf '%s\\n' 'import QtQuick\\nItem {}' >\"$stage/Widget.qml\"; "
      + "mv -- \"$1/acme.widget\" \"$old\"; mv -- \"$stage\" \"$1/acme.widget\"; "
      + "rm -rf -- \"$old\"; printf '%s\\n' \"$2/acme.widget/manifest.json\" >\"$3\"",
      "--", root.pluginsRoot, root.pluginsRoot, root.watcherFifoPath, value]
    swapProcess.running = true
  }

  function finishGuardAssertions() {
    if (root.finishStarted) return
    root.finishStarted = true
    check(root.watchReloadReadyCount >= 2, "queued swaps emit coalesced reloads")
    check(root.observedIds["acme.widget"] && root.observedIds["acme.other"]
      && root.observedIds["acme.late"], "all batched IDs observed")
    check(root.scanFinishedCount === 3, "expected asynchronous scan count")
    check(registry.installedPlugins["acme.widget"] && registry.installedPlugins["acme.other"],
      "restored valid tree installs only valid IDs")
    check(!hasError("acme.widget", "invalid JSON"), "restored tree has no manifest error")
    check(registry.localPluginIdForPath(root.pluginsRoot + "/.stage.acme/manifest.json") === "",
      "hidden staging path produces no plugin ID")
    check(registry.localPluginIdForPath(root.pluginsRoot + "/.rollback.acme/manifest.json") === "",
      "hidden rollback path produces no plugin ID")
    check(registry.localPluginIdForPath(root.pluginsRoot + "/.removed.acme/manifest.json") === "",
      "hidden removal path produces no plugin ID")
    var oldTree = block("thirdparty", root.pluginsRoot + "/acme.swap",
      manifest("acme.swap", ["panel"], { panel: "Panel.qml" }, { version: "1.0.0" }))
    var newTree = block("thirdparty", root.pluginsRoot + "/acme.swap",
      manifest("acme.swap", ["panel"], { panel: "Panel.qml" }, { version: "2.0.0" }))
    var oldGeneration = registry.pluginSourceGeneration
    registry.parseScanOutput(oldTree)
    check(registry.installedPlugins["acme.swap"].version === "1.0.0",
      "atomic watcher observes a complete old manifest")
    registry.parseScanOutput(newTree)
    check(registry.installedPlugins["acme.swap"].version === "2.0.0",
      "second atomic watcher event converges to latest manifest")
    check(registry.pluginSourceGeneration > oldGeneration,
      "plugin source generation advances independently of reload state")
    registry.recordPluginError("desktop.audio", "widget load failed", "widget")
    registry.recordPluginError("desktop.audio", "PipeWire unavailable", "capability:panel:desktop.audio")
    registry.parseScanOutput(block("thirdparty", "/third/scan", manifest("desktop.audio", ["bar-widget", "panel"], {
      barWidget: "Widget.qml", panel: "Panel.qml"
    })) + block("thirdparty", "/third/scan-two", manifest("acme.scan", ["panel"], {
      panel: "Panel.qml"
    })))
    check(hasError("desktop.audio", "widget load failed")
      && hasError("desktop.audio", "PipeWire unavailable"),
      "scan preserves independent load and capability errors")
    registry.clearPluginError("desktop.audio", "capability:panel:desktop.audio")
    check(hasError("desktop.audio", "widget load failed")
      && !hasError("desktop.audio", "PipeWire unavailable"),
      "capability recovery does not clear load errors")
    registry.recordPluginError("acme.scope", "panel load failed", "panel:panel")
    registry.recordPluginError("acme.scope", "capability failed", "capability:panel:acme.scope")
    registry.recordPluginError("acme.scope", "widget load failed", "widget")
    registry.parseScanOutput(block("thirdparty", "/third/scope", manifest("acme.scope", ["bar-widget"], {
      barWidget: "Widget.qml"
    })))
    check(!hasError("acme.scope", "panel load failed")
      && !hasError("acme.scope", "capability failed")
      && hasError("acme.scope", "widget load failed"),
      "scan drops removed kinds while retaining applicable load errors")
    registry.parseScanOutput("")
    check(!hasError("acme.scope", "widget load failed"),
      "scan drops errors for removed plugins")
    resultFile.setText(JSON.stringify({ ok: true }))
    Qt.exit(0)
  }

  function finishFifoAssertions() {
    if (root.finishStarted) return
    root.finishStarted = true
    check(root.observedVersions.length === 3, "FIFO watcher records initial and both complete scans")
    check(root.observedVersions[0] === "1.0.0" && root.observedVersions[1] === "2.0.0"
      && root.observedVersions[2] === "3.0.0", "FIFO watcher observes complete old/new/latest versions")
    check(registry.installedPlugins["acme.widget"].version === "3.0.0",
      "FIFO watcher converges to latest same-parent swap")
    resultFile.setText(JSON.stringify({ ok: true, observedVersions: root.observedVersions }))
    Qt.exit(0)
  }

  function runWatcherLifecycleAssertions() {
    if (root.watcherLifecyclePhase === 0) {
      if (registry.scanning) return
      registry.watcherRetryPending = true
      registry.watcherRetryProcessStopped = false
      registry.watcherRetryElapsed = false
      registry.markWatcherRetryElapsed()
      check(registry.watcherRetryPending && !registry.watcherRetryProcessStopped,
        "elapsed-first retry waits for stopped process")
      registry.markWatcherProcessStopped()
      check(!registry.watcherRetryPending, "elapsed-first retry starts once both conditions hold")
      registry.watcherRetryPending = true
      registry.watcherRetryProcessStopped = false
      registry.watcherRetryElapsed = false
      registry.markWatcherProcessStopped()
      check(registry.watcherRetryPending && !registry.watcherRetryElapsed,
        "stopped-first retry waits for elapsed backoff")
      registry.markWatcherRetryElapsed()
      check(!registry.watcherRetryPending, "stopped-first retry starts once both conditions hold")
      registry.pluginWatchEnabled = true
      registry.watcherRetryLimit = 2
      registry.watcherRetryBaseDelay = 20
      registry.initProcess()
      root.watcherLifecyclePhase = 1
      return
    }
    if (root.watcherLifecyclePhase === 1) {
      if (registry.watcherRetryCount < registry.watcherRetryLimit
          || !registry.watcherUnavailable
          || !hasError("registry", "dependencies are unavailable", "watcher")) return
      registry.pluginWatchEnabled = false
      registry.rescan()
      root.watcherLifecyclePhase = 2
      return
    }
    if (root.watcherLifecyclePhase === 3 && registry.watcherReady) {
      check(!registry.watcherUnavailable && registry.watcherRetryCount === 0,
        "explicit ready clears retry health")
      check(!hasError("registry", "dependencies are unavailable", "watcher"),
        "explicit ready clears watcher error")
      check(registry.watcherProcess.running, "ready watcher remains alive")
      registry.stopWatcher()
      resultFile.setText(JSON.stringify({ ok: true }))
      Qt.exit(0)
    }
  }

  function startGuardAssertions() {
    if (root.guardAssertionsStarted) return
    root.guardAssertionsStarted = true
    registry.pluginsDir = root.pluginsRoot
    registry.handleWatchOutput(root.pluginsRoot + "/acme.widget/manifest.json\n"
      + root.pluginsRoot + "/acme.other/Widget.qml")
    externalReleaseTimer.start()
  }

  function hasError(id, text, scope) {
    for (var i = 0; i < registry.pluginErrors.length; i++) {
      var error = registry.pluginErrors[i]
      if (String(error.id) === id && String(error.error).indexOf(text) !== -1
          && (!scope || String(error.scope) === scope)) return true
    }
    return false
  }

  function run() {
    var scan = ""
    scan += block("firstparty", "/first/bar", manifest("desktop.bar", ["bar"], { bar: "Bar.qml" }))
    scan += block("firstparty", "/first/clock", manifest("desktop.clock", ["bar-widget"], { barWidget: "Widget.qml" }))
    scan += block("firstparty", "/first/menu", manifest("desktop.menu", ["menu"], { menu: "Menu.qml" }))
    scan += block("thirdparty", "/third/panel", manifest("acme.panel", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/widget", manifest("acme.widget", ["bar-widget"], { barWidget: "Widget.qml" }))
    scan += block("thirdparty", "/third/bar", manifest("acme.bar", ["bar"], { bar: "Bar.qml" }))
    scan += block("thirdparty", "/third/desktop-shadow", manifest("desktop.clock", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/omarchy-reserved", manifest("omarchy.fake", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/unsafe", manifest("acme.unsafe", ["panel"], { panel: "../Panel.qml" }))
    scan += block("thirdparty", "/third/malformed", "not-json")
    scan += block("thirdparty", "/third/duplicate-one", manifest("acme.duplicate", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/duplicate-two", manifest("acme.duplicate", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/duplicate-three", manifest("acme.duplicate", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/pair-one", manifest("acme.pair", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/pair-two", manifest("acme.pair", ["panel"], { panel: "Panel.qml" }))

    registry.parseScanOutput(scan)
    check(Object.keys(registry.installedPlugins).length === 6, "valid merged plugin count")
    check(registry.installedPlugins["desktop.bar"].__isFirstParty === true, "first-party provenance")
    check(registry.installedPlugins["acme.panel"].__sourceDir === "/third/panel", "third-party provenance")
    check(registry.installedPlugins["desktop.clock"]
      && registry.installedPlugins["desktop.clock"].__isFirstParty === true,
      "authoritative first-party ID remains installed")
    check(!registry.installedPlugins["omarchy.fake"], "reserved omarchy ID rejected")
    check(!registry.installedPlugins["acme.unsafe"], "unsafe entry point rejected")
    check(!registry.installedPlugins["acme.duplicate"], "ambiguous user plugin rejected")
    check(!registry.installedPlugins["acme.pair"], "two-source user plugin rejected")
    check(hasError("desktop.clock", "invalid plugin id"), "reserved ID error recorded")
    check(hasError("acme.unsafe", "unsafe entryPoint"), "unsafe entry point error recorded")
    check(hasError("acme.duplicate", "/third/duplicate-one")
      && hasError("acme.duplicate", "/third/duplicate-two")
      && hasError("acme.duplicate", "/third/duplicate-three"), "duplicate source paths recorded")
    check(hasError("acme.pair", "/third/pair-one")
      && hasError("acme.pair", "/third/pair-two"), "two duplicate source paths recorded")
    check(registry.isEnabled("desktop.menu") === true, "first-party plugin remains loadable")

    check(registry.pluginWatchEnabled === false, "watcher disabled by test environment")
    check(registry.watcherGuardError === "", "guard error starts clear")
    check(registry.guardRetryCount === 0, "guard retry count starts clear")
    registry.guardRetryLimit = 2
    registry.guardRetryCount = 2
    registry.scheduleGuardRetry("forced guard failure")
    check(registry.watcherGuardError.indexOf("retry limit reached") !== -1,
      "guard failure reaches bounded retry limit")
    check(!registry.guardRetryTimer.running, "retry limit does not spawn a tight loop")
    registry.pendingWatchIds = ({})
    registry.watcherStopRequested = true
    registry.watchRestartTimer.stop()
    registry.handleWatcherExit(0)
    check(!registry.watchRestartTimer.running && !registry.watcherStopRequested,
      "intentional watcher exit does not restart")
    registry.watcherUnavailable = false
    registry.pluginWatchEnabled = true
    registry.watcherRetryLimit = 2
    registry.watcherRetryCount = 0
    registry.watchRestartTimer.stop()
    registry.handleWatcherExit(125)
    check(registry.watcherUnavailable && registry.watcherRetryTimer.running,
      "unavailable watcher exit schedules bounded retry")
    registry.watcherRetryTimer.stop()
    registry.handleWatcherExit(125)
    registry.watcherRetryTimer.stop()
    registry.handleWatcherExit(125)
    check(registry.watcherUnavailable && !registry.watcherRetryTimer.running
      && hasError("registry", "dependencies are unavailable", "watcher"),
      "unavailable watcher reaches durable scoped error")
    registry.handleWatcherReady()
    check(!registry.watcherUnavailable && registry.watcherRetryCount === 0
      && !hasError("registry", "dependencies are unavailable", "watcher"),
      "successful watcher startup clears only watcher health")
    registry.watcherUnavailable = false
    registry.pluginWatchEnabled = true
    registry.handleWatcherExit(1)
    check(registry.watchRestartTimer.running, "unexpected watcher exit schedules restart")
    registry.watchRestartTimer.stop()
    registry.pluginWatchEnabled = false

    registry.shellConfigProvider = function() { return root.config }
    registry.pluginStateProvider = function() { return root.state }
    registry.pluginStateWriter = function(nextState) {
      root.state = nextState
      root.config = PluginState.mergeConfig(root.config, root.state)
      if (!nextState.enabledPlugins)
        root.config.plugins = root.config.plugins.filter(function(plugin) { return plugin.id !== "acme.panel" })
      return true
    }
    var revision = registry.registryRevision
    check(registry.setEnabled("acme.panel", true) === true, "panel activation")
    check(registry.isEnabled("acme.panel") === true, "panel enabled")
    check(root.state.enabledPlugins[0].id === "acme.panel", "panel state persisted")
    check(registry.setEnabled("acme.panel", false) === true, "panel deactivation")
    check(registry.isEnabled("acme.panel") === false, "panel disabled")
    check(registry.setEnabled("acme.widget", true) === true, "widget activation")
    check(registry.inBar("acme.widget") === true, "widget placement")
    check(root.state.barWidgets[0].section === "center", "widget default center placement")
    check(registry.setBarWidget("acme.widget", "units", "c") === true, "widget settings")
    check(root.state.barWidgets[0].settings.units === "c", "widget settings persisted")
    check(registry.moveBarWidget("acme.widget", "left", 0) === true, "widget move")
    check(root.state.barWidgets[0].section === "left", "widget move persisted")
    check(registry.setEnabled("acme.bar", true) === true, "bar activation")
    check(root.state.barPluginId === "acme.bar", "bar selection persisted")
    check(registry.setEnabled("desktop.bar", true) === true, "desktop bar restoration")
    check(root.state.barPluginId === undefined, "desktop bar restored")
    check(registry.setEnabled("desktop.bar", false) === false, "first-party mutation rejected")
    check(registry.lastEnableError.indexOf("repository-managed") !== -1, "first-party error detail")
    check(registry.setEnabled("acme.missing", true) === false, "unknown plugin rejected")
    check(registry.lastEnableError.indexOf("unknown plugin") !== -1, "unknown plugin error detail")
    check(registry.registryRevision === revision, "mutations do not fake scan revision")
    registry.recordPluginError("acme.mixed", "service failed", "service")
    registry.recordPluginError("acme.mixed", "widget failed", "widget")
    registry.clearPluginError("acme.mixed", "widget")
    check(hasError("acme.mixed", "service failed") && !hasError("acme.mixed", "widget failed"),
      "component-scoped errors clear independently")
    registry.guardRetryLimit = 2
    registry.guardRetryCount = 0
    registry.pendingWatchIds = ({})
    registry.activeWatchIds = ({ "acme.retry": true })
    registry.handleGuardExit(1)
    check(registry.guardRetryTimer.running && registry.pendingWatchIds["acme.retry"] === true,
      "failed watcher child defers retry with preserved IDs")
    registry.guardRetryTimer.stop()
    registry.activeWatchIds = ({ "acme.retry": true })
    registry.handleGuardExit(1)
    registry.guardRetryTimer.stop()
    registry.activeWatchIds = ({ "acme.retry": true })
    registry.handleGuardExit(1)
    check(!registry.guardRetryTimer.running && registry.pendingWatchIds["acme.retry"] === true
      && registry.watcherGuardError.indexOf("retry limit reached") !== -1,
      "repeated watcher failures stop at the bounded retry limit")
    registry.pendingWatchIds = ({})
    registry.watcherGuardError = ""

    root.startGuardAssertions()
  }

  function runRescanAssertions() {
    if (root.rescanChecked) return
    root.rescanChecked = true
    check(registry.installedPlugins["desktop.clock"]
      && registry.installedPlugins["desktop.clock"].__isFirstParty === true,
      "real rescan preserves first-party provenance")
    root.run()
  }

  Connections {
    target: root.registry
    function onLocalPluginChanged(id) {
      root.changedId = id
      var next = ({})
      for (var key in root.observedIds) next[key] = root.observedIds[key]
      next[id] = true
      root.observedIds = next
    }
    function onWatchReloadReady(serial) {
      root.watchReloadReadyCount++
      if (root.fifoMode) {
        registry.rescan()
        return
      }
      if (root.watchReloadReadyCount === 1) {
        registry.queueLocalPluginChange("acme.late")
        registry.rescan()
      }
    }
    function onScanFinished() {
      if (root.watcherLifecycleMode) {
        if (root.watcherLifecyclePhase === 2) {
          check(hasError("registry", "dependencies are unavailable", "watcher"),
            "real post-failure scan preserves terminal watcher error")
          watcherReadyProcess.running = true
        }
        return
      }
      root.scanFinishedCount++
      if (root.fifoMode) {
        var nextVersions = root.observedVersions.slice(0)
        nextVersions.push(String(registry.installedPlugins["acme.widget"]
          ? registry.installedPlugins["acme.widget"].version : ""))
        root.observedVersions = nextVersions
        if (root.scanFinishedCount === 2) root.swapPlugin("3.0.0")
        else if (root.scanFinishedCount === 3) root.finishFifoAssertions()
        return
      }
      root.runRescanAssertions()
      if (root.watchReloadReadyCount >= 2 && root.scanFinishedCount >= 3)
        root.finishGuardAssertions()
    }
  }

  Component.onCompleted: {
    registry.firstPartyDir = root.firstPartyRoot
    registry.pluginsDir = root.pluginsRoot
    if (root.watcherLifecycleMode) registry.pluginWatchEnabled = false
    if (root.fifoMode) registry.pluginWatchEnabled = true
    registry.rescan()
    if (root.fifoMode) firstSwapTimer.start()
    if (root.watcherLifecycleMode) lifecycleTimer.start()
  }

  Timer {
    id: lifecycleTimer
    interval: 25
    repeat: true
    running: root.watcherLifecycleMode
    onTriggered: root.runWatcherLifecycleAssertions()
  }

  Timer {
    id: externalReleaseTimer
    interval: 150
    repeat: false
    onTriggered: {
      check(root.watchReloadReadyCount === 0, "manager lock suppresses reload-ready")
      check(root.scanFinishedCount === 2, "manager lock suppresses watcher scan")
      check(Object.keys(root.observedIds).length === 0, "manager lock suppresses change notifications")
      externalReleaseProcess.running = true
    }
  }

  Timer {
    interval: 5000
    repeat: false
    running: true
    onTriggered: fail("watcher timeout ready=" + root.watchReloadReadyCount
      + " scans=" + root.scanFinishedCount + " retry=" + registry.guardRetryCount
      + " watcherRetry=" + registry.watcherRetryCount + " unavailable=" + registry.watcherUnavailable
      + " retryPending=" + registry.watcherRetryPending + " processStopped=" + registry.watcherProcessStopped
      + " retryStopped=" + registry.watcherRetryProcessStopped + " retryElapsed=" + registry.watcherRetryElapsed
      + " retryTimer=" + registry.watcherRetryTimer.running + " watcherRunning=" + registry.watcherProcess.running
      + " retryInterval=" + registry.watcherRetryTimer.interval
      + " scanning=" + registry.scanning + " lifecycle=" + root.watcherLifecycleMode
      + " phase=" + root.watcherLifecyclePhase + " error=" + registry.watcherGuardError)
  }
}
