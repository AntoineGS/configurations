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
