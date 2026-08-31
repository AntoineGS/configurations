#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
watcher=$repo_root/Linux/hypr/watch-rustdesk-submap.sh
test_root=$(mktemp -d)
call_log=$test_root/hyprctl.log
query_log=$test_root/hyprctl-queries.log

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# shellcheck disable=SC1090,SC1091 # The path is resolved from this repository at runtime.
source "$watcher"

notification_scheduler_step 5 30 5 false
[[ $NOTIFICATION_SCHEDULER_ACTION == wait ]] || fail "invalid cache heartbeat at five seconds did not wait"
[[ $NOTIFICATION_SCHEDULER_REMAINING == 25 ]] || fail "invalid cache at five seconds chose the wrong remaining time: $NOTIFICATION_SCHEDULER_REMAINING"
notification_scheduler_step 10 30 10 false
[[ $NOTIFICATION_SCHEDULER_ACTION == wait ]] || fail "invalid cache heartbeat at ten seconds did not wait"
[[ $NOTIFICATION_SCHEDULER_REMAINING == 20 ]] || fail "invalid cache at ten seconds chose the wrong remaining time: $NOTIFICATION_SCHEDULER_REMAINING"
notification_scheduler_step 25 30 25 false
[[ $NOTIFICATION_SCHEDULER_ACTION == wait ]] || fail "invalid cache heartbeat at twenty-five seconds did not wait"
[[ $NOTIFICATION_SCHEDULER_REMAINING == 5 ]] || fail "invalid cache at twenty-five seconds chose the wrong remaining time: $NOTIFICATION_SCHEDULER_REMAINING"
notification_scheduler_step 5 30 5 true
[[ $NOTIFICATION_SCHEDULER_ACTION == heartbeat ]] || fail "valid cache heartbeat did not renew"
[[ $NOTIFICATION_SCHEDULER_REMAINING == 0 ]] || fail "valid cache heartbeat did not report zero remaining time: $NOTIFICATION_SCHEDULER_REMAINING"
notification_scheduler_step 30 30 35 false
[[ $NOTIFICATION_SCHEDULER_ACTION == reconcile ]] || fail "reconciliation deadline did not win at thirty seconds"
[[ $NOTIFICATION_SCHEDULER_REMAINING == 0 ]] || fail "reconciliation deadline did not report zero remaining time: $NOTIFICATION_SCHEDULER_REMAINING"

actual_hostname=$(hostname)
# shellcheck disable=SC2016 # The child shell expands LOCAL_HOSTNAME after sourcing the watcher.
resolved_hostname=$(env HOSTNAME=DESKTOP-E07VTRN bash -c '
  source "$1"
  printf "%s\n" "$LOCAL_HOSTNAME"
' -- "$watcher")
[[ $resolved_hostname == "$actual_hostname" ]] ||
  fail "the routing host trusted inherited HOSTNAME: $resolved_hostname"

hyprctl() {
  case $1 in
    clients)
      printf 'clients\n' >>"$query_log"
      printf '%s\n' '[
        {
          "address": "0x111",
          "class": "rustdesk",
          "title": "First - Remote Desktop - RustDesk",
          "workspace": {"id": 2, "name": "2"},
          "fullscreen": 0,
          "fullscreenClient": 2,
          "focusHistoryID": 1
        },
        {
          "address": "0x222",
          "class": "rustdesk",
          "title": "Second - Remote Desktop - RustDesk",
          "workspace": {"id": 2, "name": "2"},
          "fullscreen": 2,
          "fullscreenClient": 0,
          "focusHistoryID": 0
        }
      ]'
      ;;
    monitors)
      printf 'monitors\n' >>"$query_log"
      printf '%s\n' '[
        {"id": 0, "name": "HDMI-A-1", "x": 0, "y": 0, "width": 1920, "disabled": false, "dpmsStatus": true, "activeWorkspace": {"id": 2}},
        {"id": 1, "name": "DP-2", "x": 1920, "y": 0, "width": 1920, "disabled": false, "dpmsStatus": true, "activeWorkspace": {"id": 3}}
      ]'
      ;;
    eval)
      printf '%s\n' "$2" >>"$call_log"
      ;;
    *)
      fail "unexpected hyprctl command: $*"
      ;;
  esac
}

NOTIFICATION_ROUTE_DIR=$test_root/route
# shellcheck disable=SC2034 # Consumed by sourced watcher functions.
NOTIFICATION_ROUTE_FILE=$NOTIFICATION_ROUTE_DIR/notification-route.json
# shellcheck disable=SC2034 # Consumed by sourced watcher functions.
NOTIFICATION_LEASE_FILE=$NOTIFICATION_ROUTE_DIR/notification-route-lease.json

reconcile_notification_routing || fail "initial route discovery failed"
[[ $NOTIFICATION_ROUTE_CACHED_UPDATED_AT =~ ^[0-9]+$ ]] ||
  fail "successful discovery did not cache the route timestamp"
[[ $(<"$query_log") == $'monitors\nclients' ]] ||
  fail "full discovery did not query monitors and clients"

: >"$query_log"
renew_notification_route_lease || fail "cached lease heartbeat failed"
[[ ! -s $query_log ]] || fail "lease heartbeat performed Hyprland discovery"

