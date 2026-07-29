#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WRAPPER="$SCRIPT_DIR/../scripts/suspend-in.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

BIN="$TEST_ROOT/bin"
export SYSTEMCTL_LOG="$TEST_ROOT/systemctl.log"
export SYSTEMD_RUN_LOG="$TEST_ROOT/systemd-run.log"
export NOTIFY_LOG="$TEST_ROOT/notify.log"
mkdir -p "$BIN"

cat >"$BIN/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
EOF

cat >"$BIN/systemd-run" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMD_RUN_LOG"
exit "${SYSTEMD_RUN_EXIT:-0}"
EOF

cat >"$BIN/date" <<'EOF'
#!/bin/bash
printf '23:45\n'
EOF

cat >"$BIN/notify-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOF

chmod +x "$BIN/systemctl" "$BIN/systemd-run" "$BIN/date" "$BIN/notify-send"
export PATH="$BIN:/usr/bin:/bin"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

reset_logs() {
  : >"$SYSTEMCTL_LOG"
  : >"$SYSTEMD_RUN_LOG"
  : >"$NOTIFY_LOG"
}

assert_file_equals() {
  local expected=$1
  local file=$2
  local actual
  actual=$(<"$file")
  [[ $actual == "$expected" ]] || fail "$file: expected '$expected', got '$actual'"
}

reset_logs
"$WRAPPER" 15 || fail "valid delay was rejected"
assert_file_equals $'--user stop vicinae-suspend.timer vicinae-suspend.service\n--user reset-failed vicinae-suspend.timer vicinae-suspend.service' "$SYSTEMCTL_LOG"
assert_file_equals '--user --unit=vicinae-suspend --on-active=15m --collect systemctl suspend' "$SYSTEMD_RUN_LOG"
[[ $(<"$NOTIFY_LOG") == *"Suspend scheduled"* ]] || fail "success notification title missing"
[[ $(<"$NOTIFY_LOG") == *"15 minutes"* ]] || fail "success notification delay missing"
[[ $(<"$NOTIFY_LOG") == *"23:45"* ]] || fail "success notification target time missing"

for value in "" 0 -1 1.5 later; do
  reset_logs
  if "$WRAPPER" "$value"; then
    fail "invalid delay '$value' was accepted"
  fi
  [[ ! -s $SYSTEMCTL_LOG ]] || fail "invalid delay '$value' changed timer state"
  [[ ! -s $SYSTEMD_RUN_LOG ]] || fail "invalid delay '$value' scheduled a timer"
  [[ $(<"$NOTIFY_LOG") == *"Suspend not scheduled"* ]] || fail "invalid delay notification missing"
done

reset_logs
export SYSTEMD_RUN_EXIT=1
if "$WRAPPER" 20; then
  fail "systemd-run failure returned success"
fi
unset SYSTEMD_RUN_EXIT
[[ -s $SYSTEMCTL_LOG ]] || fail "scheduler failure did not attempt timer replacement"
[[ $(<"$NOTIFY_LOG") == *"Suspend not scheduled"* ]] || fail "scheduler failure notification missing"

printf 'PASS: vicinae suspend timer\n'
