#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$SCRIPT_DIR/../../.." && pwd)
APPS_LUA="$ROOT/Linux/hypr/bindings/apps.lua"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"
printf $'#!/usr/bin/env bash\nprintf "%%s\\n" "$TEST_HOSTNAME"\n' >"$TEST_ROOT/bin/hostname"
chmod +x "$TEST_ROOT/bin/hostname"
export PATH="$TEST_ROOT/bin:$PATH"

run_app_bindings() {
  local hostname=$1

  TEST_HOSTNAME=$hostname lua - "$APPS_LUA" <<'LUA'
local config_path = arg[1]

hl = {
  bind = function(key, command, options)
    if key == "SUPER + ALT + R" or key == "SUPER + ALT + P" or key == "SUPER + CTRL + P" then
      print(key .. "=" .. command .. "|" .. options.description)
    end
  end,
  dsp = {
    exec_cmd = function(command)
      return command
    end,
  },
}

dofile(config_path)
LUA
}

antoinews_bindings=$(run_app_bindings antoinews-linux)
expected_antoinews_bindings=$'SUPER + ALT + R=uwsm app -- gtk-launch asbru-cm|Asbru\nSUPER + ALT + P=launch-or-focus 1password "uwsm app -- 1password"|1Password\nSUPER + CTRL + P=uwsm app -- 1password --quick-access|1Password Quick Access'
[[ $antoinews_bindings == "$expected_antoinews_bindings" ]] ||
  fail "antoinews-linux app bindings mismatch: $antoinews_bindings"

desktop_bindings=$(run_app_bindings DESKTOP-E07VTRN)
expected_desktop_bindings=$'SUPER + ALT + R=uwsm app -- gtk-launch org.remmina.Remmina|Remmina\nSUPER + ALT + P=launch-or-focus 1password "uwsm app -- 1password"|1Password\nSUPER + CTRL + P=uwsm app -- 1password --quick-access|1Password Quick Access'
[[ $desktop_bindings == "$expected_desktop_bindings" ]] ||
  fail "non-Asbru app bindings mismatch: $desktop_bindings"

printf 'PASS: app binding tests\n'
