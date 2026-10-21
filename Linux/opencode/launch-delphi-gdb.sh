#!/bin/sh
# Shared by the global default-off entry and the selected project overrides.
set -eu

backend="$HOME/gits/delphi-gdb-mcp/.venv/bin/gdb-mcp-backend"
if [ ! -x "$backend" ]; then
    printf '%s\n' "Delphi GDB MCP backend is missing or not executable: $backend" >&2
    exit 1
fi

# Custom interactive shell startup can interfere with GDB subprocesses.
export SHELL=/bin/sh
exec "$backend" --transport stdio --delphi-profile delphi_13_2_linux64
