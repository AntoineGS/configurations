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
NOTIFICATION_TOGGLE_HELPER="$ROOT/Linux/os/helpers/toggle-notification-silencing"
UTILITIES="$ROOT/Linux/hypr/bindings/utilities.lua"
MEDIA="$ROOT/Linux/hypr/bindings/media.lua"
NOTIFICATION_RUNTIME_TEST="$SHELL_ROOT/tests/notification-runtime-test.sh"
POLKIT="$SHELL_ROOT/plugins/polkit/PolkitAgent.qml"
NOTIFICATIONS="$SHELL_ROOT/plugins/notifications/Service.qml"
OSD="$SHELL_ROOT/plugins/osd/Osd.qml"
CONFIG="$ROOT/tidydots.yaml"
BASH_PATH="$(type -P bash)"

command -v node >/dev/null 2>&1 || {
  printf 'config-test: node is required\n' >&2
  exit 1
}

node - "$TEMPLATE" "$THEME" "$COLOR" "$SHELL_ROOT/shell.qml" "$SHELL_ROOT/services/PluginRegistry.qml" \
  "$SHELL_ROOT/services/BarWidgetRegistry.qml" "$HELPER" "$BAR" "$TOGGLE_HELPER" \
  "$NOTIFICATION_TOGGLE_HELPER" "$UTILITIES" "$MEDIA" "$POLKIT" "$NOTIFICATIONS" "$OSD" "$CONFIG" <<'NODE'
const assert = require("node:assert/strict")
const fs = require("node:fs")

const [templatePath, themePath, colorPath, shellPath, registryPath, widgetRegistryPath, helperPath, barPath,
  toggleHelperPath, notificationToggleHelperPath, utilitiesPath, mediaPath, polkitPath, notificationsPath,
  osdPath, tidydotsPath] = process.argv.slice(2)
const template = fs.readFileSync(templatePath, "utf8")
const color = fs.readFileSync(colorPath, "utf8")
const shell = fs.readFileSync(shellPath, "utf8")
const registry = fs.readFileSync(registryPath, "utf8")
const widgetRegistry = fs.readFileSync(widgetRegistryPath, "utf8")
const bar = fs.readFileSync(barPath, "utf8")
const notificationToggleHelper = fs.readFileSync(notificationToggleHelperPath, "utf8")
const utilities = fs.readFileSync(utilitiesPath, "utf8")
const media = fs.readFileSync(mediaPath, "utf8")
const polkit = fs.readFileSync(polkitPath, "utf8")
const notifications = fs.readFileSync(notificationsPath, "utf8")
const osd = fs.readFileSync(osdPath, "utf8")
const tidydots = fs.readFileSync(tidydotsPath, "utf8")
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
  assert.deepEqual(config.disabledPlugins, ["desktop.battery"],
    `${hostname}: legacy battery service remains disabled during the bar-only phase`)
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
assert.match(shell, /readonly property bool testSurfaceSuppressed: Quickshell\.env\("DESKTOP_SHELL_TEST_NO_SURFACES"\) === "1"/,
  "shell has a test-only no-surfaces gate")
