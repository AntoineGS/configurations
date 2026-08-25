//@ pragma UseQApplication
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io

import qs.Commons

import "plugins/bar"
import "plugins/osd/OsdModel.js" as OsdModel
import "services"
import "services/PluginState.js" as PluginState

ShellRoot {
  id: shell

  // Shared service instances. Plugins receive these via property injection
  // rather than re-importing them as singletons — relative-path imports do
  // not share singleton state, which silently leaves consumers with their
  // own empty copies.
  property PluginRegistry pluginRegistry: PluginRegistry { }
  property BarWidgetRegistry barWidgetRegistry: BarWidgetRegistry { }
  property AppLibrary appLibrary: AppLibrary { }

  property string home: Quickshell.env("HOME")

  readonly property string shellPath: Quickshell.shellDir
  readonly property string firstPartyPluginsDir: shellPath + "/plugins"
  readonly property string defaultConfigPath: shellPath + "/config/shell.json"
  readonly property string configPath: defaultConfigPath
  readonly property string configuredPluginStatePath: Quickshell.env("DESKTOP_SHELL_STATE_PATH")
  readonly property string pluginStatePath: configuredPluginStatePath !== ""
    ? configuredPluginStatePath : home + "/.config/desktop-shell/shell.json"
  readonly property string defaultBarId: "desktop.bar"
  readonly property bool previewMode: Quickshell.env("DESKTOP_SHELL_PREVIEW") === "1"
  readonly property bool testSurfaceSuppressed: Quickshell.env("DESKTOP_SHELL_TEST_NO_SURFACES") === "1"
  readonly property bool testMutationEnabled: Quickshell.env("DESKTOP_SHELL_TEST_ALLOW_PLUGIN_STATE_MUTATION") === "1"
    && configuredPluginStatePath !== "" && testSurfaceSuppressed
  readonly property bool testPluginWidgetLoadEnabled: testMutationEnabled
    && Quickshell.env("DESKTOP_SHELL_TEST_LOAD_PLUGIN_WIDGETS") === "1"
  readonly property bool testPluginBarLoadEnabled: testMutationEnabled
    && Quickshell.env("DESKTOP_SHELL_TEST_LOAD_PLUGIN_BAR") === "1"
  readonly property string testPanelPlugin: String(Quickshell.env("DESKTOP_SHELL_TEST_PANEL_PLUGIN") || "")
  property bool barVisible: true

  // Bundled fallback so the shell can start even when the default shell.json is
  // missing or unreadable. The bar config here mirrors the on-disk defaults
  // closely enough to render a usable bar; not authoritative.
  readonly property var builtinShellConfig: ({
    version: 1,
    idle: {
      screensaver: 150,
      lock: 300
    },
    bar: {
      id: "desktop.bar",
      position: "top",
      transparent: false,
      centerAnchor: "desktop.clock",
      layout: {
        left: [{ id: "desktop.menu" }, { id: "desktop.workspaces" }],
        center: [{ id: "desktop.clock", format: "dddd HH:mm" }],
        right: [{ id: "desktop.audio" }, { id: "desktop.vm" }]
      }
    },
    plugins: [],
    disabledPlugins: []
  })

  property var defaultShellConfig: builtinShellConfig
  property var pluginState: PluginState.emptyState()
  property bool pluginStateValid: true
  property string pluginStateError: ""
  property bool pluginStateDirectoryReady: false
  property bool pluginStateWritePending: false
  property string pluginStateWriteError: ""
  property var pendingPluginState: null
  property bool pluginStateWriteResult: false
  property var shellConfig: PluginState.mergeConfig(defaultShellConfig, pluginState)
  property bool configValid: false
  readonly property var pluginErrors: pluginRegistry ? pluginRegistry.pluginErrors : []
  readonly property var notificationService: shell.serviceFor("desktop.notifications")
  readonly property var polkitService: shell.serviceFor("desktop.polkit")
  readonly property var healthState: ({
    configValid: shell.configValid,
    pluginStateValid: shell.pluginStateValid,
    pluginStateError: shell.pluginStateError,
    pluginStatePath: shell.pluginStatePath,
    pluginStateDirectoryReady: shell.pluginStateDirectoryReady,
    pluginStateWritePending: shell.pluginStateWritePending,
    pluginStateWriteError: shell.pluginStateWriteError,
    pluginErrors: shell.pluginErrors,
    watcherGuardError: pluginRegistry ? pluginRegistry.watcherGuardError : "",
    watcherGuardRetryCount: pluginRegistry ? pluginRegistry.guardRetryCount : 0,
    watcherUnavailable: pluginRegistry ? pluginRegistry.watcherUnavailable : false,
    watcherRetryCount: pluginRegistry ? pluginRegistry.watcherRetryCount : 0,
    reloadGeneration: shell.pluginReloadGeneration,
    pluginLoadEpoch: shell.pluginLoadEpoch,
    pluginBarLoadCount: shell.pluginBarLoadCount,
    pluginBarInstanceGeneration: shell.pluginBarInstanceGeneration,
    pluginBarDestroyedCount: shell.pluginBarDestroyedCount,
    serviceCreateAttemptCount: shell.serviceCreateAttemptCount,
    thirdPartyServiceCreateAttemptCount: shell.thirdPartyServiceCreateAttemptCount,
    scanFinishedCount: pluginRegistry ? pluginRegistry.scanFinishedCount : 0,
    watchChangeCount: pluginRegistry ? pluginRegistry.watchChangeCount : 0,
    activeBarId: shell.activeBarId,
    previewMode: shell.previewMode,
    testSurfaceSuppressed: shell.testSurfaceSuppressed,
    osdAvailable: shell.osdAvailable,
    notificationsOwned: notificationService ? notificationService.notificationsOwned : false,
    notificationOwnershipError: notificationService ? notificationService.ownershipError : "notification service unavailable",
    notificationRouteValid: notificationService ? notificationService.routeValid : false,
    notificationRouteVisible: notificationService ? notificationService.routeVisible : false,
    notificationRouteError: notificationService ? notificationService.routeError : "notification service unavailable",
    notificationRouteMetadataAttemptCount: notificationService ? notificationService.routeMetadataAttemptCount : 0,
    polkitRegistered: polkitService ? polkitService.polkitRegistered : false,
    polkitError: polkitService ? polkitService.polkitError : "polkit service unavailable",
    polkitPamError: polkitService ? polkitService.pamError : "polkit service unavailable",
    polkitFingerprintConfigured: polkitService ? polkitService.fingerprintConfigured : false
  })
  property bool pluginReloading: false
  property bool pluginReloadPending: false
  property int pluginReloadGeneration: 0
  property int pluginLoadEpoch: 0
  property int pluginBarLoadCount: 0
  property int pluginBarInstanceGeneration: 0
  property int pluginBarDestroyedCount: 0
  property int serviceCreateAttemptCount: 0
  property int thirdPartyServiceCreateAttemptCount: 0
  property bool pluginBarReloadEnabled: true
  property var reloadComponentStates: ({})
  property int reloadTokenCounter: 0
  property string reloadGenerationError: ""

  onShellConfigChanged: {
    if (failedBarId !== "") failedBarId = ""
    pluginRegistry.registryRevision++
    pluginRegistry.pluginsChanged()
  }

  function applyShellConfig(raw) {
    var text = String(raw || "").trim()
    if (!text) {
      configValid = false
      defaultShellConfig = builtinShellConfig
      rebuildShellConfig()
      console.warn("shell config missing, using builtin fallback")
      return
    }
    try {
      var parsed = JSON.parse(text)
      if (Util.isPlainObject(parsed) && parsed.version === 1) {
        configValid = true
        defaultShellConfig = parsed
        rebuildShellConfig()
        return
      }
      configValid = false
      defaultShellConfig = builtinShellConfig
      rebuildShellConfig()
      console.warn("shell config missing version: 1, using builtin fallback")
    } catch (e) {
      configValid = false
      defaultShellConfig = builtinShellConfig
      rebuildShellConfig()
      console.warn("shell config parse failed, using builtin fallback:", e)
    }
  }

  function rebuildShellConfig() {
    shellConfig = PluginState.mergeConfig(defaultShellConfig, pluginState)
  }

  function applyPluginState(raw) {
    var parsed = PluginState.parseState(raw)
    if (!parsed.valid) {
      pluginStateValid = false
      pluginStateError = parsed.error
      pluginState = PluginState.emptyState()
      rebuildShellConfig()
      return
    }
    pluginState = parsed.state
    pluginStateValid = true
    pluginStateError = ""
    rebuildShellConfig()
  }

  function persistPluginState(nextState) {
    if (!pluginStateValid) {
      pluginStateError = "invalid plugin state must be recovered before mutation"
      return false
    }
    if (!pluginStateDirectoryReady) {
      pluginStateError = "plugin state directory is not ready"
      return false
    }
    if (pluginStateWritePending) {
      pluginStateError = "plugin state write is already pending"
      return false
    }
    var parsed = PluginState.parseState(JSON.stringify(nextState || {}))
    if (!parsed.valid) {
      pluginStateValid = false
      pluginStateError = parsed.error
      return false
    }
    pendingPluginState = parsed.state
    pluginStateWritePending = true
    pluginStateWriteError = ""
    pluginStateWriteResult = false
    pluginStateError = "plugin state write pending"
    pluginStateFile.setText(JSON.stringify(parsed.state, null, 2) + "\n")
    return pluginStateWriteResult
  }

  readonly property var barConfig: shellConfig && Util.isPlainObject(shellConfig.bar) ? shellConfig.bar : builtinShellConfig.bar
  onBarConfigChanged: if (bar && "barConfig" in bar) bar.barConfig = shell.barConfig
  FileView {
    id: defaultsFile
    path: shell.defaultConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: shell.applyShellConfig(text())
    onLoadFailed: function(error) {
      console.warn("shell config load failed: " + error + " path=" + shell.configPath)
      shell.applyShellConfig("")
    }
    onFileChanged: reload()
  }

  FileView {
    id: pluginStateFile
    path: shell.pluginStatePath
    watchChanges: true
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: shell.applyPluginState(text())
    onLoadFailed: shell.applyPluginState("")
    onFileChanged: reload()
    onSaved: {
      if (shell.pluginStateWritePending) {
        shell.pluginState = shell.pendingPluginState
        shell.pendingPluginState = null
        shell.pluginStateWritePending = false
        shell.pluginStateWriteError = ""
        shell.pluginStateWriteResult = true
        shell.pluginStateValid = true
        shell.pluginStateError = ""
        shell.rebuildShellConfig()
      }
    }
    onSaveFailed: function(error) {
      shell.pendingPluginState = null
      shell.pluginStateWritePending = false
      shell.pluginStateWriteError = String(error || "plugin state save failed")
      shell.pluginStateWriteResult = false
      shell.pluginStateError = shell.pluginStateWriteError
    }
  }

  Process {
    id: pluginStateDirectoryProcess
    onExited: function(exitCode) {
      shell.pluginStateDirectoryReady = Number(exitCode) === 0
      if (!shell.pluginStateDirectoryReady) shell.pluginStateError = "plugin state directory could not be created"
    }
  }

  Component.onCompleted: {
    console.log("desktop-shell paths",
      "shellDir=" + Quickshell.shellDir,
      "firstPartyPluginsDir=" + shell.firstPartyPluginsDir,
      "configPath=" + shell.configPath,
      "pluginStatePath=" + shell.pluginStatePath)
    pluginStateDirectoryProcess.command = ["bash", "-c", "mkdir -p -- \"$(dirname -- \"$0\")\"", shell.pluginStatePath]
    pluginStateDirectoryProcess.running = true
    pluginRegistry.firstPartyDir = shell.firstPartyPluginsDir
    pluginRegistry.shellConfigProvider = function() { return shell.shellConfig }
    pluginRegistry.pluginStateProvider = function() { return shell.pluginState }
    pluginRegistry.pluginStateWriter = function(nextState) { return shell.persistPluginState(nextState) }
    pluginRegistry.rescan()
    shell._syncServices()
  }

  // Exposed as a property so child plugins (notifications, future panels)
  // can read barSize/barHidden/position to anchor relative to the active bar.
  readonly property string selectedBarId: {
    var config = shell.barConfig
    if (Util.isPlainObject(config)) {
      var configured = Util.canonicalWidgetId(String(config.id || ""))
      if (configured) return configured
    }
    return shell.defaultBarId
  }
  property string failedBarId: ""
  readonly property bool selectedBarAvailable: {
    var revision = shell.pluginRegistry.registryRevision
    return shell.barOptionAvailable(shell.selectedBarId)
  }
  readonly property string activeBarId: selectedBarId !== failedBarId && selectedBarAvailable ? selectedBarId : defaultBarId
  readonly property var activeBarManifest: {
    var revision = shell.pluginRegistry.registryRevision
    return shell.barManifestFor(shell.activeBarId)
  }
  readonly property string activeBarSourceUrl: activeBarId === defaultBarId ? "" : shell.pluginRegistry.entryPointUrl(activeBarManifest, "bar")
  property var bar: null

  onSelectedBarIdChanged: if (failedBarId !== "") failedBarId = ""

  function barManifestFor(pluginId) {
    var plugins = shell.pluginRegistry ? shell.pluginRegistry.installedPlugins : null
    return plugins ? plugins[String(pluginId || "")] || null : null
  }

  function isBarOptionManifest(manifest) {
    return manifest
      && Array.isArray(manifest.kinds)
      && manifest.kinds.indexOf("bar") !== -1
      && manifest.entryPoints
      && manifest.entryPoints.bar
  }

  function barOptionAvailable(pluginId) {
    var id = String(pluginId || "")
    if (id === "" || id === shell.defaultBarId) return true
    var manifest = shell.barManifestFor(id)
    return shell.isBarOptionManifest(manifest) && shell.pluginRegistry.entryPointUrl(manifest, "bar") !== ""
  }

  function isActiveBarOption(pluginId) {
    return String(pluginId || "") === shell.activeBarId
  }

  function configureBar(target, manifest) {
    if (!target) return
    if ("shellPath" in target) target.shellPath = shell.shellPath
    if ("shell" in target) target.shell = shell
    if ("manifest" in target) target.manifest = manifest
    if ("barWidgetRegistry" in target) target.barWidgetRegistry = shell.barWidgetRegistry
    if ("pluginRegistry" in target) target.pluginRegistry = shell.pluginRegistry
    if ("barConfig" in target) target.barConfig = shell.barConfig
    shell.bar = target
  }

  Component {
    id: defaultBarComponent

    Bar {
      shellPath: shell.shellPath
      barWidgetRegistry: shell.barWidgetRegistry
      barConfig: shell.barConfig
      shell: shell
      manifest: shell.barManifestFor(shell.defaultBarId)
    }
  }

  Loader {
    id: defaultBarLoader

    active: !shell.testSurfaceSuppressed && shell.activeBarId === shell.defaultBarId
    sourceComponent: defaultBarComponent
    onLoaded: shell.configureBar(item, shell.barManifestFor(shell.defaultBarId))
    onActiveChanged: if (!active && shell.activeBarId !== shell.defaultBarId) shell.bar = null
  }

  Loader {
    id: pluginBarLoader

    active: (!shell.testSurfaceSuppressed || shell.testPluginBarLoadEnabled)
      && shell.pluginBarReloadEnabled
      && shell.activeBarId !== shell.defaultBarId && shell.activeBarSourceUrl !== ""
    source: shell.activeBarId !== shell.defaultBarId ? shell.activeBarSourceUrl : ""
    asynchronous: true
    property int loadEpoch: -1
    property int loadGeneration: -1
    property string loadId: ""
    property string loadUrl: ""
    property var loadManifest: null
    property string reloadToken: ""
    onLoaded: {
      if (!shell.isPluginLoadCurrent(loadId, "bar", loadEpoch, loadGeneration, loadUrl, loadManifest)) return
      shell.pluginBarLoadCount++
      shell.pluginBarInstanceGeneration++
      shell.pluginRegistry.clearPluginError(loadId, "bar")
      shell.configureBar(item, shell.activeBarManifest)
    }
    onActiveChanged: if (!active) shell.bar = null
    onStatusChanged: {
      if (status === Loader.Loading && reloadToken === "") {
        loadEpoch = shell.pluginLoadEpoch
        loadGeneration = shell.pluginRegistry.pluginSourceGeneration
        loadId = shell.activeBarId
        loadUrl = shell.activeBarSourceUrl
        loadManifest = shell.activeBarManifest
        reloadToken = shell.beginReloadOperation("bar:" + loadId)
      }
      if (status !== Loader.Loading && reloadToken !== "") {
        if (!shell.isPluginLoadCurrent(loadId, "bar", loadEpoch, loadGeneration, loadUrl, loadManifest)) return
        shell.finishReloadOperation(reloadToken, status, errorString())
        reloadToken = ""
      }
      if (status === Loader.Error) {
        if (!shell.isPluginLoadCurrent(loadId, "bar", loadEpoch, loadGeneration, loadUrl, loadManifest)) return
        var detail = errorString && errorString() ? errorString() : ""
        console.warn("bar option " + loadId + " failed to load, falling back to " + shell.defaultBarId + ":", detail)
        shell.pluginRegistry.pluginLoadFailed(loadId, detail, loadGeneration, "bar")
        shell.failedBarId = loadId
      }
    }
    Component.onDestruction: {
      reloadToken = ""
    }
  }

  function recordPluginBarDestroyed() {
    if (shell.testPluginBarLoadEnabled) shell.pluginBarDestroyedCount++
  }

  function pluginBarTestProbe() {
    if (!shell.testPluginBarLoadEnabled) return "disabled"
    return JSON.stringify({
      loadCount: shell.pluginBarLoadCount,
      instanceGeneration: shell.pluginBarInstanceGeneration,
      destroyedCount: shell.pluginBarDestroyedCount,
      version: shell.bar && "version" in shell.bar ? String(shell.bar.version) : ""
    })
  }

  // ------------------------------------------------------------- services
  //
  // Generic loader for any enabled plugin that declares kind "service".
  // First-party infrastructure services are implicitly enabled by the registry.
  Item {
    id: serviceHost
    visible: false
  }

  property var _services: ({})

  function serviceFor(pluginId) {
    return _services[String(pluginId)] || null
  }

  function firstPartyServiceFor(pluginId) {
    return serviceFor(pluginId)
  }

  function ensureService(pluginId) {
    if (shell.previewMode) return null
    var key = String(pluginId)
    if (_services[key]) return _services[key]
    var manifest = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[key] : null
    if (!manifest) return null
    if (!Array.isArray(manifest.kinds) || manifest.kinds.indexOf("service") === -1) return null
    if (!manifest.entryPoints || !manifest.entryPoints.service) return null
    var url = pluginRegistry.entryPointUrl(manifest, "service")
    if (!url) return null

    var loadEpoch = shell.pluginLoadEpoch
    var loadGeneration = shell.pluginRegistry.pluginSourceGeneration
    var loadManifest = manifest
    var loadUrl = url
    shell.serviceCreateAttemptCount++
    if (!manifest.__isFirstParty) shell.thirdPartyServiceCreateAttemptCount++
    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (comp.status === Component.Loading) return
      var currentManifest = shell.pluginRegistry.installedPlugins[key]
      if (!shell.isPluginLoadCurrent(key, "service", loadEpoch, loadGeneration, loadUrl, loadManifest)
          || !currentManifest || !shell.pluginRegistry.isEnabled(key)) return
      if (comp.status !== Component.Ready) {
        console.warn("service plugin load failed for " + key + ": " + comp.errorString())
        shell.pluginRegistry.pluginLoadFailed(key, comp.errorString(), loadGeneration, "service")
        return
      }
      var inst = comp.createObject(serviceHost)
      if (!inst) {
        console.warn("service plugin createObject returned null for", key)
        shell.pluginRegistry.pluginLoadFailed(key, "service createObject returned null", loadGeneration, "service")
        return
      }
      if ("shellPath" in inst) inst.shellPath = shell.shellPath
      if ("shell" in inst) inst.shell = shell
       if ("manifest" in inst) inst.manifest = loadManifest
      if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = shell.barWidgetRegistry
      if ("pluginRegistry" in inst) inst.pluginRegistry = shell.pluginRegistry
      var snext = ({})
      for (var sk in _services) snext[sk] = _services[sk]
       snext[key] = inst
       _services = snext
        shell.pluginRegistry.clearPluginError(key, "service")
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
      return null
    }
    finalize()
    return _services[key] || null
  }

  function _syncServices() {
    if (!pluginRegistry || !pluginRegistry.installedPlugins) return
    if (shell.previewMode) {
      if (Object.keys(_services).length > 0) shell.unloadPluginServices()
      return
    }
    var plugins = pluginRegistry.installedPlugins
    for (var id in plugins) {
      var m = plugins[id]
      if (!m) continue
      if (!Array.isArray(m.kinds) || m.kinds.indexOf("service") === -1) continue
      if (!m.entryPoints || !m.entryPoints.service) continue
      if (!pluginRegistry.isEnabled(id)) continue
      if (_services[id]) continue
      ensureService(id)
    }
    // Drop services for plugins that have been disabled or removed.
    for (var existingId in _services) {
      var stillThere = plugins[existingId]
      var stillEnabled = stillThere && pluginRegistry.isEnabled(existingId)
      if (stillThere && stillEnabled) continue
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
      var next = ({})
      for (var k in _services) if (k !== existingId) next[k] = _services[k]
      _services = next
    }
  }

  function unloadPluginServices() {
    for (var existingId in _services) {
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
    }
    _services = ({})
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() {
      if (shell.pluginReloading || shell.pluginReloadPending || shell.pluginRegistry.scanning) return
      shell._syncServices()
    }
  }

  // Writes inline settings to a mutable bar-widget state entry. Returns true
  // if anything actually changed.
  function updateEntryInline(moduleName, settings) {
    var stripped = Util.canonicalWidgetId(moduleName)
    var copy = JSON.parse(JSON.stringify(pluginState || PluginState.emptyState()))
    var widget = (copy.barWidgets || []).find(function (item) { return item.id === stripped })
    if (!widget) return false
    var before = JSON.stringify(copy)
    for (var key in settings) {
      if (key !== "id") copy = PluginState.setWidget(copy, stripped, key, settings[key]).state
    }
    if (JSON.stringify(copy) === before) return false
    return persistPluginState(copy)
  }

  // ---------------------------------------------------------- on-demand panels

  // openPanelIds is a plain object treated as a set. A plugin id maps to
  // `true` while the panel is summoned; deleting the key (well, building a new
  // object without it) hides it. Reassigning the whole object is required for
  // QML to notice the change.
  property var openPanelIds: ({})

  // Pending payloads to deliver to a plugin's open() once its loader resolves.
  // Keyed by plugin id; the value is an array so two summon() calls before
  // the Loader resolves both reach the plugin in arrival order rather than
  // the second clobbering the first.
  property var pendingPayloads: ({})

  // Bar-widget panels (audio, bluetooth, network, power, monitor, etc.)
  // are mounted inside the bar, not via the panel loader below. Route
  // summon/hide/toggle to the live bar instance so panel hotkeys survive
  // plugin/bar reloads: the bar re-creates the widget, while a fixed IPC
  // target only ever routes to one of the per-monitor instances.
  function isBarWidgetPanelPlugin(pluginId) {
    var plugins = shell.pluginRegistry.installedPlugins
    var m = plugins[String(pluginId || "")]
    if (!m || !Array.isArray(m.kinds)) return false
    if (m.kinds.indexOf("bar-widget") === -1) return false
    // Plugins that are also panel/overlay/menu kinds are owned by the
      // panel loader (for example, the repository menu); let that path handle them.
    var loaderKinds = ["panel", "overlay", "menu"]
    for (var i = 0; i < loaderKinds.length; i++) {
      if (m.kinds.indexOf(loaderKinds[i]) !== -1) return false
    }
    return true
  }

  function summon(pluginId, payloadJson) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    if (!id) return false
    var plugins = shell.pluginRegistry.installedPlugins
    if (!plugins[id]) {
      console.warn("summon: unknown plugin", id)
      return false
    }
    // A disabled plugin has no Loader, so setting openPanelIds would only
    // produce an invisible "open" state that toggle() then has to unwind.
    // Tell the caller plainly instead of silently no-op'ing.
    if (!shell.pluginRegistry.isEnabled(id)) {
      console.warn("summon: plugin not enabled, not summoning:", id)
      return false
    }
    // Bar widgets take no payload; payloadJson is dropped on this path.
    if (shell.isBarWidgetPanelPlugin(id)) {
      var summoned = shell.invokeBarWidget(id, "open")
      if (!summoned) console.warn("summon: no live bar widget for:", id)
      return summoned === true
    }
    var panelAvailable = false
    for (var entryIndex = 0; entryIndex < shell.panelEntries.length; entryIndex++) {
      if (shell.panelEntries[entryIndex] && shell.panelEntries[entryIndex].id === id) {
        panelAvailable = true
        break
      }
    }
    if (!panelAvailable) {
      console.warn("summon: panel is not loaded:", id)
      return false
    }
    var next = ({})
    for (var k in openPanelIds) next[k] = openPanelIds[k]
    next[id] = true
    openPanelIds = next

    // Stash payload so the Loader.onLoaded handler can hand it to open().
    var pending = ({})
    for (var p in pendingPayloads) pending[p] = pendingPayloads[p].slice()
    var queue = pending[id] || []
    queue.push(payloadJson || "")
    pending[id] = queue
    pendingPayloads = pending

    // If the plugin is keepLoaded and already mounted, deliver immediately.
    deliverIfLoaded(id)
    return true
  }

  function hide(pluginId) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    if (!id) return false
    if (shell.isBarWidgetPanelPlugin(id)) {
      var hidden = shell.invokeBarWidget(id, "close")
      if (!hidden) console.warn("hide: no live bar widget for:", id)
      return hidden === true
    }
    invokeIfLoaded(id, "close", null)
    return releasePanel(id)
  }

  function releasePanel(pluginId) {
    var id = String(pluginId || "")
    if (!openPanelIds[id]) return true
    var next = ({})
    for (var k in openPanelIds) if (k !== id) next[k] = openPanelIds[k]
    openPanelIds = next
    return true
  }

  function isPluginOpen(pluginId) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    if (shell.isBarWidgetPanelPlugin(id)) {
      var widget = shell.barWidgetFor(id)
      return !!widget && widget.opened === true
    }
    var loader = panelLoaders[id]
    if (loader && loader.item && loader.item.opened !== undefined)
      return loader.item.opened === true
    return openPanelIds[id] === true
  }

  function toggle(pluginId, payloadJson) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    return isPluginOpen(id) ? hide(id) : summon(id, payloadJson)
  }

  // Map of pluginId -> Loader, populated by the Instantiator delegate below.
  property var panelLoaders: ({})

  readonly property bool osdAvailable: OsdModel.healthAvailable(
    shell.previewMode, shell.panelLoaders["desktop.osd"], Loader.Error)

  function registerPanelLoader(pluginId, loader) {
    var next = ({})
    for (var k in panelLoaders) next[k] = panelLoaders[k]
    next[pluginId] = loader
    panelLoaders = next
    deliverIfLoaded(pluginId)
  }

  function unregisterPanelLoader(pluginId) {
    if (!panelLoaders[pluginId]) return
    var next = ({})
    for (var k in panelLoaders) if (k !== pluginId) next[k] = panelLoaders[k]
    panelLoaders = next
  }

  function unloadPanels() {
    for (var id in panelLoaders) hide(id)
    panelEntries = []
    panelLoaders = ({})
    pendingPayloads = ({})
    openPanelIds = ({})
  }

  function deliverIfLoaded(pluginId) {
    var loader = panelLoaders[pluginId]
    if (!loader || !loader.item) return
    var queue = pendingPayloads[pluginId]
    if (!Array.isArray(queue) || queue.length === 0) return
    if (typeof loader.item.open === "function") {
      for (var i = 0; i < queue.length; i++) {
        try { loader.item.open(queue[i]) } catch (e) {
          console.warn("plugin " + pluginId + " open() threw:", e)
        }
      }
    }
    var next = ({})
    for (var k in pendingPayloads) if (k !== pluginId) next[k] = pendingPayloads[k].slice()
    pendingPayloads = next
  }

  function invokeIfLoaded(pluginId, method, arg) {
    var loader = panelLoaders[pluginId]
    if (!loader || !loader.item) return
    if (typeof loader.item[method] !== "function") return
    try { loader.item[method](arg) } catch (e) {
      console.warn("plugin " + pluginId + " " + method + "() threw:", e)
    }
  }

  function callIfLoaded(pluginId, method, arg) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    var service = shell.serviceFor(pluginId)
    if (service && typeof service[method] === "function") {
      try {
        var serviceResult = service[method](arg)
        return serviceResult === undefined || serviceResult === null ? "ok" : String(serviceResult)
      } catch (e) {
        console.warn("service " + id + " " + method + "() threw:", e)
        return "error"
      }
    }
    var loader = panelLoaders[id]
    if (!loader || !loader.item) return "unknown"
    if (typeof loader.item[method] !== "function") return "unknown"
    try {
      var result = loader.item[method](arg)
      return result === undefined || result === null ? "ok" : String(result)
    } catch (e) {
      console.warn("plugin " + id + " " + method + "() threw:", e)
      return "error"
    }
  }

  // One Loader per discoverable panel/overlay/menu plugin. Active when the
  // host marks it open. The Loader holds onto the instance while active so the
  // plugin's FloatingWindow + state survive between summons within a session.
  property var panelEntries: []

  function computePanelEntries() {
    if (shell.testSurfaceSuppressed && shell.testPanelPlugin !== "desktop.mixed") return []
    var out = []
    var plugins = shell.pluginRegistry.installedPlugins
    var panelKinds = ["panel", "overlay", "menu"]
    for (var id in plugins) {
      var m = plugins[id]
      if (!m || !Array.isArray(m.kinds)) continue
      if (shell.testSurfaceSuppressed && id !== "desktop.mixed") continue
      var matched = false
      for (var i = 0; i < panelKinds.length; i++)
        if (m.kinds.indexOf(panelKinds[i]) !== -1) { matched = true; break }
      if (!matched) continue
      var keepLoaded = m.keepLoaded === true
      if (shell.previewMode) keepLoaded = false
      if (!shell.pluginRegistry.isEnabled(id)) continue
      var kind = m.kinds.indexOf("panel") !== -1 ? "panel"
        : (m.kinds.indexOf("overlay") !== -1 ? "overlay" : "menu")
      out.push({ id: id, manifest: m, kind: kind, keepLoaded: keepLoaded })
    }
    return out
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() {
      if (shell.pluginReloading || shell.pluginReloadPending || shell.pluginRegistry.scanning) return
      shell.panelEntries = shell.computePanelEntries()
    }
  }

  Instantiator {
    model: shell.panelEntries
    active: true

    delegate: QtObject {
      id: panelEntry
      required property var modelData
      readonly property string pluginId: modelData.id
      readonly property var manifest: modelData.manifest
      readonly property string entryKind: modelData.kind
      readonly property bool keepLoaded: modelData.keepLoaded === true
      readonly property string sourceUrl: shell.pluginRegistry.entryPointUrl(manifest, entryKind)

      property Loader panelLoader: Loader {
        property int loadEpoch: shell.pluginLoadEpoch
        property int loadGeneration: shell.pluginReloadGeneration
        property string loadUrl: panelEntry.sourceUrl
        property string reloadToken: ""
        source: panelEntry.sourceUrl
        active: panelEntry.sourceUrl !== "" && (panelEntry.keepLoaded || shell.openPanelIds[panelEntry.pluginId] === true)
        asynchronous: true
        onLoaded: {
          if (!item) return
          if (!shell.isPluginLoadCurrent(panelEntry.pluginId, panelEntry.entryKind,
              loadEpoch, loadGeneration, loadUrl, panelEntry.manifest)) return
          shell.pluginRegistry.clearPluginError(panelEntry.pluginId, "panel:" + panelEntry.entryKind)
          if ("shellPath" in item) item.shellPath = shell.shellPath
          if ("shell" in item) item.shell = shell
          if ("manifest" in item) item.manifest = panelEntry.manifest
          if ("barWidgetRegistry" in item) item.barWidgetRegistry = shell.barWidgetRegistry
          if ("pluginRegistry" in item) item.pluginRegistry = shell.pluginRegistry
          // Plugins that pair a panel UI with a service entry read shared
          // state off `service`. Hand them the matching singleton if one was
          // loaded.
          if ("service" in item) item.service = shell.serviceFor(panelEntry.pluginId)
          shell.registerPanelLoader(panelEntry.pluginId, this)
        }
        onStatusChanged: {
          if (status === Loader.Loading && reloadToken === "") {
            loadEpoch = shell.pluginLoadEpoch
            loadGeneration = shell.pluginRegistry.pluginSourceGeneration
            loadUrl = panelEntry.sourceUrl
            reloadToken = shell.beginReloadOperation("panel:" + panelEntry.pluginId
              + ":" + panelEntry.entryKind, loadGeneration)
          }
          if (status !== Loader.Loading && reloadToken !== "") {
            if (!shell.isPluginLoadCurrent(panelEntry.pluginId, panelEntry.entryKind,
                loadEpoch, loadGeneration, loadUrl, panelEntry.manifest)) return
            shell.finishReloadOperation(reloadToken, status, errorString())
            reloadToken = ""
          }
          if (status === Loader.Error) {
            if (!shell.isPluginLoadCurrent(panelEntry.pluginId, panelEntry.entryKind,
                loadEpoch, loadGeneration, loadUrl, panelEntry.manifest)) return
            // Loader.errorString() reflects the source-load failure even when
            // sourceComponent is null. Surface both so the user sees something
            // actionable instead of a panel that silently refuses to open.
            var detail = errorString && errorString() ? errorString() : ""
            if (!detail && sourceComponent) detail = sourceComponent.errorString()
            console.warn("panel plugin " + panelEntry.pluginId + " failed to load:", detail)
            shell.pluginRegistry.pluginLoadFailed(panelEntry.pluginId, detail, loadGeneration,
              "panel:" + panelEntry.entryKind)
            shell.hide(panelEntry.pluginId)
          }
        }
        Component.onCompleted: {
          loadEpoch = shell.pluginLoadEpoch
          loadGeneration = shell.pluginRegistry.pluginSourceGeneration
        }
        Component.onDestruction: {
          reloadToken = ""
          shell.unregisterPanelLoader(panelEntry.pluginId)
        }
      }
    }
  }

  // ---------------------------------------------------------- plugin loader

  // Mirror plugin registry state into BarWidgetRegistry whenever it changes.
  // Each enabled plugin with kind "bar-widget" gets a Component created from
  // its manifest entry point and registered under its manifest id. Built-in
  // widgets use the same first-party manifest contract as third-party widgets.
  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() {
      if (shell.pluginReloading || shell.pluginReloadPending || shell.pluginRegistry.scanning) return
      shell.syncPluginWidgets()
    }
  }

  property var pluginWidgetComponents: ({})

  function syncPluginWidgets() {
    if (shell.testSurfaceSuppressed && !shell.testPluginWidgetLoadEnabled) {
      shell.unloadPluginWidgets()
      return
    }
    var plugins = shell.pluginRegistry.installedPlugins
    var seen = ({})

    for (var pluginId in plugins) {
      var manifest = plugins[pluginId]
      if (!manifest || !manifest.kinds || manifest.kinds.indexOf("bar-widget") === -1) continue
      if (!shell.pluginRegistry.isEnabled(pluginId)) continue

      var registryKey = String(manifest.id)
      seen[registryKey] = true

      // Already loaded with matching source — leave it alone.
      var existing = pluginWidgetComponents[registryKey]
      var url = shell.pluginRegistry.entryPointUrl(manifest, "barWidget")
      if (!url) {
        console.warn("Plugin " + manifest.id + " has no barWidget entry point")
        continue
      }
      var meta = manifest.barWidget || {}
      meta = {
        displayName: meta.displayName || manifest.name,
        description: meta.description || manifest.description,
        category: meta.category || "Plugin",
        allowMultiple: meta.allowMultiple === true,
        defaults: meta.defaults || {},
        settingsForm: meta.settingsForm || "",
        schema: meta.schema || [],
        pluginId: manifest.id,
        sourceDir: manifest.__sourceDir || "",
        source: "plugin"
      }

      // A load already in flight for this URL registers itself when it
      // finishes. Starting a second one produces a second Component for the
      // same widget, and swapping a slot's component rebuilds its item —
      // briefly running two of the widget, each registering its IPC handler.
       if (existing && existing.url === url && existing.loading === true) continue

      // If the component URL is unchanged, just refresh the metadata in
      // place. We can't skip this even when the URL matches: manifests can
      // change schema, defaults, or sourceDir between rescans, and the
      // settings panel reads metadata from the registry.
      if (existing && existing.url === url && shell.barWidgetRegistry.has(registryKey)) {
        shell.barWidgetRegistry.register(registryKey, existing.component, meta)
        continue
      }

      loadPluginWidget(registryKey, url, meta)
    }

    shell.syncHeadlessWidgetInstances()

    // Drop registrations for plugins that are no longer present or enabled.
    var allIds = shell.barWidgetRegistry.availableIds()
    for (var i = 0; i < allIds.length; i++) {
      var id = allIds[i]
      if (!pluginWidgetComponents[id]) continue
      if (!seen[id]) {
        shell.barWidgetRegistry.unregister(id)
        var next = ({})
        for (var k in pluginWidgetComponents) if (k !== id) next[k] = pluginWidgetComponents[k]
        pluginWidgetComponents = next
      }
    }
  }

  property var headlessWidgetInstances: ({})

  function shouldHostHeadlessWidget(pluginId) {
    var manifest = shell.pluginRegistry.installedPlugins[String(pluginId || "")]
    return !!manifest
      && Array.isArray(manifest.kinds)
      && manifest.kinds.indexOf("bar-widget") !== -1
      && manifest.keepLoaded === true
      && shell.pluginRegistry.isEnabled(pluginId)
      && !shell.pluginRegistry.inBar(pluginId)
  }

  function headlessWidgetFor(pluginId) {
    return shell.headlessWidgetInstances[String(pluginId || "")] || null
  }

  function syncHeadlessWidgetInstances() {
    var next = ({})
    for (var existingId in shell.headlessWidgetInstances) {
      if (shell.shouldHostHeadlessWidget(existingId)) next[existingId] = shell.headlessWidgetInstances[existingId]
      else {
        var existing = shell.headlessWidgetInstances[existingId]
        if (existing && typeof existing.destroy === "function") existing.destroy()
      }
    }

    for (var id in shell.pluginWidgetComponents) {
      if (!shell.shouldHostHeadlessWidget(id) || next[id]) continue
      var entry = shell.pluginWidgetComponents[id]
      if (!entry || !entry.component || entry.component.status !== Component.Ready) continue
      var instance = entry.component.createObject(shell)
      if (!instance) {
        var detail = entry.component.errorString ? entry.component.errorString() : ""
        if (!detail) detail = "failed to create hidden widget instance"
        shell.pluginRegistry.pluginLoadFailed(id, detail,
          shell.pluginRegistry.pluginSourceGeneration, "widget-host")
        continue
      }
      if (typeof instance.visible !== "undefined") instance.visible = false
      next[id] = instance
      shell.pluginRegistry.clearPluginError(id, "widget-host")
    }
    shell.headlessWidgetInstances = next
  }

  function unloadHeadlessWidgetInstances() {
    for (var id in shell.headlessWidgetInstances) {
      var instance = shell.headlessWidgetInstances[id]
      if (instance && typeof instance.destroy === "function") instance.destroy()
    }
    shell.headlessWidgetInstances = ({})
  }

  function unloadPluginWidgets() {
    shell.unloadHeadlessWidgetInstances()
    for (var id in pluginWidgetComponents) shell.barWidgetRegistry.unregister(id)
    pluginWidgetComponents = ({})
  }

  function reloadPlugins() {
    shell.pluginLoadEpoch++
    if (shell.pluginReloading || shell.pluginRegistry.scanning) {
      shell.pluginReloadPending = true
      return
    }
    shell.pluginReloadGeneration++
    shell.reloadGenerationError = ""
    shell.reloadComponentStates = ({})
    shell.pluginReloading = true
    pluginBarLoader.reloadToken = ""
    pluginBarLoader.loadGeneration = -1
    shell.pluginBarReloadEnabled = false
    shell.unloadPanels()
    shell.unloadPluginServices()
    shell.unloadPluginWidgets()
    Qt.callLater(shell.finishPluginReload)
  }

  function finishPluginReload() {
    if (!shell.pluginReloading) return
    if (shell.pluginRegistry.scanning) {
      shell.pluginReloadPending = true
      return
    }
    if (typeof Qt.clearComponentCache === "function") Qt.clearComponentCache()
    shell.pluginRegistry.rescan()
  }

  function beginReloadOperation(kind, operationGeneration) {
    if (!shell.pluginReloading) return ""
    var generation = operationGeneration === undefined
      ? shell.pluginReloadGeneration : Number(operationGeneration)
    if (generation !== shell.pluginReloadGeneration) return ""
    shell.reloadTokenCounter++
    var token = String(generation) + ":" + String(shell.reloadTokenCounter)
    var next = ({})
    for (var existing in shell.reloadComponentStates) next[existing] = shell.reloadComponentStates[existing]
    next[token] = { generation: generation, kind: String(kind) }
    shell.reloadComponentStates = next
    return token
  }

  function finishReloadOperation(token, status, detail) {
    var key = String(token || "")
    if (!key || !shell.reloadComponentStates[key]) return false
    var operation = shell.reloadComponentStates[key]
    if (Number(operation.generation) !== shell.pluginReloadGeneration) return false
    var next = ({})
    for (var existing in shell.reloadComponentStates) {
      if (existing !== key) next[existing] = shell.reloadComponentStates[existing]
    }
    shell.reloadComponentStates = next
    return true
  }

  function isReloadTokenCurrent(token) {
    var key = String(token || "")
    return key === "" && !shell.pluginReloading || !!shell.reloadComponentStates[key]
  }

  function isPluginLoadCurrent(id, kind, epoch, generation, url, manifest) {
    var current = shell.pluginRegistry.installedPlugins[String(id)]
    return Number(epoch) === shell.pluginLoadEpoch
      && Number(generation) === shell.pluginRegistry.pluginSourceGeneration
      && !!current
      && shell.pluginRegistry.entryPointUrl(current, kind) === String(url)
      && String(current.__sourceDir || "") === String(manifest.__sourceDir || "")
  }

  Connections {
    target: shell.pluginRegistry
    function onWatchReloadReady() {
      if (shell.pluginReloading || shell.pluginRegistry.scanning) {
        shell.pluginLoadEpoch++
        shell.pluginReloadPending = true
        return
      }
      shell.reloadPlugins()
    }
    function onScanFinished() {
      if (shell.pluginReloadPending) {
        shell.pluginReloadPending = false
        shell.pluginReloading = false
        shell.reloadPlugins()
        return
      }
      shell.pluginReloading = false
      shell._syncServices()
      shell.panelEntries = shell.computePanelEntries()
      shell.syncPluginWidgets()
      shell.pluginBarReloadEnabled = true
    }
    function onRescanRequested() {
      shell.reloadPlugins()
    }
  }

  function setPluginWidgetComponent(registryKey, entry) {
    var next = ({})
    for (var k in pluginWidgetComponents) if (k !== registryKey) next[k] = pluginWidgetComponents[k]
    if (entry) next[registryKey] = entry
    pluginWidgetComponents = next
  }

  function loadPluginWidget(registryKey, url, meta) {
    // Claim the key before the component exists. Qt.createComponent is
    // asynchronous and syncPluginWidgets runs several times while the shell
    // starts, so without a marker the later passes cannot tell a load in
    // flight from one that never happened.
    var loadEpoch = shell.pluginLoadEpoch
    var loadGeneration = shell.pluginRegistry.pluginSourceGeneration
    var loadManifest = shell.pluginRegistry.installedPlugins[registryKey]
    var reloadToken = shell.beginReloadOperation("widget:" + registryKey)
    setPluginWidgetComponent(registryKey, { url: url, component: null, loading: true })
    var comp = shell.testPluginWidgetLoadEnabled
      ? Qt.createComponent(url) : Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      if (comp.status === Component.Loading) return
      if (!shell.isPluginLoadCurrent(registryKey, "barWidget", loadEpoch, loadGeneration, url, loadManifest)) return
      if (reloadToken !== "" && !shell.finishReloadOperation(reloadToken, comp.status, comp.errorString())) return
      if (comp.status === Component.Ready) {
        shell.pluginRegistry.clearPluginError(registryKey, "widget")
        shell.barWidgetRegistry.register(registryKey, comp, meta)
        shell.setPluginWidgetComponent(registryKey, { url: url, component: comp, loading: false })
        shell.syncHeadlessWidgetInstances()
      } else if (comp.status === Component.Error) {
        console.warn("Plugin widget " + registryKey + " failed: " + comp.errorString())
        // Drop the claim so a later rescan can retry.
        shell.setPluginWidgetComponent(registryKey, null)
        shell.pluginRegistry.pluginLoadFailed(registryKey, comp.errorString(), loadGeneration, "widget")
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
    } else {
      finalize()
    }
  }

  function testPluginWidgetReady(id) {
    if (!shell.testPluginWidgetLoadEnabled) return "disabled"
    var key = String(id || "")
    if (!shell.pluginRegistry.installedPlugins[key]) return "absent"
    if (!shell.pluginRegistry.isEnabled(key)) return "absent"
    var entry = shell.pluginWidgetComponents[key]
    if (!entry) return "absent"
    if (!entry.component) return "loading"
    return entry.component.status === Component.Ready ? "ready" : "loading"
  }

  // Bar widgets are instantiated once per screen, but their IPC targets are
  // shell-wide. Keep one handler per target and route calls to the widget on
  // the focused screen; widget state is still shared across all bar screens.
  function barWidgetFor(pluginId) {
    var visible = shell.bar && typeof shell.bar.findPanelWidget === "function"
      ? shell.bar.findPanelWidget(pluginId) : null
    return visible || shell.headlessWidgetFor(pluginId)
  }

  function pingBarWidget(pluginId) {
    var widget = shell.barWidgetFor(pluginId)
    if (!widget) return "unavailable"
    return widget.capabilityAvailable === false ? "unavailable" : "pong"
  }

  function invokeBarWidget(pluginId, method, argument) {
    var widget = shell.barWidgetFor(pluginId)
    if (!widget || typeof widget[method] !== "function") return false
    try {
      if (method === "refresh" && typeof widget.broadcast === "function") {
        widget.broadcast("refresh")
        return true
      }
      if (argument === undefined) widget[method]()
      else widget[method](argument)
      return true
    } catch (error) {
      console.warn("bar widget " + pluginId + " " + method + "() threw:", error)
      return false
    }
  }

  component BarWidgetIpc: IpcHandler {
    required property string pluginId
    target: pluginId

    function ping(): string { return shell.pingBarWidget(pluginId) }
    function open(): void { shell.invokeBarWidget(pluginId, "open") }
    function close(): void { shell.invokeBarWidget(pluginId, "close") }
    function show(): void { shell.invokeBarWidget(pluginId, "open") }
    function hide(): void { shell.invokeBarWidget(pluginId, "close") }
    function toggle(): void { shell.invokeBarWidget(pluginId, "toggle") }
    function refresh(): string {
      return shell.invokeBarWidget(pluginId, "refresh") ? "ok" : "unavailable"
    }
    function brightness(percent: string): string {
      return shell.invokeBarWidget(pluginId, "brightness", percent) ? "ok" : "unavailable"
    }
    function up(): string {
      return shell.invokeBarWidget(pluginId, "up") ? "ok" : "unavailable"
    }
    function down(): string {
      return shell.invokeBarWidget(pluginId, "down") ? "ok" : "unavailable"
    }
    function logout(): string {
      return shell.invokeBarWidget(pluginId, "logout") ? "ok" : "unavailable"
    }
  }

  BarWidgetIpc { pluginId: "desktop.clock" }
  BarWidgetIpc { pluginId: "desktop.audio" }
  BarWidgetIpc { pluginId: "desktop.network" }
  BarWidgetIpc { pluginId: "desktop.bluetooth" }
  BarWidgetIpc { pluginId: "desktop.power" }
  BarWidgetIpc { pluginId: "desktop.monitor" }
  BarWidgetIpc { pluginId: "desktop.tailscale" }
  BarWidgetIpc { pluginId: "desktop.agents" }

  // ---------------------------------------------------------- shell IPC

  IpcHandler {
    id: shellIpc
    target: "desktop-shell"

    function toggleBar(): string {
      shell.barVisible = !shell.barVisible
      return shell.barVisible ? "visible" : "hidden"
    }

    function ping(): string {
      return "pong"
    }

    function health(): string {
      return JSON.stringify(shell.healthState)
    }

    function reloadConfig(): string {
      defaultsFile.reload()
      return "ok"
    }

    function rescanPlugins(): string {
      shell.reloadPlugins()
      return "ok"
    }

    function listPlugins(): string {
      var result = []
      var plugins = pluginRegistry.installedPlugins || ({})
      var ids = Object.keys(plugins).sort()
      for (var i = 0; i < ids.length; i++) {
        var id = ids[i]
        var manifest = plugins[id]
        var kinds = Array.isArray(manifest.kinds) ? manifest.kinds : []
        var isBarOption = kinds.indexOf("bar") !== -1
        var isBarWidget = kinds.indexOf("bar-widget") !== -1
        var active = isBarOption
          ? shell.activeBarId === id
          : isBarWidget ? !!shell.barWidgetFor(id) : pluginRegistry.isEnabled(id)
        result.push({
          id: id,
          name: String(manifest.name || id),
          kinds: kinds,
          enabled: isBarOption ? active
            : (isBarWidget ? pluginRegistry.inBar(id) : pluginRegistry.isEnabled(id)),
          active: active,
          canDisable: !manifest.__isFirstParty && !isBarOption,
          firstParty: !!manifest.__isFirstParty,
          clonedFrom: "",
        })
      }
      return JSON.stringify(result)
    }

    function parseJsonValue(raw, fallback) {
      if (raw === undefined || raw === null || String(raw).trim() === "") return { valid: true, value: fallback }
      try {
        return { valid: true, value: JSON.parse(String(raw)) }
      } catch (error) {
        return { valid: false, value: fallback }
      }
    }

    function parseJsonObject(raw, fallback) {
      var parsed = shellIpc.parseJsonValue(raw, fallback)
      return parsed.valid && parsed.value && typeof parsed.value === "object" && !Array.isArray(parsed.value)
        ? parsed.value : null
    }

    function pluginMutationResult(ok) {
      var error = String(pluginRegistry.lastEnableError || "")
      if (ok) return "ok"
      if (error.indexOf("unknown plugin ") === 0) return "unknown"
      if (error !== "") return error
      if (shell.pluginStateWriteError !== "") return "plugin state write failed: " + shell.pluginStateWriteError
      if (shell.pluginStateError !== "") return shell.pluginStateError
      return "plugin state write failed"
    }

    function setPluginEnabled(id: string, enabled: bool): string {
      return shellIpc.pluginMutationResult(pluginRegistry.setEnabled(id, enabled, {}))
    }

    function enablePlugin(id: string, placementJson: string): string {
      var placement = shellIpc.parseJsonObject(placementJson, ({}))
      if (placement === null) return "invalid placement JSON"
      return shellIpc.pluginMutationResult(pluginRegistry.setEnabled(id, true, placement))
    }

    function putBarWidget(id: string, placementJson: string): string {
      var placement = shellIpc.parseJsonObject(placementJson, ({}))
      if (placement === null) return "invalid placement JSON"
      return shellIpc.pluginMutationResult(pluginRegistry.putBarWidget(id, placement))
    }

    function moveBarWidget(id: string, placementJson: string): string {
      var placement = shellIpc.parseJsonObject(placementJson, ({}))
      if (placement === null) return "invalid placement JSON"
      return shellIpc.pluginMutationResult(pluginRegistry.moveBarWidget(id, placement))
    }

    function setBarWidget(id: string, key: string, valueJson: string, selectorJson: string): string {
      var parsedValue = shellIpc.parseJsonValue(valueJson, null)
      var selector = shellIpc.parseJsonObject(selectorJson, ({}))
      if (!parsedValue.valid || selector === null) return "invalid widget JSON"
      return shellIpc.pluginMutationResult(pluginRegistry.setBarWidget(id, key, parsedValue.value))
    }

    // Returns the effective shell.json content as JSON. Useful for debugging
    // and for CLI tools that want to inspect the merged state without
    // re-implementing the load logic.
    function listShellConfig(): string {
      return JSON.stringify(shell.shellConfig || {})
    }

    function debugBarGeometry(): string {
      return JSON.stringify(shell.bar && shell.bar.debugBarGeometry ? shell.bar.debugBarGeometry() : [])
    }

    function summon(id: string, payloadJson: string): string {
      return shell.summon(id, payloadJson) ? "ok" : "unknown"
    }

    function hide(id: string): void {
      shell.hide(id)
    }

    function toggle(id: string, payloadJson: string): void {
      shell.toggle(id, payloadJson)
    }

    // A bar section's panels answer to their position as well as their id, so a
    // hotkey can mean "the third panel in the right section" and keep meaning
    // it after the bar is rearranged. Returns the id it acted on, or "unknown"
    // when the section holds no panel at that position.
    function togglePanelAt(section: string, index: string): string {
      var id = shell.bar && typeof shell.bar.panelWidgetIdAt === "function"
        ? shell.bar.panelWidgetIdAt(section, index)
        : ""
      if (!id) return "unknown"
      shell.toggle(id, "{}")
      return id
    }

    function call(id: string, method: string, arg: string): string {
      return shell.callIfLoaded(id, method, arg)
    }
  }

  IpcHandler {
    target: "desktop-shell-test"
    enabled: shell.testMutationEnabled

    function persistPluginStateForTest(rawState: string): string {
      var nextState
      try {
        nextState = JSON.parse(rawState)
      } catch (error) {
        return "rejected-invalid-state"
      }
      if (shell.persistPluginState(nextState)) return "saved"
      if (!shell.pluginStateValid) return "rejected-invalid-state"
      if (shell.pluginStateWriteError !== "") return "rejected-write-failed"
      if (!shell.pluginStateDirectoryReady) return "rejected-not-ready"
      return "pending"
    }

    function pluginWidgetReady(id: string): string {
      return shell.testPluginWidgetReady(id)
    }

    function headlessWidgetReady(id: string): string {
      return shell.headlessWidgetFor(id) ? "ready" : "absent"
    }

    function headlessWidgetState(id: string): string {
      var widget = shell.headlessWidgetFor(id)
      return widget ? JSON.stringify({ opened: widget.opened === true, openCount: Number(widget.openCount || 0) }) : "{}"
    }

    function pluginBarTestProbe(): string {
      return shell.pluginBarTestProbe()
    }

    function queuePluginChangeForTest(path: string): string {
      pluginRegistry.queueLocalPluginChange(path)
      return "queued"
    }
  }
}
