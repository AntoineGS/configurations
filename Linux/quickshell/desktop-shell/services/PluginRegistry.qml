import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "PluginState.js" as PluginState

QtObject {
  id: registry

  property string firstPartyDir: ""
  property string home: Quickshell.env("HOME")
  property string configuredPluginsDir: Quickshell.env("DESKTOP_SHELL_PLUGINS_DIR")
  property string pluginsDir: configuredPluginsDir !== ""
    ? configuredPluginsDir : home + "/.config/omarchy/plugins"
  property bool pluginWatchEnabled: Quickshell.env("DESKTOP_SHELL_DISABLE_PLUGIN_WATCH") !== "1"
  property var shellConfigProvider: null
  property var pluginStateProvider: null
  property var pluginStateWriter: null
  property var installedPlugins: ({})
  property int registryRevision: 0
  property bool scanning: false
  property var pluginErrors: []
  property string lastScanError: ""
  property string lastEnableError: ""
  property bool watcherUnavailable: false
  property bool watcherStopRequested: false
  property var pendingWatchIds: ({})
  property string watcherGuardError: ""
  property int guardRetryCount: 0
  property int guardRetryLimit: 3
  property int guardRetryBaseDelay: 100
  property int scanFinishedCount: 0
  property int watchChangeCount: 0

  signal pluginsChanged()
  signal scanFinished()
  signal pluginLoadFailed(string id, string error, int generation)
  signal localPluginChanged(string id)
  signal watchReloadReady()

  function recordPluginError(id, error) {
    var key = String(id)
    var next = []
    for (var i = 0; i < registry.pluginErrors.length; i++) {
      var entry = registry.pluginErrors[i]
      if (!entry || String(entry.id) !== key) next.push(entry)
    }
    next.push({ id: key, error: String(error) })
    registry.pluginErrors = next
  }

  function clearPluginError(id) {
    var key = String(id)
    var next = []
    for (var i = 0; i < registry.pluginErrors.length; i++) {
      var entry = registry.pluginErrors[i]
      if (entry && String(entry.id) === key) continue
      next.push(entry)
    }
    registry.pluginErrors = next
  }

  function rejectManifest(manifest, sourcePath, reason) {
    var id = manifest && manifest.id !== undefined ? String(manifest.id) : String(sourcePath)
    var detail = String(reason) + " at " + sourcePath
    console.warn("PluginRegistry: " + detail)
    registry.recordPluginError(id, detail)
    return null
  }

  onPluginLoadFailed: function(id, error) {
    registry.recordPluginError(id, error)
  }

  function isSafeEntryPoint(value) {
    if (typeof value !== "string" || value.length === 0) return false
    if (value.charAt(0) === "/" || value.charAt(0) === "\\") return false
    if (/^[A-Za-z]:[\\/]/.test(value)) return false
    if (value.indexOf("..") !== -1) return false
    return true
  }

  function validateManifest(manifest, sourcePath, kind) {
    if (!Util.isPlainObject(manifest)) {
      return registry.rejectManifest(manifest, sourcePath, "manifest is not an object")
    }
    if (manifest.schemaVersion !== 1) {
      return registry.rejectManifest(manifest, sourcePath, "unsupported schemaVersion")
    }
    var required = ["id", "name", "version", "kinds", "entryPoints"]
    for (var i = 0; i < required.length; i++) {
      if (manifest[required[i]] === undefined) {
        return registry.rejectManifest(manifest, sourcePath,
          "missing required field '" + required[i] + "'")
      }
    }
    var id = String(manifest.id)
    var validId = kind === "firstparty"
      ? /^desktop\.[a-z0-9-]+$/.test(id)
      : PluginState.isThirdPartyId(id)
    if (!validId) {
      return registry.rejectManifest(manifest, sourcePath, "invalid plugin id '" + id + "'")
    }
    if (!Array.isArray(manifest.kinds) || manifest.kinds.length === 0) {
      return registry.rejectManifest(manifest, sourcePath, "kinds must be a non-empty array")
    }
    if (!Util.isPlainObject(manifest.entryPoints)) {
      return registry.rejectManifest(manifest, sourcePath, "entryPoints must be an object")
    }
    var allowedKinds = ["bar", "bar-widget", "menu", "overlay", "panel", "service"]
    for (var kindIndex = 0; kindIndex < manifest.kinds.length; kindIndex++) {
      var manifestKind = String(manifest.kinds[kindIndex])
      var entryPointKey = manifestKind === "bar-widget" ? "barWidget" : manifestKind
      if (allowedKinds.indexOf(manifestKind) === -1 || manifest.entryPoints[entryPointKey] === undefined) {
        return registry.rejectManifest(manifest, sourcePath, "kind '" + manifestKind
          + "' requires a matching entry point")
      }
    }
    if (manifest.barWidget !== undefined && Util.isPlainObject(manifest.barWidget)
        && manifest.barWidget.defaultSection !== undefined) {
      var defaultSection = String(manifest.barWidget.defaultSection)
      if (["left", "center", "right"].indexOf(defaultSection) === -1) {
        return registry.rejectManifest(manifest, sourcePath, "invalid barWidget.defaultSection")
      }
    }
    for (var key in manifest.entryPoints) {
      if (!isSafeEntryPoint(manifest.entryPoints[key])) {
        return registry.rejectManifest(manifest, sourcePath, "unsafe entryPoint '" + key + "'='"
          + manifest.entryPoints[key] + "'")
      }
    }
    return manifest
  }

  function entryPointUrl(manifest, kind) {
    if (!Util.isPlainObject(manifest)) return ""
    var ep = manifest.entryPoints ? manifest.entryPoints[kind] : null
    if (!ep) return ""
    var dir = manifest.__sourceDir || ""
    if (!dir) return ""
    var resolved = dir.replace(/\/$/, "") + "/" + String(ep)
    var expectedPrefix = dir.replace(/\/$/, "") + "/"
    if (resolved.indexOf(expectedPrefix) !== 0) {
      console.warn("PluginRegistry: entry point escapes sourceDir: " + resolved)
      return ""
    }
    return Util.fileUrl(resolved)
  }

  function isDisabled(config, id) {
    return Util.isPlainObject(config) && Array.isArray(config.disabledPlugins)
      && config.disabledPlugins.indexOf(Util.canonicalWidgetId(String(id))) !== -1
  }

  function barEntryId(entry) {
    return Util.canonicalWidgetId(String(Util.isPlainObject(entry) ? entry.id : entry || ""))
  }

  function findBarLocation(config, id, section) {
    if (!Util.isPlainObject(config) || !Util.isPlainObject(config.bar)
        || !Util.isPlainObject(config.bar.layout)) return { found: false }
    var key = Util.canonicalWidgetId(String(id))
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      if (section && sections[s] !== section) continue
      var entries = config.bar.layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        if (barEntryId(entries[i]) === key)
          return { found: true, kind: "bar", section: sections[s], index: i }
      }
    }
    return { found: false }
  }

  function findEntryLocation(config, id) {
    if (!Util.isPlainObject(config)) return { found: false }
    var key = Util.canonicalWidgetId(String(id))
    if (Util.isPlainObject(config.bar)) {
      var selectedBar = Util.canonicalWidgetId(String(config.bar.id || ""))
      if (selectedBar === key) return { found: true, kind: "bar-option" }
    }
    var barLocation = findBarLocation(config, key, "")
    if (barLocation.found) return barLocation
    if (Array.isArray(config.plugins)) {
      for (var i = 0; i < config.plugins.length; i++) {
        if (config.plugins[i] && Util.canonicalWidgetId(config.plugins[i].id) === key)
          return { found: true, kind: "plugin", index: i }
      }
    }
    return { found: false }
  }

  function isEnabled(id) {
    var key = Util.canonicalWidgetId(String(id || ""))
    var manifest = installedPlugins[key]
    if (!manifest) return false
    var config = shellConfigProvider ? shellConfigProvider() : null
    if (Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar") !== -1) {
      var selectedBar = ""
      if (Util.isPlainObject(config) && Util.isPlainObject(config.bar))
        selectedBar = Util.canonicalWidgetId(String(config.bar.id || ""))
      if (!selectedBar) selectedBar = "desktop.bar"
      return selectedBar === key
    }
    if (isDisabled(config, key)) return false
    if (manifest.__isFirstParty) return true
    return findEntryLocation(config, key).found
  }

  function resolveEnabledId(id) {
    return Util.canonicalWidgetId(String(id || ""))
  }

  function inBar(id) {
    var config = shellConfigProvider ? shellConfigProvider() : null
    return findBarLocation(config, id, "").found
  }

  function applyStateResult(result) {
    lastEnableError = result && result.error ? String(result.error) : ""
    if (!result || !result.ok || !pluginStateWriter) return false
    return pluginStateWriter(result.state)
  }

  function setEnabled(id, value, placement) {
    var key = String(id || "")
    var manifest = installedPlugins[key]
    if (!manifest && key !== "desktop.bar") {
      lastEnableError = "unknown plugin " + key
      return false
    }
    var state = pluginStateProvider ? pluginStateProvider() : PluginState.emptyState()
    var effective = shellConfigProvider ? shellConfigProvider() : {}
    return applyStateResult(PluginState.setEnabled(state, manifest || {
      id: "desktop.bar", kinds: ["bar"], __isFirstParty: true
    }, value, placement || {}, effective))
  }

  function putBarWidget(id, section, index) {
    var placement = Util.isPlainObject(section) ? section : { section: section, index: index }
    return setEnabled(id, true, placement)
  }

  function moveBarWidget(id, section, index) {
    var state = pluginStateProvider ? pluginStateProvider() : PluginState.emptyState()
    var effective = shellConfigProvider ? shellConfigProvider() : {}
    var placement = Util.isPlainObject(section) ? section : { section: section, index: index }
    return applyStateResult(PluginState.moveWidget(state, String(id || ""), placement, effective))
  }

  function setBarWidget(id, key, value) {
    var state = pluginStateProvider ? pluginStateProvider() : PluginState.emptyState()
    return applyStateResult(PluginState.setWidget(state, String(id || ""), key, value))
  }

  function localPluginIdForPath(path) {
    var value = String(path || "")
    var root = pluginsDir.replace(/\/$/, "") + "/"
    if (value.indexOf(root) !== 0) return ""
    var relative = value.slice(root.length).split("/")
    for (var i = 0; i < relative.length; i++) {
      if (!relative[i] || relative[i].charAt(0) === "." || relative[i] === ".git") return ""
    }
    return relative.length ? relative[0] : ""
  }

  function queueLocalPluginChange(value) {
    var candidate = localPluginIdForPath(value)
    var id = candidate || String(value || "")
    if (!id) return
    var next = ({})
    for (var existing in registry.pendingWatchIds) next[existing] = true
    next[id] = true
    registry.pendingWatchIds = next
    if (!registry.guardProcess.running) registry.startWatchReloadGuard()
  }

  function handleWatchOutput(text) {
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var id = localPluginIdForPath(lines[i])
      if (!id) continue
      registry.queueLocalPluginChange(id)
    }
  }

  function startWatchReloadGuard() {
    if (registry.guardProcess.running || Object.keys(registry.pendingWatchIds).length === 0)
      return
    if (registry.guardRetryTimer.running) registry.guardRetryTimer.stop()
    var ids = []
    for (var id in registry.pendingWatchIds) ids.push(id)
    registry.pendingWatchIds = ({})
    guardProcess.command = ["bash", "-c",
      "command -v flock >/dev/null 2>&1 || exit 125; "
      + "exec 9>\"$0/.plugin-manager.lock\"; "
      + "flock 9; flock -u 9; printf '%s\\n' \"${@:2}\"", registry.pluginsDir, "--"].concat(ids)
    guardProcess.running = true
  }

  function scheduleGuardRetry(detail) {
    registry.watcherGuardError = String(detail)
    if (registry.guardRetryCount >= registry.guardRetryLimit) {
      registry.watcherGuardError += " (retry limit reached)"
      return
    }
    registry.guardRetryCount++
    registry.guardRetryTimer.interval = Math.min(
      registry.guardRetryBaseDelay * Math.pow(2, registry.guardRetryCount - 1), 2000)
    registry.guardRetryTimer.restart()
  }

  // Output format: ===kind::<absolute-source-dir>===, manifest JSON, then EOM.
  function parseScanOutput(text) {
    registry.pluginErrors = []
    var lines = String(text || "").split("\n")
    var firstParty = {}
    var thirdPartyCandidates = ({})
    var thirdPartySources = ({})
    var ambiguousThirdPartyIds = ({})
    var currentSource = null
    var currentKind = null
    var currentJson = []

    function flush() {
      if (!currentSource) return
      var raw = currentJson.join("\n").trim()
      if (currentKind === "firstparty" || currentKind === "thirdparty") {
        try {
          var manifest = JSON.parse(raw)
          manifest.__sourceDir = currentSource
          manifest.__isFirstParty = currentKind === "firstparty"
          var validated = validateManifest(manifest, currentSource + "/manifest.json", currentKind)
          if (validated && currentKind === "firstparty") firstParty[validated.id] = validated
          if (validated && currentKind === "thirdparty") {
            if (!thirdPartySources[validated.id]) thirdPartySources[validated.id] = []
            thirdPartySources[validated.id].push(currentSource + "/manifest.json")
            thirdPartyCandidates[validated.id] = validated
            if (thirdPartySources[validated.id].length > 1)
              ambiguousThirdPartyIds[validated.id] = true
          }
        } catch (e) {
          registry.recordPluginError(currentSource + "/manifest.json", "invalid JSON: " + e)
          console.warn("PluginRegistry: bad manifest at " + currentSource + ": " + e)
        }
      }
      currentSource = null
      currentKind = null
      currentJson = []
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var startMatch = line.match(/^===([a-z]+)::(.+)===$/)
      if (startMatch) {
        flush()
        currentKind = startMatch[1]
        currentSource = startMatch[2].replace(/\/$/, "")
        currentJson = []
        continue
      }
      if (line === "=== EOM ===") {
        flush()
        continue
      }
      if (currentSource) currentJson.push(line)
    }
    flush()

    registry.lastScanError = ""
    registry.clearPluginError("registry")
    var thirdParty = ({})
    for (var candidateId in thirdPartyCandidates) {
      var sources = thirdPartySources[candidateId]
      if (firstParty[candidateId]) {
        registry.recordPluginError(candidateId, "third-party plugin shadows first-party plugin at "
          + sources.join(", "))
      } else if (ambiguousThirdPartyIds[candidateId]) {
        registry.recordPluginError(candidateId, "ambiguous third-party plugin sources: "
          + sources.join(", "))
      } else {
        thirdParty[candidateId] = thirdPartyCandidates[candidateId]
      }
    }
    var merged = ({})
    for (var firstId in firstParty) merged[firstId] = firstParty[firstId]
    for (var thirdId in thirdParty) {
      if (!firstParty[thirdId]) merged[thirdId] = thirdParty[thirdId]
    }
    installedPlugins = merged
    registryRevision++
    scanning = false
    pluginsChanged()
    registry.scanFinishedCount++
    scanFinished()
  }

  function handleScanExit(exitCode, rawOutput) {
    if (Number(exitCode) !== 0) {
      registry.lastScanError = "plugin scan failed with exit code " + String(exitCode)
      registry.recordPluginError("registry", registry.lastScanError)
      registry.scanning = false
      console.warn("PluginRegistry: " + registry.lastScanError)
      registry.scanFinishedCount++
      registry.scanFinished()
      return false
    }
    registry.parseScanOutput(rawOutput)
    return true
  }

  property Process scanProcess: Process {
    onExited: function(exitCode) {
      registry.handleScanExit(exitCode, scanStdout.text || "")
    }

    stdout: StdioCollector {
      id: scanStdout
      waitForEnd: true
    }
  }

  function ensureUserDir() {
    userDirProcess.command = ["bash", "-c", "mkdir -p -- \"$0\"", registry.pluginsDir]
    userDirProcess.running = true
  }

  function initProcess() {
    if (!registry.pluginWatchEnabled || registry.watcherUnavailable || registry.watcherProcess.running) return
    registry.watcherStopRequested = false
    watcherProcess.command = ["bash", "-c",
      "command -v inotifywait >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 || exit 125; "
      + "inotifywait -m -r -e close_write,create,delete,move --format '%w%f' -- \"$0\"",
      registry.pluginsDir]
    watcherProcess.running = true
  }

  function handleWatcherExit(exitCode) {
    if (registry.watcherStopRequested) {
      registry.watcherStopRequested = false
      return
    }
    if (Number(exitCode) === 125) {
      registry.watcherUnavailable = true
      return
    }
    if (registry.pluginWatchEnabled) watchRestartTimer.restart()
  }

  function stopWatcher() {
    if (!registry.watcherProcess.running) return
    registry.watcherStopRequested = true
    registry.watcherProcess.running = false
  }

  property Process userDirProcess: Process {
    onExited: function(exitCode) {
      if (Number(exitCode) === 0) registry.initProcess()
    }
  }

  property Process watcherProcess: Process {
    onExited: function(exitCode) { registry.handleWatcherExit(exitCode) }
    stdout: StdioCollector {
      id: watcherStdout
      waitForEnd: false
      onTextChanged: registry.handleWatchOutput(text)
    }
  }

  property Process guardProcess: Process {
    onExited: function(exitCode) {
      if (Number(exitCode) !== 0) {
        registry.scheduleGuardRetry("plugin watcher lock wait failed with exit code " + String(exitCode))
      } else {
        registry.watcherGuardError = ""
        registry.guardRetryCount = 0
      }
      if (Object.keys(registry.pendingWatchIds).length > 0) registry.startWatchReloadGuard()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onTextChanged: {
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var id = lines[i]
          if (!id) continue
          registry.watchChangeCount++
          registry.localPluginChanged(id)
        }
        if (lines.length > 0) registry.watchReloadReady()
      }
    }
  }

  property Timer guardRetryTimer: Timer {
    interval: 100
    repeat: false
    onTriggered: registry.startWatchReloadGuard()
  }

  property Timer watchRestartTimer: Timer {
    interval: 1000
    repeat: false
    onTriggered: {
      if (!registry.pluginWatchEnabled || registry.watcherUnavailable || registry.watcherProcess.running) return
      registry.rescan()
    }
  }

  function rescan() {
    if (scanning) return
    scanning = true
    var script = ""
      + "emit_manifest() { local manifest=\"$1\"; "
      + "  local kind=\"$2\"; "
      + "  if [[ ${manifest##*/} == manifest.json ]]; then "
      + "    source=\"${manifest%/manifest.json}\"; "
      + "  else source=\"$(dirname -- \"$manifest\")\"; fi; "
      + "  printf '===%s::%s===\\n' \"$kind\" \"$source\"; "
      + "  cat \"$manifest\"; printf '\\n=== EOM ===\\n'; "
      + "}; "
      + "scan_firstparty() { local dir=\"$1\"; [[ -d \"$dir\" ]] || return 0; "
      + "  while IFS= read -r manifest; do emit_manifest \"$manifest\" firstparty; done "
      + "  < <(find \"$dir\" -mindepth 2 -maxdepth 3 -type f "
      + "\\( -name manifest.json -o -name '*.manifest.json' \\) | sort); "
      + "}; "
      + "scan_thirdparty() { local dir=\"$1\"; [[ -d \"$dir\" ]] || return 0; "
      + "  while IFS= read -r sub; do "
      + "    [[ -d \"$sub\" ]] || continue; "
      + "    [[ \"$sub\" == */.* || \"$sub\" == */.git ]] && continue; "
      + "    find \"$sub\" -path \"$sub/.git\" -prune -o -type l -print -quit | grep -q . && continue; "
      + "    manifest=\"$sub/manifest.json\"; [[ -f \"$manifest\" && ! -L \"$manifest\" ]] || continue; "
      + "    valid=1; while IFS= read -r entry; do "
      + "      [[ \"$entry\" != /* && \"$entry\" != *..* && \"$entry\" != *\\\\* ]] || { valid=0; break; }; "
      + "      file=\"$sub/$entry\"; [[ -f \"$file\" && ! -L \"$file\" ]] || { valid=0; break; }; "
      + "    done < <(jq -r '.entryPoints // {} | .[]? // empty' \"$manifest\" 2>/dev/null); "
      + "    [[ $valid == 1 ]] && emit_manifest \"$manifest\" thirdparty; "
      + "  done < <(find \"$dir\" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort); "
      + "}; scan_firstparty \"$0\"; scan_thirdparty \"$1\""
    scanProcess.command = ["bash", "-c", script, registry.firstPartyDir, registry.pluginsDir]
    scanProcess.running = true
    ensureUserDir()
  }

}
