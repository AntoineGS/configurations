#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"
TEMPLATE="$SHELL_ROOT/config/shell.json.tmpl"
THEME="$SHELL_ROOT/config/shell.toml"
COLOR="$SHELL_ROOT/Commons/Color.qml"
HELPER="$ROOT/Linux/os/helpers/desktop-shell"
BAR="$SHELL_ROOT/plugins/bar/Bar.qml"
TOGGLE_HELPER="$ROOT/Linux/os/helpers/toggle-desktop-shell-bar"

command -v node >/dev/null 2>&1 || {
  printf 'config-test: node is required\n' >&2
  exit 1
}

node - "$TEMPLATE" "$THEME" "$COLOR" "$SHELL_ROOT/shell.qml" "$SHELL_ROOT/services/PluginRegistry.qml" \
  "$SHELL_ROOT/services/BarWidgetRegistry.qml" "$HELPER" "$BAR" "$TOGGLE_HELPER" <<'NODE'
const assert = require("node:assert/strict")
const fs = require("node:fs")

const [templatePath, themePath, colorPath, shellPath, registryPath, widgetRegistryPath, helperPath, barPath,
  toggleHelperPath] = process.argv.slice(2)
const template = fs.readFileSync(templatePath, "utf8")
const color = fs.readFileSync(colorPath, "utf8")
const shell = fs.readFileSync(shellPath, "utf8")
const registry = fs.readFileSync(registryPath, "utf8")
const widgetRegistry = fs.readFileSync(widgetRegistryPath, "utf8")
const bar = fs.readFileSync(barPath, "utf8")
assert.doesNotMatch(template, /onClickRight/, "command modules use onRightClick")

const palette = {
  foreground: "#cdd6f4",
  background: "#1e1e2e",
  accent: "#cba6f7",
  urgent: "#f38ba8",
  muted: "#7f849c"
}
for (const [role, value] of Object.entries(palette)) {
  assert.match(color, new RegExp(`property color ${role}: "${value}"`), `${role} uses the Catppuccin fallback`)
}

assert.ok(fs.existsSync(themePath), "repository-owned shell.toml exists")
const theme = fs.readFileSync(themePath, "utf8")
const themeValues = {}
let section = ""
for (const rawLine of theme.split("\n")) {
  const line = rawLine.trim()
  if (!line || line.startsWith("#")) continue
  const sectionMatch = line.match(/^\[([a-z-]+)\]$/)
  if (sectionMatch) {
    section = sectionMatch[1]
    continue
  }
  const valueMatch = line.match(/^([a-z-]+)\s*=\s*"(#[0-9a-f]{6})"$/i)
  if (section && valueMatch) themeValues[`${section}.${valueMatch[1]}`] = valueMatch[2].toLowerCase()
}

const surfaceRoles = {
  "bar.background": palette.background,
  "bar.text": palette.foreground,
  "bar.active": palette.urgent,
  "popups.background": palette.background,
  "popups.text": palette.foreground,
  "popups.border": palette.accent,
  "tooltip.background": palette.background,
  "tooltip.text": palette.foreground,
  "tooltip.border": palette.accent,
  "menu.background": palette.background,
  "menu.text": palette.foreground,
  "menu.border": palette.accent,
  "menu.scrim": palette.background,
  "menu.selected-background": palette.muted,
  "menu.selected-text": palette.accent,
  "menu.selected-border": palette.accent,
  "notifications.background": palette.background,
  "notifications.text": palette.foreground,
  "notifications.border": palette.accent,
  "notifications.countdown": palette.accent,
  "polkit.background": palette.background,
  "polkit.text": palette.foreground,
  "polkit.text-error": palette.urgent,
  "polkit.border": palette.accent,
  "polkit.border-error": palette.urgent,
  "polkit.accent": palette.accent,
  "polkit.scrim": palette.background,
  "lock.background": palette.background,
  "lock.text": palette.foreground,
  "lock.placeholder": palette.muted,
  "lock.text-error": palette.urgent,
  "lock.border": palette.muted,
  "lock.border-active": palette.accent,
  "lock.border-error": palette.urgent,
  "lock.selection": palette.accent
}
for (const [role, value] of Object.entries(surfaceRoles)) {
  assert.equal(themeValues[role], value, `${role} uses the expected Catppuccin token`)
}

