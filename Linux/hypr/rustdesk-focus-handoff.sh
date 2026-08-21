#!/usr/bin/env bash
set -Eeuo pipefail

readonly RUSTDESK_HANDOFF_TARGET=${RUSTDESK_HANDOFF_TARGET:-desktop-e07vtrn}
readonly RUSTDESK_HANDOFF_PORT=${RUSTDESK_HANDOFF_PORT:-45973}
readonly RUSTDESK_HANDOFF_SOURCE_HOST=${RUSTDESK_HANDOFF_SOURCE_HOST:-antoinews-linux}

active_window_address() {
  hyprctl activewindow -j | jq -er '.address | select(type == "string" and length > 0)'
}

send_focus_left() {
  local before after

  before=$(active_window_address) || return 0
  hyprctl -r eval 'hl.dispatch(hl.dsp.focus({ direction = "left" }))' >/dev/null || return 1
  after=$(active_window_address) || return 0
  [[ $after == "$before" ]] || return 0

  printf 'focus-left\n' |
    socat -u -T 1 - "TCP4-CONNECT:${RUSTDESK_HANDOFF_TARGET}:${RUSTDESK_HANDOFF_PORT},connect-timeout=0.5" \
      >/dev/null 2>&1 || true
}

receive_focus_handoff() {
  local command active_window

  IFS= read -r command || return 0
  [[ $command == focus-left ]] || return 0
  active_window=$(hyprctl --instance 0 activewindow -j) || return 0
  jq -e '
    ((.class // "") | test("rustdesk"; "i")) and
    ((.title // "") | test("Remote Desktop"; "i"))
  ' <<<"$active_window" >/dev/null || return 0

  hyprctl --instance 0 eval 'hl.dispatch(hl.dsp.focus({ monitor = "l" }))' >/dev/null
}

listen_for_focus_handoffs() {
  local status self_ip source_ip

  while :; do
    if status=$(tailscale status --json) &&
      self_ip=$(jq -er 'first(.Self.TailscaleIPs[] | select(test("^[0-9.]+$")))' <<<"$status") &&
      source_ip=$(jq -er --arg host "$RUSTDESK_HANDOFF_SOURCE_HOST" '
        first(.Peer[]
          | select(.HostName == $host)
          | .TailscaleIPs[]
          | select(test("^[0-9.]+$")))
      ' <<<"$status"); then
      break
    fi
    sleep 2
  done

  exec socat -u \
    "TCP4-LISTEN:${RUSTDESK_HANDOFF_PORT},bind=${self_ip},range=${source_ip}/32,reuseaddr,fork,max-children=4" \
    "EXEC:${BASH_SOURCE[0]} receive"
}

case ${1:-} in
  send) send_focus_left ;;
  receive) receive_focus_handoff ;;
  listen) listen_for_focus_handoffs ;;
  *)
    printf 'usage: %s {send|receive|listen}\n' "${0##*/}" >&2
    exit 2
    ;;
esac
