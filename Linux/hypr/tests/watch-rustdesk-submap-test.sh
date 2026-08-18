#!/bin/bash
# shellcheck disable=SC1091,SC2034,SC2317,SC2329 # The test intentionally replaces functions and state dynamically.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WATCHER="$SCRIPT_DIR/../watch-rustdesk-submap.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local message=$3
  [[ $actual == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_log_contains() {
  local expected=$1
  local log
  log=$(<"$MAKO_LOG")
  [[ $log == *"$expected"* ]] || fail "makoctl log does not contain '$expected': $log"
}

assert_log_empty() {
  [[ ! -s $MAKO_LOG ]] || fail "expected no makoctl mutation, got: $(<"$MAKO_LOG")"
}

reset_mako() {
  MAKO_MODE_OUTPUT=${1:-$'default\ndo-not-disturb'}
  MAKO_FAIL=false
  MAKO_EXPECTED_CUE_STATE=""
  MAKO_CUE_ORDER_CHECKED=false
  : >"$MAKO_LOG"
}

makoctl() {
  local index
  local -a arguments=("$@")

  if [[ $1 == mode && $# == 1 ]]; then
    if [[ $MAKO_FAIL == read ]]; then
      return 1
    fi
    printf '%s\n' "$MAKO_MODE_OUTPUT"
    return 0
  fi

  printf '%s\n' "$*" >>"$MAKO_LOG"
  for ((index = 1; index < $#; index += 2)); do
    if [[ ${arguments[index]} == -a && ${arguments[index + 1]} == rustdesk-cue ]]; then
      [[ -f $RUSTDESK_NOTIFICATION_CUE_STATE ]] || return 1
      assert_equal "$MAKO_EXPECTED_CUE_STATE" "$(<"$RUSTDESK_NOTIFICATION_CUE_STATE")" \
        'cue state exists before cue mode activation'
      MAKO_CUE_ORDER_CHECKED=true
    fi
    if [[ $MAKO_FAIL == remove-cue && ${arguments[index]} == -r && \
      ${arguments[index + 1]} == rustdesk-cue ]]; then
      return 1
    fi
  done
  [[ $MAKO_FAIL != apply ]]
}

monitor() {
  local id=$1
  local name=$2
  local x=$3
  local y=$4
  local focused=$5
  local disabled=${6:-false}
  local dpms_status=${7:-true}

  jq -nc \
    --argjson id "$id" \
    --arg name "$name" \
    --argjson x "$x" \
    --argjson y "$y" \
    --argjson focused "$focused" \
    --argjson disabled "$disabled" \
    --argjson dpms_status "$dpms_status" \
    '{id: $id, name: $name, x: $x, y: $y, width: 1920, height: 1080,
      focused: $focused, disabled: $disabled, dpmsStatus: $dpms_status}'
}

monitors() {
  jq -sc '.'
}

client() {
  local monitor_id=$1
  local mapped=$2
  local visible=$3
  local class=${4:-RustDesk}
  local title=${5:-Remote\ Desktop}

  jq -nc \
    --argjson monitor "$monitor_id" \
    --argjson mapped "$mapped" \
    --argjson visible "$visible" \
    --arg class "$class" \
    --arg title "$title" \
    '{monitor: $monitor, mapped: $mapped, visible: $visible, class: $class, title: $title}'
}

clients() {
  jq -sc '.'
}

# The watcher must define functions but not enter its event loop when sourced.
# shellcheck source=../watch-rustdesk-submap.sh
source "$WATCHER"

TEST_RUNTIME_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_RUNTIME_DIR"' EXIT
export XDG_RUNTIME_DIR="$TEST_RUNTIME_DIR"
export RUSTDESK_NOTIFICATION_CUE_STATE="$TEST_RUNTIME_DIR/rustdesk-notification-cue"
MAKO_LOG="$TEST_RUNTIME_DIR/makoctl.log"
HYPR_LOG="$TEST_RUNTIME_DIR/hyprctl.log"
HYPR_FAIL=false
HYPR_MONITORS_JSON='[]'
HYPR_CLIENTS_JSON='[]'

hyprctl() {
  case "$1 ${2:-}" in
    'monitors -j')
      [[ $HYPR_FAIL != monitors ]] || return 1
      printf '%s\n' "$HYPR_MONITORS_JSON"
      ;;
    'clients -j')
      [[ $HYPR_FAIL != clients ]] || return 1
      printf '%s\n' "$HYPR_CLIENTS_JSON"
      ;;
    'eval '*) printf '%s\n' "$*" >>"$HYPR_LOG" ;;
    *) fail "unexpected hyprctl invocation: $*" ;;
  esac
}

reset_mako

MONITORS_HDMI_FOCUSED=$(printf '%s\n' \
  "$(monitor 1 DVI-D-1 0 0 false)" \
  "$(monitor 2 HDMI-A-1 1920 0 true)" \
  "$(monitor 3 DP-2 3840 0 false)" | monitors)
MONITORS_DVI_FOCUSED_WITH_DP_ONLY_SAFE=$(printf '%s\n' \
  "$(monitor 1 DVI-D-1 0 0 true)" \
  "$(monitor 2 HDMI-A-1 1920 0 false true)" \
  "$(monitor 3 DP-2 3840 0 false)" | monitors)
MONITORS_VERTICAL_DOWN=$(printf '%s\n' \
  "$(monitor 1 DVI-D-1 0 0 true)" \
  "$(monitor 2 HDMI-A-1 0 1080 false)" \
  "$(monitor 3 DP-2 1920 0 false)" | monitors)
MONITORS_VERTICAL_UP=$(printf '%s\n' \
  "$(monitor 1 DVI-D-1 0 1080 true)" \
  "$(monitor 2 HDMI-A-1 0 0 false)" \
  "$(monitor 3 DP-2 1920 0 false)" | monitors)
MONITORS_DP_FOCUSED=$(printf '%s\n' \
  "$(monitor 1 DVI-D-1 0 0 false)" \
  "$(monitor 2 HDMI-A-1 1920 0 false)" \
  "$(monitor 3 DP-2 3840 0 true)" | monitors)
MONITORS_TIE_BREAK=$(printf '%s\n' \
  "$(monitor 1 DVI-D-1 100 100 true)" \
  "$(monitor 2 HDMI-A-1 20 100 false)" \
  "$(monitor 3 DP-2 40 900 false)" | monitors)
MONITORS_TIE_BREAK_Y=$(printf '%s\n' \
  "$(monitor 1 DVI-D-1 100 100 true)" \
  "$(monitor 2 HDMI-A-1 20 100 false)" \
  "$(monitor 3 DP-2 20 900 false)" | monitors)
MONITORS_TIE_BREAK_NAME=$(printf '%s\n' \
  "$(monitor 1 DVI-D-1 100 100 true)" \
  "$(monitor 2 HDMI-A-1 20 100 false)" \
  "$(monitor 3 DP-2 20 100 false)" | monitors)
MONITORS_INACTIVE=$(printf '%s\n' \
  "$(monitor 1 DVI-D-1 0 0 true)" \
  "$(monitor 2 HDMI-A-1 1920 0 false true)" \
  "$(monitor 3 DP-2 3840 0 false false false)" \
  "$(monitor 4 UNKNOWN-1 5760 0 false)" | monitors)
MONITORS_ANTOINEWS=$(printf '%s\n' \
  "$(monitor 11 USB-C-42 0 0 true)" \
  "$(monitor 12 HDMI-9 1920 0 false)" \
  "$(monitor 13 VGA-77 3840 0 false true)" | monitors)
MONITORS_UNKNOWN=$(printf '%s\n' \
  "$(monitor 21 USB-C-77 0 0 true)" \
  "$(monitor 22 eDP-99 1920 0 false)" \
  "$(monitor 23 DP-UNKNOWN 3840 0 false false false)" | monitors)

RUSTDESK_ON_HDMI=$(client 2 true true | clients)
RUSTDESK_ON_DVI=$(client 1 true true | clients)
RUSTDESK_ON_ALL=$(printf '%s\n' \
  "$(client 1 true true)" \
  "$(client 2 true true)" \
  "$(client 3 true true)" | clients)
RUSTDESK_ON_ARBITRARY=$(client 11 true true | clients)
HIDDEN_RUSTDESK_ON_DP=$(client 3 true false | clients)
UNMAPPED_RUSTDESK_ON_HDMI=$(client 2 false true | clients)
NON_RUSTDESK_ON_HDMI=$(client 2 true true AnyDesk 'Remote Desktop' | clients)
WRONG_TITLE_RUSTDESK_ON_HDMI=$(client 2 true true RustDesk 'File Transfer' | clients)

assert_equal 'rustdesk-route-HDMI-A-1|none|none' \
  "$(notification_route_state "$MONITORS_HDMI_FOCUSED" '[]')" \
  'focused safe output'

assert_equal 'rustdesk-route-HDMI-A-1|none|none' \
  "$(notification_route_state "$MONITORS_HDMI_FOCUSED" "$UNMAPPED_RUSTDESK_ON_HDMI")" \
  'unmapped RustDesk does not exclude focused output'

assert_equal 'rustdesk-route-HDMI-A-1|none|none' \
  "$(notification_route_state "$MONITORS_HDMI_FOCUSED" "$NON_RUSTDESK_ON_HDMI")" \
  'non-RustDesk client does not exclude focused output'

assert_equal 'rustdesk-route-HDMI-A-1|none|none' \
  "$(notification_route_state "$MONITORS_HDMI_FOCUSED" "$WRONG_TITLE_RUSTDESK_ON_HDMI")" \
  'non-Remote-Desktop RustDesk window does not exclude focused output'

assert_equal 'rustdesk-route-DVI-D-1|HDMI-A-1|left' \
  "$(notification_route_state "$MONITORS_HDMI_FOCUSED" "$RUSTDESK_ON_HDMI")" \
  'RustDesk focus routes left'

assert_equal 'rustdesk-route-DP-2|DVI-D-1|right' \
  "$(notification_route_state "$MONITORS_DVI_FOCUSED_WITH_DP_ONLY_SAFE" "$RUSTDESK_ON_DVI")" \
  'RustDesk focus routes right'

assert_equal 'rustdesk-route-HDMI-A-1|DVI-D-1|down' \
  "$(notification_route_state "$MONITORS_VERTICAL_DOWN" "$RUSTDESK_ON_DVI")" \
  'vertical destination routes down'

assert_equal 'rustdesk-route-HDMI-A-1|DVI-D-1|up' \
  "$(notification_route_state "$MONITORS_VERTICAL_UP" "$RUSTDESK_ON_DVI")" \
  'vertical destination routes up'

assert_equal 'rustdesk-route-hidden|DP-2|none' \
  "$(notification_route_state "$MONITORS_DP_FOCUSED" "$RUSTDESK_ON_ALL")" \
  'all occupied hides real notification'

assert_equal 'rustdesk-route-DP-2|none|none' \
  "$(notification_route_state "$MONITORS_DP_FOCUSED" "$HIDDEN_RUSTDESK_ON_DP")" \
  'hidden-workspace RustDesk does not exclude output'

assert_equal 'rustdesk-route-HDMI-A-1|DVI-D-1|left' \
  "$(notification_route_state "$MONITORS_TIE_BREAK" "$RUSTDESK_ON_DVI")" \
  'safe-output tie breaks by X'

assert_equal 'rustdesk-route-HDMI-A-1|DVI-D-1|left' \
  "$(notification_route_state "$MONITORS_TIE_BREAK_Y" "$RUSTDESK_ON_DVI")" \
  'safe-output tie breaks by Y'

assert_equal 'rustdesk-route-DP-2|DVI-D-1|left' \
  "$(notification_route_state "$MONITORS_TIE_BREAK_NAME" "$RUSTDESK_ON_DVI")" \
  'safe-output tie breaks by output name'

assert_equal 'rustdesk-route-hidden|DVI-D-1|none' \
  "$(notification_route_state "$MONITORS_INACTIVE" "$RUSTDESK_ON_DVI")" \
  'unknown disabled and DPMS-off outputs cannot replace an excluded focused output'

assert_equal 'HDMI-9' \
  "$(rightmost_monitor_from_json "$MONITORS_ANTOINEWS")" \
  'antoinews arbitrary rightmost monitor'

assert_equal 'eDP-99' \
  "$(rightmost_monitor_from_json "$MONITORS_UNKNOWN")" \
  'unknown arbitrary rightmost active monitor'

assert_equal 'rustdesk-route-hidden|none|none' \
  "$(notification_route_state "$MONITORS_ANTOINEWS" "$RUSTDESK_ON_ARBITRARY")" \
  'unknown connector notification route is hidden'

# Removing or adding a watcher-owned route must never remove unrelated Mako modes.
reset_mako
MAKO_EXPECTED_CUE_STATE='DP-2|left'
apply_notification_route_state 'rustdesk-route-DVI-D-1|DP-2|left'
assert_equal 'DP-2|left' "$(<"$RUSTDESK_NOTIFICATION_CUE_STATE")" 'cue state'
assert_equal true "$MAKO_CUE_ORDER_CHECKED" 'cue state is written before cue activation'
assert_log_contains '-r rustdesk-route-DVI-D-1'
assert_log_contains '-r rustdesk-route-HDMI-A-1'
assert_log_contains '-r rustdesk-route-DP-2'
assert_log_contains '-r rustdesk-route-hidden'
assert_log_contains '-r rustdesk-cue'
assert_log_contains '-a rustdesk-route-DVI-D-1'
assert_log_contains '-a rustdesk-cue'
if [[ $(<"$MAKO_LOG") == *'-r default'* || $(<"$MAKO_LOG") == *'-r do-not-disturb'* ]]; then
  fail 'unrelated Mako modes were removed'
fi

# Hidden routing retains a cue but must not activate an output route.
reset_mako
MAKO_EXPECTED_CUE_STATE='DP-2|none'
apply_notification_route_state 'rustdesk-route-hidden|DP-2|none'
assert_equal 'DP-2|none' "$(<"$RUSTDESK_NOTIFICATION_CUE_STATE")" 'hidden cue state'
assert_log_contains '-a rustdesk-route-hidden'
assert_log_contains '-a rustdesk-cue'
if [[ $(<"$MAKO_LOG") == *'-a rustdesk-route-DVI-D-1'* || \
  $(<"$MAKO_LOG") == *'-a rustdesk-route-HDMI-A-1'* || \
  $(<"$MAKO_LOG") == *'-a rustdesk-route-DP-2'* ]]; then
  fail 'hidden routing activated a safe route'
fi

# Cue removal follows a successful Mako update, so a failed update remains retryable.
reset_mako
printf 'DP-2|left' >"$RUSTDESK_NOTIFICATION_CUE_STATE"
apply_notification_route_state 'rustdesk-route-DVI-D-1|none|none'
[[ ! -e $RUSTDESK_NOTIFICATION_CUE_STATE ]] || fail 'cue state survived successful removal'
assert_log_contains '-r rustdesk-cue'

# A failed cue disable must retain the last usable cue state for retry.
reset_mako
printf 'DP-2|left' >"$RUSTDESK_NOTIFICATION_CUE_STATE"
MAKO_FAIL=remove-cue
if apply_notification_route_state 'rustdesk-route-DVI-D-1|none|none'; then
  fail 'failed cue disable returned success'
fi
assert_equal 'DP-2|left' "$(<"$RUSTDESK_NOTIFICATION_CUE_STATE")" \
  'cue state survives failed cue disable'
MAKO_FAIL=false

# No Mako mutation is needed when live Mako modes and the cue file already agree.
reset_mako $'default\ndo-not-disturb\nrustdesk-route-DVI-D-1\nrustdesk-cue'
printf 'DP-2|left' >"$RUSTDESK_NOTIFICATION_CUE_STATE"
apply_notification_route_state 'rustdesk-route-DVI-D-1|DP-2|left'
assert_log_empty

# A Mako failure must return an error and leave the persisted cue state for retry.
reset_mako
MAKO_EXPECTED_CUE_STATE='DP-2|left'
MAKO_FAIL=apply
if apply_notification_route_state 'rustdesk-route-DVI-D-1|DP-2|left'; then
  fail 'Mako application failure returned success'
fi
assert_equal 'DP-2|left' "$(<"$RUSTDESK_NOTIFICATION_CUE_STATE")" 'cue state survives failed apply'
MAKO_FAIL=false

# A Mako mode-read failure cannot mutate either Mako modes or the cue state.
reset_mako
printf 'DP-2|left' >"$RUSTDESK_NOTIFICATION_CUE_STATE"
MAKO_FAIL='read'
if apply_notification_route_state 'rustdesk-route-DVI-D-1|none|none'; then
  fail 'Mako mode-read failure returned success'
fi
assert_log_empty
assert_equal 'DP-2|left' "$(<"$RUSTDESK_NOTIFICATION_CUE_STATE")" \
  'cue state survives Mako mode-read failure'
MAKO_FAIL=false

# Live Mako state, rather than an in-memory cache, drives restart recovery.
reset_mako
MAKO_EXPECTED_CUE_STATE='DP-2|left'
apply_notification_route_state 'rustdesk-route-DVI-D-1|DP-2|left'
assert_log_contains '-a rustdesk-route-DVI-D-1'

for routing_event in \
  'openwindow>>abc' \
  'closewindow>>abc' \
  'movewindow>>abc,1' \
  'movewindowv2>>abc,1,1' \
  'windowtitle>>abc' \
  'windowtitlev2>>abc,Remote Desktop' \
  'activewindow>>RustDesk,Remote Desktop' \
  'activewindowv2>>abc' \
  'minimized>>abc,1' \
  'workspace>>1' \
  'workspacev2>>1,1' \
  'focusedmon>>DP-2,1' \
  'focusedmonv2>>DP-2,1' \
  'monitoradded>>DP-2' \
  'monitoraddedv2>>3,DP-2,DisplayPort' \
  'monitorremoved>>DP-2' \
  'monitorremovedv2>>3,DP-2,DisplayPort' \
  'moveworkspace>>1,DP-2' \
  'moveworkspacev2>>1,1,DP-2' \
  'activespecial>>special:scratch,DP-2' \
  'activespecialv2>>-99,special:scratch,DP-2' \
  'fullscreen>>1' \
  'pin>>abc,1' \
  'togglegroup>>1,abc' \
  'moveintogroup>>abc' \
  'moveoutofgroup>>abc' \
  'configreloaded>>'; do
  is_notification_routing_event "$routing_event" || \
    fail "${routing_event%%>>*} must reconcile routing"
done
if is_notification_routing_event 'activelayout>>keyboard,us'; then
  fail 'unrelated events must not reconcile routing'
fi

# Unavailable or malformed Hyprland state must fail closed to the hidden route.
reset_mako
HYPR_FAIL=monitors
if reconcile_notification_routing; then
  fail 'failed Hyprland state reconciliation returned success'
fi
assert_log_contains '-a rustdesk-route-hidden'
HYPR_FAIL=false

reset_mako
HYPR_MONITORS_JSON='{malformed'
HYPR_CLIENTS_JSON='[]'
if reconcile_notification_routing; then
  fail 'malformed Hyprland state reconciliation returned success'
fi
assert_log_contains '-a rustdesk-route-hidden'
HYPR_MONITORS_JSON='[]'

# Handler state is explicit, persists across events, and does not affect movement.
reset_mako
: >"$HYPR_LOG"
handler_clean_state=false
handle_hyprland_event 'activewindow>>RustDesk,Remote Desktop' handler_clean_state
assert_equal true "$handler_clean_state" 'clean-submap state after RustDesk focus'
handle_hyprland_event 'activewindow>>Firefox,Example' handler_clean_state
assert_equal false "$handler_clean_state" 'clean-submap state after focus leaves RustDesk'
assert_equal $'eval hl.dispatch(hl.dsp.submap("clean"))\neval hl.dispatch(hl.dsp.submap("reset"))' \
  "$(<"$HYPR_LOG")" 'clean-submap transitions persist across event iterations'

# Only the incoming connection manager is hidden; ordinary RustDesk windows stay visible.
: >"$HYPR_LOG"
handle_hyprland_event \
  'openwindow>>c0ffee,9,rustdesk,1520351763 - RustDesk' handler_clean_state DP-2
assert_equal \
  'eval hl.dispatch(hl.dsp.window.move({workspace="special:rustdesk-cm", follow=false, window="address:0xc0ffee"}))' \
  "$(<"$HYPR_LOG")" 'RustDesk connection manager moves to its hidden workspace'

: >"$HYPR_LOG"
handle_hyprland_event \
  'openwindow>>decaf,9,rustdesk,1520351763 - Remote Desktop - RustDesk' handler_clean_state DP-2
assert_equal '' "$(<"$HYPR_LOG")" 'ordinary RustDesk window remains visible'

: >"$HYPR_LOG"
HYPR_MONITORS_JSON='[{"name":"DP-2","x":3840,"y":0,"width":1920,"height":1080,"disabled":false,"dpmsStatus":true,"activeWorkspace":{"id":9}}]'
HYPR_CLIENTS_JSON='[
  {"class":"RustDesk","title":"Remote Desktop"},
  {"class":"RustDesk","title":"Remote Desktop"}
]'
handle_hyprland_event \
  'openwindow>>abc,1,RustDesk,Remote Desktop' handler_clean_state
