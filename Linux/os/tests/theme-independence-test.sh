#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

test -f "$ROOT/Linux/ghostty/catppuccin-mocha.conf"
grep -Fq 'config-file = ?"~/.config/ghostty/catppuccin-mocha.conf"' "$ROOT/Linux/ghostty/config.tmpl"
grep -Fq "swaybg -c '#1e1e2e'" "$ROOT/Linux/hypr/autostart.lua"
! grep -Eq '\.config/omarchy|\.local/share/omarchy|OMARCHY_PATH' \
  "$ROOT/Linux/ghostty/config.tmpl" \
  "$ROOT/Linux/hypr/autostart.lua" \
  "$ROOT/Linux/hypr/hyprlock.conf"