assert.match(shell, /previewMode: shell\.previewMode/)
assert.match(shell, /if \(shell\.previewMode\) return null/)
assert.match(shell, /if \(shell\.previewMode\) \{[\s\S]*?unloadPluginServices\(\)/)
assert.match(shell, /property bool barVisible: true/)
assert.match(shell, /disabledPlugins: \["desktop\.battery"\]/,
  "builtin config disables the duplicate battery scheduler")
assert.match(shell, /function toggleBar\(\): string \{\s*shell\.barVisible = !shell\.barVisible\s*return shell\.barVisible \? "visible" : "hidden"\s*\}/)
assert.match(shell, /readonly property var notificationService:\s*shell\.serviceFor\("desktop\.notifications"\)/,
  "shell health reads the shared notification service")
assert.match(notifications,
  /property bool ownershipEnabled: Quickshell\.env\("DESKTOP_SHELL_NOTIFICATIONS_REGISTER"\) === "1"/,
  "notification registration defaults to disabled")
assert.match(polkit,
  /property bool registrationEnabled: Quickshell\.env\("DESKTOP_SHELL_POLKIT_REGISTER"\) === "1"/,
  "polkit registration defaults to disabled")
for (const [field, expected] of [
  ["notificationsOwned", "notificationService ? notificationService.notificationsOwned : false"],
  ["notificationOwnershipError", 'notificationService ? notificationService.ownershipError : "notification service unavailable"'],
  ["notificationRouteValid", "notificationService ? notificationService.routeValid : false"],
  ["notificationRouteVisible", "notificationService ? notificationService.routeVisible : false"],
  ["notificationRouteError", 'notificationService ? notificationService.routeError : "notification service unavailable"']
]) {
  assert.ok(shell.includes(`${field}: ${expected}`),
    `healthState exposes ${field} with an unavailable fallback`)
}
assert.match(shell, /readonly property bool osdAvailable\s*:/,
  "shell exposes reactive OSD availability")
assert.match(shell, /osdAvailable: shell\.osdAvailable/,
  "healthState exposes osdAvailable")
assert.match(shell, /import "plugins\/osd\/OsdModel\.js" as OsdModel/,
  "shell uses the OSD health controller")
assert.match(shell, /OsdModel\.healthAvailable\(\s*shell\.previewMode,\s*shell\.panelLoaders\["desktop\.osd"\],\s*Loader\.Error\)/,
  "shell health delegates all OSD availability cases")
assert.match(shell, /panelLoaders\["desktop\.osd"\]/,
  "OSD health reads the desktop.osd loader")
assert.match(shell, /active: !shell\.testSurfaceSuppressed && shell\.activeBarId === shell\.defaultBarId/,
  "test runtime suppresses the default bar surface")
assert.match(shell, /active: !shell\.testSurfaceSuppressed && !shell\.pluginReloading[\s\S]*?shell\.activeBarId !== shell\.defaultBarId/,
  "test runtime suppresses optional bar surfaces")
assert.match(shell, /if \(shell\.testSurfaceSuppressed\) return \[\]/,
  "test runtime suppresses panel loaders")
assert.match(bar, /readonly property bool testSurfaceSuppressed: Quickshell\.env\("DESKTOP_SHELL_TEST_NO_SURFACES"\) === "1"/,
  "bar has a test-only no-surfaces gate")
assert.match(bar, /visible: !root\.testSurfaceSuppressed && root\.shell\.barVisible/,
  "bar surface is hidden by the test gate")
assert.match(polkit, /readonly property bool testSurfaceSuppressed: Quickshell\.env\("DESKTOP_SHELL_TEST_NO_SURFACES"\) === "1"/,
  "polkit has a test-only no-surfaces gate")
assert.match(polkit, /visible: !root\.testSurfaceSuppressed && root\.dialogVisible/,
  "polkit surface is hidden by the test gate")
assert.match(notifications, /readonly property bool testSurfaceSuppressed: Quickshell\.env\("DESKTOP_SHELL_TEST_NO_SURFACES"\) === "1"/,
  "notifications have a test-only no-surfaces gate")
assert.match(notifications, /visible: !service\.testSurfaceSuppressed[\s\S]*?service\.cardsVisibleOn/,
  "notification surfaces are hidden by the test gate")
assert.match(osd, /readonly property bool testSurfaceSuppressed: Quickshell\.env\("DESKTOP_SHELL_TEST_NO_SURFACES"\) === "1"/,
  "OSD has a test-only no-surfaces gate")
assert.match(osd, /visible: !root\.testSurfaceSuppressed && root\.opened/,
  "OSD surface is hidden by the test gate")
assert.match(shell, /readonly property var polkitService:\s*shell\.serviceFor\("desktop\.polkit"\)/,
  "shell health reads the shared polkit service")
for (const [field, expected] of [
  ["polkitRegistered", "polkitService ? polkitService.polkitRegistered : false"],
  ["polkitError", 'polkitService ? polkitService.polkitError : "polkit service unavailable"'],
  ["polkitPamError", 'polkitService ? polkitService.pamError : "polkit service unavailable"']
]) {
  assert.ok(shell.includes(`${field}: ${expected}`),
    `healthState exposes ${field} with an unavailable fallback`)
}
const graphicalLinuxCondition =
  "{{ and (eq .OS \"linux\") (or .HasDisplay (eq .Hostname \"antoinews-linux\")) (not .IsWSL) }}"
const fprintdBlock = tidydots.split(/^  - /m).find(block => block.includes("\n    name: fprintd\n"))
assert.ok(fprintdBlock, "tidydots declares a standalone fprintd application")
assert.match(fprintdBlock, /managers:\n        pacman: fprintd\n/,
  "fprintd uses a direct pacman scalar")
assert.ok(fprintdBlock.includes(`when: '${graphicalLinuxCondition}'`),
  "fprintd uses the graphical-Linux host condition")
assert.match(fprintdBlock, /entries: \[\]/, "fprintd has no configuration entries")
assert.doesNotMatch(fprintdBlock, /deps:/, "fprintd is not declared as a dependency array")
const callStart = shell.indexOf("function callIfLoaded")
const callEnd = shell.indexOf("// One Loader per", callStart)
assert.notEqual(callStart, -1, "generic call dispatcher exists")
assert.notEqual(callEnd, -1, "generic call dispatcher ends before panel loading")
const callFunction = shell.slice(callStart, callEnd)
assert.ok(callFunction.indexOf("serviceFor(pluginId)") < callFunction.indexOf("panelLoaders[id]"),
  "service-root dispatch precedes overlay dispatch")
assert.match(callFunction, /typeof service\[method\] === "function"/)
assert.match(callFunction, /service\[method\]\(arg\)/)

const notificationBindingsStart = utilities.indexOf("-- Notifications")
const notificationBindings = utilities.slice(notificationBindingsStart)
assert.match(notificationBindings, /exec_cmd\("desktop-shell call desktop\.notifications dismissAll"\)/)
assert.match(notificationBindings, /exec_cmd\("toggle-notification-silencing"\)/)
assert.match(notificationBindings, /exec_cmd\("desktop-shell call desktop\.notifications invokeLast"\)/)
assert.match(notificationBindings, /exec_cmd\("desktop-shell call desktop\.notifications restoreLast"\)/)
assert.doesNotMatch(notificationBindings, /\bmakoctl\b|\bnotify-send\b/)
assert.match(notificationToggleHelper, /^set -Eeuo pipefail$/m)
assert.match(notificationToggleHelper, /desktop-shell call desktop\.notifications toggleDnd/)
assert.match(notificationToggleHelper, /enabled\|disabled/)
assert.doesNotMatch(notificationToggleHelper, /\bmakoctl\b|\bwaybar\b|\bnotify-send\b|\b(?:pkill|kill|killall|signal)\b/)

const mediaBindings = [
  ["XF86AudioRaiseVolume", "desktop-osd volume-up 5", true, "Volume up"],
  ["XF86AudioLowerVolume", "desktop-osd volume-down 5", true, "Volume down"],
  ["XF86AudioMute", "desktop-osd volume-toggle", true, "Mute"],
  ["XF86AudioMicMute", "desktop-osd mic-toggle", true, "Mute microphone"],
  ["XF86MonBrightnessUp", "desktop-osd brightness-up 5", true, "Brightness up"],
  ["XF86MonBrightnessDown", "desktop-osd brightness-down 5", true, "Brightness down"],
  ["XF86KbdBrightnessUp", "desktop-osd keyboard-up", true, "Keyboard brightness up"],
  ["XF86KbdBrightnessDown", "desktop-osd keyboard-down", true, "Keyboard brightness down"],
  ["XF86KbdLightOnOff", "desktop-osd keyboard-cycle", false, "Keyboard backlight cycle"],
  ["ALT + XF86AudioRaiseVolume", "desktop-osd volume-up 1", true, "Volume up precise"],
  ["ALT + XF86AudioLowerVolume", "desktop-osd volume-down 1", true, "Volume down precise"],
  ["ALT + XF86MonBrightnessUp", "desktop-osd brightness-up 1", true, "Brightness up precise"],
  ["ALT + XF86MonBrightnessDown", "desktop-osd brightness-down 1", true, "Brightness down precise"],
  ["XF86AudioNext", "desktop-osd media-next", false, "Next track"],
  ["XF86AudioPause", "desktop-osd media-play-pause", false, "Pause"],
  ["XF86AudioPlay", "desktop-osd media-play-pause", false, "Play"],
  ["XF86AudioPrev", "desktop-osd media-previous", false, "Previous track"],
  ["SUPER + XF86AudioMute", "cmd-audio-switch", false, "Switch audio output"],
  ["SUPER + F6", "desktop-osd brightness-down 5", true, "Brightness down"],
  ["SUPER + F7", "desktop-osd brightness-up 5", true, "Brightness up"],
  ["SUPER + F8", "desktop-osd volume-toggle", false, "Mute"],
  ["SUPER + F9", "desktop-osd volume-down 5", true, "Volume down"],
  ["SUPER + F10", "desktop-osd volume-up 5", true, "Volume up"]
]
const escapeRegExp = value => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
for (const [key, command, repeating, description] of mediaBindings) {
  const match = media.match(new RegExp(`hl\\.bind\\(\\s*"${escapeRegExp(key)}"[\\s\\S]*?\\}\\s*\\)`))
  const binding = match && match[0]
  assert.ok(binding, `media binding exists for ${key}`)
  assert.ok(binding.includes(`exec_cmd("${command}")`), `${key} keeps its command`)
  assert.match(binding, /locked\s*=\s*true/, `${key} remains locked`)
  assert.ok(binding.includes(`description = "${description}"`), `${key} keeps its description`)
  if (repeating) assert.match(binding, /repeating\s*=\s*true/, `${key} remains repeating`)
  else assert.doesNotMatch(binding, /repeating\s*=/, `${key} remains non-repeating`)
}
const barPanelStart = bar.indexOf("component BarPanel: PanelWindow")
const barPanelEnd = bar.indexOf("component LeftModules", barPanelStart)
assert.notEqual(barPanelStart, -1, "bar panel component exists")
assert.notEqual(barPanelEnd, -1, "bar module components follow bar panel")
assert.match(bar.slice(barPanelStart, barPanelEnd), /visible: !root\.testSurfaceSuppressed && root\.shell\.barVisible/)
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
assert.match(registry, /if \(isDisabled\(config, key\)\) return false/,
  "disabled plugin config prevents the legacy battery service from loading")
assert.ok(widgetRegistry.includes("/^desktop\\.[a-z0-9-]+$/"))

const helper = fs.readFileSync(helperPath, "utf8")
assert.match(helper, /ipc_scope=\(--any-display\)/,
  "interactive helper calls keep any-display routing")
assert.match(helper, /ipc_scope=\(--pid \"\$target_pid\"\)/,
  "helper exposes PID-bound routing")
assert.match(helper, /toggle-bar\)\s+\(\(\$# == 0\)\) \|\| \{ usage; exit 2; \}\s+method="toggleBar"/)
assert.doesNotMatch(helper, /\beval\b/)
assert.ok(fs.existsSync(toggleHelperPath), "bar visibility helper exists")
const toggleHelper = fs.readFileSync(toggleHelperPath, "utf8")
assert.match(toggleHelper, /^set -Eeuo pipefail$/m)
assert.match(toggleHelper, /\(\(\$# == 0\)\) \|\| \{ usage; exit 2; \}/)
assert.match(toggleHelper, /exec quickshell ipc --any-display -p "\$HOME\/\.config\/quickshell\/desktop-shell" call desktop-shell toggleBar/)
assert.doesNotMatch(toggleHelper, /desktop-shell toggle-bar/)
assert.doesNotMatch(toggleHelper, /\beval\b/)
assert.doesNotMatch(toggleHelper, /\$[@{]/)
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
if [[ ${9-} == desktop.notifications && ${10-} == toggleDnd ]]; then
  printf '%s\n' "${DESKTOP_SHELL_FAKE_RESULT:-disabled}"
fi
FAKE_QUICKSHELL
chmod +x "$fake_bin/quickshell"

for command_name in makoctl notify-send pkill; do
  cat >"$fake_bin/$command_name" <<'FAKE_LEGACY_COMMAND'
#!/usr/bin/env bash
exit 0
FAKE_LEGACY_COMMAND
  chmod +x "$fake_bin/$command_name"
done

run_helper() {
  local helper=$1
  shift
  : >"$trace"
  PATH="$fake_bin:$ROOT/Linux/os/helpers:$PATH" HOME="$test_home" \
    DESKTOP_SHELL_IPC_TRACE="$trace" DESKTOP_SHELL_FAKE_RESULT="${DESKTOP_SHELL_FAKE_RESULT:-disabled}" \
    "$helper" "$@"
}

run_ipc() {
  run_helper "$HELPER" "$@"
}

run_toggle() {
  run_helper "$TOGGLE_HELPER" "$@"
}

run_notification_toggle() {
  run_helper "$NOTIFICATION_TOGGLE_HELPER"
}

assert_trace() {
  local -a actual expected
  mapfile -d '' actual <"$trace" || true
  expected=("ipc" "--any-display" "-p" "$test_home/.config/quickshell/desktop-shell" "call" "--" "$@")
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

assert_toggle_trace() {
  local -a actual expected
  mapfile -d '' actual <"$trace" || true
  expected=("ipc" "--any-display" "-p" "$test_home/.config/quickshell/desktop-shell" "call" "$@")
  if (( ${#actual[@]} != ${#expected[@]} )); then
    printf 'config-test: toggle IPC argument count mismatch\n' >&2
    exit 1
  fi
  for ((i = 0; i < ${#expected[@]}; i++)); do
    if [[ "${actual[i]}" != "${expected[i]}" ]]; then
      printf 'config-test: toggle IPC argument %d mismatch: %q != %q\n' "$i" "${actual[i]}" "${expected[i]}" >&2
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
run_ipc toggle-bar
assert_trace desktop-shell toggleBar
run_ipc summon desktop.agents '{}'
assert_trace desktop-shell summon desktop.agents '{}'
run_ipc hide desktop.audio
assert_trace desktop-shell hide desktop.audio
osd_payload='{"icon":"brightness","message":"","value":42,"max":100,"progressText":"42%"}'
run_ipc call desktop.osd show "$osd_payload"
assert_trace desktop-shell call desktop.osd show "$osd_payload"

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

run_toggle
assert_toggle_trace desktop-shell toggleBar

notification_state=$(run_notification_toggle)
test "$notification_state" = disabled
assert_trace desktop-shell call desktop.notifications toggleDnd ""

set +e
DESKTOP_SHELL_FAKE_RESULT=unexpected run_notification_toggle >/dev/null 2>"$fixture/invalid-notification-state.err"
notification_state_exit=$?
set -e
test "$notification_state_exit" -ne 0

set +e
run_toggle unexpected 2>"$fixture/toggle-argument.err"
toggle_exit=$?
set -e
test "$toggle_exit" -eq 2
test ! -s "$trace"

missing_runtime_bin="$fixture/missing-runtime-bin"
mkdir -p "$missing_runtime_bin"
for required_command in dirname pwd; do
  ln -s "$(type -P "$required_command")" "$missing_runtime_bin/$required_command"
done

set +e
PATH="$missing_runtime_bin" "$BASH_PATH" "$NOTIFICATION_RUNTIME_TEST" --private-bus \
  >"$fixture/missing-quickshell.out" 2>&1
missing_quickshell_exit=$?
set -e
test "$missing_quickshell_exit" -ne 0
[[ $(<"$fixture/missing-quickshell.out") == *"FAIL: quickshell is required"* ]]

printf '#!/bin/sh\nexit 0\n' >"$missing_runtime_bin/quickshell"
chmod +x "$missing_runtime_bin/quickshell"
set +e
PATH="$missing_runtime_bin" "$BASH_PATH" "$NOTIFICATION_RUNTIME_TEST" --private-bus \
  >"$fixture/missing-notify-send.out" 2>&1
missing_notify_send_exit=$?
set -e
test "$missing_notify_send_exit" -ne 0
[[ $(<"$fixture/missing-notify-send.out") == *"FAIL: notify-send is required"* ]]
