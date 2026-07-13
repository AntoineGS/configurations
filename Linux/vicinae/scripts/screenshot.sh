#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Screenshot
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]

export PATH="$HOME/.local/share/helpers:$PATH"
exec </dev/null # vicinae gives script commands a never-closing stdin; detach it so helpers do not hang

# Silent-mode commands fire while Vicinae is still on screen, and cmd-screenshot
# freezes the display (hyprpicker -r) the instant it launches — so the launcher
# would be baked into the capture. Dismiss Vicinae and wait for its layer-shell
# surface to actually leave the compositor before shooting.
vicinae close >/dev/null 2>&1
for _ in $(seq 1 100); do
  hyprctl layers -j 2>/dev/null | grep -q '"namespace": "vicinae"' || break
  sleep 0.01
done
sleep 0.05 # let the compositor paint one clean frame before it gets frozen

cmd-screenshot