(
  # shellcheck disable=SC2329 # Invoked indirectly by renew_notification_route_lease.
  write_notification_route_lease() { return 1; }
  NOTIFICATION_ROUTE_CACHED_UPDATED_AT=123
  if renew_notification_route_lease; then
    fail "failed heartbeat returned success"
  fi
  [[ -z $NOTIFICATION_ROUTE_CACHED_UPDATED_AT ]] ||
    fail "failed heartbeat retained cached route state"
)

heartbeat_calls=0
# shellcheck disable=SC2329 # Invoked indirectly by notification_heartbeat_tick.
renew_notification_route_lease() { heartbeat_calls=$((heartbeat_calls + 1)); return 0; }
# shellcheck disable=SC2329 # Invoked indirectly by notification_heartbeat_tick.
reconcile_notification_routing() { heartbeat_calls=$((heartbeat_calls + 100)); NOTIFICATION_ROUTE_CACHE_INVALID=true; return 1; }
NOTIFICATION_ROUTE_CACHE_INVALID=true
notification_heartbeat_tick || fail "invalid heartbeat tick failed"
[[ $heartbeat_calls == 0 ]] || fail "invalid heartbeat tick performed work"
NOTIFICATION_ROUTE_CACHE_INVALID=false
notification_heartbeat_tick || fail "valid heartbeat tick failed"
[[ $heartbeat_calls == 1 ]] || fail "valid heartbeat did not renew exactly once"
renew_notification_route_lease() { heartbeat_calls=$((heartbeat_calls + 1)); return 1; }
notification_heartbeat_tick || fail "failed heartbeat tick failed"
[[ $heartbeat_calls == 102 ]] || fail "failed heartbeat did not reconcile immediately"
[[ $NOTIFICATION_ROUTE_CACHE_INVALID == true ]] || fail "failed reconciliation did not retain invalid cache"
notification_heartbeat_tick || fail "invalid post-failure heartbeat tick failed"
[[ $heartbeat_calls == 102 ]] || fail "post-failure heartbeat rediscovered"
# shellcheck disable=SC2034 # Passed by name to the event handler.
activated_clean_workspace=false
handle_hyprland_event 'workspace>>1' activated_clean_workspace
[[ $heartbeat_calls == 202 ]] || fail "routing event did not reconcile invalid cache"
reconcile_notification_routing || true
[[ $heartbeat_calls == 302 ]] || fail "reconciliation deadline did not retry invalid cache"

single_monitor='[
  {
    "id": 0,
    "name": "eDP-1",
    "x": 0,
    "y": 0,
    "width": 1920,
    "height": 1080,
    "focused": true,
    "disabled": false,
    "dpmsStatus": true,
    "activeWorkspace": {"id": 1}
  }
]'
inactive_rustdesk='[
  {
    "mapped": true,
    "visible": true,
    "monitor": 0,
    "workspace": {"id": 6},
    "class": "rustdesk",
    "title": "Office PC - Remote Desktop - RustDesk"
  }
]'
active_rustdesk=${inactive_rustdesk/\"id\": 6/\"id\": 1}

route=$(notification_route_state "$single_monitor" "$inactive_rustdesk" omarchbook)
[[ $route == 'rustdesk-route-eDP-1|none|none' ]] ||
  fail "non-privacy hosts hid notifications for an inactive RustDesk workspace: $route"

route=$(notification_route_state "$single_monitor" "$active_rustdesk" omarchbook)
[[ $route == 'rustdesk-route-eDP-1|none|none' ]] ||
  fail "non-privacy hosts applied RustDesk notification routing: $route"

route=$(notification_route_state "$single_monitor" "$inactive_rustdesk" DESKTOP-E07VTRN)
[[ $route == 'rustdesk-route-eDP-1|none|none' ]] ||
  fail "the privacy host treated an inactive RustDesk workspace as visible: $route"

route=$(notification_route_state "$single_monitor" "$active_rustdesk" DESKTOP-E07VTRN)
[[ $route == 'rustdesk-route-hidden|eDP-1|none' ]] ||
  fail "the privacy host exposed notifications over an active RustDesk workspace: $route"

reconcile_notification_routing() {
  return 0
}

# shellcheck disable=SC2034 # Passed by name to the watcher's nameref.
activated_clean_workspace=false
handle_hyprland_event 'openwindow>>222,2,rustdesk,Second - Remote Desktop - RustDesk' activated_clean_workspace

expected_move='hl.dispatch(hl.dsp.window.move({workspace=3, follow=false, window="address:0x222"}))'
expected_new_fullscreen='hl.dispatch(hl.dsp.window.fullscreen_state({internal=2, client=2, action="set", window="address:0x222"}))'
expected_restore='hl.dispatch(hl.dsp.window.fullscreen_state({internal=2, client=2, action="set", window="address:0x111"}))'
expected_calls="${expected_move}"$'\n'"${expected_new_fullscreen}"$'\n'"${expected_restore}"

[[ $(<"$call_log") == "$expected_calls" ]] || fail "RustDesk windows were not moved and fullscreened in order"

printf 'PASS: RustDesk fullscreen survives second-window routing\n'
