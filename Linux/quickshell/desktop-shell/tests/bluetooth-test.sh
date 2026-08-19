#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PANEL="$ROOT/Linux/quickshell/desktop-shell/plugins/panels/bluetooth/Panel.qml"

fail() { printf 'bluetooth-test: %s\n' "$1" >&2; exit 1; }

grep -Fq 'readonly property color warningColor: "#fab387"' "$PANEL" \
  || fail "Catppuccin Mocha Peach warning color is missing"
grep -Fq 'interval: 60000' "$PANEL" || fail "battery refresh is not 60 seconds"
grep -Fq 'command: ["desktop-hardware-state", "bluetooth"]' "$PANEL" \
  || fail "Bluetooth battery collector is not wired"
grep -Fq 'if (!batteryProcess.running) batteryProcess.running = true' "$PANEL" \
  || fail "battery refreshes can overlap"
grep -Fq 'active: root.lowBattery' "$PANEL" || fail "bar icon has no low-battery state"
grep -Fq 'activeColor: root.warningColor' "$PANEL" || fail "bar icon does not use Peach"
grep -Fq 'tooltipText: root.batteryTooltip' "$PANEL" || fail "bar tooltip omits batteries"
grep -Fq 'textFormat: Text.RichText' "$PANEL" || fail "popup cannot color individual low values"
if grep -Eq 'slotSize:.*battery|text:.*batteryStatus' "$PANEL"; then
  fail "battery percentages were added permanently to the bar"
fi

printf 'bluetooth-test: panel polling, tooltip, popup, and warning contracts verified\n'