function render(hostname) {
  let rendered = template.replace(
    /{{-?\s*if\s+eq\s+\.Hostname\s+"([^"]+)"\s*-?}}([\s\S]*?){{-?\s*end\s*-?}}/g,
    (_match, expectedHostname, body) => expectedHostname === hostname ? body : ""
  )
  assert.doesNotMatch(rendered, /{{/, `unrendered template directive for ${hostname}`)
  return JSON.parse(rendered)
}

const commandModules = {
  recording: {
    id: "recording",
    type: "command",
    exec: "desktop-shell-status recording",
    interval: 1,
    onClick: "cmd-screenrecord"
  },
  voxtype: {
    id: "voxtype",
    type: "command",
    exec: "desktop-shell-status voxtype",
    interval: 1,
    onClick: "voxtype-model",
    onRightClick: "voxtype-config"
  },
  codex: {
    id: "codex",
    type: "command",
    exec: "desktop-shell-status codex",
    interval: 300,
    onClick: "desktop-shell summon desktop.agents '{}'",
    onRightClick: "xdg-open https://chatgpt.com/codex/settings/usage"
  },
  disk: {
    id: "disk",
    type: "command",
    exec: "desktop-shell-status disk",
    interval: 30,
    horizontalMargin: 2.5
  },
  memory: {
    id: "memory",
    type: "command",
    exec: "desktop-shell-status memory",
    interval: 5,
    horizontalMargin: 2.5,
    onClick: "launch-or-focus-tui btop"
  },
  cpu: {
    id: "cpu",
    type: "command",
    exec: "desktop-shell-status cpu",
    interval: 5,
    horizontalMargin: 2.5,
    onClick: "launch-or-focus-tui btop"
  }
}

function expectedRight(includeHardware) {
  const right = [
    commandModules.codex,
    { id: "desktop.tray" },
    { id: "desktop.tailscale" },
    { id: "desktop.bluetooth" },
    { id: "desktop.network" },
    { id: "desktop.audio" }
  ]
  if (includeHardware) {
    right.push({ id: "desktop.monitor" }, { id: "desktop.power" })
  }
  right.push(commandModules.disk, commandModules.memory, commandModules.cpu)
  return right
}

function assertConfig(hostname, includeHardware, workspaceLabels) {
  const config = render(hostname)
  assert.equal(config.version, 1, `${hostname}: config version`)
  assert.deepEqual(config.bar, {
    id: "desktop.bar",
    position: "top",
    transparent: false,
    centerAnchor: "desktop.clock",
    layout: {
      left: [{ id: "desktop.menu" }, { id: "desktop.workspaces", labels: workspaceLabels }],
      center: [
        commandModules.recording,
        commandModules.voxtype,
        { id: "desktop.clock", format: "dddd MMMM dd yyyy - HH:mm:ss" }
      ],
      right: expectedRight(includeHardware)
    }
  }, `${hostname}: bar contract`)
  assert.deepEqual(config.plugins, [], `${hostname}: empty plugin selection`)
}

assertConfig("DESKTOP-E07VTRN", false, {
  "1": "chat", "2": "main", "3": "secondary", "4": "obsidian", "5": "shell",
  "6": "git", "7": "browser", "8": "work", "9": "work", "10": "explorer"
})
assertConfig("antoinews-linux", false, {
  "2": "main", "3": "secondary", "5": "shell", "6": "git",
  "8": "browser", "9": "sql", "10": "explorer"
})
assertConfig("omarchbook", true, {})

assert.match(shell, /readonly property bool previewMode: Quickshell\.env\("DESKTOP_SHELL_PREVIEW"\) === "1"/)
assert.match(shell, /previewMode: shell\.previewMode/)
assert.match(shell, /if \(shell\.previewMode\) return null/)
assert.match(shell, /if \(shell\.previewMode\) \{[\s\S]*?unloadPluginServices\(\)/)
assert.match(shell, /property bool barVisible: true/)
assert.match(shell, /function toggleBar\(\): string \{\s*shell\.barVisible = !shell\.barVisible\s*return shell\.barVisible \? "visible" : "hidden"\s*\}/)
const barPanelStart = bar.indexOf("component BarPanel: PanelWindow")
const barPanelEnd = bar.indexOf("component LeftModules", barPanelStart)
assert.notEqual(barPanelStart, -1, "bar panel component exists")
assert.notEqual(barPanelEnd, -1, "bar module components follow bar panel")
assert.match(bar.slice(barPanelStart, barPanelEnd), /visible: root\.shell\.barVisible/)
const panelEntriesStart = shell.indexOf("function computePanelEntries")
const panelEntriesEnd = shell.indexOf("Connections {", panelEntriesStart)
assert.notEqual(panelEntriesStart, -1, "panel entry computation exists")
assert.notEqual(panelEntriesEnd, -1, "panel connections follow entry computation")
const panelEntriesFunction = shell.slice(panelEntriesStart, panelEntriesEnd)
assert.doesNotMatch(panelEntriesFunction, /previewMode && m\.keepLoaded === true\) continue/)
assert.match(panelEntriesFunction, /var keepLoaded = m\.keepLoaded === true/)
assert.match(panelEntriesFunction, /if \(shell\.previewMode\) keepLoaded = false/)
assert.match(panelEntriesFunction, /keepLoaded: keepLoaded/)
const panelLoaderStart = shell.indexOf("property Loader panelLoader")
const panelLoaderEnd = shell.indexOf("onLoaded:", panelLoaderStart)
const panelLoader = shell.slice(panelLoaderStart, panelLoaderEnd)
assert.match(panelLoader, /panelEntry\.keepLoaded \|\| shell\.openPanelIds\[panelEntry\.pluginId\] === true/)

function panelMountState(manifest, previewMode, opened) {
  const keepLoaded = previewMode ? false : manifest.keepLoaded === true
  return {
    entryCreated: true,
    eagerMount: keepLoaded,
    onDemandMount: !keepLoaded && opened
  }
}

const previewKeepLoaded = panelMountState({ keepLoaded: true }, true, false)
assert.equal(previewKeepLoaded.entryCreated, true, "preview keeps the panel entry")
assert.equal(previewKeepLoaded.eagerMount, false, "preview suppresses eager mounting")
assert.equal(panelMountState({ keepLoaded: true }, true, true).onDemandMount, true,
  "preview still mounts a summoned keep-loaded panel")

const applyStart = shell.indexOf("function applyShellConfig")
const persistStart = shell.indexOf("function persistShellConfig")
assert.notEqual(applyStart, -1, "config loader exists")
assert.notEqual(persistStart, -1, "config persistence is separate")
const applyFunction = shell.slice(applyStart, persistStart)
assert.match(applyFunction, /configValid = false/)
assert.match(applyFunction, /shellConfig = builtinShellConfig/)
assert.match(applyFunction, /console\.warn/)
assert.doesNotMatch(applyFunction, /setText\(/, "invalid config is never overwritten")
const barConfigStart = shell.indexOf("readonly property var barConfig")
assert.notEqual(barConfigStart, -1, "bar config follows persistence")
const persistFunction = shell.slice(persistStart, barConfigStart)
assert.match(persistFunction, /if \(!shell\.configValid\)/, "invalid config cannot be persisted")

assert.match(registry, /manifest\.schemaVersion !== 1/)
assert.ok(registry.includes("if (!/^desktop\\.[a-z0-9-]+$/.test(id))"))
assert.match(registry, /recordPluginError\(/)
assert.match(registry, /entry point.*escapes|unsafe entryPoint/)
assert.ok(widgetRegistry.includes("/^desktop\\.[a-z0-9-]+$/"))

const helper = fs.readFileSync(helperPath, "utf8")
assert.match(helper, /quickshell ipc -p \"\$HOME\/\.config\/quickshell\/desktop-shell\" call \"\$target\" \"\$method\" \"\$\{args\[@\]\}\"/)
assert.match(helper, /toggle-bar\)\s+\(\(\$# == 0\)\) \|\| \{ usage; exit 2; \}\s+method="toggleBar"/)
assert.doesNotMatch(helper, /\beval\b/)
assert.ok(fs.existsSync(toggleHelperPath), "bar visibility helper exists")
const toggleHelper = fs.readFileSync(toggleHelperPath, "utf8")
assert.match(toggleHelper, /^set -Eeuo pipefail$/m)
assert.match(toggleHelper, /\(\(\$# == 0\)\) \|\| \{ usage; exit 2; \}/)
assert.match(toggleHelper, /exec desktop-shell toggle-bar/)
console.log("config-test: rendered layout, fallback, preview, registry, and helper contracts verified")
NODE

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
fake_bin="$fixture/bin"
trace="$fixture/ipc-args"
test_home="$fixture/home"
mkdir -p "$fake_bin" "$test_home"

cat >"$fake_bin/quickshell" <<'FAKE_QUICKSHELL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\0' "$@" >"$DESKTOP_SHELL_IPC_TRACE"
FAKE_QUICKSHELL
chmod +x "$fake_bin/quickshell"

run_ipc() {
  : >"$trace"
  PATH="$fake_bin:$PATH" HOME="$test_home" DESKTOP_SHELL_IPC_TRACE="$trace" "$HELPER" "$@"
}

assert_trace() {
  local -a actual expected
  mapfile -d '' actual <"$trace" || true
  expected=("ipc" "-p" "$test_home/.config/quickshell/desktop-shell" "call" "$@")
  if (( ${#actual[@]} != ${#expected[@]} )); then
    printf 'config-test: IPC argument count mismatch\n' >&2
    exit 1
  fi
  for ((i = 0; i < ${#expected[@]}; i++)); do
    if [[ "${actual[i]}" != "${expected[i]}" ]]; then
      printf 'config-test: IPC argument %d mismatch: %q != %q\n' "$i" "${actual[i]}" "${expected[i]}" >&2
      exit 1
    fi
  done
}

run_ipc ping
assert_trace desktop-shell ping
run_ipc health
assert_trace desktop-shell health
run_ipc list-plugins
assert_trace desktop-shell listPlugins
run_ipc reload-config
assert_trace desktop-shell reloadConfig
run_ipc summon desktop.agents '{}'
assert_trace desktop-shell summon desktop.agents '{}'
run_ipc hide desktop.audio
assert_trace desktop-shell hide desktop.audio
run_ipc call desktop.osd show '{"level":1}'
assert_trace desktop-shell call desktop.osd show '{"level":1}'

set +e
run_ipc summon legacy.menu 2>"$fixture/invalid-id.err"
invalid_id_exit=$?
run_ipc hide legacy.audio 2>"$fixture/invalid-hide-id.err"
invalid_hide_id_exit=$?
run_ipc call legacy.audio show 2>"$fixture/invalid-call-id.err"
invalid_call_id_exit=$?
run_ipc unknown 2>"$fixture/unknown-command.err"
unknown_exit=$?
set -e
test "$invalid_id_exit" -eq 2
test "$invalid_hide_id_exit" -eq 2
test "$invalid_call_id_exit" -eq 2
test "$unknown_exit" -eq 2
test ! -s "$trace"
