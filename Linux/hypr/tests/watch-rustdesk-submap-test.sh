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

assert_route_payload() {
  local expected=$1
  local actual

  [[ -f $NOTIFICATION_ROUTE_FILE ]] || fail "notification route file is missing: $NOTIFICATION_ROUTE_FILE"
  if ! actual=$(jq -c 'del(.updatedAt)' "$NOTIFICATION_ROUTE_FILE"); then
    fail "notification route file is not valid JSON: $NOTIFICATION_ROUTE_FILE"
  fi
  assert_equal "$expected" "$actual" 'notification route payload'
}

assert_lease_payload() {
  local expected=$1
  local actual

  [[ -f $NOTIFICATION_LEASE_FILE ]] || fail "notification lease is missing: $NOTIFICATION_LEASE_FILE"
  if ! actual=$(jq -c . "$NOTIFICATION_LEASE_FILE"); then
    fail "notification lease is not valid JSON: $NOTIFICATION_LEASE_FILE"
  fi
  assert_equal "$expected" "$actual" 'notification lease payload'
}

assert_file_mode() {
  local expected=$1
  local path=$2
  local actual

  if ! actual=$(stat -c '%a' -- "$path"); then
    fail "could not inspect mode for $path"
  fi
  assert_equal "${expected#0}" "${actual#0}" "mode for $path"
}

assert_file_owner() {
  local expected=$1
  local path=$2
  local actual

  if ! actual=$(stat -c '%u' -- "$path"); then
    fail "could not inspect owner for $path"
  fi
  assert_equal "$expected" "$actual" "owner for $path"
}

assert_lease_contract() {
  assert_file_owner "$UID" "$NOTIFICATION_LEASE_FILE"
  assert_file_mode 0600 "$NOTIFICATION_LEASE_FILE"
  [[ ! -L $NOTIFICATION_LEASE_FILE ]] || fail 'notification lease is a symlink'
  if compgen -G "$NOTIFICATION_ROUTE_DIR/.notification-route-lease.json.*" >/dev/null; then
    fail 'temporary notification lease file was not removed after rename'
  fi
}

route_updated_at() {
  jq -er '.updatedAt | select(type == "number" and (floor == .) and (. >= 0))' \
    "$NOTIFICATION_ROUTE_FILE"
}

fake_epoch_seconds=1786930000

epoch_seconds() {
  printf '%s\n' "$fake_epoch_seconds"
}

assert_route_contract() {
  assert_file_owner "$UID" "$NOTIFICATION_ROUTE_DIR"
  assert_file_owner "$UID" "$NOTIFICATION_ROUTE_FILE"
  assert_file_mode 0700 "$NOTIFICATION_ROUTE_DIR"
  assert_file_mode 0600 "$NOTIFICATION_ROUTE_FILE"
  [[ ! -L $NOTIFICATION_ROUTE_FILE ]] || fail 'notification route file is a symlink'
  if compgen -G "$NOTIFICATION_ROUTE_DIR/.notification-route.json.*" >/dev/null; then
    fail 'temporary notification route file was not removed after rename'
  fi
}

reset_route_state() {
  rm -rf -- "$NOTIFICATION_ROUTE_DIR"
  NOTIFICATION_ROUTE_LAST_WRITE_SECONDS=-1
}

