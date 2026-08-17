#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"

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
  if ! selected_wayland_output=$(select_local_wayland_display "$requested_wayland_display"); then
    exit 1
  fi
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
  rm -f -- "$bus_log"
  exit "$status"
fi

for required_command in quickshell jq timeout ps; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'FAIL: %s is required\n' "$required_command" >&2
    exit 1
  }
done

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
shell_pid=''
shell_log="$fixture/shell.log"
runtime_dir="$fixture/runtime"
home="$fixture/home"
fixture_wayland_display=$wayland_display
if [[ $fixture_wayland_display == /* ]]; then
  fixture_wayland_display=wayland-test
fi
protected_pids="$fixture/protected-pids"
live_shell_marker="$HOME/.config/quickshell/desktop-shell"

snapshot_protected_processes() {
  local pid command_line
  ps -eo pid=,args= | while read -r pid command_line; do
    [[ -n $pid ]] || continue
    if [[ $command_line == *polkit-gnome* || $command_line == *"$live_shell_marker"* ]]; then
      printf '%s\n' "$pid"
    fi
  done | sort -n -u
}

assert_protected_processes() {
  local pid
  while IFS= read -r pid; do
    [[ -n $pid ]] || continue
    if ! kill -0 "$pid" 2>/dev/null; then
      printf 'FAIL: protected live process disappeared: %s\n' "$pid" >&2
      return 1
    fi
  done <"$protected_pids"
}

cleanup_process() {
  local pid=${1-}
  [[ -n $pid ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in {1..50}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ -n $shell_pid ]] && grep -Fxq "$shell_pid" "$protected_pids"; then
    printf 'FAIL: refusing to signal a protected live process: %s\n' "$shell_pid" >&2
    status=1
  else
    cleanup_process "$shell_pid"
  fi
  if ! assert_protected_processes; then
    status=1
  fi
  if ((status != 0)) && [[ -s $shell_log ]]; then
    printf '%s\n' '--- polkit runtime shell log ---' >&2
    printf '%s\n' "$(<"$shell_log")" >&2
  fi
  rm -rf -- "$fixture"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

snapshot_protected_processes >"$protected_pids"

umask 022
mkdir -p -- "$runtime_dir" "$home/.config" "$home/.cache" "$home/.local/share"
chmod 755 -- "$runtime_dir" "$home"
ln -s -- "$original_wayland_socket" "$runtime_dir/$fixture_wayland_display"
export XDG_RUNTIME_DIR="$runtime_dir" WAYLAND_DISPLAY="$fixture_wayland_display"

start_shell() {
  DESKTOP_SHELL_PREVIEW=0 \
  DESKTOP_SHELL_POLKIT_REGISTER=0 \
  DESKTOP_SHELL_NOTIFICATIONS_REGISTER=0 \
  HOME="$home" \
  XDG_CONFIG_HOME="$home/.config" \
  XDG_CACHE_HOME="$home/.cache" \
  XDG_DATA_HOME="$home/.local/share" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  WAYLAND_DISPLAY="$fixture_wayland_display" \
  quickshell --no-color -p "$SHELL_ROOT" >"$shell_log" 2>&1 &
  shell_pid=$!
}

call_ipc() {
  timeout --kill-after=1s 3s quickshell ipc --pid "$shell_pid" call -- "$@" 2>/dev/null
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

read_health() {
  call_ipc desktop-shell health | normalize_json
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

wait_for_health() {
  local filter=$1
  local last_health=''
  local health_json=''
  local deadline=$((SECONDS + 15))
  while ((SECONDS < deadline)); do
    if health_json=$(read_health 2>/dev/null); then
      last_health=$health_json
      if jq -e "$filter" <<<"$health_json" >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 0.2
  done
  printf 'FAIL: shell health did not satisfy %s\n' "$filter" >&2
  [[ -z $last_health ]] || printf 'last health: %s\n' "$last_health" >&2
  return 1
}

start_shell
wait_for_ipc pong desktop-shell ping

for expected_environment in \
  'DESKTOP_SHELL_POLKIT_REGISTER=0' \
  'DESKTOP_SHELL_NOTIFICATIONS_REGISTER=0'; do
  tr '\0' '\n' <"/proc/$shell_pid/environ" | grep -Fxq "$expected_environment" || {
    printf 'FAIL: shell did not receive %s\n' "$expected_environment" >&2
    exit 1
  }
done

plugins=$(call_ipc desktop-shell listPlugins | normalize_json)
jq -e 'has("desktop.polkit")' <<<"$plugins" >/dev/null || {
  printf 'FAIL: isolated shell did not discover desktop.polkit\n' >&2
  exit 1
}

wait_for_health '.polkitRegistered == false and .polkitError == "registration disabled"'
health=$(read_health)
jq -e '
  .polkitRegistered == false
  and .polkitError == "registration disabled"
  and ((.polkitPamError | type) == "string")
  and ((.configValid | type) == "boolean")
  and ((.pluginErrors | type) == "array")
  and ((.activeBarId | type) == "string")
  and ((.activeBarId | length) > 0)
  and .previewMode == false
  and ((.osdAvailable | type) == "boolean")
  and ((.notificationsOwned | type) == "boolean")
  and ((.notificationOwnershipError | type) == "string")
' <<<"$health" >/dev/null || {
  printf 'FAIL: shell health lost existing fields: %s\n' "$health" >&2
  exit 1
}

printf 'PASS: isolated polkit registration-disabled runtime and protected live owners\n'
