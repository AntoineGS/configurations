#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Suspend In
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]
# @vicinae.argument1 { "type": "text", "placeholder": "Minutes until suspend" }

minutes=${1:-}

if [[ ! $minutes =~ ^0*[1-9][0-9]*$ ]]; then
  notify-send -a "vicinae" -u critical "Suspend not scheduled" "Enter a positive whole number of minutes."
  exit 1
fi

if ! suspend_at=$(date --date="+$minutes minutes" "+%H:%M"); then
  notify-send -a "vicinae" -u critical "Suspend not scheduled" "The requested delay is too large."
  exit 1
fi

exec </dev/null

systemctl --user stop vicinae-suspend.timer vicinae-suspend.service 2>/dev/null || true
systemctl --user reset-failed vicinae-suspend.timer vicinae-suspend.service 2>/dev/null || true

if ! systemd-run --user --unit=vicinae-suspend --on-active="${minutes}m" --collect systemctl suspend >/dev/null 2>&1; then
  notify-send -a "vicinae" -u critical "Suspend not scheduled" "Could not create the suspend timer."
  exit 1
fi

notify-send -a "vicinae" "Suspend scheduled" "Suspending in $minutes minutes, at $suspend_at."