assert_mako_sentinel_empty() {
  [[ ! -s $MAKO_SENTINEL_LOG ]] || \
    fail "forbidden makoctl invocation: $(<"$MAKO_SENTINEL_LOG")"
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

TEST_RUNTIME_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_RUNTIME_DIR"' EXIT
export XDG_RUNTIME_DIR="$TEST_RUNTIME_DIR"
TEST_BIN="$TEST_RUNTIME_DIR/bin"
mkdir -p -- "$TEST_BIN"
MAKO_SENTINEL_LOG="$TEST_RUNTIME_DIR/makoctl.log"
export MAKO_SENTINEL_LOG
cat >"$TEST_BIN/makoctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MAKO_SENTINEL_LOG:?}"
printf 'FAIL: forbidden makoctl invocation: %s\n' "$*" >&2
exit 125
EOF
chmod 0700 -- "$TEST_BIN/makoctl"
unset -f makoctl 2>/dev/null || true
export PATH="$TEST_BIN:/usr/bin:/bin"

# The watcher must define functions but not enter its event loop when sourced.
# shellcheck source=../watch-rustdesk-submap.sh
source "$WATCHER"
assert_mako_sentinel_empty
fake_epoch_seconds=1786930000
epoch_seconds() {
  printf '%s\n' "$fake_epoch_seconds"
}
NOTIFICATION_RECONCILE_INTERVAL=30

NOTIFICATION_ROUTE_DIR="$TEST_RUNTIME_DIR/desktop-shell"
NOTIFICATION_ROUTE_FILE="$NOTIFICATION_ROUTE_DIR/notification-route.json"
NOTIFICATION_LEASE_FILE="$NOTIFICATION_ROUTE_DIR/notification-route-lease.json"
ROUTE_RENAME_FAIL=false
ROUTE_INTERRUPT=false
LEASE_RENAME_FAIL=false
ROUTE_POST_RENAME_CHMOD=''
LEASE_POST_RENAME_CHMOD=''
ROUTE_POST_RENAME_SYMLINK=false
LEASE_POST_RENAME_SYMLINK=false
HYPR_LOG="$TEST_RUNTIME_DIR/hyprctl.log"
HYPR_FAIL=false
HYPR_MONITORS_JSON='[]'
HYPR_CLIENTS_JSON='[]'

mv() {
  if [[ $ROUTE_INTERRUPT == true ]]; then
    kill -TERM "$BASHPID"
  fi
  local target=${!#}
  if [[ $ROUTE_RENAME_FAIL == true && $target == "$NOTIFICATION_ROUTE_FILE" ]]; then
    return 1
  fi
  if [[ $LEASE_RENAME_FAIL == true && $target == "$NOTIFICATION_LEASE_FILE" ]]; then
    return 1
  fi
  command mv "$@"
  if [[ $target == "$NOTIFICATION_ROUTE_FILE" ]]; then
    if [[ -n $ROUTE_POST_RENAME_CHMOD ]]; then
      command chmod "$ROUTE_POST_RENAME_CHMOD" -- "$target"
    fi
    if [[ $ROUTE_POST_RENAME_SYMLINK == true ]]; then
      local symlink_target="$TEST_RUNTIME_DIR/post-route-symlink-target"
      command mv -- "$target" "$symlink_target"
      command ln -s -- "$symlink_target" "$target"
    fi
  elif [[ $target == "$NOTIFICATION_LEASE_FILE" ]]; then
    if [[ -n $LEASE_POST_RENAME_CHMOD ]]; then
      command chmod "$LEASE_POST_RENAME_CHMOD" -- "$target"
    fi
    if [[ $LEASE_POST_RENAME_SYMLINK == true ]]; then
      local symlink_target="$TEST_RUNTIME_DIR/post-lease-symlink-target"
      command mv -- "$target" "$symlink_target"
      command ln -s -- "$symlink_target" "$target"
    fi
  fi
}

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

# A visible route with a directional cue publishes the exact route payload.
reset_route_state
write_notification_route_state 'rustdesk-route-DVI-D-1|HDMI-A-1|left'
assert_route_payload '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":"HDMI-A-1","direction":"left"}'
assert_route_contract
assert_lease_payload '{"version":1,"refreshedAt":1786930000,"expiresAt":1786930002,"routeUpdatedAt":1786930000}'
assert_lease_contract

# An unchanged route refreshes only the lease and leaves the route file in place.
first_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
first_lease_inode=$(stat -c '%i' -- "$NOTIFICATION_LEASE_FILE")
fake_epoch_seconds=1786930001
write_notification_route_state 'rustdesk-route-DVI-D-1|HDMI-A-1|left'
second_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
second_lease_inode=$(stat -c '%i' -- "$NOTIFICATION_LEASE_FILE")
assert_equal "$first_route_inode" "$second_route_inode" 'unchanged route keeps the existing file'
[[ $first_lease_inode != "$second_lease_inode" ]] || fail 'unchanged route did not refresh the lease'
assert_lease_payload '{"version":1,"refreshedAt":1786930001,"expiresAt":1786930003,"routeUpdatedAt":1786930000}'
assert_lease_contract
fake_epoch_seconds=1786930000

# An unchanged route is a no-op between reconciliation intervals.
first_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
first_updated_at=$(route_updated_at)
write_notification_route_state 'rustdesk-route-DVI-D-1|HDMI-A-1|left'
second_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
second_updated_at=$(route_updated_at)
assert_equal "$first_route_inode" "$second_route_inode" 'unchanged route keeps the existing file'
assert_equal "$first_updated_at" "$second_updated_at" 'unchanged route keeps its timestamp'
(( second_updated_at >= first_updated_at )) || fail 'route timestamp moved backwards'

# A fresh same-state route with insecure permissions is not eligible for a no-op.
chmod 0644 -- "$NOTIFICATION_ROUTE_FILE"
insecure_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
write_notification_route_state 'rustdesk-route-DVI-D-1|HDMI-A-1|left'
secure_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
[[ $secure_route_inode != "$insecure_route_inode" ]] || \
  fail 'insecure same-state route was not atomically replaced'
assert_route_contract

# A visible route without a cue uses null cue fields.
write_notification_route_state 'rustdesk-route-DVI-D-1|none|none'
assert_route_payload '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":null,"direction":null}'
assert_route_contract
changed_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
[[ $changed_route_inode != "$second_route_inode" ]] || fail 'changed route did not atomically replace the file'
changed_updated_at=$(route_updated_at)
(( changed_updated_at >= second_updated_at )) || fail 'changed route timestamp moved backwards'

# Hidden routing keeps the cue output while hiding notification cards.
reset_route_state
write_notification_route_state 'rustdesk-route-hidden|DP-2|none'
assert_route_payload '{"version":1,"visible":false,"output":null,"cueOutput":"DP-2","direction":null}'
assert_route_contract

# A stale unchanged route is rewritten so the service staleness gate stays healthy.
stale_route=$(jq -c --argjson updated_at 1 '.updatedAt = $updated_at' "$NOTIFICATION_ROUTE_FILE")
printf '%s\n' "$stale_route" >"$TEST_RUNTIME_DIR/stale-route"
chmod 0600 "$TEST_RUNTIME_DIR/stale-route"
mv "$TEST_RUNTIME_DIR/stale-route" "$NOTIFICATION_ROUTE_FILE"
stale_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
NOTIFICATION_ROUTE_LAST_WRITE_SECONDS=$((SECONDS - NOTIFICATION_ROUTE_REWRITE_INTERVAL - 1))
stale_publish_before=$(epoch_seconds)
write_notification_route_state 'rustdesk-route-hidden|DP-2|none'
stale_publish_after=$(epoch_seconds)
fresh_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
[[ $fresh_route_inode != "$stale_route_inode" ]] || fail 'stale route was not rewritten'
assert_route_payload '{"version":1,"visible":false,"output":null,"cueOutput":"DP-2","direction":null}'
assert_route_contract
fresh_updated_at=$(route_updated_at)
(( fresh_updated_at > 1 )) || fail 'rewritten route timestamp did not advance'
(( fresh_updated_at >= stale_publish_before && fresh_updated_at <= stale_publish_after )) || \
  fail "rewritten route timestamp is not current: $fresh_updated_at"

# A future timestamp must not suppress an overdue rewrite or move backwards.
future_timestamp=$((fresh_updated_at + 3600))
future_route=$(jq -c --argjson updated_at "$future_timestamp" '.updatedAt = $updated_at' \
  "$NOTIFICATION_ROUTE_FILE")
printf '%s\n' "$future_route" >"$TEST_RUNTIME_DIR/future-route"
chmod 0600 -- "$TEST_RUNTIME_DIR/future-route"
mv "$TEST_RUNTIME_DIR/future-route" "$NOTIFICATION_ROUTE_FILE"
future_route_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
NOTIFICATION_ROUTE_LAST_WRITE_SECONDS=$((SECONDS - NOTIFICATION_ROUTE_REWRITE_INTERVAL - 1))
write_notification_route_state 'rustdesk-route-hidden|DP-2|none'
future_refreshed_inode=$(stat -c '%i' -- "$NOTIFICATION_ROUTE_FILE")
future_refreshed=$(route_updated_at)
[[ $future_refreshed_inode != "$future_route_inode" ]] || \
  fail 'future timestamp suppressed an overdue route rewrite'
(( future_refreshed >= future_timestamp )) || \
  fail 'future route timestamp moved backwards'
assert_route_contract

# A failed atomic rename preserves the prior valid route file.
prior_route=$(<"$NOTIFICATION_ROUTE_FILE")
ROUTE_RENAME_FAIL=true
if write_notification_route_state 'rustdesk-route-DVI-D-1|none|none' 2>/dev/null; then
  fail 'failed route rename returned success'
fi
ROUTE_RENAME_FAIL=false
assert_equal "$prior_route" "$(<"$NOTIFICATION_ROUTE_FILE")" \
  'failed route write preserves the prior valid file'
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'failed route write left a lease file behind'
assert_route_payload '{"version":1,"visible":false,"output":null,"cueOutput":"DP-2","direction":null}'

# A failed lease rename invalidates the lease while preserving the route file.
write_notification_route_state 'rustdesk-route-hidden|DP-2|none'
prior_route=$(<"$NOTIFICATION_ROUTE_FILE")
LEASE_RENAME_FAIL=true
if write_notification_route_state 'rustdesk-route-DVI-D-1|none|none' 2>/dev/null; then
  fail 'failed lease rename returned success'
fi
LEASE_RENAME_FAIL=false
assert_route_payload '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":null,"direction":null}'
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'failed lease write left a lease file behind'

# Post-rename route verification rejects insecure metadata and invalidates the lease.
write_notification_route_state 'rustdesk-route-hidden|DP-2|none'
ROUTE_POST_RENAME_CHMOD=0644
if write_notification_route_state 'rustdesk-route-DVI-D-1|none|none' 2>/dev/null; then
  fail 'post-rename insecure route metadata returned success'
fi
ROUTE_POST_RENAME_CHMOD=''
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'insecure post-rename route metadata left a lease file behind'

# Post-rename lease verification rejects insecure metadata.
write_notification_route_state 'rustdesk-route-hidden|DP-2|none'
LEASE_POST_RENAME_CHMOD=0644
if write_notification_route_state 'rustdesk-route-DVI-D-1|none|none' 2>/dev/null; then
  fail 'post-rename insecure lease metadata returned success'
fi
LEASE_POST_RENAME_CHMOD=''
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'insecure post-rename lease metadata left a lease file behind'

# Post-rename route verification rejects symlink replacement and invalidates the lease.
write_notification_route_state 'rustdesk-route-hidden|DP-2|none'
ROUTE_POST_RENAME_SYMLINK=true
if write_notification_route_state 'rustdesk-route-DVI-D-1|none|none' 2>/dev/null; then
  fail 'post-rename route symlink returned success'
fi
ROUTE_POST_RENAME_SYMLINK=false
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'post-rename route symlink left a lease file behind'

# A symlinked route directory is rejected before publication.
reset_route_state
mkdir -p -- "$TEST_RUNTIME_DIR/lease-target"
ln -s -- "$TEST_RUNTIME_DIR/lease-target" "$NOTIFICATION_ROUTE_DIR"
if write_notification_route_state 'rustdesk-route-DVI-D-1|HDMI-A-1|left' 2>/dev/null; then
  fail 'symlinked route directory was accepted'
fi
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'symlinked route directory created a lease'
[[ ! -e $NOTIFICATION_ROUTE_FILE ]] || fail 'symlinked route directory created a route file'

# Cleanup removes the lease and publishes hidden state without recreating the lease.
reset_route_state
write_notification_route_state 'rustdesk-route-DVI-D-1|HDMI-A-1|left'
cleanup_notification_route_state
assert_route_payload '{"version":1,"visible":false,"output":null,"cueOutput":null,"direction":null}'
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'cleanup recreated the lease'
assert_route_contract
if compgen -G "$NOTIFICATION_ROUTE_DIR/.notification-route.json.*" >/dev/null; then
  fail 'cleanup left a temporary notification route file behind'
fi

# Cleanup still removes the lease when the route directory is insecure.
reset_route_state
write_notification_route_state 'rustdesk-route-DVI-D-1|HDMI-A-1|left'
visible_route_before_cleanup=$(<"$NOTIFICATION_ROUTE_FILE")
chmod 0755 -- "$NOTIFICATION_ROUTE_DIR"
cleanup_notification_route_state
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'cleanup through insecure directory recreated the lease'
assert_equal "$visible_route_before_cleanup" "$(<"$NOTIFICATION_ROUTE_FILE")" \
  'cleanup through insecure directory should not republish the route'

# Cleanup still removes the lease when the route directory is symlinked.
reset_route_state
write_notification_route_state 'rustdesk-route-DVI-D-1|HDMI-A-1|left'
visible_route_before_cleanup=$(<"$NOTIFICATION_ROUTE_FILE")
mv -- "$NOTIFICATION_ROUTE_DIR" "$TEST_RUNTIME_DIR/cleanup-route-target"
ln -s -- "$TEST_RUNTIME_DIR/cleanup-route-target" "$NOTIFICATION_ROUTE_DIR"
cleanup_notification_route_state
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'cleanup through symlink directory recreated the lease'
assert_equal "$visible_route_before_cleanup" "$(<"$NOTIFICATION_ROUTE_FILE")" \
  'cleanup through symlink directory should not republish the route'

# An interruption after mktemp must clean only the publisher's temporary file.
reset_route_state
write_notification_route_state 'rustdesk-route-hidden|DP-2|none'
prior_interrupted_route=$(<"$NOTIFICATION_ROUTE_FILE")
set +e
(
  ROUTE_INTERRUPT=true
  write_notification_route_state 'rustdesk-route-DVI-D-1|none|none' 2>/dev/null
)
interrupt_status=$?
set -e
((interrupt_status == 143)) || fail "interrupted route publisher exited unexpectedly: $interrupt_status"
assert_equal "$prior_interrupted_route" "$(<"$NOTIFICATION_ROUTE_FILE")" \
  'interrupted route publication preserves the prior valid file'
if compgen -G "$NOTIFICATION_ROUTE_DIR/.notification-route.json.*" >/dev/null; then
  fail 'interrupted route publication left a temporary file'
fi
write_notification_route_state 'rustdesk-route-hidden|DP-2|none'
assert_route_contract

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
reset_route_state
HYPR_FAIL=monitors
if reconcile_notification_routing 2>/dev/null; then
  fail 'failed Hyprland state reconciliation returned success'
fi
assert_route_payload '{"version":1,"visible":false,"output":null,"cueOutput":null,"direction":null}'
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'failed Hyprland state reconciliation refreshed the lease'
HYPR_FAIL=false

reset_route_state
HYPR_MONITORS_JSON='{malformed'
HYPR_CLIENTS_JSON='[]'
if reconcile_notification_routing 2>/dev/null; then
  fail 'malformed Hyprland state reconciliation returned success'
fi
assert_route_payload '{"version":1,"visible":false,"output":null,"cueOutput":null,"direction":null}'
[[ ! -e $NOTIFICATION_LEASE_FILE ]] || fail 'malformed Hyprland state reconciliation refreshed the lease'
HYPR_MONITORS_JSON='[]'

# Handler state is explicit, persists across events, and does not affect movement.
reset_route_state
: >"$HYPR_LOG"
handler_clean_state=false
handle_hyprland_event 'activewindow>>RustDesk,Remote Desktop' handler_clean_state
assert_equal true "$handler_clean_state" 'clean-submap state after RustDesk focus'
handle_hyprland_event 'activewindow>>Firefox,Example' handler_clean_state
assert_equal false "$handler_clean_state" 'clean-submap state after focus leaves RustDesk'
assert_equal $'eval hl.dispatch(hl.dsp.submap("clean"))\neval hl.dispatch(hl.dsp.submap("reset"))' \
  "$(<"$HYPR_LOG")" 'clean-submap transitions persist across event iterations'

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

# Configured reconciliation intervals cannot exceed the route freshness budget.
NOTIFICATION_ROUTE_LAST_WRITE_SECONDS=-1
: >"$STREAM_LOG"
(
  reconcile_notification_routing() {
    printf 'reconcile\n' >>"$STREAM_LOG"
  }
  read() {
    printf 'read-timeout:%s\n' "$3" >>"$STREAM_LOG"
    return 1
  }
  bounded_clean_state=false
  NOTIFICATION_RECONCILE_INTERVAL=120
  consume_hyprland_event_stream bounded_clean_state </dev/null
)
assert_equal $'reconcile\nread-timeout:30' "$(<"$STREAM_LOG")" \
  'long reconciliation interval is bounded to 30 seconds'

# An off-cadence event write schedules the next refresh from its successful write.
reset_route_state
: >"$STREAM_LOG"
(
  fake_monotonic_seconds=0
  monotonic_seconds() {
    printf '%s\n' "$fake_monotonic_seconds"
  }
  reconcile_count=0
  reconcile_notification_routing() {
    local reconcile_seconds=$fake_monotonic_seconds
    ((reconcile_count += 1))
    case $reconcile_count in
      1) write_notification_route_state 'rustdesk-route-HDMI-A-1|none|none' ;;
      *) write_notification_route_state 'rustdesk-route-DVI-D-1|none|none' ;;
    esac
    printf 'reconcile:%s:%s:%s\n' "$reconcile_count" "$reconcile_seconds" \
      "$NOTIFICATION_ROUTE_LAST_WRITE_SECONDS" >>"$STREAM_LOG"
  }
  read_count=0
  read() {
    if [[ ${2:-} != -t ]]; then
      builtin read -r "${@:2}"
      return
    fi
    if ((read_count == 0)); then
      read_count=1
      printf -v "$4" '%s' 'workspace>>1'
      fake_monotonic_seconds=1
      return 0
    fi
    if ((read_count == 1)); then
      read_count=2
      fake_monotonic_seconds=$((fake_monotonic_seconds + $3))
      return 142
    fi
    return 1
  }
  event_clean_state=false
  consume_hyprland_event_stream event_clean_state </dev/null
)
assert_equal $'reconcile:1:0:0\nreconcile:2:1:1\nreconcile:3:31:31' \
  "$(<"$STREAM_LOG")" \
  'off-cadence event write receives a refresh at age 30 seconds'

