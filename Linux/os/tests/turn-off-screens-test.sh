#!/bin/bash

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
HELPER="$REPO_ROOT/Linux/os/helpers/turn-off-screens"
WRAPPER="$REPO_ROOT/Linux/vicinae/scripts/turn-off-screens.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

BIN="$TEST_ROOT/bin"
HOME_DIR="$TEST_ROOT/home"
SLEEP_LOG="$TEST_ROOT/sleep-args"
HYPRCTL_LOG="$TEST_ROOT/hyprctl-args"
WRAPPER_LOG="$TEST_ROOT/wrapper-args"
mkdir -p "$BIN" "$HOME_DIR/.local/share/helpers"

cat >"$BIN/sleep" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_SLEEP_LOG"
EOF

cat >"$BIN/hyprctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_HYPRCTL_LOG"
EOF

cat >"$HOME_DIR/.local/share/helpers/turn-off-screens" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_WRAPPER_LOG"
EOF

chmod +x "$BIN/sleep" "$BIN/hyprctl" "$HOME_DIR/.local/share/helpers/turn-off-screens"

assert_file_equals() {
  local expected=$1
  local file=$2
  local actual
  actual=$(<"$file")
  if [[ $actual != "$expected" ]]; then
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

wait_for_file() {
  local file=$1
  for ((attempt = 0; attempt < 50; attempt++)); do
    [[ -f $file ]] && return 0
    /bin/sleep 0.02
  done
  printf 'timed out waiting for %s\n' "$file" >&2
  return 1
}

run_helper() {
  rm -f "$SLEEP_LOG" "$HYPRCTL_LOG"
  PATH="$BIN:$PATH" TEST_SLEEP_LOG="$SLEEP_LOG" TEST_HYPRCTL_LOG="$HYPRCTL_LOG" "$HELPER" "$@"
  wait_for_file "$SLEEP_LOG"
  wait_for_file "$HYPRCTL_LOG"
}

run_helper
assert_file_equals '0' "$SLEEP_LOG"
assert_file_equals $'eval\nhl.dispatch(hl.dsp.dpms({action="off"}))' "$HYPRCTL_LOG"

run_helper 2.5
assert_file_equals '2.5' "$SLEEP_LOG"

for invalid in -1 nope 1s; do
  if PATH="$BIN:$PATH" "$HELPER" "$invalid" 2>"$TEST_ROOT/error"; then
    printf 'accepted invalid delay: %s\n' "$invalid" >&2
    exit 1
  fi
  assert_file_equals 'turn-off-screens: seconds must be a non-negative number' "$TEST_ROOT/error"
done

if PATH="$BIN:$PATH" "$HELPER" 1 2 2>"$TEST_ROOT/error"; then
  printf 'accepted extra argument\n' >&2
  exit 1
fi
assert_file_equals 'usage: turn-off-screens [seconds]' "$TEST_ROOT/error"

HOME="$HOME_DIR" TEST_WRAPPER_LOG="$WRAPPER_LOG" "$WRAPPER"
assert_file_equals '2' "$WRAPPER_LOG"

printf '%s\n' 'turn-off-screens tests passed'