assert_equal \
  'eval hl.dispatch(hl.dsp.window.move({workspace=9, follow=false, window="address:0xabc"}))' \
  "$(<"$HYPR_LOG")" 'second RustDesk window still moves to the configured monitor'

: >"$HYPR_LOG"
HYPR_MONITORS_JSON='[
  {"name":"USB-C-42","x":0,"y":0,"width":1920,"height":1080,"disabled":false,"dpmsStatus":true,"activeWorkspace":{"id":4}},
  {"name":"HDMI-9","x":1920,"y":0,"width":1920,"height":1080,"disabled":false,"dpmsStatus":true,"activeWorkspace":{"id":8}},
  {"name":"VGA-77","x":3840,"y":0,"width":1920,"height":1080,"disabled":true,"dpmsStatus":true,"activeWorkspace":{"id":12}}
]'
handle_hyprland_event \
  'openwindow>>def,1,RustDesk,Remote Desktop' handler_clean_state
assert_equal \
  'eval hl.dispatch(hl.dsp.window.move({workspace=8, follow=false, window="address:0xdef"}))' \
  "$(<"$HYPR_LOG")" 'second RustDesk window uses arbitrary rightmost monitor'

# Every newly connected stream reconciles before consuming events, including reconnects.
STREAM_LOG="$TEST_RUNTIME_DIR/stream.log"
: >"$STREAM_LOG"
(
  reconcile_notification_routing() {
    printf 'reconcile\n' >>"$STREAM_LOG"
  }
  stream_clean_state=false
  consume_hyprland_event_stream stream_clean_state </dev/null
  consume_hyprland_event_stream stream_clean_state </dev/null
)
assert_equal $'reconcile\nreconcile' "$(<"$STREAM_LOG")" \
  'initial and reconnected streams reconcile immediately'

