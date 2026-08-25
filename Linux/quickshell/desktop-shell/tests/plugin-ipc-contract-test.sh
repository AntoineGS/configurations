#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: quickshell and jq are required\n'
  exit 0
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
helper_dir="$repo_root/Linux/os/helpers"
tmp_dir=$(mktemp -d)
shell_pid=""

stop_shell() {
  if [[ -n $shell_pid ]]; then
    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
    shell_pid=""
  fi
}

trap 'stop_shell; rm -rf -- "$tmp_dir"' EXIT

plugins_dir="$tmp_dir/plugins"
state_file="$tmp_dir/home/.config/desktop-shell/shell.json"
mkdir -p -- "$plugins_dir/acme.widget"
cat >"$plugins_dir/acme.widget/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"acme.widget","name":"Acme Widget","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"BarWidget.qml"}}
JSON
cat >"$plugins_dir/acme.widget/BarWidget.qml" <<'QML'
import QtQuick
Item { }
QML

env \
  HOME="$tmp_dir/home" \
  XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  XDG_CACHE_HOME="$tmp_dir/home/.cache" \
  XDG_STATE_HOME="$tmp_dir/home/.local/state" \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  DESKTOP_SHELL_TEST_ALLOW_PLUGIN_STATE_MUTATION=1 \
  DESKTOP_SHELL_TEST_LOAD_PLUGIN_WIDGETS=1 \
  DESKTOP_SHELL_STATE_PATH="$state_file" \
  DESKTOP_SHELL_PLUGINS_DIR="$plugins_dir" \
  DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1 \
  quickshell -n -p "$shell_dir" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!

plugins=""
for _ in {1..100}; do
  plugins=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell listPlugins 2>/dev/null || true)
  if jq -e 'type == "array"' <<<"$plugins" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
jq -e 'type == "array"' <<<"$plugins" >/dev/null
jq -e 'any(.[]; .id == "desktop.bar" and .firstParty == true and .canDisable == false)' <<<"$plugins" >/dev/null
jq -e 'any(.[]; .id == "acme.widget" and .firstParty == false and .enabled == false)' <<<"$plugins" >/dev/null

enable_result=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell enablePlugin acme.widget '{"section":"right"}')
[[ -n $enable_result ]]
quickshell ipc --pid "$shell_pid" call -- desktop-shell rescanPlugins >/dev/null
for _ in {1..100}; do
  health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health 2>/dev/null || true)
  if jq -e '.reloadScanTerminal == true and .reloadOutstandingCount == 0 and .reloadComponentsActive == false' <<<"$health" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
jq -e '.reloadScanTerminal == true and .reloadOutstandingCount == 0 and .reloadComponentsActive == false' <<<"$health" >/dev/null
widget_ready=""
for _ in {1..100}; do
  widget_ready=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell-test pluginWidgetReady acme.widget 2>/dev/null || true)
  if [[ $widget_ready == ready ]]; then break; fi
  sleep 0.1
done
[[ $widget_ready == ready ]]
set_result=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell setPluginEnabled acme.widget false)
[[ -n $set_result ]]
stop_shell

failure_state_file="$tmp_dir/failure-state"
mkdir -p -- "$failure_state_file"
env \
  HOME="$tmp_dir/home" \
  XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  XDG_CACHE_HOME="$tmp_dir/home/.cache" \
  XDG_STATE_HOME="$tmp_dir/home/.local/state" \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  DESKTOP_SHELL_TEST_ALLOW_PLUGIN_STATE_MUTATION=1 \
  DESKTOP_SHELL_STATE_PATH="$failure_state_file" \
  DESKTOP_SHELL_PLUGINS_DIR="$plugins_dir" \
  DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1 \
  quickshell -n -p "$shell_dir" >"$tmp_dir/failure-quickshell.log" 2>&1 &
shell_pid=$!
for _ in {1..100}; do
  plugins=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell listPlugins 2>/dev/null || true)
  if jq -e 'type == "array"' <<<"$plugins" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
failure_result=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell setPluginEnabled acme.widget false)
[[ $failure_result == "plugin state write failed: 1" ]]
failure_health=""
for _ in {1..100}; do
  failure_health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health 2>/dev/null || true)
  if jq -e '.pluginStateWriteError != ""' <<<"$failure_health" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
jq -e '.pluginStateWriteError != ""' <<<"$failure_health" >/dev/null
stop_shell

stub_bin="$tmp_dir/bin"
mkdir -p -- "$stub_bin"
cat >"$stub_bin/quickshell" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$STUB_ARGS"
printf '%s\n' "$PATH" >"$STUB_PATH"
SH
chmod +x "$stub_bin/quickshell"

