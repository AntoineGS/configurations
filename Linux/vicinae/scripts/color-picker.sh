#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Color Picker
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]

export PATH="$HOME/.local/share/helpers:$PATH"
exec </dev/null # vicinae gives script commands a never-closing stdin; detach it so helpers do not hang

# hyprpicker grabs the whole screen, so wait for Vicinae's layer-shell surface to
# leave the compositor first (same race as the screenshot command) — otherwise the
# launcher sits in the way and is itself pickable.
vicinae close >/dev/null 2>&1
for _ in $(seq 1 100); do
  hyprctl layers -j 2>/dev/null | grep -q '"namespace": "vicinae"' || break
  sleep 0.01
done
sleep 0.05

pkill hyprpicker || hyprpicker -a
