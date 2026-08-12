#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

modified_helpers=(
  update
  update-perform
  snapshot
  hibernation-available
  hibernation-remove
  hibernation-setup
  launch-floating-terminal-with-presentation
  launch-tui
  config-direct-boot
  state
  windows-vm
  voxtype-install
  cmd-screenrecord
  cmd-screenshot
  font-set
)

deleted_helpers=(
  hook
  install-terminal
  refresh-applications
  refresh-chromium
  refresh-config
  refresh-fastfetch
  refresh-hypridle
  refresh-hyprland
  refresh-hyprlock
  refresh-hyprsunset
  refresh-limine
  refresh-pacman
  refresh-plymouth
  refresh-sddm
  refresh-swayosd
  refresh-tmux
  refresh-waybar
  show-logo
  toggle-hybrid-gpu
  toggle-suspend
  update-available-reset
  update-branch
  update-git
  update-restart
  update-without-idle
)

for helper in "${modified_helpers[@]}"; do
  helper_path="$ROOT/Linux/os/helpers/$helper"
  test -x "$helper_path"
  bash -n "$helper_path"
done

for helper in "${deleted_helpers[@]}"; do
  helper_path="$ROOT/Linux/os/helpers/$helper"
  if [[ -e $helper_path || -L $helper_path ]]; then
    printf 'obsolete helper still exists: %s\n' "$helper_path" >&2
    exit 1
  fi
done

for helper in "${modified_helpers[@]}"; do
  helper_path="$ROOT/Linux/os/helpers/$helper"
  if grep -Eiq 'omarchy|OMARCHY_PATH|OMARCHY_|org\.omarchy|show-logo|show-done|update-git|update-available-reset|update-restart|hook post-update' "$helper_path"; then
    printf 'retained helper still contains obsolete runtime branding or lifecycle code: %s\n' "$helper_path" >&2
    exit 1
  fi
done

HIBERNATION_FILES=(
  "$ROOT/Linux/os/helpers/hibernation-available"
  "$ROOT/Linux/os/helpers/hibernation-remove"
  "$ROOT/Linux/os/helpers/hibernation-setup"
)
for helper_path in "${HIBERNATION_FILES[@]}"; do
  grep -Fq '/etc/mkinitcpio.conf.d/resume.conf' "$helper_path"
done

grep -Fq 'SCREENRECORD_DIR' "$ROOT/Linux/os/helpers/cmd-screenrecord"
grep -Fq 'SCREENSHOT_DIR' "$ROOT/Linux/os/helpers/cmd-screenshot"
grep -Fq 'SCREENSHOT_EDITOR' "$ROOT/Linux/os/helpers/cmd-screenshot"
grep -Fq 'SCREENRECORD_DIR' "$ROOT/Linux/os/tests/cmd-screenrecord-test.sh"
if grep -Fq 'OMARCHY_SCREENRECORD_DIR' "$ROOT/Linux/os/tests/cmd-screenrecord-test.sh"; then
  printf '%s\n' 'screenrecord test still uses the Omarchy output variable' >&2
  exit 1
fi

grep -Fq "DESC=\"pre-update \$(date --iso-8601=seconds)\"" "$ROOT/Linux/os/helpers/snapshot"
grep -Fq 'snapshot create' "$ROOT/Linux/os/helpers/update"
grep -Fq 'update-perform' "$ROOT/Linux/os/helpers/update"
grep -Fq 'update-keyring' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'update-system-pkgs' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'update-aur-pkgs' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'update-orphan-pkgs' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'update-analyze-logs' "$ROOT/Linux/os/helpers/update-perform"
grep -Fq 'noidle' "$ROOT/Linux/os/helpers/update-perform"

for helper_path in \
  "$ROOT/Linux/os/helpers/launch-floating-terminal-with-presentation" \
  "$ROOT/Linux/os/helpers/launch-tui"; do
  grep -Fq -- '--app-id=org.local.terminal' "$helper_path"
  grep -Fq -- '--title=System' "$helper_path"
done

grep -Fq "STATE_DIR=\"\$HOME/.local/state/configurations\"" "$ROOT/Linux/os/helpers/state"
grep -Fq 'arch*.efi' "$ROOT/Linux/os/helpers/config-direct-boot"
grep -Fq -- '--label "Arch"' "$ROOT/Linux/os/helpers/config-direct-boot"
grep -Fq 'voxtype setup --download' "$ROOT/Linux/os/helpers/voxtype-install"
if grep -Fq -- '--no-post-install' "$ROOT/Linux/os/helpers/voxtype-install"; then
  exit 1
fi

if grep -Fq 'hook font-set' "$ROOT/Linux/os/helpers/font-set"; then
  printf '%s\n' 'font-set still invokes the deleted hook helper' >&2
  exit 1
fi

printf '%s\n' 'system helper independence tests passed'
