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
  property int watchReloadReadyCount: 0
  property int scanFinishedCount: 0
  property bool scanObservedBeforeRelease: false
  property bool guardProbeBlocked: false
  property bool guardProbeReleased: false
  property bool guardProbeStarted: false
  property bool guardAssertionsStarted: false
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
    id: lockProbeProcess
    property bool afterRelease: false
    onExited: {
      if (afterRelease) root.guardProbeReleased = Number(exitCode) === 0
      else root.guardProbeBlocked = Number(exitCode) !== 0
      if (afterRelease) root.finishGuardAssertions()
    }
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

  function probeGuardLock(afterRelease) {
    lockProbeProcess.afterRelease = afterRelease
    lockProbeProcess.command = ["bash", "-c",
      "exec 9>\"$0/.plugin-manager.lock\"; flock -n 9", root.pluginsRoot]
    lockProbeProcess.running = true
  }

  function finishGuardAssertions() {
    check(root.guardProbeReleased, "competing flock succeeds after guard release")
    check(root.watchReloadReadyCount === 2, "batched and held events emit two guarded reloads")
    check(root.observedIds["acme.widget"] && root.observedIds["acme.other"]
      && root.observedIds["acme.late"], "all batched and held IDs observed")
    check(root.scanFinishedCount === 3, "expected guarded scan count")
    check(registry.installedPlugins["acme.widget"] && registry.installedPlugins["acme.other"],
      "restored Git tree installs only valid IDs")
    check(!hasError("acme.widget", "invalid JSON"), "restored tree has no manifest error")
    check(registry.watcherGuardError === "", "successful guard clears durable error")
    resultFile.setText(JSON.stringify({ ok: true }))
    Qt.exit(0)
  }

  function startGuardAssertions() {
    if (root.guardAssertionsStarted) return
    root.guardAssertionsStarted = true
    registry.pluginsDir = root.pluginsRoot
    registry.handleWatchOutput(root.pluginsRoot + "/acme.widget/manifest.json\n"
      + root.pluginsRoot + "/acme.other/Widget.qml")
    externalReleaseTimer.start()
  }

  function hasError(id, text) {
    for (var i = 0; i < registry.pluginErrors.length; i++) {
      var error = registry.pluginErrors[i]
      if (String(error.id) === id && String(error.error).indexOf(text) !== -1) return true
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
    registry.activeGuardIds = ({ "acme.retry": true })
    registry.requeueActiveGuardIds()
    check(registry.pendingWatchIds["acme.retry"] === true, "failed generation requeues active IDs")
    registry.pendingWatchIds = ({})
    registry.watcherStopRequested = true
    registry.handleWatcherExit(0)
    check(!registry.watchRestartTimer.running && !registry.watcherStopRequested,
      "intentional watcher exit does not restart")
    registry.watcherUnavailable = false
    registry.handleWatcherExit(125)
    check(registry.watcherUnavailable && !registry.watchRestartTimer.running,
      "unavailable watcher exit does not restart")
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
    function onWatchReloadReady() {
      root.watchReloadReadyCount++
      if (root.watchReloadReadyCount === 1) {
        registry.queueLocalPluginChange("acme.late")
        registry.rescan()
      } else {
        registry.releaseWatchReloadGuard()
      }
    }
    function onScanFinished() {
      root.scanFinishedCount++
      root.runRescanAssertions()
      if (root.watchReloadReadyCount > 0 && registry.guardHeld && !root.guardProbeStarted) {
        root.scanObservedBeforeRelease = true
        root.guardProbeStarted = true
        root.probeGuardLock(false)
      }
    }
  }

  Component.onCompleted: {
    registry.firstPartyDir = root.firstPartyRoot
    registry.rescan()
  }

  Timer {
    id: externalReleaseTimer
    interval: 150
    repeat: false
    onTriggered: {
      check(root.watchReloadReadyCount === 0, "manager lock suppresses reload-ready")
      check(root.scanFinishedCount === 2, "manager lock suppresses guarded scan")
      check(Object.keys(root.observedIds).length === 0, "manager lock suppresses change notifications")
      externalReleaseProcess.running = true
    }
  }

  Timer {
    interval: 300
    repeat: false
    running: root.guardProbeBlocked
    onTriggered: {
      check(root.scanObservedBeforeRelease, "scan/change notifications observed before guard release")
      registry.releaseWatchReloadGuard()
      var waitForRelease = Qt.createQmlObject('import QtQuick; Timer { interval: 50; repeat: true }', root)
      waitForRelease.triggered.connect(function() {
        if (root.watchReloadReadyCount === 2 && !registry.guardHeld && !lockProbeProcess.running) {
          waitForRelease.stop()
          root.probeGuardLock(true)
        }
      })
      waitForRelease.start()
    }
  }

  Timer {
    interval: 5000
    repeat: false
    running: true
    onTriggered: fail("guard timeout ready=" + root.watchReloadReadyCount
      + " held=" + registry.guardHeld + " starting=" + registry.guardStarting
      + " retry=" + registry.guardRetryCount + " error=" + registry.watcherGuardError)
  }
}
