#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  "$@"
}

run_shellcheck() {
  local -a files=(Linux/install/bootstrap Linux/install/tests/*.sh Linux/Snapper/snapper-initialize Linux/Snapper/tests/*.sh Linux/pacman/tests/boot-profile-test.sh)

  if command -v shellcheck >/dev/null 2>&1; then
    run shellcheck "${files[@]}"
  elif command -v docker >/dev/null 2>&1; then
    run docker run --rm --network none -v "$ROOT:/src:ro" -w /src koalaman/shellcheck:stable "${files[@]}"
  else
    run shellcheck "${files[@]}"
  fi
}

cd -- "$ROOT"

run bash Linux/install/tests/archinstall-config-test.sh
run bash Linux/install/tests/bootstrap-test.sh
run bash Linux/Snapper/tests/snapper-initialize-test.sh
run bash Linux/pacman/tests/all-profiles-test.sh
run bash Linux/os/tests/no-omarchy-runtime-test.sh
run bash Linux/os/tests/no-omarchy-runtime-error-test.sh
run_shellcheck
run tidydots --dir "$ROOT" list
run git diff --check
