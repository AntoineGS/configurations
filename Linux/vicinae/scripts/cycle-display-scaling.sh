#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Cycle Display Scaling
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]

export PATH="$HOME/.local/share/helpers:$PATH"
exec </dev/null # vicinae gives script commands a never-closing stdin; detach it so helpers do not hang
hyprland-monitor-scaling-cycle
