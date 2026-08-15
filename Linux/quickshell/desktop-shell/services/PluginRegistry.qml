import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// First-party manifest discovery for the repository-owned shell. The registry
// deliberately has no user plugin directory or mutation API: the shell owns
// the source tree and configuration, while later tasks add selected manifests.
QtObject {
  id: registry

  property string firstPartyDir: ""
  property var shellConfigProvider: null
  property var installedPlugins: ({})
  property int registryRevision: 0
  property bool scanning: false
  property var pluginErrors: []
  property string lastScanError: ""

  signal pluginsChanged()
  signal scanFinished()
  signal pluginLoadFailed(string id, string error)

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

  function validateManifest(manifest, sourcePath) {
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
    if (!/^desktop\.[a-z0-9-]+$/.test(id)) {
      return registry.rejectManifest(manifest, sourcePath, "invalid plugin id '" + id + "'")
    }
    if (!Array.isArray(manifest.kinds) || manifest.kinds.length === 0) {
      return registry.rejectManifest(manifest, sourcePath, "kinds must be a non-empty array")
    }
    if (!Util.isPlainObject(manifest.entryPoints)) {
      return registry.rejectManifest(manifest, sourcePath, "entryPoints must be an object")
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

  // Output format: ===firstparty::<absolute-source-dir>===, manifest JSON,
  // then === EOM ===. Each first-party directory can contain one manifest or
  // sibling *.manifest.json bar-widget manifests.
  function parseScanOutput(text) {
    registry.pluginErrors = []
    var lines = String(text || "").split("\n")
    var firstParty = {}
    var currentSource = null
    var currentKind = null
    var currentJson = []

    function flush() {
      if (!currentSource) return
      var raw = currentJson.join("\n").trim()
      if (currentKind === "firstparty") {
        try {
          var manifest = JSON.parse(raw)
          manifest.__sourceDir = currentSource
          manifest.__isFirstParty = true
          var validated = validateManifest(manifest, currentSource + "/manifest.json")
          if (validated) firstParty[validated.id] = validated
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
    installedPlugins = firstParty
    registryRevision++
    scanning = false
    pluginsChanged()
    scanFinished()
  }

  function handleScanExit(exitCode, rawOutput) {
    if (Number(exitCode) !== 0) {
      registry.lastScanError = "first-party plugin scan failed with exit code " + String(exitCode)
      registry.recordPluginError("registry", registry.lastScanError)
      registry.scanning = false
      console.warn("PluginRegistry: " + registry.lastScanError)
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

  function rescan() {
    if (scanning) return
    scanning = true
    var script = ""
      + "emit_manifest() { local manifest=\"$1\"; "
      + "  if [[ ${manifest##*/} == manifest.json ]]; then "
      + "    source=\"${manifest%/manifest.json}\"; "
      + "  else source=\"$(dirname -- \"$manifest\")\"; fi; "
      + "  printf '===firstparty::%s===\\n' \"$source\"; "
      + "  cat \"$manifest\"; printf '\\n=== EOM ===\\n'; "
      + "}; "
      + "scan_firstparty() { local dir=\"$1\"; [[ -d \"$dir\" ]] || return 0; "
      + "  while IFS= read -r manifest; do emit_manifest \"$manifest\"; done "
      + "  < <(find \"$dir\" -mindepth 2 -maxdepth 3 -type f "
      + "\\( -name manifest.json -o -name '*.manifest.json' \\) | sort); "
      + "}; scan_firstparty \"$0\""
    scanProcess.command = ["bash", "-c", script, registry.firstPartyDir]
    scanProcess.running = true
  }
}
