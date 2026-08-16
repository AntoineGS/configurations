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
preview_wrapper_pid=""
preview_wrapper_start_time=""
wayland_pid=""
wayland_start_time=""
nested_session=0
cleanup_error=0
ipc_timeout=3s
preview_direct_child=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

wall_clock_ns() {
  date +%s%N
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

process_parent_pid() {
  proc_stat_field "$1" 1
}

process_state() {
  proc_stat_field "$1" 0
}

capture_process_start_time() {
  process_start_time "$1" 2>/dev/null || true
}

process_identity_matches() {
  local pid=$1
  local expected_start_time=$2
  local actual_start_time

  [[ $pid =~ ^[1-9][0-9]*$ && -n $expected_start_time ]] || return 1
  actual_start_time=$(process_start_time "$pid" 2>/dev/null) || return 1
  [[ $actual_start_time == "$expected_start_time" ]]
}

process_is_alive() {
  local pid=$1
  local expected_start_time=$2
  local state

  process_identity_matches "$pid" "$expected_start_time" || return 1
  state=$(process_state "$pid" 2>/dev/null) || return 1
  [[ $state != Z ]] || return 1
  kill -0 "$pid" 2>/dev/null
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
  local now_ns remaining_ns

  now_ns=$(wall_clock_ns)
  remaining_ns=$((deadline_ns - now_ns))
  ((remaining_ns > 0)) || return 1
  ((remaining_ns > 3000000000)) && remaining_ns=3000000000
  format_duration "$remaining_ns"
}

sleep_until_deadline() {
  local deadline_ns=$1
  local now_ns remaining_ns

  now_ns=$(wall_clock_ns)
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
  local deadline_ns=$(( $(wall_clock_ns) + 2000000000 ))
  local now_ns

  while process_is_alive "$pid" "$expected_start_time"; do
    now_ns=$(wall_clock_ns)
    ((now_ns < deadline_ns)) || return 1
    sleep 0.05
  done
}

wait_child_bounded() {
  local pid=$1
  local timer_pid
  local wait_status

  trap ':' ALRM
  (sleep 2; kill -ALRM "$$" 2>/dev/null || true) &
  timer_pid=$!
  if wait "$pid" 2>/dev/null; then
    wait_status=0
  else
    wait_status=$?
  fi
  kill "$timer_pid" 2>/dev/null || true
  wait "$timer_pid" 2>/dev/null || true
  trap - ALRM

  if ((wait_status == 142)); then
    if process_state "$pid" >/dev/null 2>&1 && [[ $(process_state "$pid") != Z ]]; then
      return 1
    fi
    wait "$pid" 2>/dev/null || true
  fi
}

terminate_process() {
  local pid=$1
  local expected_start_time=$2
  local reap=$3
  local label=$4

  [[ -n $pid ]] || return 0

  if [[ -z $expected_start_time ]]; then
    if ((reap)); then
      kill -TERM "$pid" 2>/dev/null || true
      if ! wait_child_bounded "$pid"; then
        kill -KILL "$pid" 2>/dev/null || true
        if ! wait_child_bounded "$pid"; then
          printf 'FAIL: timed out terminating %s (PID %s)\n' "$label" "$pid" >&2
          cleanup_error=1
        fi
      fi
    fi
    return 0
  fi

  if process_identity_matches "$pid" "$expected_start_time"; then
    kill -TERM "$pid" 2>/dev/null || true
  fi

  if ! wait_for_process_exit "$pid" "$expected_start_time"; then
    if process_identity_matches "$pid" "$expected_start_time"; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
    if ! wait_for_process_exit "$pid" "$expected_start_time"; then
      printf 'FAIL: timed out terminating %s (PID %s)\n' "$label" "$pid" >&2
      cleanup_error=1
    fi
  fi

  if ((reap)) && ! wait_child_bounded "$pid"; then
    printf 'FAIL: timed out reaping %s (PID %s)\n' "$label" "$pid" >&2
    cleanup_error=1
  fi
}

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM ALRM

  terminate_process "$preview_pid" "$preview_start_time" "$preview_direct_child" 'Quickshell preview'
  terminate_process "$preview_wrapper_pid" "$preview_wrapper_start_time" 1 \
    'dbus-run-session wrapper'
  terminate_process "$wayland_pid" "$wayland_start_time" 1 'Wayland session'

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
    wayland_start_time=$(capture_process_start_time "$wayland_pid")
  elif command -v sway >/dev/null 2>&1; then
    printf '%s\n' 'output * bg #000000 solid_color' >"$config"
    WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway --unsupported-gpu -c "$config" \
      >"$wayland_log" 2>&1 &
    wayland_pid=$!
    wayland_start_time=$(capture_process_start_time "$wayland_pid")
  else
    fail 'no current or nested/test Wayland session is available'
  fi

  for _ in {1..50}; do
    [[ -S "$(wayland_socket)" ]] && {
      nested_session=1
      return 0
    }
    process_is_alive "$wayland_pid" "$wayland_start_time" || break
    sleep 0.1
  done

  fail 'nested/test Wayland session did not become available'
}

if ! current_socket=$(wayland_socket) || [[ ! -S $current_socket ]]; then
  start_nested_wayland
fi

preview_config=$(readlink -e -- "$SHELL_ROOT/shell.qml") || {
  fail 'desktop-shell shell.qml could not be canonicalized'
}

