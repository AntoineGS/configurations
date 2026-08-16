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
readonly TEST_OS_RELEASE="${BOOTSTRAP_TEST_OS_RELEASE:-}"
readonly TEST_HOSTNAME="${BOOTSTRAP_TEST_HOSTNAME:-}"

[[ -r "$TEST_OS_RELEASE" ]] || {
  printf '%s: missing readable BOOTSTRAP_TEST_OS_RELEASE fixture\n' "${BASH_SOURCE[0]##*/}" >&2
  exit 2
}
[[ -n "$TEST_HOSTNAME" ]] || {
  printf '%s: missing BOOTSTRAP_TEST_HOSTNAME fixture\n' "${BASH_SOURCE[0]##*/}" >&2
  exit 2
}

# Sourcing is the explicit test-only boundary; production bootstrap never parses a lock selector.
# shellcheck disable=SC1090
source "$BOOTSTRAP"

# Test fixtures are injected only after production functions have been loaded.
check_arch() {
  local line=""
  local os_id=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == ID=* ]]; then
      os_id="${line#ID=}"
      os_id="${os_id#\"}"
      os_id="${os_id%\"}"
      break
    fi
  done <"$TEST_OS_RELEASE"

  [[ "$os_id" == arch ]] || die 'unsupported operating system: require ID=arch'
}

resolve_hostname() {
  printf '%s\n' "$TEST_HOSTNAME"
}

# shellcheck disable=SC2034
SNAPPER_LIFECYCLE_LOCK="$TEST_LIFECYCLE_LOCK"
bootstrap_main "$@"
