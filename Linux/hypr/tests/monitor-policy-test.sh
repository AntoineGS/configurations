#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$SCRIPT_DIR/../../.." && pwd)
MONITORS_LUA="$ROOT/Linux/hypr/monitors.lua"
AUTOSTART_LUA="$ROOT/Linux/hypr/autostart.lua"
WAYBAR_TEMPLATE="$ROOT/Linux/waybar/config.jsonc.tmpl"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local message=$3

  [[ $haystack == *"$needle"* ]] || fail "$message: expected '$needle' in '$haystack'"
}

TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"
printf $'#!/usr/bin/env bash\nprintf "%%s\\n" "$TEST_HOSTNAME"\n' >"$TEST_ROOT/bin/hostname"
chmod +x "$TEST_ROOT/bin/hostname"
export PATH="$TEST_ROOT/bin:$PATH"

run_lua_config() {
  local hostname=$1
  local config=$2
  local kind=$3

  TEST_HOSTNAME=$hostname lua - "$config" "$kind" <<'LUA'
local config_path = arg[1]
local config_kind = arg[2]
local calls = {
  env = {},
  monitors = {},
  workspace_rules = {},
  window_rules = {},
  execs = {},
}
local start_callback

hl = {
  env = function(name, value)
    table.insert(calls.env, { name = name, value = value })
  end,
  monitor = function(config)
    table.insert(calls.monitors, config)
  end,
  workspace_rule = function(config)
    table.insert(calls.workspace_rules, config)
  end,
  window_rule = function(config)
    table.insert(calls.window_rules, config)
  end,
  on = function(event, callback)
    if event == "hyprland.start" then
      start_callback = callback
    end
  end,
  exec_cmd = function(command)
    table.insert(calls.execs, command)
  end,
}

dofile(config_path)
if config_kind == "autostart" then
  assert(start_callback, "hyprland.start callback was not registered")
  start_callback()
end

local workspace_moves = 0
local dp2_workarounds = 0
local laptop_output = 0
local laptop_mirror = 0
local preferred_fallback = 0
local gitkraken_rules = 0

for _, command in ipairs(calls.execs) do
  if string.find(command, "hl.dsp.workspace.move", 1, true) then
    workspace_moves = workspace_moves + 1
  end
  if string.find(command, 'hl.monitor({ output = "DP-2"', 1, true) then
    dp2_workarounds = dp2_workarounds + 1
  end
end

for _, monitor in ipairs(calls.monitors) do
  if monitor.output == "eDP-1" then
    laptop_output = laptop_output + 1
  end
  if monitor.mirror == "eDP-1" then
    laptop_mirror = laptop_mirror + 1
  end
  if monitor.output == "" and monitor.mode == "preferred" and monitor.position == "auto" then
    preferred_fallback = preferred_fallback + 1
  end
end

for _, window_rule in ipairs(calls.window_rules) do
  if window_rule.match and window_rule.match.class == "GitKraken" then
    gitkraken_rules = gitkraken_rules + 1
  end
end

print("monitor=" .. #calls.monitors)
print("workspace=" .. #calls.workspace_rules)
print("window=" .. #calls.window_rules)
print("workspace_move=" .. workspace_moves)
print("dp2_workaround=" .. dp2_workarounds)
print("laptop_output=" .. laptop_output)
print("laptop_mirror=" .. laptop_mirror)
print("preferred_fallback=" .. preferred_fallback)
print("gitkraken=" .. gitkraken_rules)
LUA
}

assert_host_policy() {
  local hostname=$1
  local expected_monitors=$2
  local expected_workspace_rules=$3
  local expected_window_rules=$4
  local expected_workspace_moves=$5
  local expected_dp2_workarounds=$6

  local monitor_output
  local autostart_output
  monitor_output=$(run_lua_config "$hostname" "$MONITORS_LUA" monitors)
  autostart_output=$(run_lua_config "$hostname" "$AUTOSTART_LUA" autostart)

  assert_contains "$monitor_output" "monitor=$expected_monitors" "$hostname monitor count"
  assert_contains "$monitor_output" "workspace=$expected_workspace_rules" "$hostname workspace-rule count"
  assert_contains "$monitor_output" "window=$expected_window_rules" "$hostname window-rule count"
  assert_contains "$monitor_output" 'gitkraken=0' "$hostname GitKraken rule absence"
  assert_contains "$autostart_output" "workspace_move=$expected_workspace_moves" "$hostname workspace move count"
  assert_contains "$autostart_output" "dp2_workaround=$expected_dp2_workarounds" "$hostname DP-2 workaround count"
}

assert_host_policy DESKTOP-E07VTRN 4 10 7 1 1
assert_host_policy omarchbook 2 0 0 0 0
assert_host_policy antoinews-linux 3 7 4 1 1
assert_host_policy unknown-host 1 0 0 0 0

laptop_output=$(run_lua_config omarchbook "$MONITORS_LUA" monitors)
assert_contains "$laptop_output" 'laptop_output=1' 'laptop built-in output'
assert_contains "$laptop_output" 'laptop_mirror=1' 'laptop external mirror'

fallback_output=$(run_lua_config unknown-host "$MONITORS_LUA" monitors)
assert_contains "$fallback_output" 'preferred_fallback=1' 'unknown-host preferred fallback'

grep -Fq '{{- if or (eq .Hostname "DESKTOP-E07VTRN") (eq .Hostname "antoinews-linux") }}' "$WAYBAR_TEMPLATE" || \
  fail 'Waybar workspace icon format is not hostname-gated'
grep -Fq '"ext/workspaces": {' "$WAYBAR_TEMPLATE" || \
  fail 'Waybar workspace module is missing'

printf 'PASS: host monitor policy tests\n'
