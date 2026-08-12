#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  "$@"
}

cd -- "$ROOT"

run bash Linux/install/tests/archinstall-config-test.sh
run bash Linux/install/tests/bootstrap-test.sh
run bash Linux/pacman/tests/all-profiles-test.sh
run bash Linux/os/tests/no-omarchy-runtime-test.sh
run shellcheck Linux/install/bootstrap Linux/install/tests/*.sh
run tidydots --dir "$ROOT" list
run git diff --check
