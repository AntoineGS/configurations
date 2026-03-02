#!/bin/bash
# Attach to main tmux session, or sec if main is already attached
if tmux has-session -t main 2>/dev/null && [ "$(tmux list-clients -t main 2>/dev/null | wc -l)" -gt 0 ]; then
  exec tmux new-session -A -s sec
else
  exec tmux new-session -A -s main
fi
