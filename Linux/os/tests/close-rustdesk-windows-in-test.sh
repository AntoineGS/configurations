#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
HELPER="$SCRIPT_DIR/../helpers/close-rustdesk-windows-in"
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
  rm -rf -- "$TEST_ROOT"
}

trap cleanup EXIT

BIN="$TEST_ROOT/bin"
export EVENT_LOG="$TEST_ROOT/events.log"
export DATE_LOG="$TEST_ROOT/date.log"
export FLOCK_LOG="$TEST_ROOT/flock.log"
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
mkdir -p "$BIN" "$XDG_RUNTIME_DIR"

cat >"$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$EVENT_LOG"
EOF

cat >"$BIN/systemd-run" <<'EOF'
#!/usr/bin/env bash
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
#!/usr/bin/env bash
printf 'date' >>"$DATE_LOG"
printf ' %q' "$@" >>"$DATE_LOG"
printf '\n' >>"$DATE_LOG"

if [[ ${DATE_EXIT:-0} != 0 ]]; then
  exit "$DATE_EXIT"
fi

if [[ -v DATE_SECOND_ENTERED && $* == *"+20 minutes"* ]]; then
  : >"$DATE_SECOND_ENTERED"
fi

printf '23:45\n'
EOF

REAL_FLOCK=$(command -v flock)
export REAL_FLOCK
cat >"$BIN/flock" <<'EOF'
#!/usr/bin/env bash
printf 'flock' >>"$FLOCK_LOG"
printf ' %q' "$@" >>"$FLOCK_LOG"
printf '\n' >>"$FLOCK_LOG"

if [[ -v FLOCK_ENTERED ]]; then
  : >"$FLOCK_ENTERED"
fi
exec "$REAL_FLOCK" "$@"
EOF

cat >"$BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >>"$EVENT_LOG"
exit "${NOTIFY_SEND_EXIT:-0}"
EOF

cat >"$BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >>"$EVENT_LOG"

case "$*" in
  "instances -j")
    [[ ${HYPRCTL_INSTANCES_EXIT:-0} == 0 ]] || exit "$HYPRCTL_INSTANCES_EXIT"
    if [[ ${HYPRCTL_NO_INSTANCES:-0} == 1 ]]; then
      printf '[]\n'
    else
      printf '[{"instance":"OLD","time":100},{"instance":"NEW","time":200}]\n'
    fi
    ;;
  "-i NEW clients -j")
    [[ ${HYPRCTL_CLIENTS_EXIT:-0} == 0 ]] || exit "$HYPRCTL_CLIENTS_EXIT"
    if [[ ${HYPRCTL_ZERO_MATCHES:-0} == 1 ]]; then
      printf '[{"address":"0xccc","class":"org.example.Editor","title":"rustdesk notes"}]\n'
    else
      printf '[{"address":"0xaaa","class":"rustdesk","title":"Remote Desktop"},{"address":"0xbbb","class":"RustDesk","title":"Settings"},{"address":"0xccc","class":"org.example.Editor","title":"rustdesk notes"}]\n'
    fi
    ;;
  *" eval "*)
    if [[ ${HYPRCTL_CLOSE_FAIL_ADDRESS:-} != "" && $* == *"${HYPRCTL_CLOSE_FAIL_ADDRESS}"* ]]; then
      exit 1
    fi
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "$BIN/systemctl" "$BIN/systemd-run" "$BIN/date" "$BIN/flock" "$BIN/notify-send" "$BIN/hyprctl"
export PATH="$BIN:/usr/bin:/bin"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

