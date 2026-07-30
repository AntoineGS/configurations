#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Close All RustDesk Windows In
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]
# @vicinae.argument1 { "type": "text", "placeholder": "Minutes until RustDesk windows close" }

export PATH="$HOME/.local/share/helpers:$PATH"
exec </dev/null
exec close-rustdesk-windows-in "$1"
