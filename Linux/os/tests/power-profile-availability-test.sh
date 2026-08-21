#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
POWERPROFILES_LIST="$ROOT/Linux/os/helpers/powerprofiles-list"
TEST_ROOT="$(mktemp -d)"
BIN="$TEST_ROOT/bin"
ERROR_LOG="$TEST_ROOT/errors.log"
mkdir -p -- "$BIN"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

printf '%s\n' '#!/bin/bash' 'exit 1' >"$BIN/pgrep"
chmod +x -- "$BIN/pgrep"
ln -s -- /usr/bin/awk "$BIN/awk"
ln -s -- /usr/bin/tac "$BIN/tac"

if ! list_output=$(PATH="$BIN" "$POWERPROFILES_LIST" 2>"$ERROR_LOG"); then
  fail 'powerprofiles-list failed without powerprofilesctl'
fi
[[ -z "$list_output" ]] || fail "powerprofiles-list returned profiles without powerprofilesctl: $list_output"
[[ ! -s "$ERROR_LOG" ]] || fail "powerprofiles-list emitted an error without powerprofilesctl: $(<"$ERROR_LOG")"

printf 'PASS: power-profile actions fail safely without powerprofilesctl\n'
