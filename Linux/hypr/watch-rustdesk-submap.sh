#!/usr/bin/env bash
# Event-driven Hyprland workspace -> submap watcher using socat for automatic reconnects
# Also moves 2nd+ RustDesk Remote Desktop windows to the rightmost monitor
# Requirements: hyprctl, socat, jq
set -euo pipefail

SOCAT=${SOCAT:-socat}
: "${XDG_RUNTIME_DIR:=/run/user/$UID}"
HYPR_DIR="$XDG_RUNTIME_DIR/hypr"

# Resolve the running Hyprland instance before doing anything else. Under UWSM
# this systemd user unit can start before the compositor environment
# (HYPRLAND_INSTANCE_SIGNATURE) is imported into the session, and a process only
# ever sees the environment it was spawned with -- so waiting on the env var
# alone would hang forever. Prefer the env var when it points at a live instance
# socket; otherwise discover the newest instance from the runtime socket dir.
# Block until a live event socket exists, then adopt it (exported so the hyprctl
# calls below inherit it too).
sig=""
while :; do
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} \
    && -S "$HYPR_DIR/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" ]]; then
    sig=$HYPRLAND_INSTANCE_SIGNATURE
    break
  fi
  candidate=$(ls -t "$HYPR_DIR" 2>/dev/null | head -1 || true)
  if [[ -n $candidate && -S "$HYPR_DIR/$candidate/.socket2.sock" ]]; then
    sig=$candidate
    break
  fi
  sleep 2
done
export HYPRLAND_INSTANCE_SIGNATURE="$sig"

HYPR_SOCKET_PATH="$HYPR_DIR/$sig/.socket2.sock"
ACTIVATED_CLEAN_WORKSPACE=false
RIGHTMOST_MONITOR="DP-2"

is_rustdesk_remote() {
  printf '%s\n' "$1" | grep -qi "rustdesk" &&
    printf '%s\n' "$1" | grep -qi "Remote Desktop"
}

count_rustdesk_remote_windows() {
  hyprctl clients -j | jq '[.[] | select(.class | test("rustdesk"; "i")) | select(.title | test("Remote Desktop"; "i"))] | length'
}

# Use socat to connect to the Hyprland socket and keep reconnecting.
# Options used:
#  -u : unidirectional (read-only from socket)
#  UNIX-CONNECT:...,forever,interval=2 : reconnect forever, waiting 2s between attempts
"$SOCAT" -u "UNIX-CONNECT:${HYPR_SOCKET_PATH},forever,interval=2" - 2>/dev/null |

while IFS= read -r evline; do
  # Move 2nd+ RustDesk Remote Desktop windows to the rightmost monitor
  if printf '%s\n' "$evline" | grep -qi "^openwindow>>" && is_rustdesk_remote "$evline"; then
    window_addr=$(printf '%s\n' "$evline" | sed 's/^openwindow>>//I' | cut -d',' -f1)
    count=$(count_rustdesk_remote_windows)
    if [ "$count" -gt 1 ]; then
      target_ws=$(hyprctl monitors -j | jq -r '.[] | select(.name == "'"${RIGHTMOST_MONITOR}"'") | .activeWorkspace.id')
      hyprctl eval "hl.dispatch(hl.dsp.window.move({workspace=${target_ws}, follow=false, window=\"address:0x${window_addr}\"}))"
    fi
  fi

  # Switch to clean submap when a RustDesk Remote Desktop window is focused
  if printf '%s\n' "$evline" | grep -qi "^activewindow>>"; then
    if is_rustdesk_remote "$evline"; then
      hyprctl eval 'hl.dispatch(hl.dsp.submap("clean"))'
      ACTIVATED_CLEAN_WORKSPACE=true
    elif [ "$ACTIVATED_CLEAN_WORKSPACE" = true ]; then
      hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))'
      ACTIVATED_CLEAN_WORKSPACE=false
    fi
  fi
done
