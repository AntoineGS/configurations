#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PATTERN='OMARCHY_PATH|\.local/share/omarchy|\.config/omarchy|\.local/state/omarchy|org\.omarchy|pkgs\.omarchy\.org|mirror\.omarchy\.org|TARGET_OS_NAME="Omarchy"|CUSTOM_UKI_NAME="omarchy"|Current=omarchy|\.local/share/omarchy/default/xcompose|\.\./omarchy/current(/|$)|\.\./omarchy/current/theme/'
RG_BIN="${RG_BIN:-rg}"

test -f "$ROOT/Linux/Xcompose/.XCompose"
grep -Fqx '          - .XCompose' "$ROOT/tidydots.yaml"
grep -Fqx 'stylesheets: ["./style.css"]' "$ROOT/Linux/hyprland-preview-share-picker/config.yaml"
test -f "$ROOT/Linux/hyprland-preview-share-picker/style.css"
grep -Fq '@define-color background-color #1e1e2e;' "$ROOT/Linux/swayosd/style.css"
grep -Fq '@define-color progress #89b4fa;' "$ROOT/Linux/swayosd/style.css"
test -f "$ROOT/Linux/swayosd/style.css"
grep -Fq 'backup: ./Linux/hyprland-preview-share-picker' "$ROOT/tidydots.yaml"
grep -Fq 'backup: ./Linux/swayosd' "$ROOT/tidydots.yaml"

set +e
if rg_output=$("$RG_BIN" -n -i --hidden "$PATTERN" \
  "$ROOT/tidydots.yaml" \
  "$ROOT/Linux/Xcompose" \
  "$ROOT/Linux/hypr" \
  "$ROOT/Linux/hyprland-preview-share-picker" \
  "$ROOT/Linux/ghostty" \
  "$ROOT/Linux/waybar" \
  "$ROOT/Linux/fastfetch" \
  "$ROOT/Linux/limine" \
  "$ROOT/Linux/sddm" \
  "$ROOT/Linux/swayosd" \
  "$ROOT/Linux/os/helpers"); then
  rg_status=0
else
  rg_status=$?
fi
set -e

if (( rg_status == 0 )); then
  printf '%s\n' "$rg_output" >&2
  printf 'active Omarchy runtime dependency found\n' >&2
  exit 1
fi

if (( rg_status > 1 )); then
  printf 'rg failed while auditing active sources (exit %s)\n' "$rg_status" >&2
  printf '%s\n' "$rg_output" >&2
  exit "$rg_status"
fi
