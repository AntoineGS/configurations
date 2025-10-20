#!/usr/bin/env bash
# Event-driven Hyprland workspace -> submap watcher using socat for automatic reconnects
# Requirements: hyprctl, socat
set -euo pipefail

SOCAT=${SOCAT:-socat}
HYPR_SOCKET_PATH="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
ACTIVATED_CLEAN_WORKSPACE=false

# Use socat to connect to the Hyprland socket and keep reconnecting.
# Options used:
#  -u : unidirectional (read-only from socket)
#  UNIX-CONNECT:...,forever,interval=2 : reconnect forever, waiting 2s between attempts
"$SOCAT" -u "UNIX-CONNECT:${HYPR_SOCKET_PATH},forever,interval=2" - 2>/dev/null |

while IFS= read -r evline; do
  if ! printf '%s\n' "$evline" | grep -qi "activewindow>>"; then
    continue
  fi

  if printf '%s\n' "$evline" | grep -qi "activewindow>>rustdesk" && \ 
      printf '%s\n' "$evline" | grep -qi "Remote Desktop"; then
    hyprctl dispatch submap clean
    ACTIVATED_CLEAN_WORKSPACE=true
  elif [ "$ACTIVATED_CLEAN_WORKSPACE" = true ]; then
    hyprctl dispatch submap reset
    ACTIVATED_CLEAN_WORKSPACE=false
  fi
done