# Stream termination waits before the next connection attempt instead of looping.
: >"$STREAM_LOG"
set +e
(
  consume_hyprland_event_stream() {
    printf 'connect\n' >>"$STREAM_LOG"
  }
  sleep() {
    printf 'sleep:%s\n' "$1" >>"$STREAM_LOG"
    exit 23
  }
  reconnect_clean_state=false
  HYPRLAND_EVENT_RECONNECT_DELAY=2
  watch_hyprland_events true /unused reconnect_clean_state
)
watch_status=$?
set -e
((watch_status == 23)) || fail "watch loop exited unexpectedly: $watch_status"
assert_equal $'connect\nsleep:2' "$(<"$STREAM_LOG")" \
  'terminated event stream uses the bounded reconnect delay'

# An idle connected stream periodically reconciles and exits normally on EOF.
: >"$STREAM_LOG"
(
  reconcile_notification_routing() {
    printf 'reconcile\n' >>"$STREAM_LOG"
  }
  stream_clean_state=false
  NOTIFICATION_RECONCILE_INTERVAL=1
  consume_hyprland_event_stream stream_clean_state < <(sleep 1.1)
)
mapfile -t stream_reconciliations <"$STREAM_LOG"
(( ${#stream_reconciliations[@]} >= 2 )) || \
  fail 'idle event stream did not reconcile periodically'

# Unrelated event traffic cannot postpone periodic recovery indefinitely.
: >"$STREAM_LOG"
(
  reconcile_notification_routing() {
    printf 'reconcile\n' >>"$STREAM_LOG"
  }
  busy_stream_clean_state=false
  NOTIFICATION_RECONCILE_INTERVAL=1
  consume_hyprland_event_stream busy_stream_clean_state < <(
    for _ in 1 2 3 4 5; do
      sleep 0.3
      printf 'activelayout>>keyboard,us\n'
    done
  )
)
mapfile -t busy_stream_reconciliations <"$STREAM_LOG"
(( ${#busy_stream_reconciliations[@]} >= 2 )) || \
  fail 'busy event stream postponed periodic reconciliation indefinitely'

# A failed startup/event reconciliation cannot stop the existing RustDesk handler.
reset_mako
: >"$HYPR_LOG"
MAKO_FAIL=apply
HYPR_MONITORS_JSON='[]'
HYPR_CLIENTS_JSON='[]'
handler_clean_state=false
consume_hyprland_event_stream handler_clean_state <<'EOF'
workspace>>1
activewindow>>RustDesk,Remote Desktop
EOF
assert_equal $'eval hl.dispatch(hl.dsp.submap("clean"))' "$(<"$HYPR_LOG")" \
  'RustDesk active-window handler continues after reconciliation failure'
assert_equal true "$handler_clean_state" \
  'handler state survives reconciliation failures and event iterations'
MAKO_FAIL=false

printf 'PASS: watch-rustdesk-submap route and reconciliation tests\n'
