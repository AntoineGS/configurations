#!/usr/bin/env bash
set -Eeuo pipefail

readonly RUSTDESK_HANDOFF_TARGET=${RUSTDESK_HANDOFF_TARGET:-127.0.0.1}
# Remote callback ports forwarded by the rustdesk-office and moonlight-office launchers.
readonly RUSTDESK_HANDOFF_PORTS=(45973 45974)
readonly RUSTDESK_HANDOFF_ENDPOINT=127.0.0.1:21120

active_window_address() {
  hyprctl activewindow -j | jq -er '.address | select(type == "string" and length > 0)'
}

send_focus_left() {
  local before after port

  before=$(active_window_address) || return 0
  hyprctl -r eval 'hl.dispatch(hl.dsp.focus({ direction = "left" }))' >/dev/null || return 1
  after=$(active_window_address) || return 0
  [[ $after == "$before" ]] || return 0

  # Each client only acts when its own remote session window is focused.
  for port in "${RUSTDESK_HANDOFF_PORTS[@]}"; do
    printf 'focus-left\n' |
      socat -u -T 1 - "TCP4-CONNECT:${RUSTDESK_HANDOFF_TARGET}:${port},connect-timeout=0.5" \
        >/dev/null 2>&1 || true
  done
}

receive_focus_handoff() {
  local session=$1 command active_window

  IFS= read -r command || return 0
  [[ $command == focus-left ]] || return 0
  active_window=$(hyprctl activewindow -j) || return 0
  jq -e --arg session "$session" --arg endpoint "$RUSTDESK_HANDOFF_ENDPOINT" '
    if $session == "moonlight" then
      .class == "com.moonlight_stream.Moonlight" and ((.title // "") | endswith(" - Moonlight"))
    else
      ((.class // "") | test("rustdesk"; "i")) and
      ((.title // "") | startswith($endpoint + " - ") or startswith($endpoint + "@")) and
      ((.title // "") | test("Remote Desktop"; "i"))
    end
  ' <<<"$active_window" >/dev/null || return 0

  hyprctl eval 'hl.dispatch(hl.dsp.focus({ monitor = "l" }))' >/dev/null
  # On a single-monitor laptop there may be no monitor to the left.
  if [[ $(active_window_address) == "$(jq -r '.address' <<<"$active_window")" ]]; then
    hyprctl eval 'hl.dispatch(hl.dsp.focus({ workspace = "previous" }))' >/dev/null
  fi
}

listen_for_focus_handoffs() {
  local socket_path=${1:?The launcher must supply a private Unix socket path}
  local session=$2
  exec socat -u -T 2 \
    "UNIX-LISTEN:${socket_path},mode=600,fork,max-children=4" \
    "EXEC:${BASH_SOURCE[0]} receive ${session}"
}

usage() {
  printf 'usage: %s {send|receive [SESSION]|listen SOCKET [SESSION]}\n' "${0##*/}" >&2
  printf 'SESSION is rustdesk (default) or moonlight\n' >&2
  exit 2
}

require_session() {
  [[ $1 == rustdesk || $1 == moonlight ]] || usage
}

case ${1:-} in
  send) send_focus_left ;;
  receive)
    require_session "${2:-rustdesk}"
    receive_focus_handoff "${2:-rustdesk}"
    ;;
  listen)
    require_session "${3:-rustdesk}"
    listen_for_focus_handoffs "${2:-}" "${3:-rustdesk}"
    ;;
  *) usage ;;
esac
