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

command -v timeout >/dev/null 2>&1 || {
  printf 'FAIL: timeout is required to bound Quickshell CLI calls\n' >&2
  exit 1
}

test_root=$(mktemp -d)
preview_log="$test_root/quickshell.log"
wayland_log="$test_root/wayland.log"
preview_pid=""
preview_start_time=""
wayland_pid=""
wayland_start_time=""
cleanup_error=0
ipc_timeout=3s
ipc_kill_after=1s

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

proc_stat_field() {
  local pid=$1
  local index=$2
  local stat_text
  local -a fields=()

  [[ -r "/proc/$pid/stat" ]] || return 1
  stat_text=$(<"/proc/$pid/stat") || return 1
  stat_text=${stat_text##*) }
  read -r -a fields <<<"$stat_text"
  ((index >= 0 && index < ${#fields[@]})) || return 1
  printf '%s\n' "${fields[index]}"
}

process_start_time() {
  proc_stat_field "$1" 19
}

process_state() {
  proc_stat_field "$1" 0
}

capture_process_start_time() {
  local pid=$1

  process_start_time "$pid" 2>/dev/null || true
}

process_identity_matches() {
  local pid=$1
  local expected_start_time=$2
  local actual_start_time

  [[ $pid =~ ^[1-9][0-9]*$ && -n $expected_start_time ]] || return 1
  actual_start_time=$(process_start_time "$pid" 2>/dev/null) || return 1
  [[ $actual_start_time == "$expected_start_time" ]]
}

process_is_running() {
  local pid=$1
  local expected_start_time=$2
  local state

  process_identity_matches "$pid" "$expected_start_time" || return 1
  state=$(process_state "$pid" 2>/dev/null) || return 1
  [[ $state != Z ]]
}

monotonic_ns() {
  local uptime seconds fraction

  read -r uptime _ < /proc/uptime || return 1
  seconds=${uptime%%.*}
  fraction=${uptime#*.}
  [[ $seconds =~ ^[0-9]+$ && $fraction =~ ^[0-9]+$ ]] || return 1
  fraction=${fraction}000000000
  fraction=${fraction:0:9}
  printf '%d\n' "$((10#$seconds * 1000000000 + 10#$fraction))"
}

format_duration() {
  local duration_ns=$1
  local seconds nanos

  ((duration_ns > 0)) || return 1
  seconds=$((duration_ns / 1000000000))
  nanos=$((duration_ns % 1000000000))
  printf '%d.%09ds\n' "$seconds" "$nanos"
}

timeout_for_deadline() {
  local deadline_ns=$1
  local now_ns remaining_ns timeout_ns kill_after_ns

  now_ns=$(monotonic_ns)
  remaining_ns=$((deadline_ns - now_ns))
  ((remaining_ns > 0)) || return 1

  kill_after_ns=250000000
  if ((remaining_ns <= kill_after_ns)); then
    kill_after_ns=$((remaining_ns / 2))
  fi
  ((kill_after_ns > 0)) || return 1
  timeout_ns=$((remaining_ns - kill_after_ns))
  ((timeout_ns > 0)) || return 1
  ((timeout_ns > 3000000000)) && timeout_ns=3000000000
  printf '%s %s\n' "$(format_duration "$timeout_ns")" "$(format_duration "$kill_after_ns")"
}

sleep_until_deadline() {
  local deadline_ns=$1
  local now_ns remaining_ns

  now_ns=$(monotonic_ns)
  remaining_ns=$((deadline_ns - now_ns))
  ((remaining_ns > 0)) || return 1
  if ((remaining_ns > 100000000)); then
    sleep 0.1
  else
    sleep "$(format_duration "$remaining_ns")"
  fi
}

wait_for_process_exit() {
  local pid=$1
  local expected_start_time=$2
  local deadline_ns=$(( $(monotonic_ns) + 2000000000 ))
  local actual_start_time state now_ns

  while :; do
    [[ -r "/proc/$pid/stat" ]] || return 0
    actual_start_time=$(process_start_time "$pid" 2>/dev/null) || {
      now_ns=$(monotonic_ns)
      ((now_ns < deadline_ns)) || return 1
      sleep 0.05
      continue
    }
    [[ $actual_start_time == "$expected_start_time" ]] || return 0
    state=$(process_state "$pid" 2>/dev/null) || {
      now_ns=$(monotonic_ns)
      ((now_ns < deadline_ns)) || return 1
      sleep 0.05
      continue
    }
    [[ $state == Z ]] && return 0
    now_ns=$(monotonic_ns)
    ((now_ns < deadline_ns)) || return 1
    sleep 0.05
  done
}

reap_child() {
  wait "$1" 2>/dev/null || true
}

terminate_process() {
  local pid=$1
  local expected_start_time=$2
  local label=$3

  [[ -n $pid ]] || return 0

  if [[ -z $expected_start_time ]]; then
    # The child was gone before /proc identity capture; only reap the known job.
    reap_child "$pid"
    return 0
  fi

  if process_is_running "$pid" "$expected_start_time" &&
    process_identity_matches "$pid" "$expected_start_time"; then
    kill -TERM "$pid" 2>/dev/null || true
  fi

  if wait_for_process_exit "$pid" "$expected_start_time"; then
    reap_child "$pid"
    return 0
  fi

  if process_is_running "$pid" "$expected_start_time" &&
    process_identity_matches "$pid" "$expected_start_time"; then
    kill -KILL "$pid" 2>/dev/null || true
  fi

  if wait_for_process_exit "$pid" "$expected_start_time"; then
    reap_child "$pid"
    return 0
  fi

  printf 'FAIL: timed out terminating %s (PID %s)\n' "$label" "$pid" >&2
  cleanup_error=1
}

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM

  terminate_process "$preview_pid" "$preview_start_time" 'Quickshell preview'
  terminate_process "$wayland_pid" "$wayland_start_time" 'Wayland session'

  ((cleanup_error == 0)) || status=1

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

  wayland_start_time=$(capture_process_start_time "$wayland_pid")
  if [[ -z $wayland_start_time ]]; then
    reap_child "$wayland_pid"
    fail 'nested Wayland compositor exited before process identity was captured'
  fi

  for _ in {1..50}; do
    [[ -S "$(wayland_socket)" ]] && {
      return 0
    }
    process_is_running "$wayland_pid" "$wayland_start_time" || break
    sleep 0.1
  done

  fail 'nested/test Wayland session did not become available'
}

if ! current_socket=$(wayland_socket) || [[ ! -S $current_socket ]]; then
  start_nested_wayland
fi

DESKTOP_SHELL_PREVIEW=1 quickshell -p "$SHELL_ROOT" >"$preview_log" 2>&1 &
preview_pid=$!
preview_start_time=$(capture_process_start_time "$preview_pid")
if [[ -z $preview_start_time ]]; then
  reap_child "$preview_pid"
  fail 'Quickshell preview exited before process identity was captured'
fi

require_preview_alive() {
  process_is_running "$preview_pid" "$preview_start_time" || fail "$1"
}

readiness_deadline_ns=$(( $(monotonic_ns) + 15000000000 ))
ping=''
while :; do
  ping_output=''
  ping_status=0
  require_preview_alive 'Quickshell preview exited before desktop-shell ping returned pong'
  if ! read -r ping_timeout ping_kill_after < <(timeout_for_deadline "$readiness_deadline_ns"); then
    break
  fi
  ping_output=$(timeout --foreground --kill-after="$ping_kill_after" "$ping_timeout" \
    quickshell ipc --pid "$preview_pid" call desktop-shell ping 2>/dev/null) || ping_status=$?
  ping_completed_ns=$(monotonic_ns)
  if [[ $ping_output == pong ]]; then
    ((ping_completed_ns <= readiness_deadline_ns)) || {
      fail 'desktop-shell ping returned after the 15-second readiness deadline'
    }
  fi
  if ((ping_status == 0)); then
    ping=$ping_output
    require_preview_alive 'Quickshell preview exited before desktop-shell ping was accepted'
    [[ $ping == pong ]] && break
  else
    ping=''
    require_preview_alive 'Quickshell preview exited before desktop-shell ping returned pong'
  fi
  sleep_until_deadline "$readiness_deadline_ns" || break
done

require_preview_alive 'Quickshell preview is not alive after the 15-second readiness window'
[[ $ping == pong ]] || fail 'desktop-shell ping did not return exactly pong within 15 seconds'

require_preview_alive 'Quickshell preview exited before listPlugins'
plugins_json=$(timeout --foreground --kill-after="$ipc_kill_after" "$ipc_timeout" \
  quickshell ipc --pid "$preview_pid" call desktop-shell listPlugins 2>/dev/null) || {
  fail 'desktop-shell listPlugins failed'
}
require_preview_alive 'Quickshell preview exited before listPlugins was accepted'

jq -e -s '
  length == 1 and
  (.[0] |
    (if type == "string" then try fromjson catch null else . end) |
    type == "object" and has("desktop.bar"))
' <<<"$plugins_json" >/dev/null || fail 'listPlugins was not one object containing desktop.bar'

if grep -Fq 'Loader.Error' "$preview_log"; then
  fail 'Loader.Error found in the Quickshell preview log'
fi