reset_logs() {
  : >"$EVENT_LOG"
  : >"$DATE_LOG"
  : >"$FLOCK_LOG"
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

assert_events() {
  local expected=$1
  local actual

  actual=$(<"$EVENT_LOG")
  actual=${actual%$'\n'}
  [[ $actual == "$expected" ]] || fail "$EVENT_LOG: expected events '$expected', got '$actual'"
}

assert_flock_calls() {
  local expected_count=$1
  local call
  local -a calls=()

  mapfile -t calls <"$FLOCK_LOG"
  (( ${#calls[@]} == expected_count )) || fail "expected $expected_count flock calls, got ${#calls[@]}"
  for call in "${calls[@]}"; do
    [[ $call =~ ^flock\ [0-9]+$ ]] || fail "unexpected flock invocation: $call"
  done
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
assert_replacement_events $'systemctl --user stop vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service\nsystemctl --user reset-failed vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service\nsystemd-run --user --unit=vicinae-close-rustdesk-windows --on-active=15m --collect '"$(readlink -f "$HELPER")"$' --close-now\nsystemctl --user stop vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service\nsystemctl --user reset-failed vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service\nsystemd-run --user --unit=vicinae-close-rustdesk-windows --on-active=30m --collect '"$(readlink -f "$HELPER")"$' --close-now'
assert_file_equals $'date --date=+15\\ minutes +%H:%M\ndate --date=+30\\ minutes +%H:%M' "$DATE_LOG"
assert_flock_calls 2

reset_logs
export SYSTEMD_RUN_ENTERED="$TEST_ROOT/entered"
export DATE_SECOND_ENTERED="$TEST_ROOT/date-second-entered"
export SYSTEMD_RUN_RELEASE="$TEST_ROOT/release"
FLOCK_ENTERED="$TEST_ROOT/first-flock-entered" "$HELPER" 10 &
first_pid=$!
wait_for_file "$SYSTEMD_RUN_ENTERED" || fail "first invocation did not reach scheduler"
FLOCK_ENTERED="$TEST_ROOT/second-flock-entered" "$HELPER" 20 &
second_pid=$!
wait_for_file "$TEST_ROOT/second-flock-entered" || fail "second invocation did not attempt replacement lock"
[[ ! -e $DATE_SECOND_ENTERED ]] || fail "second invocation calculated target time before acquiring replacement lock"
: >"$SYSTEMD_RUN_RELEASE"
wait "$first_pid" || fail "first concurrent invocation failed"
wait_for_file "$DATE_SECOND_ENTERED" || fail "second invocation did not calculate target time after acquiring replacement lock"
wait "$second_pid" || fail "second concurrent invocation failed"
unset SYSTEMD_RUN_ENTERED DATE_SECOND_ENTERED SYSTEMD_RUN_RELEASE
assert_replacement_events $'systemctl --user stop vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service\nsystemctl --user reset-failed vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service\nsystemd-run --user --unit=vicinae-close-rustdesk-windows --on-active=10m --collect '"$(readlink -f "$HELPER")"$' --close-now\nsystemctl --user stop vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service\nsystemctl --user reset-failed vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service\nsystemd-run --user --unit=vicinae-close-rustdesk-windows --on-active=20m --collect '"$(readlink -f "$HELPER")"$' --close-now'
assert_file_equals $'date --date=+10\\ minutes +%H:%M\ndate --date=+20\\ minutes +%H:%M' "$DATE_LOG"
assert_flock_calls 2

for value in "" 0 -1 1.5 later; do
  reset_logs
  if "$HELPER" "$value"; then
    fail "invalid delay '$value' was accepted"
  fi
  [[ $(<"$EVENT_LOG") == *"Close not scheduled Enter a positive whole number of minutes."* ]] || fail "invalid delay notification missing"
  [[ $(<"$EVENT_LOG") != *"systemctl"* ]] || fail "invalid delay '$value' changed timer state"
  [[ $(<"$EVENT_LOG") != *"systemd-run"* ]] || fail "invalid delay '$value' scheduled a timer"
done

reset_logs
if "$HELPER" 15 extra; then
  fail "extra arguments were accepted"
fi
[[ $(<"$EVENT_LOG") == *"Close not scheduled Enter a positive whole number of minutes."* ]] || fail "extra argument notification missing"
[[ $(<"$EVENT_LOG") != *"systemctl"* ]] || fail "extra arguments changed timer state"
[[ $(<"$EVENT_LOG") != *"systemd-run"* ]] || fail "extra arguments scheduled a timer"

reset_logs
export DATE_EXIT=1
if "$HELPER" 20; then
  fail "date failure returned success"
fi
unset DATE_EXIT
[[ $(<"$EVENT_LOG") == *"Close not scheduled The requested delay is too large."* ]] || fail "date failure notification missing"
[[ $(<"$EVENT_LOG") != *"systemctl"* ]] || fail "date failure changed timer state"

reset_logs
unset XDG_RUNTIME_DIR
if "$HELPER" 20; then
  fail "missing XDG_RUNTIME_DIR returned success"
fi
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
[[ $(<"$EVENT_LOG") == *"Close not scheduled Could not lock the RustDesk close timer."* ]] || fail "missing XDG_RUNTIME_DIR notification missing"
[[ $(<"$EVENT_LOG") != *"systemctl"* ]] || fail "missing XDG_RUNTIME_DIR changed timer state"
[[ $(<"$EVENT_LOG") != *"systemd-run"* ]] || fail "missing XDG_RUNTIME_DIR scheduled a timer"

reset_logs
export SYSTEMD_RUN_EXIT=1
if "$HELPER" 20; then
  fail "scheduler failure returned success"
fi
unset SYSTEMD_RUN_EXIT
[[ $(<"$EVENT_LOG") == *"systemctl"* ]] || fail "scheduler failure did not attempt timer replacement"
[[ $(<"$EVENT_LOG") == *"Close not scheduled Could not create the RustDesk close timer."* ]] || fail "scheduler failure notification missing"

reset_logs
export NOTIFY_SEND_EXIT=1
"$HELPER" 20 || fail "failed success notification returned failure"
unset NOTIFY_SEND_EXIT
[[ $(<"$EVENT_LOG") == *"systemd-run"* ]] || fail "notification failure did not schedule a timer"

reset_logs
"$HELPER" --close-now || fail "RustDesk close mode was rejected"
assert_events $'hyprctl instances -j\nhyprctl -i NEW clients -j\nhyprctl -i NEW eval hl.dispatch(hl.dsp.window.close({window="address:0xaaa"}))\nhyprctl -i NEW eval hl.dispatch(hl.dsp.window.close({window="address:0xbbb"}))\nnotify-send -a vicinae RustDesk windows closed Closed 2 RustDesk windows.'
[[ $(<"$EVENT_LOG") != *"0xccc"* ]] || fail "non-RustDesk window received a close request"

reset_logs
export HYPRCTL_NO_INSTANCES=1
if "$HELPER" --close-now; then
  fail "no active Hyprland instance returned success"
fi
unset HYPRCTL_NO_INSTANCES
[[ $(<"$EVENT_LOG") == *"RustDesk windows not closed"* ]] || fail "no-instance failure notification missing"
[[ $(<"$EVENT_LOG") != *"clients -j"* ]] || fail "no-instance mode enumerated clients"

reset_logs
export HYPRCTL_CLIENTS_EXIT=1
if "$HELPER" --close-now; then
  fail "client enumeration failure returned success"
fi
unset HYPRCTL_CLIENTS_EXIT
[[ $(<"$EVENT_LOG") == *"RustDesk windows not closed"* ]] || fail "client enumeration failure notification missing"

reset_logs
export HYPRCTL_ZERO_MATCHES=1
"$HELPER" --close-now || fail "zero RustDesk windows should succeed"
unset HYPRCTL_ZERO_MATCHES
[[ $(<"$EVENT_LOG") == *"No RustDesk windows were open."* ]] || fail "zero-match completion notification missing"

reset_logs
export HYPRCTL_CLOSE_FAIL_ADDRESS=0xaaa
if "$HELPER" --close-now; then
  fail "partial close failure returned success"
fi
unset HYPRCTL_CLOSE_FAIL_ADDRESS
[[ $(<"$EVENT_LOG") == *"address:0xaaa"* && $(<"$EVENT_LOG") == *"address:0xbbb"* ]] || fail "partial failure did not attempt every RustDesk window"

printf 'PASS: vicinae RustDesk close timer scheduling\n'
