#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)"
PANEL="$ROOT/Linux/quickshell/desktop-shell/plugins/panels/vm/Panel.qml"

node - "$PANEL" <<'NODE'
const assert = require("node:assert/strict")
const fs = require("node:fs")

const panel = fs.readFileSync(process.argv[2], "utf8")

assert.match(panel, /function applyState\(raw, processError\)/,
  "state application must accept process diagnostics")
assert.match(panel, /Model\.stateFromRaw\(vmState, raw, processError\)/,
  "state application must use the malformed-state retention model")
assert.match(panel, /if \(!nextState\.malformed && !nextState\.visible && root\.opened\) root\.close\(\)/,
  "valid unavailable state must close an open VM panel")
assert.match(panel, /open: root\.opened && root\.vmState\.visible/,
  "keyboard panel must be gated by both logical and VM visibility")
assert.match(panel, /memorySlider\.dragging \|\| root\.resizePending/,
  "allocation label must expose the preview while interacting or pending")
assert.match(panel, /root\.previewGiB/,
  "allocation label must use the requested preview value")
assert.match(panel, /id: stateStdout/,
  "state stdout must be available when the process exits")
assert.match(panel, /id: stateStderr/,
  "state stderr must be available when the process exits")
assert.match(panel, /stateStdout\.text \|\| ""/,
  "state output must be applied after process completion")
assert.match(panel, /function openFrom\(anchorItem\)/,
  "VM metrics must be able to anchor the existing popup independently")
assert.match(panel, /id: vmMemoryButton[\s\S]*root\.openFrom\(vmMemoryButton\)/,
  "the bracketed VM memory value must open the popup")
assert.match(panel, /id: vmCpuButton[\s\S]*root\.openFrom\(vmCpuButton\)/,
  "the bracketed VM CPU value must open the popup")
assert.match(panel, /anchorItem: root\.popupAnchorItem/,
  "the existing popup must follow the clicked VM metric")
assert.match(panel, /Model\.memoryCritical\(root\.hostMemoryState\.percent\)/,
  "host RAM must use the shared critical threshold")
assert.match(panel, /Model\.memoryCritical\(root\.vmState\.memoryPercent\)/,
  "VM RAM must use the shared critical threshold")

console.log("vm-panel-contract-test: host/VM stat interaction and popup contracts verified")
NODE
