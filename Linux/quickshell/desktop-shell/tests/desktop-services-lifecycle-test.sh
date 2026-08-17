#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
ACTIVATE="$ROOT/Linux/os/helpers/desktop-shell-activate"
ROLLBACK="$ROOT/Linux/os/helpers/desktop-shell-rollback"

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

assert_contains() {
  local haystack=$1
  local needle=$2
  local message=$3

  [[ $haystack == *"$needle"* ]] || fail "$message: missing '$needle'"
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  local message=$3

  [[ $haystack != *"$needle"* ]] || fail "$message: found '$needle'"
}

assert_log_contains() {
  local needle=$1
  local message=$2

  awk -v needle="$needle" 'index($0, needle) { found = 1; exit } END { exit !found }' "$MOCK_LOG" || \
    fail "$message: missing '$needle'"
}

assert_log_not_contains() {
  local needle=$1
  local message=$2

  if awk -v needle="$needle" 'index($0, needle) { found = 1; exit } END { exit found }' "$MOCK_LOG"; then
    return 0
  fi
  fail "$message: found '$needle'"
}

assert_log_order() {
  local previous=0
  local needle
  local line

  for needle in "$@"; do
    line=$(awk -v needle="$needle" -v previous="$previous" \
      'NR > previous && index($0, needle) { print NR; exit }' "$MOCK_LOG")
    [[ -n $line ]] || fail "event order: missing '$needle' after line $previous"
    previous=$line
  done
}

assert_status() {
  local expected=$1
  local actual=$2
  local message=$3

  assert_equal "$expected" "$actual" "$message"
}

[[ -f $ACTIVATE ]] || fail "activation helper is missing: $ACTIVATE"
[[ -f $ROLLBACK ]] || fail "rollback helper is missing: $ROLLBACK"

TEST_ROOT=$(mktemp -d)
BIN="$TEST_ROOT/bin"
RUNTIME_DIR="$TEST_ROOT/runtime"
STATE_HOME="$TEST_ROOT/state"
MOCK_LOG="$TEST_ROOT/mock.log"
FALLTHROUGH_LOG="$TEST_ROOT/live-fallthrough.log"
PROCESS_STATE="$TEST_ROOT/processes"
SERVICE_STATE="$TEST_ROOT/services"
SERVICE_PID_STATE="$TEST_ROOT/service-pids"
BUS_OWNER_STATE="$TEST_ROOT/bus-owner"
MAKO_MODE_ATTEMPTS_FILE="$TEST_ROOT/mako-mode-attempts"
MAKO_MODE_RESPONDS_FILE="$TEST_ROOT/mako-mode-responds"
HEALTH_FILE="$TEST_ROOT/health.json"
HISTORY_FILE="$STATE_HOME/desktop-shell/notifications.json"
CUE_FILE="$RUNTIME_DIR/rustdesk-notification-cue"
POLKIT_AGENT="$BIN/polkit-gnome-authentication-agent-1"
POLKIT_COMM="${POLKIT_AGENT##*/}"
POLKIT_COMM="${POLKIT_COMM:0:15}"

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  rm -rf -- "$TEST_ROOT"
  exit "$status"
}

trap cleanup EXIT HUP INT TERM

mkdir -p -- "$BIN" "$RUNTIME_DIR/desktop-shell" "$STATE_HOME/desktop-shell"
: >"$MOCK_LOG"
: >"$FALLTHROUGH_LOG"

cat >"$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'systemctl|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == --user ]] || exit 125
shift

set_unit_state() {
  local unit=$1
  local state=$2
  local temporary_file

  temporary_file="${SERVICE_STATE}.tmp"
  awk -F= -v unit="$unit" '$1 != unit' "$SERVICE_STATE" >"$temporary_file"
  printf '%s=%s\n' "$unit" "$state" >>"$temporary_file"
  mv -- "$temporary_file" "$SERVICE_STATE"
}

unit_state() {
  local unit=$1
  awk -F= -v unit="$unit" '$1 == unit { print $2; exit }' "$SERVICE_STATE"
}

