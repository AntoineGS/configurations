#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helpers=$repo_root/Linux/os/helpers
suspend_helper=$helpers/suspend-in
rustdesk_helper=$helpers/close-rustdesk-windows-in
test_root=$(mktemp -d)
bin=$test_root/bin
runtime=$test_root/runtime
call_log=$test_root/calls.log
notify_log=$test_root/notify.log

trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

install -d -m 700 "$bin" "$runtime"

cat >"$bin/command-stub" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${0##*/}" >>"$SCHEDULE_TEST_CALL_LOG"
if (( $# > 0 )); then printf ' %s' "$@" >>"$SCHEDULE_TEST_CALL_LOG"; fi
printf '\n' >>"$SCHEDULE_TEST_CALL_LOG"
EOF
for command in systemctl systemd-run; do ln -s command-stub "$bin/$command"; done
cat >"$bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SCHEDULE_TEST_NOTIFY_LOG"
EOF
cat >"$bin/date" <<'EOF'
#!/usr/bin/env bash
printf '12:34\n'
EOF
chmod +x "$bin"/*

run_env=(
  PATH="$bin:$PATH"
  XDG_RUNTIME_DIR="$runtime"
  SCHEDULE_TEST_CALL_LOG="$call_log"
  SCHEDULE_TEST_NOTIFY_LOG="$notify_log"
)

env "${run_env[@]}" "$suspend_helper" 15
grep -Fqx 'systemctl --user stop vicinae-suspend.timer vicinae-suspend.service desktop-shell-suspend.timer desktop-shell-suspend.service' "$call_log" || fail "suspend did not replace old and new units"
grep -Fqx 'systemctl --user reset-failed vicinae-suspend.timer vicinae-suspend.service desktop-shell-suspend.timer desktop-shell-suspend.service' "$call_log" || fail "suspend did not reset old and new units"
grep -Fqx 'systemd-run --user --unit=desktop-shell-suspend --on-active=15m --collect systemctl suspend' "$call_log" || fail "suspend used the wrong transient unit"
[[ -f $runtime/desktop-shell-suspend.lock ]] || fail "suspend used the wrong lock path"
grep -F -- '-a desktop-shell' "$notify_log" >/dev/null || fail "suspend notifications use the wrong app name"

: >"$call_log"
: >"$notify_log"
env "${run_env[@]}" "$rustdesk_helper" 30
grep -Fqx 'systemctl --user stop vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service desktop-shell-close-rustdesk-windows.timer desktop-shell-close-rustdesk-windows.service' "$call_log" || fail "RustDesk did not replace old and new units"
grep -Fqx 'systemctl --user reset-failed vicinae-close-rustdesk-windows.timer vicinae-close-rustdesk-windows.service desktop-shell-close-rustdesk-windows.timer desktop-shell-close-rustdesk-windows.service' "$call_log" || fail "RustDesk did not reset old and new units"
grep -Fqx "systemd-run --user --unit=desktop-shell-close-rustdesk-windows --on-active=30m --collect $rustdesk_helper --close-now" "$call_log" || fail "RustDesk used the wrong transient unit"
[[ -f $runtime/desktop-shell-close-rustdesk-windows.lock ]] || fail "RustDesk used the wrong lock path"
grep -F -- '-a desktop-shell' "$notify_log" >/dev/null || fail "RustDesk notifications use the wrong app name"

for invalid in 0 -1 1.5 text ''; do
  : >"$call_log"
  expect_failure env "${run_env[@]}" "$suspend_helper" "$invalid"
  ! grep -q '^systemd-run ' "$call_log" || fail "invalid suspend input created a timer"
done

expect_failure env -u XDG_RUNTIME_DIR PATH="$bin:$PATH" SCHEDULE_TEST_CALL_LOG="$call_log" SCHEDULE_TEST_NOTIFY_LOG="$notify_log" "$suspend_helper" 5
expect_failure env -u XDG_RUNTIME_DIR PATH="$bin:$PATH" SCHEDULE_TEST_CALL_LOG="$call_log" SCHEDULE_TEST_NOTIFY_LOG="$notify_log" "$rustdesk_helper" 5

printf 'PASS: generic scheduled desktop actions\n'
