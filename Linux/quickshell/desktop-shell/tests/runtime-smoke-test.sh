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
main_pid=$BASHPID
preview_pid=""
preview_start_time=""
wayland_pid=""
wayland_start_time=""
cleanup_error=0
cleanup_running=0
launch_critical_section=0
pending_signal_status=0
launch_failure_reason=""
ownership_timeout_ns=500000000
ipc_timeout=3s
ipc_kill_after=1s

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

handle_signal() {
  local status=$1

  if ((launch_critical_section)); then
    if ((pending_signal_status == 0)); then
      pending_signal_status=$status
    fi
    return 0
  fi

  if ((cleanup_running)); then
    return 0
  fi

  exit "$status"
}

honor_pending_signal() {
  local status=$pending_signal_status

  pending_signal_status=0
  if ((status != 0)); then
    exit "$status"
  fi
}

capture_process_identity() {
  local pid=$1
  local stat_text
  local -a fields=()

  observed_process_state=""
  observed_process_parent_pid=""
  observed_process_start_time=""

  [[ $pid =~ ^[1-9][0-9]*$ && -r "/proc/$pid/stat" ]] || return 1
  stat_text=$(<"/proc/$pid/stat") || return 1
  stat_text=${stat_text##*) }
  read -r -a fields <<<"$stat_text"
  (( ${#fields[@]} > 19 )) || return 1

  observed_process_state=${fields[0]}
  observed_process_parent_pid=${fields[1]}
  observed_process_start_time=${fields[19]}
  [[ $observed_process_parent_pid =~ ^[1-9][0-9]*$ ]] || return 1
  [[ $observed_process_start_time =~ ^[1-9][0-9]*$ ]]
}

process_identity_matches() {
  local pid=$1
  local expected_start_time=$2

  [[ $pid =~ ^[1-9][0-9]*$ && $expected_start_time =~ ^[1-9][0-9]*$ ]] || return 1
  capture_process_identity "$pid" 2>/dev/null || return 1
  [[ $observed_process_start_time == "$expected_start_time" &&
    $observed_process_parent_pid == "$main_pid" &&
    $observed_process_state != Z ]]
}

process_is_running() {
  local pid=$1
  local expected_start_time=$2

  process_identity_matches "$pid" "$expected_start_time"
}

establish_process_ownership() {
  local pid=$1
  local deadline_ns=$2
  local now_ns candidate_start_time

  child_start_time=""
  launch_failure_reason=""

  [[ $pid =~ ^[1-9][0-9]*$ ]] || {
    launch_failure_reason='invalid-pid'
    return 1
  }

  while :; do
    if ! capture_process_identity "$pid" 2>/dev/null; then
      [[ -r "/proc/$pid/stat" ]] || {
        launch_failure_reason='exited'
        return 1
      }
    elif [[ $observed_process_state == Z ]]; then
      launch_failure_reason='exited'
      return 1
    elif [[ $observed_process_parent_pid != "$main_pid" ]]; then
      launch_failure_reason='ppid-mismatch'
      return 1
    else
      candidate_start_time=$observed_process_start_time
      if capture_process_identity "$pid" 2>/dev/null; then
        if [[ $observed_process_start_time == "$candidate_start_time" &&
          $observed_process_parent_pid == "$main_pid" &&
          $observed_process_state != Z ]]; then
          child_start_time=$candidate_start_time
          return 0
        fi
        if [[ $observed_process_state == Z ]]; then
          launch_failure_reason='exited'
        else
          launch_failure_reason='identity-changed'
        fi
        return 1
      fi
      if [[ ! -r "/proc/$pid/stat" ]]; then
        launch_failure_reason='exited'
      else
        launch_failure_reason='identity-unreadable'
      fi
      return 1
    fi

    read_monotonic_ns || {
      launch_failure_reason='clock'
      return 1
    }
    now_ns=$monotonic_value_ns
    if ((now_ns >= deadline_ns)); then
      if [[ ! -r "/proc/$pid/stat" ]]; then
        launch_failure_reason='exited'
      else
        launch_failure_reason='timeout'
      fi
      return 1
    fi
  done
}

read_monotonic_ns() {
  local uptime seconds fraction

  read -r uptime _ < /proc/uptime || return 1
  seconds=${uptime%%.*}
  fraction=${uptime#*.}
  [[ $seconds =~ ^[0-9]+$ && $fraction =~ ^[0-9]+$ ]] || return 1
  fraction=${fraction}000000000
  fraction=${fraction:0:9}
  monotonic_value_ns=$((10#$seconds * 1000000000 + 10#$fraction))
}

monotonic_ns() {
  read_monotonic_ns || return 1
  printf '%d\n' "$monotonic_value_ns"
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
  local now_ns

  while :; do
    if ! capture_process_identity "$pid" 2>/dev/null; then
      [[ -r "/proc/$pid/stat" ]] || return 0
      return 2
    fi
    [[ $observed_process_start_time == "$expected_start_time" &&
      $observed_process_parent_pid == "$main_pid" ]] || return 2
    [[ $observed_process_state == Z ]] && return 0
    now_ns=$(monotonic_ns)
    ((now_ns < deadline_ns)) || return 1
    sleep 0.05 || true
  done
}

reap_child() {
  wait "$1" 2>/dev/null || true
}

terminate_process() {
  local pid=$1
  local expected_start_time=$2
  local label=$3
  local wait_status

  [[ -n $pid && -n $expected_start_time ]] || return 0

  if process_is_running "$pid" "$expected_start_time"; then
    kill -TERM "$pid" 2>/dev/null || true
  fi

  wait_status=0
  wait_for_process_exit "$pid" "$expected_start_time" || wait_status=$?
  if ((wait_status == 0)); then
    reap_child "$pid"
    return 0
  fi
  if ((wait_status == 2)); then
    printf 'FAIL: lost ownership while terminating %s (PID %s)\n' "$label" "$pid" >&2
    cleanup_error=1
    return 0
  fi

  if process_is_running "$pid" "$expected_start_time"; then
    kill -KILL "$pid" 2>/dev/null || true
  fi

  wait_status=0
  wait_for_process_exit "$pid" "$expected_start_time" || wait_status=$?
  if ((wait_status == 0)); then
    reap_child "$pid"
    return 0
  fi
  if ((wait_status == 2)); then
    printf 'FAIL: lost ownership while terminating %s (PID %s)\n' "$label" "$pid" >&2
    cleanup_error=1
    return 0
  fi

  printf 'FAIL: timed out terminating %s (PID %s)\n' "$label" "$pid" >&2
  cleanup_error=1
}

launch_background() {
  local pid_variable=$1
  local start_variable=$2
  local output_log=$3
  local child_pid launch_start_ns launch_deadline_ns

  shift 3
  launch_failure_reason=""
  printf -v "$pid_variable" '%s' ''
  printf -v "$start_variable" '%s' ''
  launch_start_ns=$(monotonic_ns) || {
    launch_failure_reason='clock'
    return 1
  }
  launch_deadline_ns=$((launch_start_ns + ownership_timeout_ns))
  launch_critical_section=1

  "$@" >"$output_log" 2>&1 &
  child_pid=$!
  printf -v "$pid_variable" '%s' "$child_pid"

  if establish_process_ownership "$child_pid" "$launch_deadline_ns"; then
    printf -v "$start_variable" '%s' "$child_start_time"
    launch_critical_section=0
    honor_pending_signal
    return 0
  fi

  if [[ $launch_failure_reason == exited ]]; then
    reap_child "$child_pid"
  fi
  printf -v "$pid_variable" '%s' ''
  printf -v "$start_variable" '%s' ''
  launch_critical_section=0
  honor_pending_signal
  return 1
}

cleanup() {
  local status=$?

  if ((cleanup_running)); then
    return "$status"
  fi
  cleanup_running=1
  trap - EXIT
  trap ':' HUP INT TERM

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
trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

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
    if ! launch_background wayland_pid wayland_start_time "$wayland_log" \
      weston --backend=headless-backend.so --socket="$WAYLAND_DISPLAY" --idle-time=0; then
      case $launch_failure_reason in
        exited) fail 'nested Wayland compositor exited before process identity was captured' ;;
        ppid-mismatch) fail 'nested Wayland compositor did not remain a direct child' ;;
        *) fail 'could not establish ownership of the nested Wayland compositor' ;;
      esac
    fi
  elif command -v sway >/dev/null 2>&1; then
    printf '%s\n' 'output * bg #000000 solid_color' >"$config"
    if ! WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 launch_background \
      wayland_pid wayland_start_time "$wayland_log" sway --unsupported-gpu -c "$config"; then
      case $launch_failure_reason in
        exited) fail 'nested Wayland compositor exited before process identity was captured' ;;
        ppid-mismatch) fail 'nested Wayland compositor did not remain a direct child' ;;
        *) fail 'could not establish ownership of the nested Wayland compositor' ;;
      esac
    fi
  else
    fail 'no current or nested/test Wayland session is available'
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

if ! DESKTOP_SHELL_PREVIEW=1 launch_background \
  preview_pid preview_start_time "$preview_log" quickshell -p "$SHELL_ROOT"; then
  case $launch_failure_reason in
    exited) fail 'Quickshell preview exited before process identity was captured' ;;
    ppid-mismatch) fail 'Quickshell preview did not remain a direct child' ;;
    *) fail 'could not establish ownership of the Quickshell preview' ;;
  esac
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
