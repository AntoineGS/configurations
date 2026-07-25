#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Screenrecord
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]

export PATH="$HOME/.local/share/helpers:$PATH"
exec </dev/null >/dev/null 2>&1 # Vicinae closes command pipes on exit; descendants must not inherit them
menu screenrecord
