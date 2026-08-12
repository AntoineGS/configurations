#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PATTERN='OMARCHY_PATH|\.local/share/omarchy|\.config/omarchy|\.local/state/omarchy|org\.omarchy|pkgs\.omarchy\.org|mirror\.omarchy\.org|TARGET_OS_NAME="Omarchy"|CUSTOM_UKI_NAME="omarchy"|Current=omarchy'

if rg -n -i "$PATTERN" \
  "$ROOT/tidydots.yaml" \
  "$ROOT/Linux/hypr" \
  "$ROOT/Linux/ghostty" \
  "$ROOT/Linux/waybar" \
  "$ROOT/Linux/fastfetch" \
  "$ROOT/Linux/limine" \
  "$ROOT/Linux/sddm" \
  "$ROOT/Linux/os/helpers"; then
  printf 'active Omarchy runtime dependency found\n' >&2
  exit 1
fi
