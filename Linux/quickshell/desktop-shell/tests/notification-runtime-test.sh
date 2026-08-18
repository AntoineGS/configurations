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
  rm -f "$bus_log"
  exit "$status"
fi

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'FAIL: quickshell is required\n' >&2
  exit 1
fi
if ! command -v notify-send >/dev/null 2>&1; then
  printf 'FAIL: notify-send is required\n' >&2
  exit 1
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
if ! python3 -c 'import dbus' >/dev/null 2>&1; then
  printf "FAIL: python3 dbus module is required (python3 -c 'import dbus' failed)\n" >&2
  exit 1
fi
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

fixture="$(mktemp -d)"
shell_pid=''
owner_pid=''
action_pid=''
runtime_dir="$fixture/runtime"
state_home="$fixture/state"
home="$fixture/home"
route_dir="$runtime_dir/desktop-shell"
route_path="$route_dir/notification-route.json"
popup_dir="$state_home/desktop-shell/notifications"
history_dir="$popup_dir/history"
fixture_wayland_display="$wayland_display"
if [[ $fixture_wayland_display == /* ]]; then
  fixture_wayland_display=wayland-test
fi
shell_generation=0
shell_log=''
runtime_shell_root="$SHELL_ROOT"

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
  cleanup_process "$action_pid"
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

umask 022
mkdir -p "$runtime_dir" "$state_home" "$home/.config" "$home/.cache" "$home/.local/share" "$route_dir"
chmod 755 "$runtime_dir" "$state_home" "$home" "$route_dir"
ln -s -- "$original_wayland_socket" "$runtime_dir/$fixture_wayland_display"
export XDG_RUNTIME_DIR="$runtime_dir" WAYLAND_DISPLAY="$fixture_wayland_display"

printf '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":null,"direction":null,"updatedAt":%s}\n' \
  "$(date +%s)" >"$route_path"
chmod 600 "$route_path"

write_route_payload() {
  local payload=$1
  local mode=${2:-600}
  local temporary="$route_path.test.$$"
  printf '%s\n' "$payload" >"$temporary"
  chmod "$mode" "$temporary"
  mv -f -- "$temporary" "$route_path"
}

assert_mode() {
  local expected=$1
  local path=$2
  local actual
  actual=$(stat -c '%a' -- "$path")
  [[ $actual == "$expected" ]] || {
    printf 'FAIL: mode for %s was %s, expected %s\n' "$path" "$actual" "$expected" >&2
    return 1
  }
}

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

wait_for_path() {
  local path=$1
  local deadline=$((SECONDS + 10))
  while ((SECONDS < deadline)); do
    [[ -e $path ]] && return 0
    sleep 0.2
  done
  printf 'FAIL: expected path was not created: %s\n' "$path" >&2
  return 1
}

wait_for_process_exit() {
  local pid=$1
  local deadline=$((SECONDS + 10))
  local stat_line=''
  local state=''
  while kill -0 "$pid" 2>/dev/null; do
    if [[ -r /proc/$pid/stat ]]; then
      stat_line=$(<"/proc/$pid/stat")
      state=${stat_line#*) }
      state=${state%% *}
      [[ $state == Z ]] && break
    fi
    ((SECONDS < deadline)) || {
      printf 'FAIL: process %s did not exit in time (%s)\n' "$pid" "$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)" >&2
      return 1
    }
    sleep 0.1
  done
  wait "$pid"
}

wait_for_setting_dnd() {
  local expected_dnd=$1
  local expected_writes=$2
  local last_dnd=''
  local last_writes='0'
  local deadline=$((SECONDS + 15))
  while ((SECONDS < deadline)); do
    if [[ -f $state_home/desktop-shell/notifications.json ]]; then
      last_dnd=$(jq -r '.dnd' "$state_home/desktop-shell/notifications.json" 2>/dev/null) || last_dnd=''
    fi
    if [[ -f ${settings_write_count:-} ]]; then
      last_writes=$(<"$settings_write_count")
    fi
    if [[ $last_dnd == "$expected_dnd" && $last_writes == "$expected_writes" ]]; then
      return 0
    fi
    sleep 0.2
  done
  printf 'FAIL: settings did not persist dnd=%s after %s writes (last dnd=%s writes=%s)\n' \
    "$expected_dnd" "$expected_writes" "$last_dnd" "$last_writes" >&2
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

wait_for_json_count() {
  local directory=$1
  local expected=$2
  local deadline=$((SECONDS + 10))
  while ((SECONDS < deadline)); do
    [[ $(count_json_files "$directory") == "$expected" ]] && return 0
    sleep 0.2
  done
  printf 'FAIL: expected %s JSON files in %s, found %s\n' \
    "$expected" "$directory" "$(count_json_files "$directory")" >&2
  for file in "$directory"/*.json; do
    [[ -f $file ]] || continue
    printf '  %s: %s\n' "$file" "$(jq -c . "$file" 2>/dev/null || true)" >&2
  done
  return 1
}

start_shell() {
  shell_generation=$((shell_generation + 1))
  shell_log="$fixture/shell-$shell_generation.log"
  local shell_path="$PATH"
  if [[ -n ${DESKTOP_SHELL_TEST_BUSCTL_BIN:-} ]]; then
    if [[ ${DESKTOP_SHELL_TEST_BUSCTL_ISOLATE:-0} == 1 ]]; then
      shell_path="$DESKTOP_SHELL_TEST_BUSCTL_BIN"
    else
      shell_path="$DESKTOP_SHELL_TEST_BUSCTL_BIN:$shell_path"
    fi
  fi
  if [[ -n ${DESKTOP_SHELL_TEST_SETTINGS_BIN:-} ]]; then
    shell_path="$DESKTOP_SHELL_TEST_SETTINGS_BIN:$shell_path"
  fi
  if [[ -n ${DESKTOP_SHELL_TEST_PERSISTENCE_BIN:-} ]]; then
    shell_path="$DESKTOP_SHELL_TEST_PERSISTENCE_BIN:$shell_path"
  fi
  DESKTOP_SHELL_PREVIEW=0 \
  DESKTOP_SHELL_POLKIT_REGISTER=0 \
  DESKTOP_SHELL_NOTIFICATIONS_REGISTER=1 \
  HOME="$home" \
  XDG_CONFIG_HOME="$home/.config" \
  XDG_CACHE_HOME="$home/.cache" \
  XDG_DATA_HOME="$home/.local/share" \
  XDG_STATE_HOME="$state_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  WAYLAND_DISPLAY="$fixture_wayland_display" \
  DESKTOP_SHELL_TEST_NO_SURFACES="${DESKTOP_SHELL_TEST_NO_SURFACES:-1}" \
  PATH="$shell_path" \
  DESKTOP_SHELL_TEST_BUSCTL_COUNT="${DESKTOP_SHELL_TEST_BUSCTL_COUNT-}" \
  quickshell --no-color -p "$runtime_shell_root" >"$shell_log" 2>&1 &
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

mixed_shell_root="$fixture/mixed-shell"
mkdir -p "$mixed_shell_root"
cp -a "$SHELL_ROOT/." "$mixed_shell_root/"
mkdir -p "$mixed_shell_root/plugins/mixed"
cat >"$mixed_shell_root/plugins/mixed/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "desktop.mixed",
  "name": "Mixed Test Plugin",
  "version": "1.0.0",
  "author": "Task 4 test",
  "kinds": ["service", "panel"],
  "entryPoints": { "service": "Service.qml", "panel": "Panel.qml" }
}
JSON
cat >"$mixed_shell_root/plugins/mixed/Service.qml" <<'QML'
import QtQuick

Item {
  function serviceOnly(argument) { return "service-ok" }
}
QML
cat >"$mixed_shell_root/plugins/mixed/Panel.qml" <<'QML'
import QtQuick

Item {
  function overlayOnly(argument) { return "overlay-ok" }
}
QML

runtime_shell_root="$mixed_shell_root"
DESKTOP_SHELL_TEST_NO_SURFACES=0 start_shell
[[ $(call_ipc desktop-shell summon desktop.mixed '{}') == ok ]]
wait_for_ipc service-ok desktop-shell call desktop.mixed serviceOnly ''
wait_for_ipc overlay-ok desktop-shell call desktop.mixed overlayOnly ''
stop_shell
runtime_shell_root="$SHELL_ROOT"

settings_delay_bin="$fixture/settings-delay-bin"
settings_write_started="$fixture/settings-write-started"
settings_write_release="$fixture/settings-write-release"
settings_write_count="$fixture/settings-write-count"
mkdir -p "$settings_delay_bin"
real_mv="$(type -P mv)"
cat >"$settings_delay_bin/mv" <<FAKE_SETTINGS_MV
#!/usr/bin/env bash
set -Eeuo pipefail
args=("\$@")
last_index=\$((\${#args[@]} - 1))
source_path=\${args[\$((last_index - 1))]}
destination_path=\${args[\$last_index]}
if [[ \$source_path == *notifications.json.* && \$destination_path == *notifications.json ]]; then
  write_count=0
  if [[ -f \${DESKTOP_SHELL_TEST_SETTINGS_COUNT:?} ]]; then
    write_count=\$(<"\${DESKTOP_SHELL_TEST_SETTINGS_COUNT}")
  fi
  write_count=\$((write_count + 1))
  printf '%s\\n' "\$write_count" >"\${DESKTOP_SHELL_TEST_SETTINGS_COUNT}"
  if ((write_count == 1)); then
    : >"\${DESKTOP_SHELL_TEST_SETTINGS_START:?}"
    while [[ ! -e \${DESKTOP_SHELL_TEST_SETTINGS_RELEASE:?} ]]; do
      sleep 0.05
    done
  fi
fi
exec "$real_mv" "\$@"
FAKE_SETTINGS_MV
chmod 700 "$settings_delay_bin/mv"
export DESKTOP_SHELL_TEST_SETTINGS_BIN="$settings_delay_bin"
export DESKTOP_SHELL_TEST_SETTINGS_START="$settings_write_started"
export DESKTOP_SHELL_TEST_SETTINGS_RELEASE="$settings_write_release"
export DESKTOP_SHELL_TEST_SETTINGS_COUNT="$settings_write_count"

start_shell
wait_for_ipc pong desktop.notifications ping
wait_for_ipc pong desktop-shell call desktop.notifications ping ''
wait_for_status '.notificationsOwned == true and .routeValid == true and .routeVisible == true and .routeError == ""'
wait_for_health '.notificationsOwned == true and .notificationRouteValid == true and .notificationRouteVisible == true and .notificationOwnershipError == "" and .notificationRouteError == ""'

wait_for_path "$state_home/desktop-shell"
assert_mode 700 "$state_home/desktop-shell"
assert_mode 700 "$popup_dir"
assert_mode 700 "$history_dir"
assert_mode 700 "$popup_dir/images"

notification_image="$fixture/notification-image.png"
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' |
  base64 -d >"$notification_image"
chmod 644 "$notification_image"

notify-send --app-name task4-runtime --icon "$notification_image" \
  --hint=string:image-path:"$notification_image" --urgency normal --expire-time 30000 \
  'Task 4 notification' 'runtime popup/history contract'
wait_for_status '.popupCount == 1 and .historyCount == 0'
[[ $(count_json_files "$popup_dir") -eq 1 ]]
popup_file=$(printf '%s\n' "$popup_dir"/*.json)
assert_mode 600 "$popup_file"
image_count=0
for image_file in "$popup_dir/images"/*; do
  [[ -f $image_file ]] || continue
  image_count=$((image_count + 1))
  assert_mode 600 "$image_file"
done
((image_count > 0)) || {
  printf 'FAIL: notification image was not persisted: %s\n' "$(<"$popup_file")" >&2
  exit 1
}

# Cue state is visible for both a normal route and an all-unsafe cue-only route.
write_route_payload '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":"HDMI-A-1","direction":"left","updatedAt":'"$(date +%s)"'}'
wait_for_status '.routeValid == true and .routeVisible == true and .routeCueOutput == "HDMI-A-1" and .routeDirection == "left" and .routeCueGlyph == "←"'
write_route_payload '{"version":1,"visible":false,"output":null,"cueOutput":"DP-2","direction":null,"updatedAt":'"$(date +%s)"'}'
wait_for_status '.routeValid == true and .routeVisible == false and .routeCueOutput == "DP-2" and .routeDirection == null and .routeCueGlyph == "•"'
write_route_payload '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":null,"direction":null,"updatedAt":'"$(date +%s)"'}'
wait_for_status '.routeValid == true and .routeVisible == true and .routeCueOutput == null'

# FileView must fail closed across every route lifecycle transition.
write_route_payload '{malformed'
wait_for_status '.routeValid == false and .routeVisible == false and (.routeError | test("invalid|unavailable"))'
wait_for_health '.notificationRouteValid == false and .notificationRouteVisible == false and (.notificationRouteError | test("invalid|unavailable"))'

write_route_payload '{"version":1,"visible":false,"output":null,"cueOutput":null,"direction":null,"updatedAt":'"$(date +%s)"'}'
wait_for_status '.routeValid == true and .routeVisible == false and .routeError == ""'
wait_for_health '.notificationRouteValid == true and .notificationRouteVisible == false and .notificationRouteError == ""'

rm -f -- "$route_path"
wait_for_status '.routeValid == false and .routeVisible == false and (.routeError | test("unavailable"))'
wait_for_health '.notificationRouteValid == false and .notificationRouteVisible == false'

write_route_payload '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":null,"direction":null,"updatedAt":'"$(date +%s)"'}' 000
wait_for_status '.routeValid == false and .routeVisible == false and (.routeError | test("unavailable|invalid"))'
wait_for_health '.notificationRouteValid == false and .notificationRouteVisible == false'

near_expiry=$(( $(date +%s) - 44 ))
write_route_payload '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":null,"direction":null,"updatedAt":'"$near_expiry"'}'
wait_for_status '.routeValid == true and .routeVisible == true'
wait_for_status '.routeValid == false and .routeVisible == false and (.routeError | test("stale"))'
wait_for_health '.notificationRouteValid == false and .notificationRouteVisible == false and (.notificationRouteError | test("stale"))'

write_route_payload '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":null,"direction":null,"updatedAt":'"$(date +%s)"'}'
wait_for_status '.routeValid == true and .routeVisible == true and .routeError == ""'

[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0 and .historyCount == 1'
[[ $(count_json_files "$history_dir") -eq 1 ]]
history_file=$(printf '%s\n' "$history_dir"/*.json)
assert_mode 600 "$history_file"

[[ $(call_notification restoreLast) == ok ]]
wait_for_status '.popupCount == 1 and .historyCount == 1'

[[ $(call_notification dismissAll) == ok ]]
wait_for_status '.popupCount == 0 and .historyCount == 1 and .persistenceError == ""'

# Default actions invoke the retained live action and archive only after success.
default_action_output="$fixture/default-action.out"
notify-send --app-name task4-default-action --action=default=Open --urgency normal \
  --expire-time 30000 'Task 4 default action' 'default action contract' >"$default_action_output" 2>&1 &
action_pid=$!
wait_for_status '.popupCount == 1 and .liveCount == 1'
[[ $(call_notification invokeLast) == ok ]]
wait_for_process_exit "$action_pid"
action_pid=''
[[ $(<"$default_action_output") == default ]]
wait_for_status '.popupCount == 0 and .liveCount == 0 and .historyCount == 2'
default_history_file=$(printf '%s\n' "$history_dir"/*.json | sort -n | tail -n 1)
jq -e '.actions == []' "$default_history_file" >/dev/null

# A non-default-only notification must survive the card default click, then invoke
# the selected action through the retained live reference.
nondefault_action_output="$fixture/nondefault-action.out"
notify-send --app-name task4-nondefault-action --action=archive=Archive --urgency normal \
  --expire-time 30000 'Task 4 non-default action' 'non-default action contract' >"$nondefault_action_output" 2>&1 &
action_pid=$!
wait_for_status '.popupCount == 1 and .liveCount == 1'
[[ $(call_notification invokeLast) == ok ]]
sleep 0.5
kill -0 "$action_pid"
wait_for_status '.popupCount == 1 and .liveCount == 1'
[[ $(call_notification invokeAction archive) == ok ]]
wait_for_process_exit "$action_pid"
action_pid=''
[[ $(<"$nondefault_action_output") == archive ]]
wait_for_status '.popupCount == 0 and .liveCount == 0'

# Resident actions remain visible after successful invocation until dismissed.
resident_action_output="$fixture/resident-action.out"
resident_sender="$fixture/resident-sender.py"
cat >"$resident_sender" <<'PY'
import dbus
import dbus.mainloop.glib
import sys
from gi.repository import GLib

output_path = sys.argv[1]
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
loop = GLib.MainLoop()
resident_id = None

def write(value):
    with open(output_path, "a", encoding="ascii") as output:
        output.write(value + "\n")

def on_action(notification_id, action):
    if resident_id is not None and int(notification_id) == int(resident_id):
        write(str(action))

def on_close(notification_id, reason):
    if resident_id is not None and int(notification_id) == int(resident_id):
        write("closed")
        loop.quit()

def on_timeout():
    loop.quit()
    return False

bus.add_signal_receiver(
    on_action,
    dbus_interface="org.freedesktop.Notifications",
    signal_name="ActionInvoked",
    path="/org/freedesktop/Notifications",
)
bus.add_signal_receiver(
    on_close,
    dbus_interface="org.freedesktop.Notifications",
    signal_name="NotificationClosed",
    path="/org/freedesktop/Notifications",
)
proxy = bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
notifications = dbus.Interface(proxy, "org.freedesktop.Notifications")
resident_id = notifications.Notify(
    "task4-resident-python", 0, "", "Resident action", "resident action contract",
    dbus.Array(["archive", "Archive"], signature="s"),
    dbus.Dictionary({"resident": dbus.Boolean(True)}, signature="sv"), dbus.Int32(30000),
)
GLib.timeout_add(5000, on_timeout)
loop.run()
PY
chmod 700 "$resident_sender"
python3 "$resident_sender" "$resident_action_output" &
action_pid=$!
wait_for_status '.popupCount == 1 and .liveCount == 1'
[[ $(call_notification invokeAction archive) == ok ]]
wait_for_status '.popupCount == 1 and .liveCount == 1'
kill -0 "$action_pid"
[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0 and .liveCount == 0'
wait_for_process_exit "$action_pid"
action_pid=''
[[ $(<"$resident_action_output") == *archive* ]] && [[ $(<"$resident_action_output") == *closed* ]]

# Sender-side closure removes the matching live row and active file without
# archiving it or invoking a backend dismiss/expire operation.
closed_sender="$fixture/closed-sender.py"
cat >"$closed_sender" <<'PY'
import dbus
import sys
import time

output_path, app_name, urgency, expire_timeout = sys.argv[1:]
bus = dbus.SessionBus()
proxy = bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
notifications = dbus.Interface(proxy, "org.freedesktop.Notifications")
notification_id = notifications.Notify(
    app_name, 0, "", "Sender close", "sender close contract",
    dbus.Array([], signature="s"),
    dbus.Dictionary({"urgency": dbus.Byte(int(urgency))}, signature="sv"),
    dbus.Int32(int(expire_timeout)),
)
time.sleep(0.5)
notifications.CloseNotification(notification_id)
with open(output_path, "w", encoding="ascii") as output:
    output.write("closed\n")
PY
chmod 700 "$closed_sender"

run_sender_close_case() {
  local app_name=$1
  local urgency=$2
  local expire_timeout=$3
  local output_path="$fixture/$app_name-closed.out"
  local history_before
  history_before=$(count_json_files "$history_dir")
  python3 - "$output_path" "$app_name" "$urgency" "$expire_timeout" <"$closed_sender" &
  action_pid=$!
  wait_for_status '.popupCount == 1 and .liveCount == 1'
  wait_for_process_exit "$action_pid"
  action_pid=''
  wait_for_status '.popupCount == 0 and .liveCount == 0'
  wait_for_json_count "$popup_dir" 0 || {
    printf 'sender-close status: %s\n' "$(read_status 2>/dev/null || true)" >&2
    exit 1
  }
  [[ $(count_json_files "$history_dir") == "$history_before" ]]
  [[ $(<"$output_path") == closed ]]
}

# Positive and default lifetimes persist an absolute deadline. Replacements reset
# that deadline, while one or more service restarts preserve the same deadline.
positive_id=$(notify-send --app-name task4-positive-deadline --print-id --expire-time 12000 \
  'Task 4 positive deadline' 'initial positive lifetime' 2>/dev/null)
wait_for_status '.popupCount == 1 and .liveCount == 1'
wait_for_json_count "$popup_dir" 1
positive_file=$(printf '%s\n' "$popup_dir"/*.json)
positive_deadline=$(jq -r '.deadline' "$positive_file")
[[ $positive_deadline =~ ^[0-9]+$ && $positive_deadline -gt $(date +%s%3N) ]] || {
  printf 'FAIL: positive deadline was %s in %s\n' "$positive_deadline" "$positive_file" >&2
  exit 1
}
sleep 0.2
notify-send --app-name task4-positive-deadline --replace-id "$positive_id" --expire-time 12000 \
  'Task 4 positive deadline replacement' 'replacement resets lifetime' >/dev/null 2>&1
wait_for_status '.popupCount == 1 and .liveCount == 1'
wait_for_json_count "$popup_dir" 1
positive_file=$(printf '%s\n' "$popup_dir"/*.json)
replaced_positive_deadline=$(jq -r '.deadline' "$positive_file")
[[ $replaced_positive_deadline =~ ^[0-9]+$ && $replaced_positive_deadline -gt $positive_deadline ]] || {
  printf 'FAIL: replacement positive deadline was %s, initial was %s\n' \
    "$replaced_positive_deadline" "$positive_deadline" >&2
  exit 1
}
stop_shell
start_shell
wait_for_status '.popupCount == 1 and .routeValid == true'
wait_for_json_count "$popup_dir" 1
positive_file=$(printf '%s\n' "$popup_dir"/*.json)
restored_positive_deadline=$(jq -r '.deadline' "$positive_file")
[[ $restored_positive_deadline == "$replaced_positive_deadline" ]] || {
  printf 'FAIL: one-restart positive deadline was %s, expected %s\n' \
    "$restored_positive_deadline" "$replaced_positive_deadline" >&2
  exit 1
}
stop_shell
start_shell
wait_for_status '.popupCount == 1 and .routeValid == true'
wait_for_json_count "$popup_dir" 1
positive_file=$(printf '%s\n' "$popup_dir"/*.json)
restarted_positive_deadline=$(jq -r '.deadline' "$positive_file")
[[ $restarted_positive_deadline == "$replaced_positive_deadline" ]] || {
  printf 'FAIL: two-restart positive deadline was %s, expected %s\n' \
    "$restarted_positive_deadline" "$replaced_positive_deadline" >&2
  exit 1
}
[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0'

default_id=$(notify-send --app-name task4-default-deadline --print-id \
  'Task 4 default deadline' 'default lifetime' 2>/dev/null)
wait_for_status '.popupCount == 1 and .liveCount == 1'
wait_for_json_count "$popup_dir" 1
default_file=$(printf '%s\n' "$popup_dir"/*.json)
default_deadline=$(jq -r '.deadline' "$default_file")
[[ $default_deadline =~ ^[0-9]+$ && $default_deadline -gt $(date +%s%3N) ]] || {
  printf 'FAIL: default deadline was %s in %s\n' "$default_deadline" "$default_file" >&2
  exit 1
}
notify-send --app-name task4-default-deadline --replace-id "$default_id" \
  'Task 4 default deadline replacement' 'default replacement resets lifetime' >/dev/null 2>&1
wait_for_status '.popupCount == 1 and .liveCount == 1'
wait_for_json_count "$popup_dir" 1
default_file=$(printf '%s\n' "$popup_dir"/*.json)
replaced_default_deadline=$(jq -r '.deadline' "$default_file")
[[ $replaced_default_deadline =~ ^[0-9]+$ && $replaced_default_deadline -gt $default_deadline ]] || {
  printf 'FAIL: replacement default deadline was %s, initial was %s\n' \
    "$replaced_default_deadline" "$default_deadline" >&2
  exit 1
}
stop_shell
start_shell
wait_for_status '.popupCount == 1 and .routeValid == true'
wait_for_json_count "$popup_dir" 1
default_file=$(printf '%s\n' "$popup_dir"/*.json)
[[ $(jq -r '.deadline' "$default_file") == "$replaced_default_deadline" ]] || {
  printf 'FAIL: restored default deadline was %s, expected %s\n' \
    "$(jq -r '.deadline' "$default_file")" "$replaced_default_deadline" >&2
  exit 1
}
[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0'

# Transient notifications may render, but never create active files or history
# entries when dismissed or when their visible lifetime ends.
transient_history_before=$(count_json_files "$history_dir")
notify-send --app-name task4-transient-visible --hint=boolean:transient:true --expire-time 12000 \
  'Task 4 transient visible' 'transient dismissal contract'
wait_for_status '.popupCount == 1 and .liveCount == 1'
wait_for_json_count "$popup_dir" 0
[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0 and .liveCount == 0'
[[ $(count_json_files "$history_dir") == "$transient_history_before" ]]

[[ $(call_notification toggleDnd) == enabled ]]
wait_for_status '.dnd == true and .popupCount == 1'
[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0'
transient_history_before=$(count_json_files "$history_dir")
notify-send --app-name task4-transient-dnd --hint=boolean:transient:true --expire-time 12000 \
  'Task 4 transient DND' 'transient DND contract'
wait_for_status '.popupCount == 0 and .liveCount == 0'
wait_for_json_count "$popup_dir" 0
[[ $(count_json_files "$history_dir") == "$transient_history_before" ]]
[[ $(call_notification toggleDnd) == disabled ]]
wait_for_status '.dnd == false and .popupCount == 1'
[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0'

transient_history_before=$(count_json_files "$history_dir")
notify-send --app-name task4-transient-timeout --hint=boolean:transient:true --urgency low --expire-time 1000 \
  'Task 4 transient timeout' 'transient timeout contract'
wait_for_status '.popupCount == 1 and .liveCount == 1'
wait_for_json_count "$popup_dir" 0
wait_for_status '.popupCount == 0 and .liveCount == 0'
[[ $(count_json_files "$history_dir") == "$transient_history_before" ]]

# Explicit zero survives replacement and a service restart, while persisted rows
# have no action references.
replacement_id=$(notify-send --app-name task4-timeout --print-id --expire-time 0 \
  'Task 4 timeout' 'explicit never timeout' 2>/dev/null)
wait_for_status '.popupCount == 1 and .liveCount == 1'
notify-send --app-name task4-timeout --replace-id "$replacement_id" --expire-time 0 \
  'Task 4 timeout replacement' 'replacement remains resident' >/dev/null 2>&1
wait_for_status '.popupCount == 1 and .liveCount == 1'
stop_shell
start_shell
wait_for_status '.popupCount == 1 and .routeValid == true'
timeout_file=$(printf '%s\n' "$popup_dir"/*.json)
jq -e '.expireTimeout == 0 and .actions == []' "$timeout_file" >/dev/null
[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0'

run_sender_close_case task4-closed-critical 2 0
run_sender_close_case task4-closed-zero 1 0
run_sender_close_case task4-closed-positive 1 12000

# A stale close from the replaced object must not remove the replacement row.
stale_replacement_id=$(notify-send --app-name task4-stale-close --print-id --expire-time 0 \
  'Task 4 stale close' 'old generation' 2>/dev/null)
wait_for_status '.popupCount == 1 and .liveCount == 1'
notify-send --app-name task4-stale-close --replace-id "$stale_replacement_id" --expire-time 0 \
  'Task 4 stale close replacement' 'new generation' >/dev/null 2>&1
wait_for_status '.popupCount == 1 and .liveCount == 1'
sleep 0.5
wait_for_status '.popupCount == 1 and .liveCount == 1'
wait_for_json_count "$popup_dir" 1
[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0'

# A failed running write must not retry over a newer archive operation for the
# same key. The newer archive may fail because A never published, but stale A
# must not recreate the active file.
persistence_bin="$fixture/persistence-bin"
persistence_fail_started="$fixture/persistence-fail-started"
persistence_fail_release="$fixture/persistence-fail-release"
persistence_fail_count="$fixture/persistence-fail-count"
real_mv="$(type -P mv)"
mkdir -p "$persistence_bin"
cat >"$persistence_bin/mv" <<'FAKE_PERSISTENCE_MV'
#!/usr/bin/env bash
set -Eeuo pipefail
args=("$@")
last_index=$(( ${#args[@]} - 1 ))
source_path=${args[$((last_index - 1))]}
destination_path=${args[$last_index]}
if [[ $source_path == "$DESKTOP_SHELL_TEST_POPUP_DIR"/*.json.* &&
      $destination_path == "$DESKTOP_SHELL_TEST_POPUP_DIR"/*.json ]]; then
  count=0
  if [[ -f ${DESKTOP_SHELL_TEST_PERSISTENCE_COUNT:?} ]]; then
    count=$(<"$DESKTOP_SHELL_TEST_PERSISTENCE_COUNT")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$DESKTOP_SHELL_TEST_PERSISTENCE_COUNT"
  if ((count == 1)); then
    : >"$DESKTOP_SHELL_TEST_PERSISTENCE_START"
    while [[ ! -e ${DESKTOP_SHELL_TEST_PERSISTENCE_RELEASE:?} ]]; do
      sleep 0.05
    done
    exit 1
  fi
fi
exec "$DESKTOP_SHELL_TEST_REAL_MV" "$@"
FAKE_PERSISTENCE_MV
chmod 700 "$persistence_bin/mv"
export DESKTOP_SHELL_TEST_PERSISTENCE_BIN="$persistence_bin"
export DESKTOP_SHELL_TEST_POPUP_DIR="$popup_dir"
export DESKTOP_SHELL_TEST_PERSISTENCE_START="$persistence_fail_started"
export DESKTOP_SHELL_TEST_PERSISTENCE_RELEASE="$persistence_fail_release"
export DESKTOP_SHELL_TEST_PERSISTENCE_COUNT="$persistence_fail_count"
export DESKTOP_SHELL_TEST_REAL_MV="$real_mv"
stop_shell
start_shell
wait_for_status '.dnd == false and .popupCount == 0'
generation_history_before=$(count_json_files "$history_dir")
notify-send --app-name task4-generation-failure --expire-time 0 \
  'Task 4 generation failure' 'older write must not supersede newer archive'
wait_for_status '.popupCount == 1 and .liveCount == 1'
wait_for_path "$persistence_fail_started"
[[ $(call_notification dismissLast) == ok ]]
wait_for_status '.popupCount == 0 and .liveCount == 0'
: >"$persistence_fail_release"
wait_for_json_count "$popup_dir" 0
[[ $(count_json_files "$history_dir") == "$generation_history_before" ]]
wait_for_status '.persistenceError != ""'
unset DESKTOP_SHELL_TEST_PERSISTENCE_BIN DESKTOP_SHELL_TEST_POPUP_DIR \
  DESKTOP_SHELL_TEST_PERSISTENCE_START DESKTOP_SHELL_TEST_PERSISTENCE_RELEASE \
  DESKTOP_SHELL_TEST_PERSISTENCE_COUNT DESKTOP_SHELL_TEST_REAL_MV
stop_shell
start_shell
wait_for_status '.dnd == false and .popupCount == 0'

# A popup whose persisted absolute deadline is already elapsed is archived and
# removed during restore instead of being shown or extending its lifetime.
stop_shell
expired_timestamp=$(date +%s%3N)
expired_file="$popup_dir/${expired_timestamp}-77.json"
printf '%s\n' '{"id":77,"originalId":77,"app":"task4-expired","appIcon":"","summary":"Expired restore","body":"expired","image":"","urgency":1,"expireTimeout":12000,"timestamp":'"$expired_timestamp"',"actions":[],"deadline":'"$((expired_timestamp - 1))"'}' >"$expired_file"
chmod 600 "$expired_file"
start_shell
wait_for_status '.popupCount == 0 and .routeValid == true'
wait_for_json_count "$popup_dir" 0
wait_for_file "$history_dir/${expired_timestamp}-77.json"

# Hold the first atomic settings rename, change DND again while it is active,
# and require one follow-up write with the latest state.
[[ $(call_notification toggleDnd) == enabled ]]
wait_for_status '.dnd == true and .popupCount == 1'
wait_for_path "$settings_write_started"
[[ $(call_notification toggleDnd) == disabled ]]
wait_for_status '.dnd == false and .popupCount == 1'
sleep 1
: >"$settings_write_release"
wait_for_setting_dnd false 2
assert_mode 600 "$state_home/desktop-shell/notifications.json"
unset DESKTOP_SHELL_TEST_SETTINGS_BIN DESKTOP_SHELL_TEST_SETTINGS_START \
  DESKTOP_SHELL_TEST_SETTINGS_RELEASE DESKTOP_SHELL_TEST_SETTINGS_COUNT

stop_shell
start_shell
wait_for_status '.notificationsOwned == true and .routeValid == true and .routeVisible == true and .dnd == false and .popupCount == 0'
[[ $(call_notification toggleDnd) == enabled ]]
wait_for_status '.dnd == true and .popupCount == 1'
wait_for_setting_dnd true 2
assert_mode 600 "$state_home/desktop-shell/notifications.json"

stop_shell
start_shell
wait_for_status '.notificationsOwned == true and .routeValid == true and .routeVisible == true and .dnd == true and .popupCount == 0'
wait_for_health '.notificationsOwned == true and .notificationRouteValid == true and .notificationOwnershipError == ""'

# A bounded history failure must be surfaced and must release the tracked object.
rm -rf -- "$history_dir"
printf 'history path blocker\n' >"$history_dir"
chmod 600 "$history_dir"
notify-send --app-name task4-dnd-failure --urgency normal --expire-time 30000 \
  'Task 4 DND failure' 'history persistence failure contract'
wait_for_status '.persistenceError != "" and .popupCount == 0 and .liveCount == 0'
rm -f -- "$history_dir"
mkdir -p -- "$history_dir"
chmod 700 "$history_dir"
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'

# A slow first DND history write fills the bounded queue. The evicted history
# callback must release exactly its tracked notification, and all remaining
# intents must settle without leaving a live reference behind.
dnd_queue_bin="$fixture/dnd-queue-bin"
dnd_queue_started="$fixture/dnd-queue-started"
dnd_queue_release="$fixture/dnd-queue-release"
dnd_queue_count="$fixture/dnd-queue-count"
dnd_queue_real_mv="$(type -P mv)"
mkdir -p "$dnd_queue_bin"
cat >"$dnd_queue_bin/mv" <<'FAKE_DND_QUEUE_MV'
#!/usr/bin/env bash
set -Eeuo pipefail
args=("$@")
last_index=$(( ${#args[@]} - 1 ))
source_path=${args[$((last_index - 1))]}
destination_path=${args[$last_index]}
if [[ $source_path == "$DESKTOP_SHELL_TEST_HISTORY_DIR"/*.json.* &&
      $destination_path == "$DESKTOP_SHELL_TEST_HISTORY_DIR"/*.json ]]; then
  count=0
  if [[ -f ${DESKTOP_SHELL_TEST_DND_QUEUE_COUNT:?} ]]; then
    count=$(<"$DESKTOP_SHELL_TEST_DND_QUEUE_COUNT")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$DESKTOP_SHELL_TEST_DND_QUEUE_COUNT"
  if ((count == 1)); then
    : >"$DESKTOP_SHELL_TEST_DND_QUEUE_STARTED"
    while [[ ! -e ${DESKTOP_SHELL_TEST_DND_QUEUE_RELEASE:?} ]]; do
      sleep 0.05
    done
  fi
fi
exec "$DESKTOP_SHELL_TEST_DND_QUEUE_REAL_MV" "$@"
FAKE_DND_QUEUE_MV
chmod 700 "$dnd_queue_bin/mv"
export DESKTOP_SHELL_TEST_PERSISTENCE_BIN="$dnd_queue_bin"
export DESKTOP_SHELL_TEST_HISTORY_DIR="$history_dir"
export DESKTOP_SHELL_TEST_DND_QUEUE_STARTED="$dnd_queue_started"
export DESKTOP_SHELL_TEST_DND_QUEUE_RELEASE="$dnd_queue_release"
export DESKTOP_SHELL_TEST_DND_QUEUE_COUNT="$dnd_queue_count"
export DESKTOP_SHELL_TEST_DND_QUEUE_REAL_MV="$dnd_queue_real_mv"
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'
for index in $(seq 1 102); do
  notify-send --app-name task4-dnd-queue --urgency normal --expire-time 30000 \
    "Task 4 DND queue $index" 'DND queue capacity contract'
done
wait_for_path "$dnd_queue_started"
wait_for_status '.pendingPersistenceCount == 100 and .liveCount == 101 and .admissionDropped == 0'
: >"$dnd_queue_release"
wait_for_status '.pendingPersistenceCount == 0 and .persistenceGenerationCount == 0 and .liveCount == 0 and .popupCount == 0'
unset DESKTOP_SHELL_TEST_PERSISTENCE_BIN DESKTOP_SHELL_TEST_HISTORY_DIR \
  DESKTOP_SHELL_TEST_DND_QUEUE_STARTED DESKTOP_SHELL_TEST_DND_QUEUE_RELEASE \
  DESKTOP_SHELL_TEST_DND_QUEUE_COUNT DESKTOP_SHELL_TEST_DND_QUEUE_REAL_MV
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'

# A same-object DND replacement flood must coalesce to one hidden refresh gate,
# then settle the exact hidden object instead of recursively persisting forever.
dnd_refresh_bin="$fixture/dnd-refresh-bin"
dnd_refresh_started="$fixture/dnd-refresh-started"
dnd_refresh_release="$fixture/dnd-refresh-release"
dnd_refresh_count="$fixture/dnd-refresh-count"
dnd_refresh_real_mv="$(type -P mv)"
mkdir -p "$dnd_refresh_bin"
cat >"$dnd_refresh_bin/mv" <<'FAKE_DND_REFRESH_MV'
#!/usr/bin/env bash
set -Eeuo pipefail
args=("$@")
last_index=$(( ${#args[@]} - 1 ))
source_path=${args[$((last_index - 1))]}
destination_path=${args[$last_index]}
if [[ $source_path == "$DESKTOP_SHELL_TEST_HISTORY_DIR"/*.json.* &&
      $destination_path == "$DESKTOP_SHELL_TEST_HISTORY_DIR"/*.json ]]; then
  count=0
  if [[ -f ${DESKTOP_SHELL_TEST_DND_REFRESH_COUNT:?} ]]; then
    count=$(<"$DESKTOP_SHELL_TEST_DND_REFRESH_COUNT")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$DESKTOP_SHELL_TEST_DND_REFRESH_COUNT"
  if ((count == 1)); then
    : >"$DESKTOP_SHELL_TEST_DND_REFRESH_STARTED"
    while [[ ! -e ${DESKTOP_SHELL_TEST_DND_REFRESH_RELEASE:?} ]]; do
      sleep 0.05
    done
  fi
fi
exec "$DESKTOP_SHELL_TEST_DND_REFRESH_REAL_MV" "$@"
FAKE_DND_REFRESH_MV
chmod 700 "$dnd_refresh_bin/mv"
export DESKTOP_SHELL_TEST_PERSISTENCE_BIN="$dnd_refresh_bin"
export DESKTOP_SHELL_TEST_HISTORY_DIR="$history_dir"
export DESKTOP_SHELL_TEST_DND_REFRESH_STARTED="$dnd_refresh_started"
export DESKTOP_SHELL_TEST_DND_REFRESH_RELEASE="$dnd_refresh_release"
export DESKTOP_SHELL_TEST_DND_REFRESH_COUNT="$dnd_refresh_count"
export DESKTOP_SHELL_TEST_DND_REFRESH_REAL_MV="$dnd_refresh_real_mv"
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'
dnd_refresh_id=$(notify-send --app-name task4-dnd-refresh --print-id --urgency normal --expire-time 30000 \
  'Task 4 DND refresh seed' 'refresh seed' 2>/dev/null)
wait_for_path "$dnd_refresh_started"
for index in $(seq 1 130); do
  notify-send --app-name task4-dnd-refresh --replace-id "$dnd_refresh_id" --urgency normal --expire-time 30000 \
    "Task 4 DND refresh $index" 'refresh flood contract' >/dev/null 2>&1
done
: >"$dnd_refresh_release"
wait_for_status '.dnd == true and .popupCount == 0 and .pendingPersistenceCount == 0 and .liveCount == 0 and .admissionWindowCount == 2 and .admissionDropped == 0'
dnd_refresh_file=''
for file in "$history_dir"/*.json; do
  [[ -f $file ]] || continue
  [[ $(jq -r '.app' "$file" 2>/dev/null) == task4-dnd-refresh ]] || continue
  dnd_refresh_file=$file
done
[[ -n $dnd_refresh_file ]] || {
  printf 'FAIL: DND refresh history snapshot was not persisted\n' >&2
  exit 1
}
[[ $(jq -r '.summary' "$dnd_refresh_file") == 'Task 4 DND refresh 130' ]] || {
  printf 'FAIL: DND refresh history snapshot was not coalesced to the latest update\n' >&2
  exit 1
}
unset DESKTOP_SHELL_TEST_PERSISTENCE_BIN DESKTOP_SHELL_TEST_HISTORY_DIR \
  DESKTOP_SHELL_TEST_DND_REFRESH_STARTED DESKTOP_SHELL_TEST_DND_REFRESH_RELEASE \
  DESKTOP_SHELL_TEST_DND_REFRESH_COUNT DESKTOP_SHELL_TEST_DND_REFRESH_REAL_MV
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'

# Exhaust the admission window while the target history write is slow. Its
# changed backend snapshot must be denied, leave the seed file intact, and
# release the exact hidden target alongside the other settled senders.
rm -f -- "$dnd_refresh_started" "$dnd_refresh_release" "$dnd_refresh_count"
export DESKTOP_SHELL_TEST_PERSISTENCE_BIN="$dnd_refresh_bin"
export DESKTOP_SHELL_TEST_HISTORY_DIR="$history_dir"
export DESKTOP_SHELL_TEST_DND_REFRESH_STARTED="$dnd_refresh_started"
export DESKTOP_SHELL_TEST_DND_REFRESH_RELEASE="$dnd_refresh_release"
export DESKTOP_SHELL_TEST_DND_REFRESH_COUNT="$dnd_refresh_count"
export DESKTOP_SHELL_TEST_DND_REFRESH_REAL_MV="$dnd_refresh_real_mv"
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'
denied_dnd_id=$(notify-send --app-name task4-dnd-refresh-denied --print-id --urgency normal --expire-time 30000 \
  'Task 4 DND denied seed' 'denied seed' 2>/dev/null)
wait_for_path "$dnd_refresh_started"
for index in $(seq 1 119); do
  notify-send --app-name task4-dnd-refresh-filler --urgency normal --expire-time 30000 \
    --hint=boolean:transient:true \
    "Task 4 DND denied filler $index" 'denied admission filler' >/dev/null 2>&1
done
notify-send --app-name task4-dnd-refresh-denied --replace-id "$denied_dnd_id" --urgency normal --expire-time 30000 \
  'Task 4 DND denied update' 'denied update' >/dev/null 2>&1
: >"$dnd_refresh_release"
wait_for_status '.dnd == true and .popupCount == 0 and .pendingPersistenceCount == 0 and .liveCount == 0 and .admissionWindowCount == 120 and .admissionDropped == 1'
denied_dnd_file=''
for file in "$history_dir"/*.json; do
  [[ -f $file ]] || continue
  [[ $(jq -r '.app' "$file" 2>/dev/null) == task4-dnd-refresh-denied ]] || continue
  denied_dnd_file=$file
done
[[ -n $denied_dnd_file ]] || {
  printf 'FAIL: denied DND target history snapshot was removed\n' >&2
  exit 1
}
[[ $(jq -r '.summary' "$denied_dnd_file") == 'Task 4 DND denied seed' ]] || {
  printf 'FAIL: denied DND refresh replaced the last persisted snapshot\n' >&2
  exit 1
}
unset DESKTOP_SHELL_TEST_PERSISTENCE_BIN DESKTOP_SHELL_TEST_HISTORY_DIR \
  DESKTOP_SHELL_TEST_DND_REFRESH_STARTED DESKTOP_SHELL_TEST_DND_REFRESH_RELEASE \
  DESKTOP_SHELL_TEST_DND_REFRESH_COUNT DESKTOP_SHELL_TEST_DND_REFRESH_REAL_MV
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'

# The same hidden refresh is admitted after a deterministic service restart
# resets the global window.
rm -f -- "$dnd_refresh_started" "$dnd_refresh_release" "$dnd_refresh_count"
export DESKTOP_SHELL_TEST_PERSISTENCE_BIN="$dnd_refresh_bin"
export DESKTOP_SHELL_TEST_HISTORY_DIR="$history_dir"
export DESKTOP_SHELL_TEST_DND_REFRESH_STARTED="$dnd_refresh_started"
export DESKTOP_SHELL_TEST_DND_REFRESH_RELEASE="$dnd_refresh_release"
export DESKTOP_SHELL_TEST_DND_REFRESH_COUNT="$dnd_refresh_count"
export DESKTOP_SHELL_TEST_DND_REFRESH_REAL_MV="$dnd_refresh_real_mv"
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'
reset_dnd_id=$(notify-send --app-name task4-dnd-refresh-reset --print-id --urgency normal --expire-time 30000 \
  'Task 4 DND reset seed' 'reset seed' 2>/dev/null)
wait_for_path "$dnd_refresh_started"
notify-send --app-name task4-dnd-refresh-reset --replace-id "$reset_dnd_id" --urgency normal --expire-time 30000 \
  'Task 4 DND reset update' 'reset update' >/dev/null 2>&1
: >"$dnd_refresh_release"
wait_for_status '.dnd == true and .popupCount == 0 and .pendingPersistenceCount == 0 and .liveCount == 0 and .admissionWindowCount == 2 and .admissionDropped == 0'
reset_dnd_file=''
for file in "$history_dir"/*.json; do
  [[ -f $file ]] || continue
  [[ $(jq -r '.app' "$file" 2>/dev/null) == task4-dnd-refresh-reset ]] || continue
  reset_dnd_file=$file
done
[[ -n $reset_dnd_file ]] || {
  printf 'FAIL: reset DND refresh history snapshot was not persisted\n' >&2
  exit 1
}
[[ $(jq -r '.summary' "$reset_dnd_file") == 'Task 4 DND reset update' ]] || {
  printf 'FAIL: admitted DND refresh did not persist the latest snapshot\n' >&2
  exit 1
}
unset DESKTOP_SHELL_TEST_PERSISTENCE_BIN DESKTOP_SHELL_TEST_HISTORY_DIR \
  DESKTOP_SHELL_TEST_DND_REFRESH_STARTED DESKTOP_SHELL_TEST_DND_REFRESH_RELEASE \
  DESKTOP_SHELL_TEST_DND_REFRESH_COUNT DESKTOP_SHELL_TEST_DND_REFRESH_REAL_MV
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'

# The global admission window applies before DND persistence, even when the
# active-popup cap is never reached.
for index in $(seq 1 121); do
  notify-send --app-name task4-dnd-admission --urgency normal --expire-time 30000 \
    "Task 4 DND admission $index" 'DND admission window contract'
done
wait_for_status '.popupCount == 0 and .liveCount == 0 and .admissionDropped == 1 and .admissionWindowCount == 120'
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'

# Critical notifications bypass DND but share the total active cap. Replacing
# an existing critical row must not consume another slot.
critical_id=$(notify-send --app-name task4-critical-flood --print-id --urgency critical \
  --expire-time 0 'Task 4 critical flood' 'critical replacement seed' 2>/dev/null)
for index in $(seq 1 120); do
  notify-send --app-name task4-critical-flood --urgency critical --expire-time 0 \
    "Task 4 critical flood $index" 'critical active-cap contract'
done
wait_for_status '.popupCount == 50 and .liveCount == 50 and .pendingPersistenceCount <= 100 and .admissionDropped == 1 and .admissionWindowCount == 120'
critical_file=$(printf '%s\n' "$popup_dir"/*.json | sort -n | tail -n 1)
critical_safe_summary=$(jq -r '.summary' "$critical_file")
[[ -n $critical_safe_summary && $critical_safe_summary != null ]] || {
  printf 'FAIL: critical flood did not leave a persisted safe snapshot\n' >&2
  exit 1
}
notify-send --app-name task4-critical-flood --replace-id "$critical_id" --urgency critical \
  --expire-time 0 'Task 4 critical replacement' 'replacement does not consume a slot' >/dev/null 2>&1
wait_for_status '.popupCount == 50 and .liveCount == 50'
critical_file=$(printf '%s\n' "$popup_dir"/*.json | sort -n | tail -n 1)
[[ $(jq -r '.summary' "$critical_file") == "$critical_safe_summary" ]] || {
  printf 'FAIL: denied critical replacement changed the safe snapshot from %s\n' \
    "$critical_safe_summary" >&2
  exit 1
}
[[ $(call_notification dismissAll) == ok ]]
wait_for_status '.popupCount == 0 and .liveCount == 0 and .pendingPersistenceCount == 0'

# Restart deterministically resets the admission window; a later replacement
# is then admitted and becomes the new safe snapshot.
stop_shell
start_shell
wait_for_status '.dnd == true and .popupCount == 0 and .admissionDropped == 0 and .admissionWindowCount == 0'
reset_critical_id=$(notify-send --app-name task4-critical-reset --print-id --urgency critical \
  --expire-time 0 'Task 4 critical reset seed' 'reset seed' 2>/dev/null)
wait_for_status '.popupCount == 1 and .liveCount == 1'
notify-send --app-name task4-critical-reset --replace-id "$reset_critical_id" --urgency critical \
  --expire-time 0 'Task 4 critical reset replacement' 'replacement after reset' >/dev/null 2>&1
wait_for_status '.popupCount == 1 and .liveCount == 1 and .admissionWindowCount == 2'
critical_file=$(printf '%s\n' "$popup_dir"/*.json | sort -n | tail -n 1)
[[ $(jq -r '.summary' "$critical_file") == 'Task 4 critical reset replacement' ]] || {
  printf 'FAIL: admitted critical replacement did not update the safe snapshot\n' >&2
  exit 1
}
[[ $(call_notification dismissAll) == ok ]]
wait_for_status '.popupCount == 0 and .liveCount == 0'

stop_shell
probe_bin="$fixture/probe-bin"
probe_count="$fixture/probe-count"
mkdir -p "$probe_bin"
for command_name in bash sh quickshell mkdir find cat sort awk ls head stat rm mv cp date sleep mktemp; do
  command_path="$(type -P "$command_name")"
  [[ -n $command_path ]] && ln -s "$command_path" "$probe_bin/$command_name"
done
cat >"$probe_bin/busctl" <<'FAKE_BUSCTL'
#!/usr/bin/env bash
set -Eeuo pipefail

count=0
if [[ -f ${DESKTOP_SHELL_TEST_BUSCTL_COUNT:?} ]]; then
  count=$(<"$DESKTOP_SHELL_TEST_BUSCTL_COUNT")
fi
count=$((count + 1))
printf '%s\n' "$count" >"$DESKTOP_SHELL_TEST_BUSCTL_COUNT"
if ((count == 1)); then
  printf 'PID=%s\n' "$PPID"
  rm -f -- "$0"
  exit 0
fi
exit 127
FAKE_BUSCTL
chmod +x "$probe_bin/busctl"

DESKTOP_SHELL_TEST_BUSCTL_BIN="$probe_bin" \
DESKTOP_SHELL_TEST_BUSCTL_COUNT="$probe_count" \
DESKTOP_SHELL_TEST_BUSCTL_ISOLATE=1 \
start_shell
wait_for_health '.notificationsOwned == true and .notificationOwnershipError == ""'
wait_for_health '.notificationsOwned == false and .notificationOwnershipError == "busctl status failed (exit 127)"'
stop_shell

start_competing_owner
kill -0 "$owner_pid" 2>/dev/null || {
  printf 'FAIL: competing-owner fixture exited before shell startup\n' >&2
  exit 1
}
start_shell
owner_status_filter=".notificationsOwned == false and .ownershipError == \"notification owner is PID $owner_pid\" and .routeValid == true"
owner_health_filter=".notificationsOwned == false and .notificationOwnershipError == \"notification owner is PID $owner_pid\" and .notificationRouteValid == true"
wait_for_status "$owner_status_filter"
wait_for_health "$owner_health_filter"
kill -0 "$owner_pid" 2>/dev/null || {
  printf 'FAIL: competing-owner fixture exited during ownership assertion\n' >&2
  exit 1
}
printf 'PASS: isolated notification runtime ownership, routing, persistence, and history contracts\n'
