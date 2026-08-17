#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"

if [[ ${1-} != --private-bus ]]; then
  command -v dbus-run-session >/dev/null 2>&1 || {
    printf 'FAIL: dbus-run-session is required\n' >&2
    exit 1
  }
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

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell is unavailable\n'
  exit 0
fi
if ! command -v notify-send >/dev/null 2>&1; then
  printf 'SKIP: notify-send is unavailable\n'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'FAIL: jq is required\n' >&2
  exit 1
fi
if ! command -v timeout >/dev/null 2>&1; then
  printf 'FAIL: timeout is required\n' >&2
  exit 1
fi
if ! command -v busctl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  printf 'FAIL: busctl and python3 are required\n' >&2
  exit 1
fi
original_runtime_dir=${XDG_RUNTIME_DIR:-}
wayland_display=wayland-1
if [[ -z $original_runtime_dir || ! -S "$original_runtime_dir/$wayland_display" ]]; then
  printf 'FAIL: Wayland socket is unavailable for WAYLAND_DISPLAY=%s\n' "$wayland_display" >&2
  exit 1
fi

fixture="$(mktemp -d)"
shell_pid=''
owner_pid=''
runtime_dir="$fixture/runtime"
state_home="$fixture/state"
home="$fixture/home"
route_dir="$runtime_dir/desktop-shell"
route_path="$route_dir/notification-route.json"
popup_dir="$state_home/desktop-shell/notifications"
history_dir="$popup_dir/history"
shell_generation=0
shell_log=''

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
  cleanup_process "$shell_pid"
  cleanup_process "$owner_pid"
  if ((status != 0)); then
    if [[ -n $shell_log && -s $shell_log ]]; then
      printf '%s\n' '--- notification runtime shell log ---' >&2
      printf '%s\n' "$(<"$shell_log")" >&2
    fi
    if [[ -s "$fixture/owner.log" ]]; then
      printf '%s\n' '--- notification runtime owner log ---' >&2
      printf '%s\n' "$(<"$fixture/owner.log")" >&2
    fi
  fi
  rm -rf "$fixture"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$runtime_dir" "$state_home" "$home/.config" "$home/.cache" "$home/.local/share" "$route_dir"
chmod 700 "$runtime_dir" "$state_home" "$home" "$route_dir"
ln -s -- "$original_runtime_dir/$wayland_display" "$runtime_dir/$wayland_display"
export XDG_RUNTIME_DIR="$runtime_dir" WAYLAND_DISPLAY="$wayland_display"

printf '{"version":1,"visible":false,"output":null,"cueOutput":null,"direction":null,"updatedAt":%s}\n' \
  "$(date +%s)" >"$route_path"
chmod 600 "$route_path"

call_ipc() {
  timeout --kill-after=1s 3s quickshell ipc --pid "$shell_pid" call "$@" 2>/dev/null
}

call_notification() {
  local method=$1
  local argument=${2-}
  call_ipc desktop-shell call desktop.notifications "$method" "$argument"
}

normalize_status() {
  jq -e -s '
    if length == 1 then
      (.[0] | if type == "string" then fromjson else . end)
    else
      error("expected one IPC response")
    end
  '
}

read_status() {
  local raw
  raw=$(call_notification status) || return 1
  normalize_status <<<"$raw"
}

