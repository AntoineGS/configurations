#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Suspend In
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]
# @vicinae.argument1 { "type": "text", "placeholder": "Minutes until suspend" }

export PATH="$HOME/.local/share/helpers:$PATH"
exec </dev/null
exec suspend-in "$1"
