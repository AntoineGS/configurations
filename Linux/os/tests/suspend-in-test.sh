#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HELPER="$SCRIPT_DIR/../helpers/suspend-in"
TEST_ROOT=$(mktemp -d)

cleanup() {
  if [[ -v SYSTEMD_RUN_RELEASE ]]; then
    : >"$SYSTEMD_RUN_RELEASE"
  fi
  if [[ -v first_pid ]]; then
    wait "$first_pid" 2>/dev/null || true
  fi
  if [[ -v second_pid ]]; then
    wait "$second_pid" 2>/dev/null || true
  fi
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

BIN="$TEST_ROOT/bin"
export EVENT_LOG="$TEST_ROOT/events.log"
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
mkdir -p "$BIN"
mkdir -p "$XDG_RUNTIME_DIR"

cat >"$BIN/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$EVENT_LOG"
EOF

cat >"$BIN/systemd-run" <<'EOF'
#!/bin/bash
printf 'systemd-run %s\n' "$*" >>"$EVENT_LOG"

case "$*" in
  *"--on-active=10m"*)
    : >"$SYSTEMD_RUN_ENTERED"
    while [[ ! -e $SYSTEMD_RUN_RELEASE ]]; do
      sleep 0.01
    done
    ;;
  *"--on-active=20m"*)
    if [[ -v SYSTEMD_RUN_SECOND_ENTERED ]]; then
      : >"$SYSTEMD_RUN_SECOND_ENTERED"
    fi
    ;;
esac

exit "${SYSTEMD_RUN_EXIT:-0}"
EOF

cat >"$BIN/date" <<'EOF'
#!/bin/bash
if [[ ${DATE_EXIT:-0} != 0 ]]; then
  exit "$DATE_EXIT"
fi

if [[ -v DATE_SECOND_ENTERED && $* == *"+20 minutes"* ]]; then
  : >"$DATE_SECOND_ENTERED"
fi

printf '23:45\n'
EOF

cat >"$BIN/notify-send" <<'EOF'
#!/bin/bash
printf 'notify-send %s\n' "$*" >>"$EVENT_LOG"
exit "${NOTIFY_SEND_EXIT:-0}"
EOF

chmod +x "$BIN/systemctl" "$BIN/systemd-run" "$BIN/date" "$BIN/notify-send"
export PATH="$BIN:/usr/bin:/bin"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

reset_logs() {
  : >"$EVENT_LOG"
}

assert_file_equals() {
  local expected=$1
  local file=$2
  local actual
  actual=$(<"$file")
  [[ $actual == "$expected" ]] || fail "$file: expected '$expected', got '$actual'"
}

assert_replacement_events() {
  local expected=$1
  local event
  local actual=""

  while IFS= read -r event; do
    if [[ $event == systemctl\ * || $event == systemd-run\ * ]]; then
      actual+="$event"$'\n'
    fi
  done <"$EVENT_LOG"

  actual=${actual%$'\n'}
  [[ $actual == "$expected" ]] || fail "$EVENT_LOG: expected replacement events '$expected', got '$actual'"
}

wait_for_file() {
  local file=$1
  local attempts=0

  while [[ ! -e $file ]] && (( attempts < 100 )); do
    sleep 0.01
    ((attempts += 1))
  done

  [[ -e $file ]]
}

reset_logs
"$HELPER" 15 || fail "valid delay was rejected"
"$HELPER" 30 || fail "replacement delay was rejected"
assert_file_equals $'systemctl --user stop vicinae-suspend.timer vicinae-suspend.service\nsystemctl --user reset-failed vicinae-suspend.timer vicinae-suspend.service\nsystemd-run --user --unit=vicinae-suspend --on-active=15m --collect systemctl suspend\nnotify-send -a vicinae Suspend scheduled Suspending in 15 minutes, at 23:45.\nsystemctl --user stop vicinae-suspend.timer vicinae-suspend.service\nsystemctl --user reset-failed vicinae-suspend.timer vicinae-suspend.service\nsystemd-run --user --unit=vicinae-suspend --on-active=30m --collect systemctl suspend\nnotify-send -a vicinae Suspend scheduled Suspending in 30 minutes, at 23:45.' "$EVENT_LOG"

reset_logs
export SYSTEMD_RUN_ENTERED="$TEST_ROOT/entered"
export DATE_SECOND_ENTERED="$TEST_ROOT/date-second-entered"
export SYSTEMD_RUN_SECOND_ENTERED="$TEST_ROOT/second-entered"
export SYSTEMD_RUN_RELEASE="$TEST_ROOT/release"
"$HELPER" 10 &
first_pid=$!
wait_for_file "$SYSTEMD_RUN_ENTERED" || fail "first invocation did not reach scheduler"
"$HELPER" 20 &
second_pid=$!
wait_for_file "$DATE_SECOND_ENTERED" || fail "second invocation did not reach timer replacement"
if wait_for_file "$SYSTEMD_RUN_SECOND_ENTERED"; then
  fail "concurrent replacement was not serialized"
fi
: >"$SYSTEMD_RUN_RELEASE"
wait "$first_pid" || fail "first concurrent invocation failed"
wait "$second_pid" || fail "second concurrent invocation failed"
unset SYSTEMD_RUN_ENTERED DATE_SECOND_ENTERED SYSTEMD_RUN_SECOND_ENTERED SYSTEMD_RUN_RELEASE
assert_replacement_events $'systemctl --user stop vicinae-suspend.timer vicinae-suspend.service\nsystemctl --user reset-failed vicinae-suspend.timer vicinae-suspend.service\nsystemd-run --user --unit=vicinae-suspend --on-active=10m --collect systemctl suspend\nsystemctl --user stop vicinae-suspend.timer vicinae-suspend.service\nsystemctl --user reset-failed vicinae-suspend.timer vicinae-suspend.service\nsystemd-run --user --unit=vicinae-suspend --on-active=20m --collect systemctl suspend'

for value in "" 0 -1 1.5 later; do
  reset_logs
  if "$HELPER" "$value"; then
    fail "invalid delay '$value' was accepted"
  fi
  [[ $(<"$EVENT_LOG") == *"Suspend not scheduled"* ]] || fail "invalid delay notification missing"
  [[ $(<"$EVENT_LOG") != *"systemctl"* ]] || fail "invalid delay '$value' changed timer state"
  [[ $(<"$EVENT_LOG") != *"systemd-run"* ]] || fail "invalid delay '$value' scheduled a timer"
done

reset_logs
export DATE_EXIT=1
if "$HELPER" 20; then
  fail "date failure returned success"
fi
unset DATE_EXIT
[[ $(<"$EVENT_LOG") == *"Suspend not scheduled The requested delay is too large."* ]] || fail "date failure notification missing"
[[ $(<"$EVENT_LOG") != *"systemctl"* ]] || fail "date failure changed timer state"

reset_logs
export SYSTEMD_RUN_EXIT=1
if "$HELPER" 20; then
  fail "systemd-run failure returned success"
fi
unset SYSTEMD_RUN_EXIT
[[ $(<"$EVENT_LOG") == *"systemctl"* ]] || fail "scheduler failure did not attempt timer replacement"
[[ $(<"$EVENT_LOG") == *"Suspend not scheduled"* ]] || fail "scheduler failure notification missing"

reset_logs
export NOTIFY_SEND_EXIT=1
"$HELPER" 20 || fail "failed success notification returned failure"
unset NOTIFY_SEND_EXIT
[[ $(<"$EVENT_LOG") == *"systemd-run"* ]] || fail "notification failure did not schedule a timer"

printf 'PASS: vicinae suspend timer\n'
