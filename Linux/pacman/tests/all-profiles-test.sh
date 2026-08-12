#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"

run_test() {
  local name="$1"
  shift

  printf '==> %s\n' "$name"
  "$@"
}

cd -- "$ROOT"

run_test "shared desktop profile" bash Linux/pacman/tests/shared-desktop-profile-test.sh
run_test "headless antoinews-linux graphical profile" bash Linux/pacman/tests/headless-antoinews-linux-profile-test.sh
run_test "networkd and iwd setup" bash Linux/network/tests/setup-networkd-iwd-test.sh
run_test "antoinews-linux Intel profile" bash Linux/pacman/tests/antoinews-linux-profile-test.sh
run_test "Limine and Snapper boot profile" bash Linux/pacman/tests/boot-profile-test.sh
run_test "tidydots list (worktree override)" tidydots --dir "$ROOT" list
run_test "Omarchy runtime audit" bash Linux/os/tests/no-omarchy-runtime-test.sh

printf 'PASS: all package-profile and runtime audits\n'
