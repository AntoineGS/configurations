#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SHELLCHECK_IMAGE="${SHELLCHECK_IMAGE:-koalaman/shellcheck:v0.10.0}"

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  "$@"
}

run_shellcheck() {
  local -a files=(
    Linux/install/bootstrap
    Linux/install/tests/*.sh
    Linux/Snapper/snapper-initialize
    Linux/Snapper/tests/*.sh
    Linux/network/tests/setup-networkd-iwd-test.sh
    Linux/pacman/tests/all-profiles-test.sh
    Linux/pacman/tests/antoinews-linux-profile-test.sh
    Linux/pacman/tests/boot-profile-test.sh
    Linux/pacman/tests/headless-antoinews-linux-profile-test.sh
    Linux/pacman/tests/shared-desktop-profile-test.sh
    Linux/hypr/watch-rustdesk-submap.sh
    Linux/hypr/tests/monitor-policy-test.sh
    Linux/hypr/tests/watch-rustdesk-submap-test.sh
    Linux/quickshell/desktop-shell/tests/bluetooth-test.sh
    Linux/opencode/tests/test-setup-context-tokenizers.sh
    Linux/opencode/tests/test-setup-temp-cleanup.sh
    Linux/os/helpers/cmd-screenrecord
    Linux/os/helpers/menu
    Linux/os/helpers/powerprofiles-list
    Linux/os/helpers/setup-remmina-hostkey
    Linux/os/tests/cmd-screenrecord-test.sh
    Linux/os/tests/desktop-bluetooth-state-test.sh
    Linux/os/tests/desktop-status-independence-test.sh
    Linux/os/tests/helper-independence-test.sh
    Linux/os/tests/setup-remmina-hostkey-test.sh
    Linux/os/tests/system-helper-independence-test.sh
    Linux/os/tests/theme-independence-test.sh
    Linux/os/tests/power-profile-availability-test.sh
    Linux/vicinae/scripts/*.sh
    Both/ShellPicker/setup-shell-picker.sh
    Both/ShellPicker/tests/test-setup-shell-picker.sh
  )

  if command -v docker >/dev/null 2>&1 && docker image inspect "$SHELLCHECK_IMAGE" >/dev/null 2>&1; then
    run docker run --rm --network none --pull=never -v "$ROOT:/src:ro" -w /src "$SHELLCHECK_IMAGE" "${files[@]}"
  elif command -v shellcheck >/dev/null 2>&1; then
    run shellcheck "${files[@]}"
  elif command -v docker >/dev/null 2>&1; then
    run docker run --rm --network none --pull=missing -v "$ROOT:/src:ro" -w /src "$SHELLCHECK_IMAGE" "${files[@]}"
  else
    printf '%s\n' 'ShellCheck requires shellcheck or Docker' >&2
    return 127
  fi
}

cd -- "$ROOT"

run bash Linux/install/tests/archinstall-config-test.sh
run bash Linux/install/tests/snapper-host-policy-test.sh
run bash Linux/install/tests/bootstrap-test.sh
run bash Linux/install/tests/snapper-bootstrap-test.sh
run bash Linux/Snapper/tests/snapper-initialize-test.sh
run bash Linux/Snapper/tests/btrfs-loop-fixture-test.sh
run bash Linux/pacman/tests/all-profiles-test.sh
run bash Linux/os/tests/theme-independence-test.sh
run bash Linux/os/tests/desktop-status-independence-test.sh
run bash Linux/os/tests/helper-independence-test.sh
run bash Linux/os/tests/system-helper-independence-test.sh
run bash Linux/os/tests/cmd-screenrecord-test.sh
run bash Linux/os/tests/setup-remmina-hostkey-test.sh
run bash Linux/network/tests/setup-networkd-iwd-test.sh
run bash Linux/opencode/tests/test-setup-context-tokenizers.sh
run bash Linux/opencode/tests/test-setup-temp-cleanup.sh
run bash Linux/os/tests/no-omarchy-runtime-test.sh
run bash Linux/os/tests/no-omarchy-runtime-error-test.sh
run bash Both/ShellPicker/tests/test-setup-shell-picker.sh
run bash Linux/hypr/tests/monitor-policy-test.sh
run bash Linux/hypr/tests/watch-rustdesk-submap-test.sh
run bash Linux/os/tests/desktop-bluetooth-state-test.sh
run bash Linux/quickshell/desktop-shell/tests/bluetooth-test.sh
run bash Linux/quickshell/desktop-shell/tests/service-test.sh
run bash Linux/quickshell/desktop-shell/tests/desktop-services-setup-test.sh
run bash Linux/quickshell/desktop-shell/tests/desktop-services-cutover-test.sh
run bash Linux/os/tests/power-profile-availability-test.sh
run bash -n Linux/hypr/watch-rustdesk-submap.sh
run bash -n Linux/hypr/tests/monitor-policy-test.sh
run bash -n Linux/hypr/tests/watch-rustdesk-submap-test.sh
run luac -p Linux/hypr/autostart.lua Linux/hypr/monitors.lua
run_shellcheck
run tidydots --dir "$ROOT" list
run git diff --check
