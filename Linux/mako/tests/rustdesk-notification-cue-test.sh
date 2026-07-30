#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
HELPER="$SCRIPT_DIR/../rustdesk-notification-cue"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local message=$3

  [[ $actual == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_empty_log() {
  [[ ! -s $NOTIFY_LOG ]] || fail "expected no cue, got: $(<"$NOTIFY_LOG")"
}

assert_no_private_content() {
  local log
  log=$(<"$NOTIFY_LOG")

  [[ $log != *'secret title'* && $log != *'secret body'* && $log != *'Signal'* ]] ||
    fail 'cue log exposed original notification content'
}

reset_fixture() {
  local app_name=${1:-Signal}
  local category=${2:-null}

  MAKO_LIST_JSON=$(jq -nc \
    --arg app_name "$app_name" \
    --argjson category "$category" \
    '[{id: 42, app_name: $app_name, category: $category, summary: "secret title", body: "secret body"}]')
  MAKO_MODE_OUTPUT=default
  MAKO_FAIL_LIST=false
  MAKO_FAIL_MODE=false
  export MAKO_LIST_JSON MAKO_MODE_OUTPUT MAKO_FAIL_LIST MAKO_FAIL_MODE
  : >"$NOTIFY_LOG"
}

run_helper() {
  "$HELPER" "$@" >"$HELPER_STDOUT" 2>"$HELPER_STDERR"
}

write_state() {
  printf '%s' "$1" >"$RUSTDESK_NOTIFICATION_CUE_STATE"
}

TEST_RUNTIME_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_RUNTIME_DIR"' EXIT
FAKE_BIN="$TEST_RUNTIME_DIR/bin"
mkdir -p -- "$FAKE_BIN"
export PATH="$FAKE_BIN:$PATH"
export XDG_RUNTIME_DIR="$TEST_RUNTIME_DIR"
export RUSTDESK_NOTIFICATION_CUE_STATE="$TEST_RUNTIME_DIR/rustdesk-notification-cue"
export NOTIFY_LOG="$TEST_RUNTIME_DIR/notify-send.log"
export HELPER_STDOUT="$TEST_RUNTIME_DIR/helper.stdout"
export HELPER_STDERR="$TEST_RUNTIME_DIR/helper.stderr"

cat >"$FAKE_BIN/makoctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list)
    [[ ${2:-} == -j && ${MAKO_FAIL_LIST:-false} != true ]] || exit 1
    printf '%s\n' "$MAKO_LIST_JSON"
    ;;
  mode)
    [[ $# == 1 && ${MAKO_FAIL_MODE:-false} != true ]] || exit 1
    printf '%s\n' "$MAKO_MODE_OUTPUT"
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$FAKE_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

for argument in "$@"; do
  printf '%s\n' "$argument"
done >>"$NOTIFY_LOG"
[[ ${NOTIFY_SEND_FAIL:-false} != true ]]
EOF
chmod +x "$FAKE_BIN/makoctl" "$FAKE_BIN/notify-send"

# A wrong output, direction, cue category, or notify-send argument must fail this test.
[[ -x $HELPER ]] || fail "helper is not executable: $HELPER"

reset_fixture
write_state 'DP-2|left'
run_helper 42
assert_equal $'--app-name=notify-send\n--category=rustdesk-notification-cue-DP-2\n--expire-time=5000\n--\n←' \
  "$(<"$NOTIFY_LOG")" 'DP-2 left cue arguments'
assert_no_private_content

for case in 'DVI-D-1|right|→' 'HDMI-A-1|up|↑' 'HDMI-A-1|down|↓' 'DP-2|none|•'; do
  IFS='|' read -r output direction symbol <<<"$case"
  reset_fixture
  write_state "$output|$direction"
  run_helper 42
  assert_equal $'--app-name=notify-send\n--category=rustdesk-notification-cue-'"$output"$'\n--expire-time=5000\n--\n'"$symbol" \
    "$(<"$NOTIFY_LOG")" "$output $direction cue arguments"
  assert_no_private_content
done

reset_fixture
rm -f -- "$RUSTDESK_NOTIFICATION_CUE_STATE"
run_helper 42
assert_empty_log

for state in 'DP-2left' 'DP-2|left|extra' 'UNKNOWN-1|left' 'DP-2|diagonal' $'DP-2|left\nuntrusted'; do
  reset_fixture
  write_state "$state"
  run_helper 42
  assert_empty_log
  [[ ! -s $HELPER_STDOUT && ! -s $HELPER_STDERR ]] || fail "invalid state emitted helper output: $state"
done

for id in '' 'not-a-number'; do
  reset_fixture
  write_state 'DP-2|left'
  if [[ -n $id ]]; then
    run_helper "$id"
  else
    run_helper
  fi
  assert_empty_log
done

reset_fixture
MAKO_LIST_JSON='[]'
write_state 'DP-2|left'
run_helper 42
assert_empty_log

for failure in list mode; do
  reset_fixture
  write_state 'DP-2|left'
  if [[ $failure == list ]]; then
    MAKO_FAIL_LIST=true
  else
    MAKO_FAIL_MODE=true
  fi
  run_helper 42
  assert_empty_log
  [[ ! -s $HELPER_STDOUT && ! -s $HELPER_STDERR ]] || fail "failed makoctl $failure exposed output"
done

reset_fixture Spotify
write_state 'DP-2|left'
run_helper 42
assert_empty_log

reset_fixture
MAKO_MODE_OUTPUT=$'default\ndo-not-disturb'
write_state 'DP-2|left'
run_helper 42
assert_empty_log

reset_fixture notify-send
MAKO_MODE_OUTPUT=$'default\ndo-not-disturb'
write_state 'DP-2|left'
run_helper 42
assert_equal $'--app-name=notify-send\n--category=rustdesk-notification-cue-DP-2\n--expire-time=5000\n--\n←' \
  "$(<"$NOTIFY_LOG")" 'notify-send cue allowed under do-not-disturb'

reset_fixture Signal '"rustdesk-notification-cue-DP-2"'
write_state 'DP-2|left'
run_helper 42
assert_empty_log

reset_fixture
NOTIFY_SEND_FAIL=true
write_state 'DP-2|left'
run_helper 42
assert_no_private_content
assert_equal $'--app-name=notify-send\n--category=rustdesk-notification-cue-DP-2\n--expire-time=5000\n--\n←' \
  "$(<"$NOTIFY_LOG")" 'failed notify-send is attempted once'
[[ ! -s $HELPER_STDOUT && ! -s $HELPER_STDERR ]] || fail 'failed notify-send exposed helper output'

printf 'PASS: rustdesk notification cue privacy and suppression tests\n'
