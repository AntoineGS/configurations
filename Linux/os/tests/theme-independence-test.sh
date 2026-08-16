#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PALETTE="$ROOT/Linux/ghostty/catppuccin-mocha.conf"

test -f "$PALETTE"

assert_contains() {
  local expected="$1"
  local file="$2"
  local status

  if grep -Fq -- "$expected" "$file"; then
    return 0
  else
    status=$?
  fi

  if ((status == 1)); then
    printf 'missing expected line in %s: %s\n' "$file" "$expected" >&2
  else
    printf 'grep failed for %s with status %d\n' "$file" "$status" >&2
  fi
  exit 1
}

assert_absent() {
  local pattern="$1"
  shift
  local status

  if grep -Eiq -- "$pattern" "$@"; then
    printf 'forbidden theme dependency found: %s\n' "$pattern" >&2
    exit 1
  else
    status=$?
  fi

  if ((status != 1)); then
    printf 'grep failed while checking for %s with status %d\n' "$pattern" "$status" >&2
    exit 1
  fi
}

for line in \
  'background = #1e1e2e' \
  'foreground = #cdd6f4' \
  'cursor-color = #f5e0dc' \
  'selection-background = #f5e0dc' \
  'selection-foreground = #1e1e2e' \
  'palette = 0=#45475a' \
  'palette = 1=#f38ba8' \
  'palette = 2=#a6e3a1' \
  'palette = 3=#f9e2af' \
  'palette = 4=#89b4fa' \
  'palette = 5=#f5c2e7' \
  'palette = 6=#94e2d5' \
  'palette = 7=#bac2de' \
  'palette = 8=#585b70' \
  'palette = 9=#f38ba8' \
  'palette = 10=#a6e3a1' \
  'palette = 11=#f9e2af' \
  'palette = 12=#89b4fa' \
  'palette = 13=#f5c2e7' \
  'palette = 14=#94e2d5' \
  'palette = 15=#a6adc8'; do
  assert_contains "$line" "$PALETTE"
done

assert_contains 'config-file = ?"~/.config/ghostty/catppuccin-mocha.conf"' "$ROOT/Linux/ghostty/config.tmpl"
assert_contains "hl.exec_cmd(\"uwsm-app -- swaybg -c '#1e1e2e'\")" "$ROOT/Linux/hypr/autostart.lua"
assert_absent '\.config/omarchy|\.local/share/omarchy|OMARCHY_PATH' \
  "$ROOT/Linux/ghostty/config.tmpl" \
  "$ROOT/Linux/hypr/autostart.lua" \
  "$ROOT/Linux/hypr/hyprlock.conf"
