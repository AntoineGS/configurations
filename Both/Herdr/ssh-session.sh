#!/bin/sh

set -u

herdr_bin=${HERDR_BIN_PATH:-herdr}

set_opencode_animations() {
  mode=$1
  case "$mode" in
    disable) action='Disable animations' ;;
    enable) action='Enable animations' ;;
    *) return 2 ;;
  esac

  pane_list=$("$herdr_bin" pane list 2>/dev/null) || return 1
  panes=$(printf '%s\n' "$pane_list" |
    jq -r '.result.panes[]? | select((.agent // "" | ascii_downcase) == "opencode") | select((.agent_status // "unknown") as $status | ["idle", "done", "working"] | index($status)) | .pane_id' 2>/dev/null) || return 1

  [ -n "$panes" ] || return 1
  changed=1
  incomplete=0

  while IFS= read -r pane_id; do
    [ -n "$pane_id" ] || continue

    if ! "$herdr_bin" pane send-keys "$pane_id" ctrl+p >/dev/null 2>&1; then
      incomplete=1
      continue
    fi
    sleep 0.1
    if ! "$herdr_bin" pane send-text "$pane_id" "$action" >/dev/null 2>&1; then
      incomplete=1
      continue
    fi
    sleep 0.1
    if "$herdr_bin" pane send-keys "$pane_id" enter >/dev/null 2>&1; then
      changed=0
      animation_command_sent=1
    else
      incomplete=1
    fi
  done <<EOF
$panes
EOF

  [ "$changed" -eq 0 ] && [ "$incomplete" -eq 0 ]
}

restore_until_success() {
  while ! set_opencode_animations enable >/dev/null 2>&1; do
    sleep 1
  done
}

attach_with_animation_cleanup() {
  cleaned_up=0
  animations_changed=0
  cleanup() {
    [ "$cleaned_up" -eq 0 ] || return
    cleaned_up=1
    if command -v herdr-waypipe-env >/dev/null 2>&1; then
      herdr-waypipe-env clear >/dev/null 2>&1 || true
    fi
    [ "$animations_changed" -eq 1 ] || return
    attempts=0
    while [ "$attempts" -lt 20 ]; do
      set_opencode_animations enable >/dev/null 2>&1 && return
      attempts=$((attempts + 1))
      sleep 0.25
    done

    if command -v setsid >/dev/null 2>&1; then
      setsid sh "$0" restore </dev/null >/dev/null 2>&1 &
    else
      nohup sh "$0" restore </dev/null >/dev/null 2>&1 &
    fi
  }

  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap cleanup EXIT

  animation_command_sent=0
  set_opencode_animations disable >/dev/null 2>&1 || true
  animations_changed=$animation_command_sent
  "$herdr_bin"
  status=$?

  cleanup
  trap - EXIT HUP INT TERM
  return "$status"
}

case "${1:-attach}" in
  attach) attach_with_animation_cleanup ;;
  disable | enable) set_opencode_animations "$1" ;;
  restore) restore_until_success ;;
  *)
    printf '%s\n' 'usage: ssh-session.sh {attach|disable|enable}' >&2
    exit 2
    ;;
esac
