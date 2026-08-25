pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "BorderGeometry.js" as Geometry
import "CardStyle.js" as CardStyle

// Color surfaces for the shell. Foundational palette (foreground, background,
// accent, urgent) comes from theme/colors.toml. Per-surface roles come from
// theme/shell.toml — generated per theme from default/themed/shell.toml.tpl,
// or shipped directly by a theme to replace the generated file. Surfaces that
// don't appear in shell.toml fall back to the foundational palette.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentThemePath: stateHome + "/desktop-shell/current/theme"

  property color foreground: "#cdd6f4"
  property color background: "#1e1e2e"
  property color accent: "#cba6f7"
  property color urgent: "#f38ba8"
  property color muted: "#7f849c"

  // Flat dictionary of "section.key" -> raw string from shell.toml.
  // Reassigning this whole property is what makes surface bindings below
  // re-evaluate when the theme swaps; mutating it in place would not.
  property var shellValues: ({})

  function pick(key, fallback) {
    var v = shellValues[key]
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  function pickAlpha(key, fallback) {
    var v = shellValues[key]
    if (typeof v !== "string" || v.length === 0) return fallback
    var n = Number(v)
    if (!isFinite(n)) return fallback
    return Util.clampAlpha(n)
  }

  function inheritedPick(section, key, baseSection, fallback) {
    return CardStyle.inheritedPick(root.shellValues, section, key, baseSection, fallback)
  }

  function inheritedAlpha(section, key, baseSection, fallback) {
    return CardStyle.inheritedAlpha(root.shellValues, section, key, baseSection, fallback)
  }

  function inheritedComposed(section, baseSection, colorKey, alphaKey, colorFallback, alphaFallback) {
    return Util.alpha(
      flatColor(inheritedPick(section, colorKey, baseSection, colorFallback), colorFallback),
      inheritedAlpha(section, alphaKey, baseSection, alphaFallback))
  }

  function firstColorToken(value) {
    var parts = String(value || "").replace(/^\s+|\s+$/g, "").split(/\s+/)
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i].match(/^-?\d+(?:\.\d+)?deg$/)) return parts[i]
    }
    return value
  }

  function flatColor(value, fallback) {
    var token = firstColorToken(value)
    var role = String(token || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    if (root.shellValues[role] && root.shellValues[role] !== token) return flatColor(root.shellValues[role], fallback)
    if (role === "foreground" || role === "text") return root.foreground
    if (role === "accent") return root.accent
    if (role === "urgent") return root.urgent
    if (role === "muted") return root.muted
    if (role === "background") return root.background
    if (role === "transparent") return Qt.rgba(0, 0, 0, 0)

    var color = Geometry.canonicalColor(token, 1)
    if (typeof color === "string" && color === token && token.charAt(0) !== "#") return fallback
    return color
  }

  // Compose a color from a base-color key and its `-alpha` companion. If the
  // base token is a gradient, color-only consumers use the first stop.
  function composed(colorKey, alphaKey, colorFallback, alphaFallback) {
    return Util.alpha(flatColor(pick(colorKey, colorFallback), colorFallback), pickAlpha(alphaKey, alphaFallback))
  }

  readonly property QtObject bar: QtObject {
    property color background: root.composed("bar.background", "bar.background-alpha", root.background, 1.0)
    property color text: root.pick("bar.text", root.foreground)
    property color active: root.pick("bar.active", root.urgent)
  }
  readonly property QtObject cards: QtObject {
    property color background: root.composed("cards.background", "cards.background-alpha", root.background, 1.0)
    property color text: root.pick("cards.text", root.foreground)
    property color secondaryText: root.pick("cards.text-secondary", root.foreground)
    property color border: root.composed("cards.border", "cards.border-alpha", root.accent, 1.0)
  }
  readonly property QtObject popups: QtObject {
    property color background: root.composed("popups.background", "popups.background-alpha", root.background, 1.0)
    property color text: root.pick("popups.text", root.foreground)
    property color border: root.composed("popups.border", "popups.border-alpha", root.accent, 1.0)
  }
  readonly property QtObject tooltip: QtObject {
    property color background: root.inheritedComposed("tooltip",
      "cards", "background", "background-alpha", root.background, 1.0)
    property color text: root.inheritedPick("tooltip", "text", "cards", root.foreground)
    property color secondaryText: root.inheritedPick("tooltip", "text-secondary", "cards", root.foreground)
    property color border: root.inheritedComposed("tooltip",
      "cards", "border", "border-alpha", root.foreground, 1.0)
  }
  readonly property QtObject barPanels: QtObject {
    property color background: root.inheritedComposed("bar-panels",
      "cards", "background", "background-alpha", root.background, 1.0)
    property color text: root.inheritedPick("bar-panels", "text", "cards", root.foreground)
    property color secondaryText: root.inheritedPick("bar-panels", "text-secondary", "cards", root.foreground)
    property color border: root.inheritedComposed("bar-panels",
      "cards", "border", "border-alpha", root.accent, 1.0)
  }
  readonly property QtObject notifications: QtObject {
    property color background: root.inheritedComposed("notifications",
      "cards", "background", "background-alpha", root.background, 1.0)
    property color text: root.inheritedPick("notifications", "text", "cards", root.foreground)
    property color secondaryText: root.inheritedPick("notifications", "text-secondary", "cards", root.foreground)
    property color border: root.inheritedComposed("notifications",
      "cards", "border", "border-alpha", root.accent, 1.0)
    property color countdown: root.pick("notifications.countdown", root.accent)
    property color low: root.pick("notifications.low", "#89dceb")
    property color critical: root.pick("notifications.critical", root.urgent)
  }
  readonly property QtObject modal: QtObject {
    property color scrim: root.composed(
      "modal.scrim",
      "modal.scrim-alpha",
      root.background,
      0.5
    )
  }
  // polkit + lock share a single border-alpha across border / border-active /
  // border-error: the three states are mutually exclusive in time, so one
  // companion is enough.
  readonly property QtObject polkit: QtObject {
    property color background: root.inheritedComposed(
      "polkit", "bar-panels", "background", "background-alpha", root.background, 1.0)
    property color text: root.inheritedPick("polkit", "text", "bar-panels", root.foreground)
    property color border: root.inheritedComposed(
      "polkit", "bar-panels", "border", "border-alpha", root.accent, 1.0)
    property color textError: root.pick("polkit.text-error", root.urgent)
    property color borderError: root.composed(
      "polkit.border-error", "polkit.border-alpha", root.urgent, 1.0)
    property color accent: root.pick("polkit.accent", root.accent)
    property color scrim: root.composed(
      "polkit.scrim", "polkit.scrim-alpha", root.background, 0.5)
  }
  readonly property QtObject lock: QtObject {
    property color background: root.composed("lock.background", "lock.background-alpha", root.background, 0.8)
    property color text: root.pick("lock.text", root.foreground)
    property color placeholder: root.shellValues["lock.placeholder"] ? root.flatColor(root.shellValues["lock.placeholder"], Util.alpha(root.foreground, 0.66)) : Util.alpha(root.foreground, 0.66)
    property color textError: root.pick("lock.text-error", root.urgent)
    property color border: root.composed("lock.border", "lock.border-alpha", root.foreground, 1.0)
    property color borderActive: root.composed("lock.border-active", "lock.border-alpha", root.accent, 1.0)
    property color borderError: root.composed("lock.border-error", "lock.border-alpha", root.urgent, 1.0)
    property color selection: root.composed("lock.selection", "lock.selection-alpha", root.accent, 0.45)
  }
  // The image picker has no card surface; `scrim` is the full-screen dim
  // wash, and per-slice dim overlays / text outlines use the foundational
  // `background` color directly.
  readonly property QtObject imagePicker: QtObject {
    property color scrim: root.composed("image-picker.scrim", "image-picker.scrim-alpha", root.background, 0.5)
    property color text: root.pick("image-picker.text", root.foreground)
    property color selectedBorder: root.composed("image-picker.selected-border", "image-picker.selected-border-alpha", root.accent, 1.0)
    property color unselectedBorder: root.composed("image-picker.unselected-border", "image-picker.unselected-border-alpha", root.foreground, 0.28)
  }

  function loadColors(raw) {
    var lines = String(raw || "").split("\n")
    var foundAccent = false
    var foundMuted = false
    var loadedForeground = false
    var loadedBackground = false
    var color0Value = ""
    var color4Value = ""
    var color7Value = ""
    var color8Value = ""
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "foreground") { foreground = match[2]; loadedForeground = true }
      else if (match[1] === "background") { background = match[2]; loadedBackground = true }
      // Prefer the explicit `accent` key; only fall back to color4 when the
      // theme doesn't define a separate accent. color4 appears later in the
      // file so the old single-property approach clobbered accent with it.
      else if (match[1] === "accent") { accent = match[2]; foundAccent = true }
      else if (match[1] === "muted") { muted = match[2]; foundMuted = true }
      else if (match[1] === "color0") color0Value = match[2]
      else if (match[1] === "color4") color4Value = match[2]
      else if (match[1] === "color7") color7Value = match[2]
      else if (match[1] === "color8") color8Value = match[2]
      else if (match[1] === "red" || match[1] === "color1") urgent = match[2]
    }
    if (!loadedBackground && color0Value.length > 0) background = color0Value
    if (!loadedForeground && color7Value.length > 0) foreground = color7Value
    if (!foundAccent && color4Value.length > 0) accent = color4Value
    if (!foundMuted) muted = color8Value.length > 0 ? color8Value : foreground
  }

  // Last theme-supplied and user-supplied shell.toml dicts, kept separate so
  // either can be reloaded without re-reading the other. `shellValues` is
  // always the merge of theme (base) and user (override) — see mergeShell.
  property var themeShellValues: ({})
  property var userShellValues: ({})

  // Single TOML walker for shell.toml. Both Color (surface roles) and Style
  // (typography, spacing, bar, control states) consume the resulting dict.
  // Accepts quoted strings, bare numeric values, bare width lists, and bare
  // role names; tolerates inline comments. Numbers are kept as strings here —
  // readers coerce when they pull a value.
  function parseShell(raw) {
    var parsed = {}
    var text = String(raw || "")
    if (text) {
      var lines = text.split("\n")
      var section = ""
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s+|\s+$/g, "")
        if (!line || line.charAt(0) === "#") continue
        var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
        if (sectionMatch) { section = sectionMatch[1]; continue }
        var stringKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/)
        var numKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
        var widthKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?(?:\s+-?\d+(?:\.\d+)?){1,3})\s*(#.*)?$/)
        var bareKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*(#.*)?$/)
        var kv = stringKv || numKv || widthKv || bareKv
        if (!kv || !section) continue
        parsed[section + "." + kv[1]] = kv[2]
      }
    }
    return parsed
  }

  // Re-derive `shellValues` from theme base + user override and push it to
  // Style. User keys win, so a machine-level shell.toml survives theme
  // switches (which replace only themeShellValues).
  function mergeShell() {
    var merged = {}
    for (var tk in themeShellValues) merged[tk] = themeShellValues[tk]
    for (var uk in userShellValues) merged[uk] = userShellValues[uk]
    shellValues = merged
    Style.applyShellValues(merged)
  }

  function loadShell(raw) {
    themeShellValues = parseShell(raw)
    mergeShell()
  }

  function loadUserShell(raw) {
    userShellValues = parseShell(raw)
    mergeShell()
  }

  // Startup load only. Runtime theme switches push the payload explicitly
  // through shell IPC.
  property FileView colorsFile: FileView {
    id: colorsFile
    path: root.currentThemePath + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.loadColors(text())
  }
  property FileView shellFile: FileView {
    id: shellFile
    path: root.currentThemePath + "/shell.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.loadShell(text())
    onLoadFailed: root.loadShell("")
  }
  // Machine-level override, layered on top of whatever theme is active. This
  // Local font settings are watched so they take effect live without
  // restarting the shell; absent by default.
  property FileView userShellFile: FileView {
    id: userShellFile
    path: root.home + "/.config/quickshell/desktop-shell/config/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadUserShell(text())
    // Re-read on change (including first creation) before loading — `text()`
    // is stale in the change signal itself, so route both paths through reload
    // → onLoaded to always parse fresh content.
    onFileChanged: reload()
    onLoadFailed: root.loadUserShell("")
  }
}