read_health() {
  local raw
  raw=$(call_ipc desktop-shell health) || return 1
  normalize_status <<<"$raw"
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

wait_for_status() {
  local filter=$1
  local last_status=''
  local status_json=''
  local deadline=$((SECONDS + 15))
  while ((SECONDS < deadline)); do
    if status_json=$(read_status 2>/dev/null); then
      last_status=$status_json
      if jq -e "$filter" <<<"$status_json" >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 0.2
  done
  printf 'FAIL: status did not satisfy %s\n' "$filter" >&2
  [[ -z $last_status ]] || printf 'last status: %s\n' "$last_status" >&2
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

wait_for_file() {
  local path=$1
  local deadline=$((SECONDS + 10))
  while ((SECONDS < deadline)); do
    [[ -f $path ]] && return 0
    sleep 0.2
  done
  printf 'FAIL: expected file was not created: %s\n' "$path" >&2
  return 1
}

count_json_files() {
  local directory=$1
  local count=0
  local file
  shopt -s nullglob
  local files=("$directory"/*.json)
  shopt -u nullglob
  for file in "${files[@]}"; do
    [[ -f $file ]] && count=$((count + 1))
  done
  printf '%s\n' "$count"
}

start_shell() {
  shell_generation=$((shell_generation + 1))
  shell_log="$fixture/shell-$shell_generation.log"
  DESKTOP_SHELL_PREVIEW=0 \
  DESKTOP_SHELL_POLKIT_REGISTER=0 \
  DESKTOP_SHELL_NOTIFICATIONS_REGISTER=1 \
  HOME="$home" \
  XDG_CONFIG_HOME="$home/.config" \
  XDG_CACHE_HOME="$home/.cache" \
  XDG_DATA_HOME="$home/.local/share" \
  XDG_STATE_HOME="$state_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  WAYLAND_DISPLAY="$wayland_display" \
  quickshell --no-color -p "$SHELL_ROOT" >"$shell_log" 2>&1 &
  shell_pid=$!
  wait_for_ipc pong desktop-shell ping
}

stop_shell() {
  cleanup_process "$shell_pid"
  shell_pid=''
}

start_competing_owner() {
  local ready="$fixture/owner-ready"
  rm -f "$ready"
  python3 - "$ready" >"$fixture/owner.log" 2>&1 <<'PY' &
import sys
import time

import dbus

ready_path = sys.argv[1]
bus = dbus.SessionBus()
reply = bus.request_name(
    "org.freedesktop.Notifications",
    dbus.bus.NAME_FLAG_DO_NOT_QUEUE,
)
if reply != dbus.bus.REQUEST_NAME_REPLY_PRIMARY_OWNER:
    raise SystemExit(f"failed to acquire notification name: {reply}")
with open(ready_path, "w", encoding="ascii") as ready:
    ready.write("primary\n")
while True:
    time.sleep(1)
PY
  owner_pid=$!

  local deadline=$((SECONDS + 10))
  while ((SECONDS < deadline)); do
    if [[ -s $ready ]]; then
      [[ $(<"$ready") == primary ]] || return 1
      return 0
    fi
    kill -0 "$owner_pid" 2>/dev/null || return 1
    sleep 0.1
  done
  printf 'FAIL: competing notification owner did not acquire the bus name\n' >&2
  return 1
}

start_shell
wait_for_ipc pong desktop.notifications ping
wait_for_ipc pong desktop-shell call desktop.notifications ping ''
wait_for_status '.notificationsOwned == true and .routeValid == true and .routeError == ""'
wait_for_health '.notificationsOwned == true and .notificationRouteValid == true and .notificationOwnershipError == "" and .notificationRouteError == ""'

notify-send --app-name task4-runtime --urgency normal --expire-time 30000 \
  'Task 4 notification' 'runtime popup/history contract'
wait_for_status '.popupCount == 1 and .historyCount == 0'
[[ $(count_json_files "$popup_dir") -eq 1 ]]

[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0 and .historyCount == 1'
[[ $(count_json_files "$history_dir") -eq 1 ]]

[[ $(call_notification restoreLast) == ok ]]
wait_for_status '.popupCount == 1 and .historyCount == 1'

[[ $(call_notification dismissAll) == ok ]]
wait_for_status '.popupCount == 0 and .historyCount == 1'
[[ $(call_notification toggleDnd) == enabled ]]
wait_for_status '.dnd == true and .popupCount == 1'
wait_for_file "$state_home/desktop-shell/notifications.json"
[[ $(jq -e -r '.dnd' "$state_home/desktop-shell/notifications.json") == true ]]

stop_shell
start_shell
wait_for_status '.notificationsOwned == true and .routeValid == true and .dnd == true and .popupCount == 0'
wait_for_health '.notificationsOwned == true and .notificationRouteValid == true and .notificationOwnershipError == ""'

stop_shell
start_competing_owner
start_shell
wait_for_status '.notificationsOwned == false and (.ownershipError | test("PID [0-9]+")) and .routeValid == true'
wait_for_health '.notificationsOwned == false and (.notificationOwnershipError | test("PID [0-9]+")) and .notificationRouteValid == true'
printf 'PASS: isolated notification runtime ownership, routing, persistence, and history contracts\n'
