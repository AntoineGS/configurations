#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
watcher=$repo_root/Linux/hypr/watch-rustdesk-submap.sh
test_root=$(mktemp -d)
call_log=$test_root/hyprctl.log

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# shellcheck disable=SC1090,SC1091 # The path is resolved from this repository at runtime.
source "$watcher"

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