# A deadline-driven interval-29 no-op must retry at write age 30, not age 58.
reset_route_state
: >"$STREAM_LOG"
(
  fake_monotonic_seconds=0
  monotonic_seconds() {
    printf '%s\n' "$fake_monotonic_seconds"
  }
  reconcile_count=0
  reconcile_notification_routing() {
    local reconcile_seconds=$fake_monotonic_seconds
    ((reconcile_count += 1))
    case $reconcile_count in
      1) write_notification_route_state 'rustdesk-route-HDMI-A-1|none|none' ;;
      *) write_notification_route_state 'rustdesk-route-DVI-D-1|none|none' ;;
    esac
    printf 'reconcile:%s:%s:%s\n' "$reconcile_count" "$reconcile_seconds" \
      "$NOTIFICATION_ROUTE_LAST_WRITE_SECONDS" >>"$STREAM_LOG"
  }
  read_count=0
  read() {
    if [[ ${2:-} != -t ]]; then
      builtin read -r "${@:2}"
      return
    fi
    if ((read_count == 0)); then
      read_count=1
      printf -v "$4" '%s' 'workspace>>1'
      fake_monotonic_seconds=1
      return 0
    fi
    if ((read_count == 1)); then
      ((read_count += 1))
      printf -v "$4" '%s' 'activelayout>>keyboard,us'
      fake_monotonic_seconds=30
      return 0
    fi
    if ((read_count == 2)); then
      ((read_count += 1))
      fake_monotonic_seconds=$((fake_monotonic_seconds + $3))
      return 142
    fi
    return 1
  }
  event_clean_state=false
  NOTIFICATION_RECONCILE_INTERVAL=29
  consume_hyprland_event_stream event_clean_state </dev/null
)
assert_equal $'reconcile:1:0:0\nreconcile:2:1:1\nreconcile:3:30:30\nreconcile:4:59:59' \
  "$(<"$STREAM_LOG")" \
  'interval-29 deadline rechecks at route age 30 seconds'

