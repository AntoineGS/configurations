#!/usr/bin/env bash
set -Eeuo pipefail

readonly RUSTDESK_HANDOFF_TARGET=${RUSTDESK_HANDOFF_TARGET:-127.0.0.1}
readonly RUSTDESK_HANDOFF_PORT=${RUSTDESK_HANDOFF_PORT:-45973}
readonly RUSTDESK_HANDOFF_ENDPOINT=127.0.0.1:21120

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
  active_window=$(hyprctl activewindow -j) || return 0
  jq -e --arg endpoint "$RUSTDESK_HANDOFF_ENDPOINT" '
    ((.class // "") | test("rustdesk"; "i")) and
    ((.title // "") | startswith($endpoint + " - ") or startswith($endpoint + "@")) and
    ((.title // "") | test("Remote Desktop"; "i"))
  ' <<<"$active_window" >/dev/null || return 0

  hyprctl eval 'hl.dispatch(hl.dsp.focus({ monitor = "l" }))' >/dev/null
  # On a single-monitor laptop there may be no monitor to the left.
  if [[ $(active_window_address) == "$(jq -r '.address' <<<"$active_window")" ]]; then
    hyprctl eval 'hl.dispatch(hl.dsp.focus({ workspace = "previous" }))' >/dev/null
  fi
}

listen_for_focus_handoffs() {
  local socket_path=${1:?The launcher must supply a private Unix socket path}
  exec socat -u -T 2 \
    "UNIX-LISTEN:${socket_path},mode=600,fork,max-children=4" \
    "EXEC:${BASH_SOURCE[0]} receive"
}

case ${1:-} in
  send) send_focus_left ;;
  receive) receive_focus_handoff ;;
  listen) listen_for_focus_handoffs "${2:-}" ;;
  *)
    printf 'usage: %s {send|receive|listen SOCKET}\n' "${0##*/}" >&2
    exit 2
    ;;
esac
