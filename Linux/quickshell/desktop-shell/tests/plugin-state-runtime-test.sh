#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
tmp_dir=$(mktemp -d)
shell_pid=""
trap '[[ -z $shell_pid ]] || kill "$shell_pid" 2>/dev/null || true; rm -rf -- "$tmp_dir"' EXIT

start_shell() {
  local state_file=$1
  local log_file=$2
  local allow_mutation=${3:-0}
  shell_pid=""
  local -a launch_env=(
    "DESKTOP_SHELL_TEST_NO_SURFACES=1"
    "DESKTOP_SHELL_STATE_PATH=$state_file"
    "DESKTOP_SHELL_PLUGINS_DIR=$tmp_dir/plugins"
    "DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1"
    "HOME=$tmp_dir/home"
    "XDG_CONFIG_HOME=$tmp_dir/home/.config"
    "XDG_CACHE_HOME=$tmp_dir/home/.cache"
    "XDG_STATE_HOME=$tmp_dir/home/.local/state"
  )
  if [[ $allow_mutation == 1 ]]; then
    launch_env+=("DESKTOP_SHELL_TEST_ALLOW_PLUGIN_STATE_MUTATION=1")
  fi
  env "${launch_env[@]}" quickshell -n -p "$shell_dir" >"$log_file" 2>&1 &
  shell_pid=$!

  local config=""
  for _ in {1..50}; do
    config=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell listShellConfig 2>/dev/null || true)
    if jq -e 'type == "object"' <<<"$config" >/dev/null 2>&1; then break; fi
    sleep 0.1
  done
  if ! jq -e 'type == "object"' <<<"$config" >/dev/null 2>&1; then
    sed -n '1,180p' "$log_file" >&2
    exit 1
  fi
}

wait_for_health() {
  local expression=$1
  local health=""
  for _ in {1..50}; do
    health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health 2>/dev/null || true)
    if jq -e "$expression" <<<"$health" >/dev/null 2>&1; then
      printf '%s' "$health"
      return 0
    fi
    sleep 0.1
  done
  sed -n '1,180p' "$tmp_dir"/*-shell.log >&2 || true
  printf '%s\n' "$health" >&2
  return 1
}

stop_shell() {
  kill "$shell_pid"
  wait "$shell_pid" 2>/dev/null || true
  shell_pid=""
}

state_file="$tmp_dir/config/desktop-shell/shell.json"
mkdir -p -- "$(dirname -- "$state_file")"
cat >"$state_file" <<'JSON'
{"version":1,"enabledPlugins":[{"id":"acme.panel"}],"barWidgets":[{"id":"acme.widget","section":"right","index":0,"settings":{"units":"c"}}]}
JSON

start_shell "$state_file" "$tmp_dir/valid-shell.log"
config=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell listShellConfig)
jq -e '.plugins | any(.id == "acme.panel")' <<<"$config" >/dev/null
jq -e '.bar.layout.right[0] == {"id":"acme.widget","units":"c"}' <<<"$config" >/dev/null
health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health)
jq -e '.pluginStateValid == true and .pluginStateDirectoryReady == true' <<<"$health" >/dev/null
normal_hook_result=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell-test persistPluginStateForTest '{"version":1}' )
[[ $normal_hook_result == "Function not found." || $normal_hook_result == "Target not found." ]]
stop_shell

first_write_file="$tmp_dir/first-write/config/desktop-shell/shell.json"
start_shell "$first_write_file" "$tmp_dir/first-write-shell.log" 1
wait_for_health '.pluginStateDirectoryReady == true and .pluginStateValid == true' >/dev/null
[[ ! -e $first_write_file ]]
write_result=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell-test persistPluginStateForTest '{"version":1,"enabledPlugins":[{"id":"acme.first-write"}]}' )
if [[ $write_result != "saved" ]]; then
  printf 'unexpected first-write result: %s\n' "$write_result" >&2
  sed -n '1,180p' "$tmp_dir/first-write-shell.log" >&2
  exit 1
fi
jq -e '.pluginStateWritePending == false and .pluginStateWriteError == ""' <<<"$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health)" >/dev/null
[[ -f $first_write_file ]]
jq -e '.enabledPlugins == [{"id":"acme.first-write"}]' "$first_write_file" >/dev/null
stop_shell

invalid_state_file="$tmp_dir/invalid/config/desktop-shell/shell.json"
mkdir -p -- "$(dirname -- "$invalid_state_file")"
invalid_bytes='{"version":1,"enabledPlugins":['
printf '%s' "$invalid_bytes" >"$invalid_state_file"
cp -- "$invalid_state_file" "$tmp_dir/invalid-before"
start_shell "$invalid_state_file" "$tmp_dir/invalid-shell.log" 1
health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health)
jq -e '.pluginStateValid == false and .pluginStateError != "" and .pluginStateDirectoryReady == true' <<<"$health" >/dev/null
invalid_result=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell-test persistPluginStateForTest '{"version":1}' )
[[ $invalid_result == "rejected-invalid-state" ]]
config=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell listShellConfig)
jq -e '.version == 1 and (.plugins | any(.id == "acme.panel") | not)' <<<"$config" >/dev/null
cmp -- "$invalid_state_file" "$tmp_dir/invalid-before"
stop_shell

failure_state_file="$tmp_dir/failure/config/desktop-shell/shell.json"
start_shell "$failure_state_file" "$tmp_dir/failure-shell.log" 1
wait_for_health '.pluginStateDirectoryReady == true and .pluginStateValid == true' >/dev/null
mkdir -p -- "$failure_state_file"
failure_result=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell-test persistPluginStateForTest '{"version":1,"enabledPlugins":[{"id":"acme.failed-write"}]}' )
[[ $failure_result == "rejected-write-failed" ]]
wait_for_health '.pluginStateWritePending == false and .pluginStateWriteError != ""' >/dev/null
[[ -d $failure_state_file ]]
