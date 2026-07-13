#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Keybindings
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]

export PATH="$HOME/.local/share/helpers:$PATH"

# Vicinae runs script commands with a stdin that never closes; some helpers
# (e.g. xkbcli inside menu-keybindings) block forever reading it. Detach stdin.
exec </dev/null

menu-keybindings
