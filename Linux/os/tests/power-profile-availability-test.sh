#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
POWERPROFILES_LIST="$ROOT/Linux/os/helpers/powerprofiles-list"
MENU="$ROOT/Linux/os/helpers/menu"
WAYBAR_TEMPLATE="$ROOT/Linux/waybar/config.jsonc.tmpl"
TEST_ROOT="$(mktemp -d)"
BIN="$TEST_ROOT/bin"
MENU_OPTIONS="$TEST_ROOT/menu-options"
ERROR_LOG="$TEST_ROOT/errors.log"
mkdir -p -- "$BIN" "$TEST_ROOT/home"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

printf '%s\n' '#!/bin/bash' 'exit 1' >"$BIN/pgrep"
# shellcheck disable=SC2016 # These lines are generated for the runtime menu stub.
printf '%s\n' \
  '#!/bin/bash' \
  ': >"$POWER_PROFILE_MENU_OPTIONS"' \
  'while IFS= read -r line || [[ -n "$line" ]]; do printf "%s\\n" "$line" >>"$POWER_PROFILE_MENU_OPTIONS"; done' \
  'printf "CNCLD\\n"' >"$BIN/vicinae"
chmod +x -- "$BIN/pgrep" "$BIN/vicinae"
ln -s -- /usr/bin/awk "$BIN/awk"
ln -s -- /usr/bin/tac "$BIN/tac"

if ! list_output=$(PATH="$BIN" "$POWERPROFILES_LIST" 2>"$ERROR_LOG"); then
  fail 'powerprofiles-list failed without powerprofilesctl'
fi
[[ -z "$list_output" ]] || fail "powerprofiles-list returned profiles without powerprofilesctl: $list_output"
[[ ! -s "$ERROR_LOG" ]] || fail "powerprofiles-list emitted an error without powerprofilesctl: $(<"$ERROR_LOG")"

PATH="$BIN" \
  HOME="$TEST_ROOT/home" \
  POWER_PROFILE_MENU_OPTIONS="$MENU_OPTIONS" \
  "$MENU" setup >/dev/null 2>"$ERROR_LOG" || fail 'setup menu failed without powerprofilesctl'
if grep -Fq 'Power Profile' "$MENU_OPTIONS"; then
  fail 'setup menu exposed Power Profile without powerprofilesctl'
fi
[[ ! -s "$ERROR_LOG" ]] || fail "setup menu emitted an error without powerprofilesctl: $(<"$ERROR_LOG")"

grep -Fq 'command -v powerprofilesctl >/dev/null 2>&1 &&' "$WAYBAR_TEMPLATE" || \
  fail 'Waybar power-profile action is not conditional on powerprofilesctl'

printf 'PASS: power-profile actions fail safely without powerprofilesctl\n'