action=${1:-}
shift || true
case $action in
  stop)
    (($# > 0)) || exit 125
    for unit in "$@"; do
      case $unit in
        desktop-shell.service|desktop-shell-mako-route.service) set_unit_state "$unit" inactive ;;
        *) exit 125 ;;
      esac
    done
    ;;
  start)
    (($# == 1)) || exit 125
    case $1 in
      desktop-shell.service)
        set_unit_state "$1" active
        printf '%s\n' 5001 >"$SERVICE_PID_STATE"
        printf '%s\n' desktop-shell >"$BUS_OWNER_STATE"
        if [[ -e ${CUE_FILE:?} ]]; then
          printf 'systemctl-shell-start-cue=present\n' >>"$MOCK_LOG"
        else
          printf 'systemctl-shell-start-cue=absent\n' >>"$MOCK_LOG"
        fi
        ;;
      desktop-shell-mako-route.service)
        set_unit_state "$1" active
        printf '%s\n' 6001 >>"$SERVICE_PID_STATE"
        ;;
      *) exit 125 ;;
    esac
    ;;
  is-active)
    [[ ${1:-} == --quiet ]] || exit 125
    [[ ${2:-} == desktop-shell.service || ${2:-} == desktop-shell-mako-route.service ]] || exit 125
    [[ $(unit_state "$2") == active ]]
    ;;
  show)
    property=''
    value_only=false
    unit=''
    while (($# > 0)); do
      case $1 in
        --property=*) property=${1#*=} ;;
        --value) value_only=true ;;
        desktop-shell.service|desktop-shell-mako-route.service) unit=$1 ;;
        *) exit 125 ;;
      esac
      shift
    done
    [[ $value_only == true && $property == MainPID && -n $unit ]] || exit 125
    if [[ $unit == desktop-shell.service ]]; then
      awk 'NR == 1 { print; exit }' "$SERVICE_PID_STATE"
    else
      awk 'NR == 2 { print; exit }' "$SERVICE_PID_STATE"
    fi
    ;;
  *)
    exit 125
    ;;
esac
EOF