# A persistent overdue reconciliation failure must wait for a bounded retry
# instead of reusing the expired route deadline without reading from the stream.
reset_route_state
: >"$STREAM_LOG"
set +e
(
  fake_monotonic_seconds=0
  monotonic_seconds() {
    printf '%s\n' "$fake_monotonic_seconds"
  }
  reconcile_count=0
  read_count=0
  reconcile_notification_routing() {
    local reconcile_seconds=$fake_monotonic_seconds
    ((reconcile_count += 1))
    if ((reconcile_count == 1)); then
      NOTIFICATION_ROUTE_LAST_WRITE_SECONDS=0
      printf 'reconcile:%s:%s:%s\n' "$reconcile_count" "$reconcile_seconds" \
        "$NOTIFICATION_ROUTE_LAST_WRITE_SECONDS" >>"$STREAM_LOG"
      return 0
    fi
    printf 'reconcile:%s:%s:%s:failed\n' "$reconcile_count" "$reconcile_seconds" \
      "$NOTIFICATION_ROUTE_LAST_WRITE_SECONDS" >>"$STREAM_LOG"
    if ((reconcile_count >= 3 && read_count == 1)); then
      printf 'spin-detected\n' >>"$STREAM_LOG"
      exit 99
    fi
    return 1
  }
  read() {
    if [[ ${2:-} != -t ]]; then
      builtin read -r "${@:2}"
      return
    fi
    ((read_count += 1))
    if ((read_count <= 2)); then
      printf 'read-timeout:%s:%s\n' "$3" "$fake_monotonic_seconds" >>"$STREAM_LOG"
      fake_monotonic_seconds=$((fake_monotonic_seconds + $3))
      return 142
    fi
    return 1
  }
  failed_retry_clean_state=false
  consume_hyprland_event_stream failed_retry_clean_state </dev/null
)
failed_retry_status=$?
set -e
((failed_retry_status == 0)) || fail 'overdue reconciliation failure retried without advancing the read/time'
assert_equal $'reconcile:1:0:0\nread-timeout:30:0\nreconcile:2:30:0:failed\nread-timeout:1:30\nreconcile:3:31:0:failed' \
  "$(<"$STREAM_LOG")" \
  'overdue reconciliation failure uses bounded retries'

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
reset_route_state
: >"$HYPR_LOG"
ROUTE_RENAME_FAIL=true
HYPR_MONITORS_JSON='[]'
HYPR_CLIENTS_JSON='[]'
handler_clean_state=false
consume_hyprland_event_stream handler_clean_state 2>/dev/null <<'EOF'
workspace>>1
activewindow>>RustDesk,Remote Desktop
EOF
assert_equal $'eval hl.dispatch(hl.dsp.submap("clean"))' "$(<"$HYPR_LOG")" \
  'RustDesk active-window handler continues after reconciliation failure'
assert_equal true "$handler_clean_state" \
  'handler state survives reconciliation failures and event iterations'
ROUTE_RENAME_FAIL=false
assert_mako_sentinel_empty

printf 'PASS: watch-rustdesk-submap route and reconciliation tests\n'
