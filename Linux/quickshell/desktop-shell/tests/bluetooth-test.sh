#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PANEL="$ROOT/Linux/quickshell/desktop-shell/plugins/panels/bluetooth/Panel.qml"

fail() { printf 'bluetooth-test: %s\n' "$1" >&2; exit 1; }

node "$ROOT/Linux/quickshell/desktop-shell/tests/bluetooth-model-test.js"

node - "$PANEL" <<'NODE'
const assert = require("node:assert/strict")
const fs = require("node:fs")

const panel = fs.readFileSync(process.argv[2], "utf8")
const refresh = panel.match(/function refreshBatteries\(\) \{([\s\S]*?)\n  \}/)
const processBlock = panel.match(/Process \{\n    id: batteryProcess([\s\S]*?)\n  \}/)
assert.ok(refresh, "battery refresh function exists")
assert.ok(processBlock, "battery process exists")
assert.match(panel, /readonly property color warningColor: "#fab387"/,
  "Catppuccin Mocha Peach warning color is missing")
assert.match(panel, /interval: 60000/, "battery refresh is not 60 seconds")
assert.match(panel, /command: \["desktop-hardware-state", "bluetooth"\]/,
  "Bluetooth battery collector is not wired")
assert.match(panel, /property bool batteryRefreshQueued: false/,
  "in-flight battery refreshes do not have a single follow-up slot")
assert.match(panel, /property int batteryRefreshGeneration: 0/,
  "battery refresh requests have no generation")
assert.match(panel, /property int batteryProcessGeneration: 0/,
  "battery process results have no generation")
assert.match(refresh[1], /if \(!batteryCollectorLoaded\) return/,
  "refreshes continue after destruction")
assert.match(refresh[1], /batteryRefreshGeneration\+\+/,
  "battery refresh requests do not advance their generation")
assert.match(refresh[1], /if \(batteryProcess\.running\) \{[\s\S]*batteryRefreshQueued = true[\s\S]*return/,
  "in-flight refreshes are dropped instead of queued")
assert.match(refresh[1], /batteryProcessGeneration = batteryRefreshGeneration/,
  "started battery processes are not tied to their request generation")
assert.match(refresh[1], /batteryProcess\.running = true/,
  "battery refresh never starts the collector")
assert.match(processBlock[1], /onExited: \{/, "battery result handling waits for process completion")
assert.match(processBlock[1], /if \(!root\.batteryCollectorLoaded\) return/,
  "destroyed panels can still apply collector output")
assert.match(processBlock[1], /completedGeneration === root\.batteryRefreshGeneration/,
  "older collector output can overwrite a newer request")
assert.match(processBlock[1], /root\.batteryRefreshQueued = false/,
  "queued battery refreshes are not consumed")
assert.match(processBlock[1], /root\.refreshBatteries\(\)/,
  "queued battery refreshes are not restarted after completion")
assert.match(panel, /onOpenedChanged: \{[\s\S]*refreshBatteries\(\)/,
  "opening the popup does not refresh batteries")
assert.match(panel, /onConnectedDevicesChanged: refreshBatteries\(\)/,
  "connected-device changes do not refresh batteries")
assert.match(panel, /Component\.onCompleted: \{[\s\S]*refreshBatteries\(\)/,
  "startup does not refresh batteries")
assert.match(panel, /Component\.onDestruction: \{[\s\S]*batteryCollectorLoaded = false[\s\S]*batteryRefreshQueued = false[\s\S]*batteryRefreshTimer\.stop\(\)/,
  "battery refresh lifecycle is not stopped on destruction")
assert.match(panel, /text: deviceRow\.statusText/, "popup does not render the committed battery status")
assert.match(panel, /readonly property string statusText: \{[\s\S]*rowData\.batteryStatus/,
  "popup status does not use merged battery values")
assert.match(panel, /textFormat: Text\.RichText/, "popup cannot color individual low values")
const statusTextStart = panel.indexOf("text: deviceRow.statusText")
const statusTextEnd = panel.indexOf("font.family", statusTextStart)
assert.ok(statusTextStart >= 0 && statusTextEnd > statusTextStart, "popup status text block exists")
assert.match(panel.slice(statusTextStart, statusTextEnd), /color: root\.panelSecondary/,
  "healthy popup details do not use semantic secondary styling")
assert.match(panel, /active: root\.lowBattery/, "bar icon has no low-battery state")
assert.match(panel, /activeColor: root\.warningColor/, "bar icon does not use Peach")

const barStart = panel.indexOf("  BarIconButton {")
const popupStart = panel.indexOf("  KeyboardPanel {", barStart)
assert.ok(barStart >= 0 && popupStart > barStart, "bar button block exists")
const barButton = panel.slice(barStart, popupStart)
assert.match(barButton, /text: root\.icon/, "bar button is no longer icon-only")
assert.match(barButton, /tooltipText: root\.batteryTooltip/, "bar tooltip omits batteries")
assert.doesNotMatch(barButton, /batteryStatus|batteryValues|Peripheral|Central/,
  "battery details consume permanent bar space")
NODE

printf 'bluetooth-test: panel polling, tooltip, popup, and warning contracts verified\n'