if ((nested_session == 1)) && command -v dbus-run-session >/dev/null 2>&1; then
  DESKTOP_SHELL_PREVIEW=1 dbus-run-session -- quickshell -p "$SHELL_ROOT" \
    >"$preview_log" 2>&1 &
  preview_wrapper_pid=$!
  preview_wrapper_start_time=$(capture_process_start_time "$preview_wrapper_pid")
else
  DESKTOP_SHELL_PREVIEW=1 quickshell -p "$SHELL_ROOT" >"$preview_log" 2>&1 &
  preview_pid=$!
  preview_start_time=$(capture_process_start_time "$preview_pid")
  preview_direct_child=1
fi

is_descendant_of() {
  local child=$1
  local ancestor=$2
  local current=$child
  local parent
  local -A seen=()

  [[ $child != "$ancestor" ]] || return 1
  while [[ $current != "$ancestor" ]]; do
    [[ -z ${seen[$current]+seen} ]] || return 1
    seen[$current]=1
    parent=$(process_parent_pid "$current" 2>/dev/null) || return 1
    [[ $parent =~ ^[1-9][0-9]*$ && $parent != 1 ]] || return 1
    current=$parent
  done
}

discover_nested_preview() {
  local deadline_ns=$1
  local list_timeout
  local instances_json
  local matching_pids_text
  local candidate candidate_start_time
  local live_pid=''
  local live_start_time=''
  local live_count=0
  local -a matching_pids=()

  process_is_alive "$preview_wrapper_pid" "$preview_wrapper_start_time" || {
    fail 'dbus-run-session wrapper exited before Quickshell PID discovery'
  }

  list_timeout=$(timeout_for_deadline "$deadline_ns") || return 1
  if ! instances_json=$(timeout --foreground "$list_timeout" quickshell list -j --all 2>/dev/null); then
    process_is_alive "$preview_wrapper_pid" "$preview_wrapper_start_time" || {
      fail 'dbus-run-session wrapper exited before Quickshell PID discovery'
    }
    return 1
  fi

  if ! matching_pids_text=$(jq -r -s --arg config "$preview_config" '
    if length != 1 then
      error("instance registry must contain exactly one JSON value")
    elif (.[0] | type) != "array" then
      error("instance registry must be one JSON array")
    elif (.[0] | any(.[]; type != "object")) then
      error("instance registry array contains a non-object entry")
    else
      .[0][] |
      select(type == "object" and .config_path == $config) |
      if (.pid | type) != "number" then
        error("matching instance has a non-numeric PID")
      elif .pid <= 0 then
        error("matching instance has a non-positive PID")
      elif .pid != (.pid | floor) then
        error("matching instance has a non-integer PID")
      else
        .pid | tostring
      end
    end
  ' <<<"$instances_json"); then
    fail 'Quickshell instance registry did not contain one JSON array'
  fi

  while IFS= read -r candidate; do
    if [[ -n $candidate ]]; then
      matching_pids+=("$candidate")
    fi
  done <<<"$matching_pids_text"

  for candidate in "${matching_pids[@]}"; do
    candidate_start_time=$(capture_process_start_time "$candidate")
    if [[ -n $candidate_start_time ]] && process_is_alive "$candidate" "$candidate_start_time"; then
      live_count=$((live_count + 1))
      live_pid=$candidate
      live_start_time=$candidate_start_time
    fi
  done

  ((live_count <= 1)) || fail 'Quickshell instance registry has multiple live matching previews'
  ((live_count == 1)) || return 1

  process_is_alive "$preview_wrapper_pid" "$preview_wrapper_start_time" || {
    fail 'dbus-run-session wrapper exited before Quickshell PID discovery'
  }
  is_descendant_of "$live_pid" "$preview_wrapper_pid" || {
    fail 'discovered Quickshell PID is not a descendant of dbus-run-session'
  }

  preview_pid=$live_pid
  preview_start_time=$live_start_time
}

require_preview_alive() {
  process_is_alive "$preview_pid" "$preview_start_time" || fail "$1"
}

readiness_deadline_ns=$(( $(wall_clock_ns) + 15000000000 ))
ping=''
while :; do
  if ((nested_session == 1)) && [[ -z $preview_pid ]]; then
    discover_nested_preview "$readiness_deadline_ns" || {
      if ! process_is_alive "$preview_wrapper_pid" "$preview_wrapper_start_time"; then
        fail 'dbus-run-session wrapper exited before Quickshell PID discovery'
      fi
      sleep_until_deadline "$readiness_deadline_ns" || break
      continue
    }
  fi

  require_preview_alive 'Quickshell preview exited before desktop-shell ping returned pong'
  ping_timeout=$(timeout_for_deadline "$readiness_deadline_ns") || break
  if ping=$(timeout --foreground "$ping_timeout" quickshell ipc --pid "$preview_pid" \
    call desktop-shell ping 2>/dev/null); then
    require_preview_alive 'Quickshell preview exited before desktop-shell ping was accepted'
    [[ $ping == pong ]] && break
  else
    require_preview_alive 'Quickshell preview exited before desktop-shell ping returned pong'
  fi
  sleep_until_deadline "$readiness_deadline_ns" || break
done

require_preview_alive 'Quickshell preview is not alive after the 15-second readiness window'
[[ $ping == pong ]] || fail 'desktop-shell ping did not return exactly pong within 15 seconds'

require_preview_alive 'Quickshell preview exited before listPlugins'
plugins_json=$(timeout --foreground "$ipc_timeout" quickshell ipc --pid "$preview_pid" \
  call desktop-shell listPlugins 2>/dev/null) || {
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
