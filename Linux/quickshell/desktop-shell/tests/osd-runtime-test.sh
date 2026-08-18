#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"
HARNESS="$SHELL_ROOT/tests/osd-runtime-shell.qml"
PROCESS_HELPER="$SHELL_ROOT/tests/osd-runtime-process.sh"

# shellcheck source=osd-runtime-process.sh
# shellcheck disable=SC1091
source "$PROCESS_HELPER"

select_local_wayland_display() {
  local requested=${1-}
  local selected_runtime=${XDG_RUNTIME_DIR:-}
  local local_display=${HERDR_LOCAL_WAYLAND_DISPLAY:-}
  local selected_display=${requested:-${WAYLAND_DISPLAY:-}}
  local socket

  if [[ ${HERDR_ENV:-0} == 1 ]]; then
    if [[ -z $local_display ]]; then
      printf 'FAIL: remote Waypipe session has no HERDR_LOCAL_WAYLAND_DISPLAY\n' >&2
      return 1
    fi
    if [[ -n $requested && $requested != "$local_display" ]]; then
      printf 'FAIL: refusing remote Waypipe display %s; use local display %s\n' \
        "$requested" "$local_display" >&2
      return 1
    fi
    selected_display=$local_display
    selected_runtime=${HERDR_LOCAL_XDG_RUNTIME_DIR:-$selected_runtime}
  fi

  if [[ -z $selected_display || -z $selected_runtime ]]; then
    printf 'FAIL: a local WAYLAND_DISPLAY and XDG_RUNTIME_DIR are required\n' >&2
    return 1
  fi
  if [[ $selected_display == /* ]]; then
    socket=$selected_display
  else
    socket="$selected_runtime/$selected_display"
  fi
  if [[ ! -S $socket ]]; then
    printf 'FAIL: local Wayland socket is unavailable: %s\n' "$socket" >&2
    return 1
  fi

  printf '%s\n%s\n' "$selected_display" "$selected_runtime"
}

if [[ ${1-} != --private-bus ]]; then
  requested_wayland_display=''
  case ${1-} in
    '') ;;
    --wayland-display)
      [[ -n ${2-} && -z ${3-} ]] || {
        printf 'usage: %s [--wayland-display DISPLAY]\n' "$0" >&2
        exit 2
      }
      requested_wayland_display=$2
      ;;
    *)
      printf 'usage: %s [--wayland-display DISPLAY]\n' "$0" >&2
      exit 2
      ;;
  esac
  command -v dbus-run-session >/dev/null 2>&1 || {
    printf 'FAIL: dbus-run-session is required\n' >&2
    exit 1
  }
  selected_wayland_output=$(select_local_wayland_display "$requested_wayland_display")
  mapfile -t selected_wayland <<<"$selected_wayland_output"
  export DESKTOP_SHELL_TEST_WAYLAND_DISPLAY=${selected_wayland[0]}
  export DESKTOP_SHELL_TEST_WAYLAND_RUNTIME_DIR=${selected_wayland[1]}
  bus_log=$(mktemp)
  if dbus-run-session -- bash "$0" --private-bus 2>"$bus_log"; then
    status=0
  else
    status=$?
  fi
  if ((status != 0)) && [[ -s $bus_log ]]; then
    printf '%s\n' '--- private D-Bus log ---' >&2
    printf '%s\n' "$(<"$bus_log")" >&2
  fi
  rm -f "$bus_log"
  exit "$status"
fi

command -v quickshell >/dev/null 2>&1 || {
  printf 'FAIL: quickshell is required\n' >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  printf 'FAIL: jq is required\n' >&2
  exit 1
}
command -v timeout >/dev/null 2>&1 || {
  printf 'FAIL: timeout is required\n' >&2
  exit 1
}
expected_shell_executable=$(osd_runtime_resolve_executable quickshell) || {
  printf 'FAIL: unable to resolve the expected quickshell executable\n' >&2
  exit 1
}

original_runtime_dir=${DESKTOP_SHELL_TEST_WAYLAND_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-}}
wayland_display=${DESKTOP_SHELL_TEST_WAYLAND_DISPLAY:-}
if [[ -z $original_runtime_dir || -z $wayland_display ]]; then
  printf 'FAIL: validated local Wayland display selection is unavailable\n' >&2
  exit 1
fi
if [[ $wayland_display == /* ]]; then
  original_wayland_socket=$wayland_display
else
  original_wayland_socket="$original_runtime_dir/$wayland_display"
fi
if [[ ! -S $original_wayland_socket ]]; then
  printf 'FAIL: local Wayland socket is unavailable for WAYLAND_DISPLAY=%s\n' "$wayland_display" >&2
  exit 1
fi

fixture=$(mktemp -d)
harness_pid=$BASHPID
shell_pid=''
shell_pending_pid=''
shell_pending_start_time=''
shell_pending_executable=''
shell_pending_parent_pid=''
shell_start_time=''
shell_executable=''
shell_parent_pid=''
shell_log="$fixture/shell.log"
runtime_dir="$fixture/runtime"
home="$fixture/home"
runtime_shell_root="$fixture/shell"
fixture_wayland_display=$wayland_display
if [[ $fixture_wayland_display == /* ]]; then
  fixture_wayland_display=wayland-test
fi

cleanup_pending_shell() {
  [[ -n $shell_pending_pid ]] || return 0
  if [[ -z $shell_pending_start_time || -z $shell_pending_executable || -z $shell_pending_parent_pid ]]; then
    osd_runtime_cleanup_pending_identity "$shell_pending_pid" "$harness_pid" "$expected_shell_executable" || return 1
    shell_pending_pid=''
    return 0
  fi
  [[ -n $shell_pending_start_time && -n $shell_pending_executable && -n $shell_pending_parent_pid ]] || {
    osd_runtime_reap_if_exited "$shell_pending_pid"
    return $?
  }
  osd_runtime_cleanup_pending_child \
    "$shell_pending_pid" "$shell_pending_start_time" "$shell_pending_executable" \
    "$shell_pending_parent_pid" "$expected_shell_executable" || return 1
  osd_runtime_reap_if_exited "$shell_pending_pid" || return 1
  shell_pending_pid=''
}

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ -n $shell_pid ]]; then
    osd_runtime_cleanup_child "$shell_pid" "$shell_start_time" "$shell_executable" "$shell_parent_pid" || status=1
    osd_runtime_reap_if_exited "$shell_pid" || status=1
  fi
  cleanup_pending_shell || status=1
  if ((status != 0)) && [[ -s $shell_log ]]; then
    printf '%s\n' '--- OSD runtime shell log ---' >&2
    printf '%s\n' "$(<"$shell_log")" >&2
  fi
  rm -rf "$fixture"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

umask 022
mkdir -p "$runtime_dir" "$home/.config" "$home/.cache" "$home/.local/share"
chmod 755 "$runtime_dir" "$home"
ln -s -- "$original_wayland_socket" "$runtime_dir/$fixture_wayland_display"
cp -a "$SHELL_ROOT/." "$runtime_shell_root"
cp -- "$HARNESS" "$runtime_shell_root/shell.qml"
export XDG_RUNTIME_DIR="$runtime_dir" WAYLAND_DISPLAY="$fixture_wayland_display"

start_shell() {
  local pending_identity
  local promoted_identity

  export DESKTOP_SHELL_TEST_NO_SURFACES=1
  DESKTOP_SHELL_PREVIEW=0 \
  DESKTOP_SHELL_NOTIFICATIONS_REGISTER=0 \
  DESKTOP_SHELL_POLKIT_REGISTER=0 \
  HOME="$home" \
  XDG_CONFIG_HOME="$home/.config" \
  XDG_CACHE_HOME="$home/.cache" \
  XDG_DATA_HOME="$home/.local/share" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  WAYLAND_DISPLAY="$fixture_wayland_display" \
  quickshell --no-color -p "$runtime_shell_root" >"$shell_log" 2>&1 &
  shell_pending_pid=$!
  shell_pending_parent_pid=$harness_pid
  pending_identity=$(osd_runtime_capture_pending_identity "$shell_pending_pid" "$harness_pid") || {
    printf 'FAIL: unable to capture pending test shell identity\n' >&2
    return 1
  }
  IFS=$'\t' read -r shell_pending_start_time shell_pending_executable shell_pending_parent_pid <<<"$pending_identity"
  promoted_identity=$(osd_runtime_promote_child_identity \
    "$shell_pending_pid" "$harness_pid" "$expected_shell_executable" "$shell_pending_start_time") || {
    printf 'FAIL: test shell did not reach the expected quickshell executable\n' >&2
    return 1
  }
  IFS=$'\t' read -r shell_start_time shell_executable shell_parent_pid <<<"$promoted_identity"
  shell_pid=$shell_pending_pid
  shell_pending_pid=''
  shell_pending_start_time=''
  shell_pending_executable=''
  shell_pending_parent_pid=''
}

call_ipc() {
  timeout --kill-after=1s 3s quickshell ipc --pid "$shell_pid" call -- "$@" 2>/dev/null
}

call_ipc_debug() {
  timeout --kill-after=1s 3s quickshell ipc --pid "$shell_pid" call -- "$@"
}

wait_for_ipc() {
  local expected=$1
  shift
  local result=''
  local deadline=$((SECONDS + 15))
  while ((SECONDS < deadline)); do
    result=$(call_ipc "$@") || true
    if [[ $result == "$expected" ]]; then
      return 0
    fi
    sleep 0.2
  done
  printf 'FAIL: IPC %q returned %q, expected %s\n' "$*" "$result" "$expected" >&2
  return 1
}

normalize_json() {
  jq -e -s '
    if length != 1 then
      error("expected one IPC response")
    elif (.[0] | type) == "string" then
      .[0] | fromjson
    else
      .[0]
    end
  '
}

read_state() {
  call_ipc desktop.osd state | normalize_json
}

read_screen_state() {
  call_ipc desktop.osd-test screenState | normalize_json
}

assert_state() {
  local filter=$1 state
  state=$(read_state) || {
    printf 'FAIL: unable to read OSD state\n' >&2
    return 1
  }
  jq -e "$filter" <<<"$state" >/dev/null || {
    printf 'FAIL: OSD state did not satisfy %s: %s\n' "$filter" "$state" >&2
    return 1
  }
}

wait_for_state() {
  local filter=$1
  local last_state=''
  local deadline=$((SECONDS + 8))
  while ((SECONDS < deadline)); do
    if last_state=$(read_state 2>/dev/null) && jq -e "$filter" <<<"$last_state" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  printf 'FAIL: OSD state did not satisfy %s\n' "$filter" >&2
  [[ -z $last_state ]] || printf 'last state: %s\n' "$last_state" >&2
  return 1
}

start_shell
wait_for_ipc pong desktop.osd ping

surface_state=$(call_ipc desktop.osd-test surfaceState | normalize_json)
jq -e '.suppressed == true and .visible == false and .opened == false' <<<"$surface_state" >/dev/null || {
  printf 'FAIL: OSD test surface was not suppressed before opening: %s\n' "$surface_state" >&2
  exit 1
}

screen_state=$(read_screen_state)
jq -e '.target as $target | ($target != "") and (.focused == "" or any(.screens[]; . == $target))' <<<"$screen_state" >/dev/null || {
  printf 'FAIL: initial OSD target screen is not a validated local screen: %s\n' "$screen_state" >&2
  exit 1
}
focused_name=$(jq -r '.focused' <<<"$screen_state")

empty_state=$(call_ipc desktop.osd-test setScreenFixture empty | normalize_json)
jq -e --arg focused "$focused_name" '.focused == $focused and .screens == [] and .target == ""' <<<"$empty_state" >/dev/null || {
  printf 'FAIL: OSD target did not clear when the screen list became empty: %s\n' "$empty_state" >&2
  exit 1
}
available_state=$(call_ipc desktop.osd-test setScreenFixture available | normalize_json)
jq -e --arg focused "$focused_name" '.target as $target | .focused == $focused and ($target != "") and any(.screens[]; . == $target)' <<<"$available_state" >/dev/null || {
  printf 'FAIL: OSD target did not follow the republished screen list: %s\n' "$available_state" >&2
  exit 1
}

show_result=$(call_ipc_debug desktop.osd show '{"icon":"brightness","message":"","value":20,"max":100,"progressText":"20%","duration":500}' 2>"$fixture/show.err") || true
[[ $show_result == ok ]] || {
  printf 'FAIL: valid OSD show returned %q: %s\n' "$show_result" "$(<"$fixture/show.err")" >&2
  exit 1
}
wait_for_state '.opened == true and .value == 20 and .duration == 500'
surface_state=$(call_ipc desktop.osd-test surfaceState | normalize_json)
jq -e '.suppressed == true and .visible == false and .opened == true' <<<"$surface_state" >/dev/null || {
  printf 'FAIL: OSD test surface became visible while suppressed: %s\n' "$surface_state" >&2
  exit 1
}
before_invalid=$(read_state)
[[ $(call_ipc desktop.osd show '{"value":"invalid"}') == invalid ]] || {
  printf 'FAIL: invalid OSD show was accepted\n' >&2
  exit 1
}
after_invalid=$(read_state)
[[ $(jq -c . <<<"$before_invalid") == $(jq -c . <<<"$after_invalid") ]] || {
  printf 'FAIL: invalid OSD show mutated state\n' >&2
  exit 1
}

[[ $(call_ipc desktop.osd show '{"icon":"brightness","message":"","value":30,"max":100,"progressText":"30%","duration":700}') == ok ]] || {
  printf 'FAIL: first timeout test show failed\n' >&2
  exit 1
}
sleep 0.35
[[ $(call_ipc desktop.osd show '{"icon":"brightness","message":"","value":40,"max":100,"progressText":"40%","duration":700}') == ok ]] || {
  printf 'FAIL: repeated timeout test show failed\n' >&2
  exit 1
}
sleep 0.35
assert_state '.opened == true and .value == 40'
wait_for_state '.opened == false'

[[ $(call_ipc desktop.osd show '{"icon":"volume","message":"","value":50,"max":100,"progressText":"50%","duration":0}') == ok ]] || {
  printf 'FAIL: duration-zero OSD show failed\n' >&2
  exit 1
}
sleep 1
assert_state '.opened == true and .duration == 0 and .value == 50'
[[ $(call_ipc desktop.osd close) == ok ]] || {
  printf 'FAIL: OSD close failed\n' >&2
  exit 1
}
assert_state '.opened == false and .value == 50'
sleep 1
assert_state '.opened == false and .value == 50'

printf 'PASS: isolated Quickshell OSD controller, timer, IPC, and screen runtime\n'
