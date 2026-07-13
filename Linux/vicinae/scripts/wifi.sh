#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Wi-Fi
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]

export PATH="$HOME/.local/share/helpers:$PATH"
exec </dev/null # vicinae gives script commands a never-closing stdin; detach it so helpers do not hang
launch-wifi
