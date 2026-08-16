#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
MENU="$ROOT/Linux/os/helpers/menu"
LOCK_SCREEN="$ROOT/Linux/os/helpers/lock-screen"
SYSTEM_RULES="$ROOT/Linux/hypr/apps/system.lua"
VICINAE_SCRIPTS="$ROOT/Linux/vicinae/scripts"

for file in "$MENU" "$LOCK_SCREEN"; do
  bash -n "$file"
done

for script in "$VICINAE_SCRIPTS"/*.sh; do
  bash -n "$script"
done

deleted_helpers=(
  cmd-screensaver
  launch-screensaver
  toggle-screensaver
  theme-bg-install
  theme-bg-next
  theme-bg-set
  theme-current
  theme-install
  theme-list
  theme-refresh
  theme-remove
  theme-set
  theme-set-browser
  theme-set-gnome
  theme-set-keyboard
  theme-set-keyboard-asus-rog
  theme-set-keyboard-f16
  theme-set-obsidian
  theme-set-templates
  theme-set-vscode
  theme-update
)

for helper in "${deleted_helpers[@]}"; do
  helper_path="$ROOT/Linux/os/helpers/$helper"
  if [[ -e "$helper_path" || -L "$helper_path" ]]; then
    printf 'obsolete helper still exists: %s\n' "$helper_path" >&2
    exit 1
  fi
done

for script in toggle-screensaver.sh background.sh theme.sh; do
  if [[ -e "$VICINAE_SCRIPTS/$script" || -L "$VICINAE_SCRIPTS/$script" ]]; then
    printf 'obsolete Vicinae script still exists: %s\n' "$VICINAE_SCRIPTS/$script" >&2
    exit 1
  fi
done

if grep -Eiq 'install-terminal|toggle-screensaver|menu (background|theme)' "$MENU" "$VICINAE_SCRIPTS"/*.sh; then
  printf '%s\n' 'Vicinae or menu sources still reference removed actions' >&2
  exit 1
fi

for helper in font-current font-list font-set; do
  test -x "$ROOT/Linux/os/helpers/$helper"
done

if grep -Eiq 'omarchy|screensaver|theme|background|channel|hybrid gpu|toggle-suspend|default config' \
  "$MENU" "$LOCK_SCREEN" "$SYSTEM_RULES"; then
  printf '%s\n' 'retained helper surface still contains removed lifecycle or theme references' >&2
  exit 1
fi

stylua --check "$SYSTEM_RULES"

printf '%s\n' 'helper independence tests passed'
