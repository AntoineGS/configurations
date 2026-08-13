#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 1 || "$1" == --* ]]; then
  printf 'Usage: %s LOCK_PATH [bootstrap options...]\n' "${BASH_SOURCE[0]##*/}" >&2
  exit 2
fi

readonly TEST_LIFECYCLE_LOCK="$1"
shift

[[ "$TEST_LIFECYCLE_LOCK" == /* ]] || {
  printf '%s: lock path must be absolute\n' "${BASH_SOURCE[0]##*/}" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly BOOTSTRAP="$SCRIPT_DIR/../bootstrap"

# Sourcing is the explicit test-only boundary; production bootstrap never parses a lock selector.
# shellcheck disable=SC1090
source "$BOOTSTRAP"
# shellcheck disable=SC2034
SNAPPER_LIFECYCLE_LOCK="$TEST_LIFECYCLE_LOCK"
bootstrap_main "$@"
