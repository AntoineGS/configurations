#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell is unavailable\n'
  exit 0
fi

command -v jq >/dev/null 2>&1 || {
  printf 'FAIL: jq is required to validate listPlugins JSON\n' >&2
  exit 1
}

test_root=$(mktemp -d)
preview_log="$test_root/quickshell.log"
wayland_log="$test_root/wayland.log"
preview_pid=""
wayland_pid=""
nested_session=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

terminate_process() {
  local pid=$1

  if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
  if [[ -n $pid ]]; then
    wait "$pid" 2>/dev/null || true
  fi
}

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM

  terminate_process "$preview_pid"
  terminate_process "$wayland_pid"

  if [[ -s $preview_log ]] && grep -Fq 'Loader.Error' "$preview_log"; then
    printf 'FAIL: Loader.Error found in the Quickshell preview log\n' >&2
    status=1
  fi

  if ((status != 0)); then
    if [[ -s $preview_log ]]; then
      printf '%s\n' '--- quickshell preview log ---' >&2
      printf '%s\n' "$(<"$preview_log")" >&2
    fi
    if [[ -s $wayland_log ]]; then
      printf '%s\n' '--- Wayland session log ---' >&2
      printf '%s\n' "$(<"$wayland_log")" >&2
    fi
  fi

  rm -rf "$test_root"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

wayland_socket() {
  local display=${WAYLAND_DISPLAY:-}

  [[ -n $display && -n ${XDG_RUNTIME_DIR:-} ]] || return 1
  if [[ $display == /* ]]; then
    printf '%s\n' "$display"
  else
    printf '%s/%s\n' "$XDG_RUNTIME_DIR" "$display"
  fi
}

start_nested_wayland() {
  local runtime="$test_root/runtime"
  local config="$test_root/sway.conf"

  mkdir -m 700 "$runtime"
  export XDG_RUNTIME_DIR="$runtime"
  export WAYLAND_DISPLAY=desktop-shell-test-wayland

  if command -v weston >/dev/null 2>&1; then
    weston --backend=headless-backend.so --socket="$WAYLAND_DISPLAY" --idle-time=0 \
      >"$wayland_log" 2>&1 &
    wayland_pid=$!
  elif command -v sway >/dev/null 2>&1; then
    printf '%s\n' 'output * bg #000000 solid_color' >"$config"
    WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway --unsupported-gpu -c "$config" \
      >"$wayland_log" 2>&1 &
    wayland_pid=$!
  else
    fail 'no current or nested/test Wayland session is available'
  fi

  for _ in {1..50}; do
    [[ -S "$(wayland_socket)" ]] && {
      nested_session=1
      return 0
    }
    kill -0 "$wayland_pid" 2>/dev/null || break
    sleep 0.1
  done

  fail 'nested/test Wayland session did not become available'
}

if ! current_socket=$(wayland_socket) || [[ ! -S $current_socket ]]; then
  start_nested_wayland
fi

if ((nested_session == 1)) && command -v dbus-run-session >/dev/null 2>&1; then
  DESKTOP_SHELL_PREVIEW=1 dbus-run-session -- quickshell -n -p "$SHELL_ROOT" \
    >"$preview_log" 2>&1 &
else
  DESKTOP_SHELL_PREVIEW=1 quickshell -n -p "$SHELL_ROOT" >"$preview_log" 2>&1 &
fi
preview_pid=$!

deadline=$((SECONDS + 15))
ping=''
while ((SECONDS < deadline)); do
  if ping=$(quickshell ipc -p "$SHELL_ROOT" call desktop-shell ping 2>/dev/null); then
    [[ $ping == pong ]] && break
  fi
  kill -0 "$preview_pid" 2>/dev/null || fail 'Quickshell preview exited before desktop-shell ping returned pong'
  sleep 0.1
done

[[ $ping == pong ]] || fail 'desktop-shell ping did not return exactly pong within 15 seconds'

plugins_json=$(quickshell ipc -p "$SHELL_ROOT" call desktop-shell listPlugins 2>/dev/null) || {
  fail 'desktop-shell listPlugins failed'
}

jq -e '
  if type == "string" then
    (fromjson | type == "object" and has("desktop.bar"))
  else
    type == "object" and has("desktop.bar")
  end
' <<<"$plugins_json" >/dev/null || fail 'listPlugins did not report desktop.bar'

grep -Fq 'Loader.Error' "$preview_log" && fail 'Loader.Error found in the Quickshell preview log'
