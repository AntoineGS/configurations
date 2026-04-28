#!/usr/bin/env bash
# Toggle the external monitor between mirror mode and takeover mode.
#   Mirror   : laptop (eDP-1) active, external mirrors it at 1920x1080@60.
#   Takeover : laptop disabled, external is the sole display at 1920x1080@60.
# Bound to SUPER+E in bindings/utilities.conf.

set -euo pipefail

LAPTOP="eDP-1"
RES="1920x1080@60"

# `monitors all` is required: regular `monitors` hides mirrored & disabled ones.
monitors_json=$(hyprctl monitors all -j)
external=$(printf '%s' "$monitors_json" \
  | jq -r --arg laptop "$LAPTOP" '.[] | select(.name != $laptop and .disabled == false) | .name' \
  | head -n1)
laptop_disabled=$(printf '%s' "$monitors_json" \
  | jq -r --arg laptop "$LAPTOP" '.[] | select(.name == $laptop) | .disabled')
# Capture the focused workspace before reshuffling so we can restore focus after.
focused_ws=$(printf '%s' "$monitors_json" \
  | jq -r '[.[] | select(.focused == true)] | .[0].activeWorkspace.id')

notify() { notify-send -a "display-toggle" "External display" "$1"; }

# Move every workspace currently on $1 over to $2. Needed because in mirror
# mode all workspaces live on the laptop and the external owns none — disabling
# the laptop without migrating leaves the external with nothing to render.
move_workspaces() {
  local from="$1" to="$2"
  hyprctl workspaces -j \
    | jq -r --arg from "$from" '.[] | select(.monitor == $from) | .id' \
    | while read -r ws; do
        [ -n "$ws" ] && hyprctl dispatch moveworkspacetomonitor "$ws $to" >/dev/null
      done
}

toggled=0
if [ "$laptop_disabled" = "true" ]; then
  # Currently in takeover mode — restore mirror.
  hyprctl keyword monitor "$LAPTOP, preferred, auto, 1"
  if [ -n "$external" ]; then
    move_workspaces "$external" "$LAPTOP"
    hyprctl keyword monitor "$external, $RES, auto, 1, mirror, $LAPTOP"
  fi
  [ -n "$focused_ws" ] && hyprctl dispatch workspace "$focused_ws" >/dev/null
  notify "Mirror mode"
  toggled=1
elif [ -n "$external" ]; then
  # Mirror mode with external connected — switch to takeover.
  # Bounce the external (disable → re-enable) instead of just rewriting its
  # config: when transitioning straight out of mirror mode Hyprland fails to
  # re-advertise the wl_output global, which leaves waybar with no output to
  # bind a bar surface to. The full disable/enable cycle forces a clean
  # re-advertisement.
  hyprctl keyword monitor "$external, disable"
  sleep 0.3
  hyprctl keyword monitor "$external, $RES, 0x0, 1"
  move_workspaces "$LAPTOP" "$external"
  hyprctl keyword monitor "$LAPTOP, disable"
  [ -n "$focused_ws" ] && hyprctl dispatch workspace "$focused_ws" >/dev/null
  notify "Takeover ($external)"
  toggled=1
else
  notify "No external monitor connected"
fi

# Mirrored monitors share a single Wayland output, so waybar only spawns one
# bar in mirror mode. After de-mirroring we need to restart it so it sees the
# new output and renders a bar on the TV.
if [ "$toggled" = "1" ]; then
  restart-waybar >/dev/null 2>&1 &
fi
