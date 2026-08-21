#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
ACTIVATE="$ROOT/Linux/os/helpers/desktop-shell-activate"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected=$1 actual=$2 message=$3
  [[ $actual == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack=$1 needle=$2 message=$3
  [[ $haystack == *"$needle"* ]] || fail "$message: missing '$needle'"
}

assert_not_contains() {
  local haystack=$1 needle=$2 message=$3
  [[ $haystack != *"$needle"* ]] || fail "$message: found '$needle'"
}

TEST_ROOT=$(mktemp -d)
BIN="$TEST_ROOT/bin"
RUNTIME_DIR="$TEST_ROOT/runtime"
COMMAND_LOG="$TEST_ROOT/commands.log"
MUTATION_LOG="$TEST_ROOT/mutations.log"
CUE_FILE="$RUNTIME_DIR/rustdesk-notification-cue"
OWNER_SEQUENCE="$TEST_ROOT/owners"
SHOW_SEQUENCE="$TEST_ROOT/main-pids"
SHOW_COUNT="$TEST_ROOT/main-pid-count"
PING_COUNT="$TEST_ROOT/ping-count"
HEALTH_COUNT="$TEST_ROOT/health-count"
HEALTH_JSON="$TEST_ROOT/health.json"
STDOUT_FILE="$TEST_ROOT/stdout"
STDERR_FILE="$TEST_ROOT/stderr"

mkdir -p "$BIN" "$RUNTIME_DIR"

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  rm -rf -- "$TEST_ROOT"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

cat >"$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'systemctl|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${COMMAND_LOG:?}"
[[ ${1:-} == --user ]] || exit 125
shift
case ${1:-} in
  restart)
    [[ $# == 2 ]] || exit 125
    case ${2:-} in
      watch-rustdesk-submap.service)
        if ((FAIL_ROUTE_RESTART != 0)); then exit "$FAIL_ROUTE_RESTART"; fi
        printf 'systemctl --user restart watch-rustdesk-submap.service\n' >>"${MUTATION_LOG:?}"
        ;;
      desktop-shell.service)
        if ((FAIL_SHELL_RESTART != 0)); then exit "$FAIL_SHELL_RESTART"; fi
        printf 'systemctl --user restart desktop-shell.service\n' >>"${MUTATION_LOG:?}"
        ;;
      *) exit 125 ;;
    esac
    ;;
  is-active)
    [[ ${2:-} == --quiet ]] || exit 125
    case ${3:-} in
      watch-rustdesk-submap.service) exit "$FAIL_ROUTE_ACTIVE" ;;
      desktop-shell.service) exit "$FAIL_SHELL_ACTIVE" ;;
      *) exit 125 ;;
    esac
    ;;
  show)
    [[ ${2:-} == desktop-shell.service && ${3:-} == --property=MainPID &&
      ${4:-} == --value && $# == 4 ]] || exit 125
    count=$(<"${SHOW_COUNT:?}")
    count=$((count + 1))
    printf '%s\n' "$count" >"$SHOW_COUNT"
    awk -v line_no="$count" 'NR == line_no { print; found = 1; exit } END { exit !found }' "${SHOW_SEQUENCE:?}"
    ;;
  *)
    printf 'DENIED systemctl fallback operation: %s\n' "$*" >>"${COMMAND_LOG:?}"
    exit 125
    ;;
esac
EOF

cat >"$BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'pgrep|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${COMMAND_LOG:?}"
[[ ${1:-} == -x && ${2:-} == -- && $# == 3 ]] || exit 125
[[ $3 == quickshell ]] || {
  printf 'DENIED fallback process discovery: %s\n' "$*" >>"${COMMAND_LOG:?}"
  exit 125
}
printf '%s\n' 5001 5002
EOF

cat >"$BIN/readlink" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'readlink|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${COMMAND_LOG:?}"
[[ ${1:-} == -- && ${2:-} =~ ^/proc/(5001|5002)/exe$ && $# == 2 ]] || exit 125
printf '%s\n' /usr/bin/quickshell
EOF

cat >"$BIN/busctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'busctl|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${COMMAND_LOG:?}"
[[ ${1:-} == --user && ${2:-} == call && ${3:-} == org.freedesktop.DBus &&
  ${4:-} == /org/freedesktop/DBus && ${5:-} == org.freedesktop.DBus &&
  ${6:-} == GetConnectionUnixProcessID && ${7:-} == s &&
  ${8:-} == org.freedesktop.Notifications && $# == 8 ]] || exit 125
if [[ -s ${OWNER_SEQUENCE:?} ]]; then
  line=$(sed -n '1p' "$OWNER_SEQUENCE")
  sed -i '1d' "$OWNER_SEQUENCE"
  printf '%s\n' "$line"
else
  printf 'u 5001\n'
fi
EOF

cat >"$BIN/desktop-shell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'desktop-shell|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${COMMAND_LOG:?}"
[[ ${1:-} == --pid && ${2:-} =~ ^(5001|5002)$ && $# == 3 ]] || exit 125
case $3 in
  ping)
    count=$(<"${PING_COUNT:?}")
    count=$((count + 1))
    printf '%s\n' "$count" >"$PING_COUNT"
    ((count > PING_FAILURES)) || exit 1
    printf 'pong\n'
    ;;
  health)
    count=$(<"${HEALTH_COUNT:?}")
    count=$((count + 1))
    printf '%s\n' "$count" >"$HEALTH_COUNT"
    ((count > HEALTH_FAILURES)) || exit 1
    cat "$HEALTH_JSON"
    ;;
  *) exit 125 ;;
esac
EOF

cat >"$BIN/rm" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'rm|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${COMMAND_LOG:?}"
[[ ${1:-} == -f && ${2:-} == -- && ${3:-} == "${CUE_FILE:?}" && $# == 3 ]] || exit 125
exec /usr/bin/rm -f -- "$3"
EOF

cat >"$BIN/timeout" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'timeout|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${COMMAND_LOG:?}"
if ((IPC_TIMEOUT_STATUS != 0)) && [[ " $* " == *' desktop-shell '* ]]; then
  exit "$IPC_TIMEOUT_STATUS"
fi
while (($# > 0)); do
  case $1 in
    --signal=*|--kill-after=*) shift ;;
    --signal|--kill-after) shift 2 ;;
    *s) shift ;;
    *) break ;;
  esac
done
exec "$@"
EOF

cat >"$BIN/flock" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'flock|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${COMMAND_LOG:?}"
exec /usr/bin/flock "$@"
EOF

for command in systemctl pgrep readlink busctl desktop-shell rm timeout flock; do
  chmod +x "$BIN/$command"
done

fallback_commands=(
  kill pkill mako makoctl swayosd swayosd-server swayosd-client
  uwsm-app polkit-gnome-authentication-agent-1
)

for command in "${fallback_commands[@]}"; do
  cat >"$BIN/$command" <<EOF
#!/usr/bin/env bash
printf 'DENIED fallback command: %s|%s\\n' "$command" "\$*" >>"\${COMMAND_LOG:?}"
exit 125
EOF
  chmod +x "$BIN/$command"
done

assert_fallback_commands_denied() {
  local command status

  for command in "${fallback_commands[@]}"; do
    status=0
    PATH="$BIN:/usr/bin:/bin" /usr/bin/env "$command" >/dev/null 2>&1 || status=$?
    ((status != 0)) || fail "fallback command unexpectedly executed: $command"
    assert_contains "$(<"$COMMAND_LOG")" "DENIED fallback command: $command|" \
      "fallback command was not logged: $command"
  done
}

export COMMAND_LOG MUTATION_LOG CUE_FILE OWNER_SEQUENCE SHOW_SEQUENCE SHOW_COUNT PING_COUNT HEALTH_COUNT HEALTH_JSON
export FAIL_ROUTE_RESTART=0 FAIL_SHELL_RESTART=0 FAIL_ROUTE_ACTIVE=0 FAIL_SHELL_ACTIVE=0
export PING_FAILURES=0 HEALTH_FAILURES=0 IPC_TIMEOUT_STATUS=0
: >"$COMMAND_LOG"
assert_fallback_commands_denied

reset_case() {
  : >"$COMMAND_LOG"
  : >"$MUTATION_LOG"
  : >"$OWNER_SEQUENCE"
  printf '%s\n' 5001 5001 >"$SHOW_SEQUENCE"
  printf '%s\n' 0 >"$SHOW_COUNT"
  printf '%s\n' 0 >"$PING_COUNT"
  printf '%s\n' 0 >"$HEALTH_COUNT"
  printf '%s\n' '{"notificationsOwned":true,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":""}' >"$HEALTH_JSON"
  rm -f -- "$CUE_FILE" "$RUNTIME_DIR/desktop-shell-lifecycle.lock"
  FAIL_ROUTE_RESTART=0 FAIL_SHELL_RESTART=0 FAIL_ROUTE_ACTIVE=0 FAIL_SHELL_ACTIVE=0
  PING_FAILURES=0 HEALTH_FAILURES=0 IPC_TIMEOUT_STATUS=0
}

run_activation() {
  local status=0
  PATH="$BIN:/usr/bin:/bin" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    "$ACTIVATE" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?
  return "$status"
}

assert_success_trace() {
  local expected=$'systemctl --user restart watch-rustdesk-submap.service\nsystemctl --user restart desktop-shell.service'
  assert_equal "$expected" "$(<"$MUTATION_LOG")" 'active mutation trace'
}

assert_no_fallback_commands() {
  local log
  log=$(<"$COMMAND_LOG")
  for forbidden in mako swayosd polkit-gnome desktop-shell-mako-route mask unmask; do
    assert_not_contains "$log" "$forbidden" "fallback operation: $forbidden"
  done
  assert_not_contains "$log" 'DENIED fallback' 'fallback command attempted'
  assert_not_contains "$log" 'DENIED systemctl fallback' 'fallback systemctl operation attempted'
}

assert_no_shell_readiness() {
  local log
  log=$(<"$COMMAND_LOG")
  assert_not_contains "$log" 'systemctl|--user|show|desktop-shell.service' \
    'failure reached desktop-shell MainPID readiness'
  assert_not_contains "$log" 'busctl|' 'failure reached notification-owner readiness'
  assert_not_contains "$log" 'desktop-shell|' 'failure reached desktop-shell IPC readiness'
}

reset_case
run_activation unexpected >/dev/null 2>&1 && fail 'argument rejection accepted an argument'
assert_equal '' "$(<"$COMMAND_LOG")" 'argument rejection caused side effects'

reset_case
exec {held_lock_fd}>"$RUNTIME_DIR/desktop-shell-lifecycle.lock"
flock -n "$held_lock_fd" || fail 'could not hold lifecycle lock fixture'
run_activation >/dev/null 2>&1 && fail 'held lifecycle lock was accepted'
assert_not_contains "$(<"$COMMAND_LOG")" 'systemctl|' 'held lock caused lifecycle mutations'
exec {held_lock_fd}>&-

reset_case
printf '%s\n' stale >"$CUE_FILE"
run_activation || fail "successful activation failed: $(<"$STDERR_FILE")"
assert_success_trace
assert_contains "$(<"$COMMAND_LOG")" 'flock|' 'lifecycle lock acquisition was not traced'
[[ ! -e $CUE_FILE ]] || fail 'successful activation did not remove the cue file'
assert_contains "$(<"$COMMAND_LOG")" 'desktop-shell|--pid|5001|ping' 'ping was not PID scoped'
assert_contains "$(<"$COMMAND_LOG")" 'desktop-shell|--pid|5001|health' 'health was not PID scoped'
assert_not_contains "$(<"$COMMAND_LOG")" $'desktop-shell|ping\n' 'unscoped ping was used'
assert_no_fallback_commands

reset_case
printf '%s\n' 'u 9999' 'malformed owner' 'u 5001' >"$OWNER_SEQUENCE"
run_activation || fail "notification owner retry failed: $(<"$STDERR_FILE")"
assert_success_trace
assert_equal 4 "$(grep -c '^busctl|' "$COMMAND_LOG")" 'owner retry and revalidation command count'

reset_case
PING_FAILURES=2 HEALTH_FAILURES=2
run_activation || fail "IPC retries failed: $(<"$STDERR_FILE")"
assert_success_trace
assert_equal 3 "$(<"$PING_COUNT")" 'ping retry count'
assert_equal 3 "$(<"$HEALTH_COUNT")" 'health retry count'

reset_case
FAIL_ROUTE_RESTART=7
run_activation >/dev/null 2>&1 && fail 'route restart failure was accepted'
assert_equal '' "$(<"$MUTATION_LOG")" 'route restart failure mutated later services'

reset_case
FAIL_ROUTE_ACTIVE=7
run_activation >/dev/null 2>&1 && fail 'route active failure was accepted'
assert_equal 'systemctl --user restart watch-rustdesk-submap.service' "$(<"$MUTATION_LOG")" \
  'route active failure mutated the shell service'

reset_case
FAIL_SHELL_RESTART=7
run_activation >/dev/null 2>&1 && fail 'desktop-shell restart failure was accepted'
assert_equal 'systemctl --user restart watch-rustdesk-submap.service' "$(<"$MUTATION_LOG")" \
  'desktop-shell restart failure mutated later services'
assert_no_shell_readiness

reset_case
FAIL_SHELL_ACTIVE=7
run_activation >/dev/null 2>&1 && fail 'desktop-shell inactive state was accepted'
assert_equal 50 "$(grep -c '^systemctl|--user|is-active|--quiet|desktop-shell.service$' "$COMMAND_LOG")" \
  'desktop-shell active retry bound'
assert_success_trace
assert_no_shell_readiness

reset_case
IPC_TIMEOUT_STATUS=124
run_activation >/dev/null 2>&1 && fail 'IPC timeout was accepted'
assert_equal 20 "$(grep -c '^timeout|.*desktop-shell' "$COMMAND_LOG")" 'ping timeout retry bound'
assert_success_trace

reset_case
HEALTH_FAILURES=20
run_activation >/dev/null 2>&1 && fail 'health failure was accepted'
assert_equal 20 "$(<"$HEALTH_COUNT")" 'health failure retry bound'
assert_success_trace

reset_case
printf '%s\n' '{"notificationsOwned":false,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":"ownership conflict"}' >"$HEALTH_JSON"
run_activation >/dev/null 2>&1 && fail 'failed notification health was accepted'
assert_equal 20 "$(<"$HEALTH_COUNT")" 'failed health retry bound'
assert_success_trace

reset_case
printf '%s\n' '{"notificationsOwned":true,"polkitRegistered":false,"osdAvailable":true,"notificationRouteError":""}' >"$HEALTH_JSON"
run_activation >/dev/null 2>&1 && fail 'unregistered polkit health was accepted'
assert_equal 20 "$(<"$HEALTH_COUNT")" 'unregistered polkit health retry bound'
assert_equal 1 "$(<"$SHOW_COUNT")" 'unregistered polkit health reached MainPID revalidation'
assert_equal 1 "$(grep -c '^busctl|' "$COMMAND_LOG")" 'unregistered polkit health reached owner revalidation'
assert_success_trace

reset_case
printf '%s\n' '{"notificationsOwned":true,"polkitRegistered":true,"osdAvailable":false,"notificationRouteError":""}' >"$HEALTH_JSON"
run_activation >/dev/null 2>&1 && fail 'unavailable OSD health was accepted'
assert_equal 20 "$(<"$HEALTH_COUNT")" 'unavailable OSD health retry bound'
assert_equal 1 "$(<"$SHOW_COUNT")" 'unavailable OSD health reached MainPID revalidation'
assert_equal 1 "$(grep -c '^busctl|' "$COMMAND_LOG")" 'unavailable OSD health reached owner revalidation'
assert_success_trace

reset_case
printf '%s\n' 5001 5002 >"$SHOW_SEQUENCE"
run_activation >/dev/null 2>&1 && fail 'MainPID change was accepted'
assert_equal 2 "$(<"$SHOW_COUNT")" 'MainPID was not revalidated'
assert_success_trace
assert_no_fallback_commands

reset_case
run_activation || fail "successful activation failed: $(<"$STDERR_FILE")"
assert_equal $'desktop-shell activation status\ndesktop-shell.service: active\ndesktop-shell.pid: 5001\nnotification-owner: desktop-shell\npolkit-registered: true' \
  "$(<"$STDOUT_FILE")" 'activation final status'

printf '%s\n' 'desktop services active-only lifecycle contracts passed'
