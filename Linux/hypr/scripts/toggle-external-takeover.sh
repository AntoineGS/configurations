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
        [ -n "$ws" ] && hyprctl eval "hl.dispatch(hl.dsp.workspace.move({workspace=\"$ws\", monitor=\"$to\"}))" >/dev/null
      done
}

if [ "$laptop_disabled" = "true" ]; then
  # Currently in takeover mode — restore mirror.
  hyprctl eval "hl.monitor({output=\"$LAPTOP\", mode=\"preferred\", position=\"auto\", scale=1})"
  if [ -n "$external" ]; then
    move_workspaces "$external" "$LAPTOP"
    hyprctl eval "hl.monitor({output=\"$external\", mode=\"$RES\", position=\"auto\", scale=1, mirror=\"$LAPTOP\"})"
  fi
  [ -n "$focused_ws" ] && hyprctl eval "hl.dispatch(hl.dsp.focus({workspace=\"$focused_ws\"}))" >/dev/null
  notify "Mirror mode"
elif [ -n "$external" ]; then
  # Mirror mode with external connected — switch to takeover.
  # Bounce the external (disable → re-enable) instead of just rewriting its
  # config so Hyprland cleanly re-advertises the external output.
  hyprctl eval "hl.monitor({output=\"$external\", disabled=true})"
  sleep 0.3
  hyprctl eval "hl.monitor({output=\"$external\", mode=\"$RES\", position=\"0x0\", scale=1})"
  move_workspaces "$LAPTOP" "$external"
  hyprctl eval "hl.monitor({output=\"$LAPTOP\", disabled=true})"
  [ -n "$focused_ws" ] && hyprctl eval "hl.dispatch(hl.dsp.focus({workspace=\"$focused_ws\"}))" >/dev/null
  notify "Takeover ($external)"
else
  notify "No external monitor connected"
fi
