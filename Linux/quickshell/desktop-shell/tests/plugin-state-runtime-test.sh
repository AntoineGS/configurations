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
  shell_pid=""
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  DESKTOP_SHELL_STATE_PATH="$state_file" \
  DESKTOP_SHELL_PLUGINS_DIR="$tmp_dir/plugins" \
  DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1 \
  HOME="$tmp_dir/home" \
  XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  XDG_CACHE_HOME="$tmp_dir/home/.cache" \
  XDG_STATE_HOME="$tmp_dir/home/.local/state" \
    quickshell -n -p "$shell_dir" >"$log_file" 2>&1 &
  shell_pid=$!

  local config=""
  for _ in {1..50}; do
    config=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell listShellConfig 2>/dev/null || true)
    if jq -e 'type == "object"' <<<"$config" >/dev/null 2>&1; then break; fi
    sleep 0.1
  done
  [[ -n $config ]] || { sed -n '1,180p' "$log_file" >&2; exit 1; }
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
kill "$shell_pid"
wait "$shell_pid" 2>/dev/null || true
shell_pid=""

invalid_state_file="$tmp_dir/invalid/config/desktop-shell/shell.json"
mkdir -p -- "$(dirname -- "$invalid_state_file")"
invalid_bytes='{"version":1,"enabledPlugins":['
printf '%s' "$invalid_bytes" >"$invalid_state_file"
cp -- "$invalid_state_file" "$tmp_dir/invalid-before"
start_shell "$invalid_state_file" "$tmp_dir/invalid-shell.log"
health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health)
jq -e '.pluginStateValid == false and .pluginStateError != "" and .pluginStateDirectoryReady == true' <<<"$health" >/dev/null
config=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell listShellConfig)
jq -e '.version == 1 and (.plugins | any(.id == "acme.panel") | not)' <<<"$config" >/dev/null
cmp -- "$invalid_state_file" "$tmp_dir/invalid-before"