export STUB_ARGS="$tmp_dir/args"
export STUB_PATH="$tmp_dir/path"
PATH="$stub_bin:/usr/bin:/bin" "$helper_dir/desktop-shell" ping
[[ $(<"$STUB_ARGS") == *'ipc --any-display -p '* ]]
[[ $(<"$STUB_ARGS") == *'call -- desktop-shell ping' ]]

if PATH="$stub_bin:/usr/bin:/bin" "$helper_dir/desktop-shell" nope >/dev/null 2>&1; then
  printf 'desktop-shell accepted an unknown verb\n' >&2
  exit 1
fi
if PATH="$stub_bin:/usr/bin:/bin" "$helper_dir/desktop-shell" plugin-enable bad..id '{}' >/dev/null 2>&1; then
  printf 'desktop-shell accepted an invalid plugin id\n' >&2
  exit 1
fi

launch_home="$tmp_dir/launch-home"
mkdir -p -- "$launch_home/.config/quickshell/desktop-shell/config" "$launch_home/.local/share/helpers"
touch "$launch_home/.config/quickshell/desktop-shell/shell.qml" "$launch_home/.config/quickshell/desktop-shell/config/shell.json"
assert_launch_path() {
  local input_path=$1
  local expected_path=$2
  PATH="$input_path" HOME="$launch_home" "$helper_dir/desktop-shell-launch"
  [[ $(<"$STUB_PATH") == "$expected_path" ]]
}

assert_launch_path \
  "$stub_bin:/usr/bin:/bin" \
  "$launch_home/.local/share/helpers:$stub_bin:/usr/bin:/bin"
assert_launch_path \
  "$launch_home/.local/share/helpers:$stub_bin:/usr/bin:/bin" \
  "$launch_home/.local/share/helpers:$stub_bin:/usr/bin:/bin"
assert_launch_path \
  "$stub_bin:$launch_home/.local/share/helpers:/usr/bin" \
  "$launch_home/.local/share/helpers:$stub_bin:/usr/bin"
assert_launch_path \
  "$stub_bin:$launch_home/.local/share/helpers:/usr/bin:$launch_home/.local/share/helpers:/bin" \
  "$launch_home/.local/share/helpers:$stub_bin:/usr/bin:/bin"

facade="$tmp_dir/facade"
mkdir -p -- "$facade"
cp -- "$helper_dir/omarchy-shell" "$facade/omarchy-shell"
cat >"$facade/desktop-shell" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OMARCHY_CALLS"
if [[ ${OMARCHY_FAIL:-0} == 1 ]]; then exit 1; fi
SH
chmod +x "$facade/omarchy-shell" "$facade/desktop-shell"
export OMARCHY_CALLS="$tmp_dir/omarchy-calls"

assert_translation() {
  local expected=$1
  shift
  : >"$OMARCHY_CALLS"
  "$facade/omarchy-shell" "$@"
  [[ $(<"$OMARCHY_CALLS") == "$expected" ]]
}

assert_translation "ping" shell ping
assert_translation "plugin-rescan" shell rescanPlugins
assert_translation "plugin-list" shell listPlugins
assert_translation "list-shell-config" shell listShellConfig
assert_translation 'plugin-enable acme.widget {"section":"right"}' shell enablePlugin acme.widget '{"section":"right"}'
assert_translation "plugin-set-enabled acme.widget false" shell setPluginEnabled acme.widget false
assert_translation 'plugin-put acme.widget {"section":"right"}' shell putBarWidget acme.widget '{"section":"right"}'
assert_translation 'plugin-move acme.widget {"section":"left"}' shell moveBarWidget acme.widget '{"section":"left"}'
assert_translation 'plugin-set-widget acme.widget units "c" {}' shell setBarWidget acme.widget units '"c"'
assert_translation 'toggle acme.widget {}' shell toggle acme.widget
assert_translation 'summon acme.widget {}' shell summon acme.widget
assert_translation 'hide acme.widget' shell hide acme.widget
if "$facade/omarchy-shell" other listPlugins >/dev/null 2>&1; then exit 1; fi
if "$facade/omarchy-shell" shell unknown >/dev/null 2>&1; then exit 1; fi
if "$facade/omarchy-shell" shell setPluginEnabled acme.widget >/dev/null 2>&1; then exit 1; fi
OMARCHY_FAIL=1 "$facade/omarchy-shell" -q shell listPlugins

printf 'PASS: plugin IPC contract\n'
