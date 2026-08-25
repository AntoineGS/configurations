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

    registry.pluginsDir = "/tmp/plugins"
    registry.handleWatchOutput("/tmp/plugins/acme.widget/Widget.qml")
    check(root.changedId === "acme.widget", "watcher change notification delivery")

    resultFile.setText(JSON.stringify({ ok: true }))
    Qt.exit(0)
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
    function onLocalPluginChanged(id) { root.changedId = id }
    function onScanFinished() { root.runRescanAssertions() }
  }

  Component.onCompleted: {
    registry.firstPartyDir = root.firstPartyRoot
    registry.rescan()
  }
}
