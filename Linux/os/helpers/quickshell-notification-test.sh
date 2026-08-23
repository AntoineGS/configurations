#!/usr/bin/env bash
set -Eeuo pipefail

command -v notify-send >/dev/null 2>&1 || {
  printf 'quickshell-notification-test: notify-send is required\n' >&2
  exit 1
}

urgencies=(low normal critical)

for index in "${!urgencies[@]}"; do
  urgency=${urgencies[$index]}
  notify-send \
    --app-name "Quickshell Notification Test" \
    --urgency "$urgency" \
    --expire-time 3000 \
    "${urgency^} notification" \
    "This is a $urgency urgency notification."

  if ((index < ${#urgencies[@]} - 1)); then
    sleep 3
  fi
done
