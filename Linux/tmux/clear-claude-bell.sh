#!/usr/bin/env bash
set -eu
window_id="$1"
name="$2"
stripped="${name#󰂚 }"
if [ "$stripped" != "$name" ]; then
  tmux rename-window -t "$window_id" "$stripped"
fi
