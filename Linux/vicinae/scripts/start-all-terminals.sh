#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Start All Terminals
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]

set -Eeuo pipefail

exec </dev/null >/dev/null 2>&1
exec start-all-terminals