cat >"$BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'pgrep|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == -x ]] || exit 125
shift
[[ ${1:-} == -- ]] && shift
[[ $# == 1 ]] || exit 125
name=$1
matches=()
while IFS='|' read -r comm pid executable; do
  [[ -n ${comm:-} && $comm == "$name" ]] || continue
  matches+=("$pid")
done <"${PROCESS_STATE:?}"

((${#matches[@]} > 0)) || exit 1
printf '%s\n' "${matches[@]}"
EOF

cat >"$BIN/pkill" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'pkill|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == -TERM ]] || exit 125
shift
match_mode=${1:-}
[[ $match_mode == -x || $match_mode == -f ]] || exit 125
shift
[[ ${1:-} == -- ]] && shift
[[ $# == 1 ]] || exit 125
pattern=$1

temporary_file="${PROCESS_STATE}.tmp"
if [[ $match_mode == -x ]]; then
  awk -F'|' -v name="$pattern" '$1 != name' "$PROCESS_STATE" >"$temporary_file"
else
  [[ $pattern == *polkit-gnome-authentication-agent-1* ]] || exit 125
  awk -F'|' -v name="${POLKIT_COMM:?}" -v executable="${DESKTOP_SHELL_POLKIT_AGENT:?}" \
    '!($1 == name && $3 == executable)' "$PROCESS_STATE" >"$temporary_file"
fi
mv -- "$temporary_file" "$PROCESS_STATE"
EOF

cat >"$BIN/uwsm-app" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'uwsm-app|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == -- ]] || exit 125
shift
[[ $# == 1 ]] || exit 125

case $1 in
  mako)
    printf '%s\n' "mako|1101|/usr/bin/mako" >>"${PROCESS_STATE:?}"
    printf '%s\n' mako >"${BUS_OWNER_STATE:?}"
    ;;
  swayosd-server)
    printf '%s\n' "swayosd-server|1102|/usr/bin/swayosd-server" >>"${PROCESS_STATE:?}"
    ;;
  *) exit 125 ;;
esac
EOF

cat >"$BIN/makoctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'makoctl|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == mode && $# == 1 ]] || exit 125
attempts=$(<"${MAKO_MODE_ATTEMPTS_FILE:?}")
attempts=$((attempts + 1))
printf '%s\n' "$attempts" >"$MAKO_MODE_ATTEMPTS_FILE"
[[ $(<"${MAKO_MODE_RESPONDS_FILE:?}") == true ]] || exit 1
[[ $attempts -gt ${MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS:?} ]] || exit 1
printf '%s\n' default
EOF

cat >"$BIN/busctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'busctl|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == --user && ${2:-} == status && ${3:-} == org.freedesktop.Notifications && $# == 3 ]] || exit 125
owner=$(<"${BUS_OWNER_STATE:?}")
[[ -n $owner ]] || exit 1
case $owner in
  desktop-shell) printf 'PID=5001\nCommandLine=desktop-shell\n' ;;
  mako) printf 'PID=1101\nCommandLine=mako\n' ;;
  *) printf 'PID=9999\nCommandLine=%s\n' "$owner" ;;
esac
EOF

cat >"$BIN/readlink" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'readlink|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
path=''
while (($# > 0)); do
  case $1 in
    --) shift ;;
    -*) shift ;;
    *) path=$1; break ;;
  esac
done
[[ $path == /proc/*/exe ]] || exit 125
pid=${path#/proc/}
pid=${pid%/exe}
while IFS='|' read -r comm process_pid executable; do
  if [[ ${process_pid:-} == "$pid" ]]; then
    printf '%s\n' "$executable"
    exit 0
  fi
done <"${PROCESS_STATE:?}"
exit 1
EOF

cat >"$BIN/desktop-shell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'desktop-shell|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
case ${1:-} in
  ping)
    [[ $# == 1 ]] || exit 125
    printf '%s\n' pong
    ;;
  health)
    [[ $# == 1 ]] || exit 125
    jq -R -s . "${HEALTH_FILE:?}"
    ;;
  *) exit 125 ;;
esac
EOF

cat >"$BIN/quickshell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'quickshell invoked\n' >>"${FALLTHROUGH_LOG:?}"
exit 125
EOF

cat >"$POLKIT_AGENT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'polkit-agent|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
printf '%s\n' "polkit-gnome-au|1103|${DESKTOP_SHELL_POLKIT_AGENT:?}" >>"${PROCESS_STATE:?}"
exit 0
EOF

chmod 0700 "$BIN"/*

export MOCK_LOG FALLTHROUGH_LOG PROCESS_STATE SERVICE_STATE SERVICE_PID_STATE BUS_OWNER_STATE
export MAKO_MODE_ATTEMPTS_FILE MAKO_MODE_RESPONDS_FILE MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS=0
export HEALTH_FILE CUE_FILE POLKIT_COMM DESKTOP_SHELL_POLKIT_AGENT="$POLKIT_AGENT"
export XDG_RUNTIME_DIR="$RUNTIME_DIR" XDG_STATE_HOME="$STATE_HOME"
export PATH="$BIN:/usr/bin:/bin"

write_services() {
  printf '%s\n' \
    'desktop-shell.service=inactive' \
    'desktop-shell-mako-route.service=inactive' >"$SERVICE_STATE"
  : >"$SERVICE_PID_STATE"
}

write_processes() {
  printf '%s\n' \
    'mako|1001|/usr/bin/mako' \
    'swayosd-server|1002|/usr/bin/swayosd-server' \
    "${POLKIT_COMM}|1003|$POLKIT_AGENT" \
    "${POLKIT_COMM}|1005|/usr/bin/unrelated-polkit" \
    'quickshell|1004|/usr/bin/quickshell' >"$PROCESS_STATE"
}

write_health() {
  printf '%s\n' "$1" >"$HEALTH_FILE"
}

reset_log() {
  : >"$MOCK_LOG"
  : >"$FALLTHROUGH_LOG"
  printf '%s\n' 0 >"$MAKO_MODE_ATTEMPTS_FILE"
  printf '%s\n' true >"$MAKO_MODE_RESPONDS_FILE"
}

run_helper() {
  local helper=$1
  shift

  env \
    PATH="$PATH" \
    HOME="$TEST_ROOT/home" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    XDG_STATE_HOME="$XDG_STATE_HOME" \
    MOCK_LOG="$MOCK_LOG" \
    FALLTHROUGH_LOG="$FALLTHROUGH_LOG" \
    PROCESS_STATE="$PROCESS_STATE" \
    SERVICE_STATE="$SERVICE_STATE" \
    SERVICE_PID_STATE="$SERVICE_PID_STATE" \
    BUS_OWNER_STATE="$BUS_OWNER_STATE" \
    MAKO_MODE_ATTEMPTS_FILE="$MAKO_MODE_ATTEMPTS_FILE" \
    MAKO_MODE_RESPONDS_FILE="$MAKO_MODE_RESPONDS_FILE" \
    MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS="$MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS" \
    HEALTH_FILE="$HEALTH_FILE" \
    CUE_FILE="$CUE_FILE" \
    POLKIT_COMM="$POLKIT_COMM" \
    DESKTOP_SHELL_POLKIT_AGENT="$DESKTOP_SHELL_POLKIT_AGENT" \
    "$helper" "$@"
}

assert_no_fallthrough() {
  [[ ! -s $FALLTHROUGH_LOG ]] || fail "helper fell through to the live quickshell binary"
  assert_log_not_contains 'systemctl|--user|disable' 'unit disabling is forbidden'
  assert_log_not_contains 'systemctl|--user|enable' 'unit enabling is forbidden'
  assert_log_not_contains 'systemctl|--user|daemon-reload' 'daemon reload is forbidden'
  if awk -F'|' '$1 == "pkill" && index($0, "quickshell") { found = 1; exit } END { exit found }' "$MOCK_LOG"; then
    return 0
  fi
  fail 'broad Quickshell termination is forbidden'
}

assert_process_present() {
  local expected=$1
  awk -F'|' -v expected="$expected" '$1 == expected { found = 1; exit } END { exit !found }' "$PROCESS_STATE" || \
    fail "process is absent: $expected"
}

assert_process_absent() {
  local expected=$1
  if awk -F'|' -v expected="$expected" '$1 == expected { found = 1; exit } END { exit found }' "$PROCESS_STATE"; then
    return 0
  fi
  fail "process is present: $expected"
}

assert_source_contract() {
  local helper
  local source

  for helper in "$ACTIVATE" "$ROLLBACK"; do
    source=$(<"$helper")
    assert_contains "$source" 'set -Eeuo pipefail' "$helper strict mode"
    assert_not_contains "$source" '/usr/bin/systemctl' "$helper must use PATH systemctl"
    assert_not_contains "$source" '/usr/bin/pgrep' "$helper must use PATH pgrep"
    assert_not_contains "$source" '/usr/bin/pkill' "$helper must use PATH pkill"
    assert_not_contains "$source" '/systemctl' "$helper must use PATH systemctl"
    assert_not_contains "$source" '/pgrep' "$helper must use PATH pgrep"
    assert_not_contains "$source" '/pkill' "$helper must use PATH pkill"
    assert_not_contains "$source" '/uwsm-app' "$helper must use PATH uwsm-app"
    assert_not_contains "$source" '/makoctl' "$helper must use PATH makoctl"
    assert_not_contains "$source" '/busctl' "$helper must use PATH busctl"
    assert_not_contains "$source" 'pkill quickshell' "$helper must not broadly kill Quickshell"
    assert_not_contains "$source" 'systemctl --user disable' "$helper must not disable units"
    assert_not_contains "$source" 'systemctl --user enable' "$helper must not enable units"
  done
  assert_contains "$(<"$ROLLBACK")" '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1' \
    'rollback default polkit executable'
}

assert_source_contract

write_services
write_processes
write_health '{"notificationsOwned":true,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":"stale route hidden"}'
printf '%s\n' preserved >"$HISTORY_FILE"
printf '%s\n' stale >"$CUE_FILE"
printf '%s\n' mako >"$BUS_OWNER_STATE"

log_before=$(wc -l <"$MOCK_LOG")
status=0
run_helper "$ACTIVATE" unexpected >/dev/null 2>&1 || status=$?
assert_status 2 "$status" 'activation argument rejection'
assert_equal "$log_before" "$(wc -l <"$MOCK_LOG")" 'activation argument rejection performed commands'

status=0
run_helper "$ROLLBACK" unexpected >/dev/null 2>&1 || status=$?
assert_status 2 "$status" 'rollback argument rejection'
assert_equal "$log_before" "$(wc -l <"$MOCK_LOG")" 'rollback argument rejection performed commands'

reset_log
activation_output="$TEST_ROOT/activation.out"
activation_error="$TEST_ROOT/activation.err"
if ! run_helper "$ACTIVATE" >"$activation_output" 2>"$activation_error"; then
  fail "activation unexpectedly failed: $(<"$activation_error")"
fi

assert_log_order \
  'systemctl|--user|stop|desktop-shell.service|desktop-shell-mako-route.service' \
  'pkill|-TERM|-x|--|mako' \
  'pkill|-TERM|-x|--|swayosd-server' \
  'pkill|-TERM|-f|--|' \
  'systemctl|--user|start|desktop-shell.service' \
  'systemctl-shell-start-cue=absent' \
  'systemctl|--user|is-active|--quiet|desktop-shell.service' \
  'busctl|--user|status|org.freedesktop.Notifications' \
  'desktop-shell|ping' \
  'desktop-shell|health'
assert_log_contains "pgrep|-x|--|$POLKIT_COMM" 'polkit comm lookup is truncated to Linux comm length'
assert_log_contains 'readlink|' 'polkit executable was verified'
assert_process_absent mako
assert_process_absent swayosd-server
if awk -F'|' -v name="$POLKIT_COMM" -v executable="$POLKIT_AGENT" \
  '$1 == name && $3 == executable { found = 1; exit } END { exit !found }' "$PROCESS_STATE"; then
  fail 'exact polkit executable survived activation'
fi
if ! awk -F'|' -v name="$POLKIT_COMM" '$1 == name && $3 == "/usr/bin/unrelated-polkit" { found = 1; exit } END { exit !found }' \
  "$PROCESS_STATE"; then
  fail 'activation terminated a decoy process sharing polkit comm prefix'
fi
assert_process_present quickshell
[[ ! -e $CUE_FILE ]] || fail 'activation left stale RustDesk cue state'
assert_equal preserved "$(<"$HISTORY_FILE")" 'activation deleted notification history'
assert_contains "$(<"$activation_error")" 'stale route hidden' 'route error warning'
assert_contains "$(<"$activation_output")" 'desktop-shell activation status' 'activation status heading'
assert_contains "$(<"$activation_output")" 'desktop-shell.service: active' 'activation service status'
assert_contains "$(<"$activation_output")" 'desktop-shell.pid: 5001' 'activation process status'
assert_contains "$(<"$activation_output")" 'notification-owner: desktop-shell' 'activation notification owner'
assert_contains "$(<"$activation_output")" 'polkit-registered: true' 'activation polkit status'
assert_no_fallthrough

reset_log
if ! run_helper "$ACTIVATE" >"$activation_output" 2>"$activation_error"; then
  fail "idempotent activation unexpectedly failed: $(<"$activation_error")"
fi
pkill_count_after=$(awk 'index($0, "pkill|") { count++ } END { print count + 0 }' "$MOCK_LOG")
uwsm_count_after=$(awk 'index($0, "uwsm-app|") { count++ } END { print count + 0 }' "$MOCK_LOG")
polkit_start_count_after=$(awk 'index($0, "polkit-agent|") { count++ } END { print count + 0 }' "$MOCK_LOG")
assert_equal 0 "$pkill_count_after" 'idempotent activation re-terminated legacy processes'
assert_equal 0 "$uwsm_count_after" 'idempotent activation started legacy processes'
assert_equal 0 "$polkit_start_count_after" 'idempotent activation started polkit'
[[ ! -e $CUE_FILE ]] || fail 'idempotent activation left stale RustDesk cue state'
assert_no_fallthrough

reset_log
write_services
write_processes
write_health '{"notificationsOwned":false,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":"ownership conflict"}'
status=0
run_helper "$ACTIVATE" >"$activation_output" 2>"$activation_error" || status=$?
((status != 0)) || fail 'activation accepted failed notification ownership health'
assert_log_contains 'desktop-shell|health' 'failed activation did not inspect health'
assert_process_present quickshell
assert_no_fallthrough

reset_log
write_services
write_processes
sed -i '/mako|/d; /swayosd-server|/d; /polkit-gnome-au|/d' "$PROCESS_STATE"
write_health '{"notificationsOwned":true,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":""}'
printf '%s\n' 0 >"$MAKO_MODE_ATTEMPTS_FILE"
export MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS=1
rollback_output="$TEST_ROOT/rollback.out"
rollback_error="$TEST_ROOT/rollback.err"
if ! run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error"; then
  fail "rollback unexpectedly failed: $(<"$rollback_error")"
fi

assert_log_order \
  'systemctl|--user|stop|desktop-shell.service' \
  'uwsm-app|--|mako' \
  'uwsm-app|--|swayosd-server' \
  'polkit-agent|' \
  'makoctl|mode' \
  'systemctl|--user|start|desktop-shell-mako-route.service' \
  'busctl|--user|status|org.freedesktop.Notifications'
assert_log_contains "pgrep|-x|--|$POLKIT_COMM" 'rollback polkit comm lookup is truncated to Linux comm length'
assert_log_contains 'readlink|' 'rollback polkit executable was verified'
assert_process_present mako
assert_process_present swayosd-server
assert_process_present "$POLKIT_COMM"
assert_process_present quickshell
assert_contains "$(<"$rollback_output")" 'desktop-shell rollback status' 'rollback status heading'
assert_contains "$(<"$rollback_output")" 'desktop-shell-mako-route.service: active' 'rollback adapter status'
assert_contains "$(<"$rollback_output")" 'mako.pid: 1101' 'rollback Mako process status'
assert_contains "$(<"$rollback_output")" 'swayosd-server.pid: 1102' 'rollback SwayOSD process status'
assert_contains "$(<"$rollback_output")" 'polkit.pid: 1103' 'rollback polkit process status'
assert_contains "$(<"$rollback_output")" 'notification-owner: mako' 'rollback notification owner'
assert_contains "$(<"$rollback_output")" 'polkit-registered: true' 'rollback polkit status'
assert_equal preserved "$(<"$HISTORY_FILE")" 'rollback deleted notification history'
assert_no_fallthrough

uwsm_count_before=$(awk 'index($0, "uwsm-app|") { count++ } END { print count + 0 }' "$MOCK_LOG")
polkit_start_count_before=$(awk 'index($0, "polkit-agent|") { count++ } END { print count + 0 }' "$MOCK_LOG")
adapter_start_count_before=$(awk 'index($0, "systemctl|--user|start|desktop-shell-mako-route.service") { count++ } END { print count + 0 }' "$MOCK_LOG")
reset_log
export MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS=0
if ! run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error"; then
  fail "idempotent rollback unexpectedly failed: $(<"$rollback_error")"
fi
uwsm_count_after=$(awk 'index($0, "uwsm-app|") { count++ } END { print count + 0 }' "$MOCK_LOG")
polkit_start_count_after=$(awk 'index($0, "polkit-agent|") { count++ } END { print count + 0 }' "$MOCK_LOG")
adapter_start_count_after=$(awk 'index($0, "systemctl|--user|start|desktop-shell-mako-route.service") { count++ } END { print count + 0 }' "$MOCK_LOG")
assert_equal 0 "$uwsm_count_after" 'idempotent rollback restarted legacy processes'
assert_equal 0 "$polkit_start_count_after" 'idempotent rollback restarted polkit'
assert_equal 0 "$adapter_start_count_after" 'idempotent rollback restarted an active adapter'
assert_equal 2 "$uwsm_count_before" 'rollback did not start both missing legacy services once'
assert_equal 1 "$polkit_start_count_before" 'rollback did not start polkit once'
assert_equal 1 "$adapter_start_count_before" 'rollback did not start the adapter once'
assert_no_fallthrough

reset_log
write_services
printf '%s\n' \
  'mako|1101|/usr/bin/mako' \
  'swayosd-server|1102|/usr/bin/swayosd-server' \
  "${POLKIT_COMM}|1103|$POLKIT_AGENT" \
  'quickshell|1004|/usr/bin/quickshell' >"$PROCESS_STATE"
printf '%s\n' other >"$BUS_OWNER_STATE"
status=0
run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
((status != 0)) || fail 'rollback accepted an incorrect notification owner'
assert_log_contains 'busctl|--user|status|org.freedesktop.Notifications' 'rollback ownership failure did not query D-Bus'
assert_no_fallthrough

reset_log
write_services
: >"$PROCESS_STATE"
printf '%s\n' none >"$BUS_OWNER_STATE"
printf '%s\n' false >"$MAKO_MODE_RESPONDS_FILE"
export MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS=0
status=0
run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
((status != 0)) || fail 'rollback accepted an unresponsive Mako mode probe'
assert_log_contains 'makoctl|mode' 'rollback did not probe Mako mode'
assert_log_not_contains 'systemctl|--user|start|desktop-shell-mako-route.service' \
  'rollback started the adapter before Mako mode responded'
assert_no_fallthrough

printf '%s\n' 'PASS: mocked desktop service activation and rollback lifecycle contract'
