#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell is unavailable\n'
  exit 0
fi

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  printf 'SKIP: no Wayland session is available\n'
  exit 0
fi

command -v jq >/dev/null 2>&1 || {
  printf 'FAIL: jq is required\n' >&2
  exit 1
}
command -v timeout >/dev/null 2>&1 || {
  printf 'FAIL: timeout is required\n' >&2
  exit 1
}

selected_ids=()
while IFS='|' read -r plugin_id _ _; do
  [[ -n $plugin_id && ${plugin_id:0:1} != '#' ]] || continue
  selected_ids+=("$plugin_id")
done <"$SHELL_ROOT/SELECTED_PLUGINS"

if ((${#selected_ids[@]} == 0)); then
  printf 'FAIL: SELECTED_PLUGINS contains no plugin IDs\n' >&2
  exit 1
fi

preview_log=$(mktemp)
preview_pid=''

cleanup() {
  local status=$?

  trap - EXIT HUP INT TERM
  if [[ -n $preview_pid ]] && kill -0 "$preview_pid" 2>/dev/null; then
    kill "$preview_pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$preview_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$preview_pid" 2>/dev/null || true
  fi
  [[ -z $preview_pid ]] || wait "$preview_pid" 2>/dev/null || true

  if grep -Fq 'Loader.Error' "$preview_log"; then
    printf 'FAIL: Loader.Error found in the Quickshell preview log\n' >&2
    status=1
  fi
  if grep -Eq 'Plugin widget [^[:space:]]+ failed:' "$preview_log"; then
    printf 'FAIL: plugin widget failure found in the Quickshell preview log\n' >&2
    status=1
  fi
  if grep -Fq 'Handler was registered but will not be used because another handler is registered for target' "$preview_log"; then
    printf 'FAIL: duplicate Quickshell IPC handler found in the preview log\n' >&2
    status=1
  fi
  if ((status != 0)) && [[ -s $preview_log ]]; then
    printf '%s\n' '--- quickshell preview log ---' >&2
    printf '%s\n' "$(<"$preview_log")" >&2
  fi

  rm -f "$preview_log"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

DESKTOP_SHELL_PREVIEW=1 quickshell -p "$SHELL_ROOT" >"$preview_log" 2>&1 &
preview_pid=$!

deadline=$((SECONDS + 15))
ping=''
while ((SECONDS < deadline)); do
  kill -0 "$preview_pid" 2>/dev/null || {
    printf 'FAIL: Quickshell preview exited before becoming ready\n' >&2
    exit 1
  }
  ping=$(timeout --kill-after=1s 1s quickshell ipc --pid "$preview_pid" \
    call desktop-shell ping 2>/dev/null) || true
  [[ $ping == pong ]] && break
  sleep 0.2
done

[[ $ping == pong ]] || {
  printf 'FAIL: desktop-shell ping did not return pong within 15 seconds\n' >&2
  exit 1
}

plugins=$(timeout --kill-after=1s 3s quickshell ipc --pid "$preview_pid" \
  call desktop-shell listPlugins 2>/dev/null) || {
  printf 'FAIL: desktop-shell listPlugins failed\n' >&2
  exit 1
}

plugin_json=$(jq -e -s '
  if length == 1 then
    (.[0] | if type == "string" then fromjson else . end)
  else
    error("expected one IPC response")
  end
' <<<"$plugins") || {
  printf 'FAIL: listPlugins did not return a JSON object\n' >&2
  exit 1
}

jq -e 'has("desktop.bar")' <<<"$plugin_json" >/dev/null || {
  printf 'FAIL: listPlugins did not report desktop.bar\n' >&2
  exit 1
}
for plugin_id in "${selected_ids[@]}"; do
  jq -e --arg id "$plugin_id" 'has($id)' <<<"$plugin_json" >/dev/null || {
    printf 'FAIL: listPlugins did not report selected plugin %s\n' "$plugin_id" >&2
    exit 1
  }
done

call_ipc() {
  timeout --kill-after=1s 2s quickshell ipc --pid "$preview_pid" call "$@" 2>/dev/null
}

wait_for_ipc() {
  local target=$1
  local method=$2
  local expected=$3
  local optional=${4:-0}
  local result=''
  local deadline=$((SECONDS + 10))

  while ((SECONDS < deadline)); do
    result=$(call_ipc "$target" "$method") || true
    if [[ $result == "$expected" ]]; then
      return 0
    fi
    if ((optional == 1)) && [[ $result == unavailable ]]; then
      printf 'INFO: %s %s unavailable\n' "$target" "$method"
      return 0
    fi
    sleep 0.2
  done

  printf 'FAIL: %s %s returned %q, expected %s%s\n' \
    "$target" "$method" "$result" "$expected" \
    "$([[ $optional == 1 ]] && printf ' or unavailable')" >&2
  return 1
}

call_ipc desktop-shell summon desktop.menu '{"menu":"root"}' | grep -Fxq ok || {
  printf 'FAIL: desktop.menu summon failed\n' >&2
  exit 1
}
wait_for_ipc desktop.menu ping pong

call_ipc desktop-shell summon desktop.agents '{}' | grep -Fxq ok || {
  printf 'FAIL: desktop.agents summon failed\n' >&2
  exit 1
}
wait_for_ipc desktop.agents refresh ok

wait_for_ipc desktop.audio ping pong
wait_for_ipc desktop.network ping pong 1
wait_for_ipc desktop.bluetooth ping pong
wait_for_ipc desktop.power ping pong 1
wait_for_ipc desktop.monitor ping pong 1
wait_for_ipc desktop.tailscale ping pong 1

printf 'PASS: Quickshell preview runtime\n'
