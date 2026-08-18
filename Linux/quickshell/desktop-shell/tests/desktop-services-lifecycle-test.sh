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
SIGNAL_LOG="$TEST_ROOT/signal.log"
PROCESS_STATE="$TEST_ROOT/processes"
SERVICE_STATE="$TEST_ROOT/services"
SERVICE_PID_STATE="$TEST_ROOT/service-pids"
BUS_OWNER_STATE="$TEST_ROOT/bus-owner"
BUS_OWNER_RESPONSE=''
MAKO_MODE_ATTEMPTS_FILE="$TEST_ROOT/mako-mode-attempts"
MAKO_MODE_RESPONDS_FILE="$TEST_ROOT/mako-mode-responds"
MAKO_MODE_ERROR_STATUS=0
MAKO_MODE_APPLY_ERROR_STATUS=0
MAKO_MODE_READBACK_ERROR_STATUS=0
MAKO_MODE_QUERY_COUNT_FILE="$TEST_ROOT/mako-mode-query-count"
MAKO_MODE_STATE="$TEST_ROOT/mako-mode-state"
PGREP_ERROR_NAME="$TEST_ROOT/pgrep-error-name"
PGREP_ERROR_STATUS="$TEST_ROOT/pgrep-error-status"
SIGNAL_READD_DECOY=false
INJECT_UNEXPECTED_LIFECYCLE=false
FORGED_ANY_DISPLAY_RESPONDER=false
READLINK_CALLS_FILE="$TEST_ROOT/readlink-calls"
READLINK_FLIP_PID="$TEST_ROOT/readlink-flip-pid"
READLINK_FLIP_AFTER="$TEST_ROOT/readlink-flip-after"
HEALTH_FILE="$TEST_ROOT/health.json"
HISTORY_FILE="$STATE_HOME/desktop-shell/notifications.json"
CUE_FILE="$RUNTIME_DIR/rustdesk-notification-cue"
MAKO_EXECUTABLE="$BIN/mako"
SWAYOSD_SERVER_EXECUTABLE="$BIN/swayosd-server"
POLKIT_AGENT="$BIN/polkit-gnome-authentication-agent-1"
POLKIT_COMM="${POLKIT_AGENT##*/}"
POLKIT_COMM="${POLKIT_COMM:0:15}"
SYSTEMCTL_STOP_ADAPTER_STATUS=0
SYSTEMCTL_STOP_SHELL_STATUS=0
SYSTEMCTL_START_ADAPTER_STATUS=0
SYSTEMCTL_ADAPTER_ACTIVE_STATUS=0
UWSM_MAKO_STATUS=0
UWSM_SWAYOSD_STATUS=0
POLKIT_AGENT_STATUS=0
POLKIT_AGENT_REGISTER=true
PKCHECK_STATUS=0
TIMEOUT_STATUS=0
DROP_MAKO_AFTER_HIDDEN=false
DROP_MAKO_AFTER_ADAPTER=false
DROP_MAKO_AFTER_SWAYOSD=false
DROP_MAKO_AFTER_POLKIT=false
DROP_MAKO_AFTER_PROBE=false
DROP_MAKO_BEFORE_OWNER=false
MOCK_PATH="$BIN"
SIGNAL_COMMAND="$BIN/kill"

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
: >"$SIGNAL_LOG"

cat >"$BIN/bash" <<'EOF'
#!/bin/sh
exec /usr/bin/bash "$@"
EOF

for utility in cat jq mv wc; do
  cat >"$BIN/$utility" <<EOF
#!/bin/sh
exec /usr/bin/$utility "\$@"
EOF
done

cat >"$BIN/awk" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

path=${*: -1}
if [[ $path == /proc/*/stat || $path == /proc/*/status ]]; then
  pid=${path#/proc/}
  pid=${pid%/stat}
  pid=${pid%/status}
  if [[ $path == */stat ]]; then
    awk -F'|' -v pid="$pid" '$2 == pid { print $5; exit }' "${PROCESS_STATE:?}"
  else
    awk -F'|' -v pid="$pid" '$2 == pid { print $6; exit }' "${PROCESS_STATE:?}"
  fi
  exit 0
fi
exec /usr/bin/awk "$@"
EOF

cat >"$BIN/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$BIN/rm" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'rm|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == -f && ${2:-} == -- && ${3:-} == "${CUE_FILE:?}" && $# == 3 ]] || exit 125
exec /usr/bin/rm -f -- "$3"
EOF

cat >"$BIN/kill" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'kill|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == -TERM && ${2:-} =~ ^[1-9][0-9]*$ && $# == 2 ]] || exit 125
pid=$2

if [[ -s ${SIGNAL_ERROR_STATUS:-} ]]; then
  exit "$(<"$SIGNAL_ERROR_STATUS")"
fi

temporary_file="${PROCESS_STATE}.tmp"
awk -F'|' -v pid="$pid" '$2 != pid' "$PROCESS_STATE" >"$temporary_file"
if [[ ${SIGNAL_READD_DECOY:-false} == true && $pid == 1003 ]]; then
  printf '%s\n' "${POLKIT_COMM:?}|$pid|/usr/bin/argv-spoof|${DESKTOP_SHELL_POLKIT_AGENT:?}|11003|1000" >>"$temporary_file"
fi
mv -- "$temporary_file" "$PROCESS_STATE"
printf '%s\n' "$pid" >>"${SIGNAL_LOG:?}"
EOF

cat >"$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'path|%s\n' "${PATH:?}" >>"${MOCK_LOG:?}"
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
if [[ ${INJECT_UNEXPECTED_LIFECYCLE:-false} == true && $action == stop ]]; then
  printf '%s\n' 'systemctl|--user|start|unexpected.service' >>"${MOCK_LOG:?}"
  printf '%s\n' 'kill|-TERM|9999' >>"${MOCK_LOG:?}"
fi
case $action in
  stop)
    (($# > 0)) || exit 125
    for unit in "$@"; do
      case $unit in
        desktop-shell-mako-route.service)
          set_unit_state "$unit" inactive
          ((SYSTEMCTL_STOP_ADAPTER_STATUS == 0)) || exit "$SYSTEMCTL_STOP_ADAPTER_STATUS"
          ;;
        desktop-shell.service)
          set_unit_state "$unit" inactive
          ((SYSTEMCTL_STOP_SHELL_STATUS == 0)) || exit "$SYSTEMCTL_STOP_SHELL_STATUS"
          ;;
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
        temporary_file="${PROCESS_STATE}.tmp"
        awk -F'|' '$2 != 5001' "$PROCESS_STATE" >"$temporary_file"
        printf '%s\n' 'quickshell|5001|/usr/bin/quickshell|quickshell' >>"$temporary_file"
        mv -- "$temporary_file" "$PROCESS_STATE"
        printf '%s\n' desktop-shell >"$BUS_OWNER_STATE"
        if [[ -e ${CUE_FILE:?} ]]; then
          printf 'systemctl-shell-start-cue=present\n' >>"$MOCK_LOG"
        else
          printf 'systemctl-shell-start-cue=absent\n' >>"$MOCK_LOG"
        fi
        ;;
      desktop-shell-mako-route.service)
        ((SYSTEMCTL_START_ADAPTER_STATUS == 0)) || exit "$SYSTEMCTL_START_ADAPTER_STATUS"
        set_unit_state "$1" active
        printf '%s\n' 6001 >>"$SERVICE_PID_STATE"
        if [[ ${DROP_MAKO_AFTER_ADAPTER:?} == true ]]; then
          temporary_file="${PROCESS_STATE}.tmp"
          awk -F'|' '$2 != 1101' "${PROCESS_STATE:?}" >"$temporary_file"
          mv -- "$temporary_file" "${PROCESS_STATE:?}"
        fi
        ;;
      *) exit 125 ;;
    esac
    ;;
  is-active)
    [[ ${1:-} == --quiet ]] || exit 125
    [[ ${2:-} == desktop-shell.service || ${2:-} == desktop-shell-mako-route.service ]] || exit 125
    if [[ ${2:-} == desktop-shell-mako-route.service && $SYSTEMCTL_ADAPTER_ACTIVE_STATUS != 0 ]]; then
      exit "$SYSTEMCTL_ADAPTER_ACTIVE_STATUS"
    fi
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
if [[ -s ${PGREP_ERROR_NAME:?} && $(<"$PGREP_ERROR_NAME") == "$name" ]]; then
  exit "$(<"${PGREP_ERROR_STATUS:?}")"
fi
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
printf 'pkill invoked\n' >>"${FALLTHROUGH_LOG:?}"
exit 125
EOF

cat >"$BIN/uwsm-app" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'uwsm-app|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == -- ]] || exit 125
shift
[[ $# == 1 ]] || exit 125

case $1 in
  mako|"${DESKTOP_SHELL_MAKO:?}")
    ((UWSM_MAKO_STATUS == 0)) || exit "$UWSM_MAKO_STATUS"
    printf '%s\n' "mako|1101|${DESKTOP_SHELL_MAKO:?}|mako|11101|1000" >>"${PROCESS_STATE:?}"
    printf '%s\n' mako >"${BUS_OWNER_STATE:?}"
    ;;
  swayosd-server|"${DESKTOP_SHELL_SWAYOSD_SERVER:?}")
    ((UWSM_SWAYOSD_STATUS == 0)) || exit "$UWSM_SWAYOSD_STATUS"
    printf '%s\n' "swayosd-server|1102|${DESKTOP_SHELL_SWAYOSD_SERVER:?}|swayosd-server|11102|1000" >>"${PROCESS_STATE:?}"
    if [[ ${DROP_MAKO_AFTER_SWAYOSD:?} == true ]]; then
      temporary_file="${PROCESS_STATE}.tmp"
      awk -F'|' '$2 != 1101' "${PROCESS_STATE:?}" >"$temporary_file"
      mv -- "$temporary_file" "${PROCESS_STATE:?}"
    fi
    ;;
  *) exit 125 ;;
esac
EOF

cat >"$BIN/makoctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'makoctl|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == mode ]] || exit 125
adapter_state=$(awk -F= '$1 == "desktop-shell-mako-route.service" { print $2; exit }' "${SERVICE_STATE:?}")
printf 'makoctl|mode|adapter=%s\n' "$adapter_state" >>"${MOCK_LOG:?}"
shift
state=$(<"${MAKO_MODE_STATE:?}")

if (($# == 0)); then
  attempts=$(<"${MAKO_MODE_ATTEMPTS_FILE:?}")
  attempts=$((attempts + 1))
  printf '%s\n' "$attempts" >"$MAKO_MODE_ATTEMPTS_FILE"
  if ((MAKO_MODE_ERROR_STATUS != 0)); then
    exit "$MAKO_MODE_ERROR_STATUS"
  fi
  [[ $(<"${MAKO_MODE_RESPONDS_FILE:?}") == true ]] || exit 1
  [[ $attempts -gt ${MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS:?} ]] || exit 1
  query_count=$(<"${MAKO_MODE_QUERY_COUNT_FILE:?}")
  query_count=$((query_count + 1))
  printf '%s\n' "$query_count" >"$MAKO_MODE_QUERY_COUNT_FILE"
  if ((query_count > 1 && MAKO_MODE_READBACK_ERROR_STATUS != 0)); then
    exit "$MAKO_MODE_READBACK_ERROR_STATUS"
  fi
  if ((query_count > 1)) && [[ ${DROP_MAKO_AFTER_HIDDEN:?} == true ]]; then
    temporary_file="${PROCESS_STATE}.tmp"
    awk -F'|' '$2 != 1101' "${PROCESS_STATE:?}" >"$temporary_file"
    mv -- "$temporary_file" "${PROCESS_STATE:?}"
  fi
  printf '%s\n' "$state"
  exit 0
fi

if ((MAKO_MODE_APPLY_ERROR_STATUS != 0)); then
  exit "$MAKO_MODE_APPLY_ERROR_STATUS"
fi

mode_arguments=("$@")
while (($# > 0)); do
  case $1 in
    -r|-a)
      [[ $# -ge 2 ]] || exit 125
      mode=$2
      read -r -a modes <<<"$state"
      next=()
      for existing in "${modes[@]}"; do
        [[ $1 == -r && $existing == "$mode" ]] && continue
        next+=("$existing")
      done
      state="${next[*]}"
      if [[ $1 == -a ]]; then
        read -r -a modes <<<"$state"
        present=false
        for existing in "${modes[@]}"; do
          [[ $existing == "$mode" ]] && present=true
        done
        [[ $present == true ]] || state="${state:+$state }$mode"
      fi
      ;;
    *) exit 125 ;;
  esac
  shift 2
done

printf '%s\n' "$state" >"${MAKO_MODE_STATE:?}"
EOF

cat >"$BIN/timeout" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'timeout|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
if ((TIMEOUT_STATUS != 0)); then
  exit "$TIMEOUT_STATUS"
fi

while (($# > 0)); do
  case $1 in
    --signal=*|--kill-after=*) shift ;;
    --signal|--kill-after) shift 2 ;;
    *) shift; break ;;
  esac
done
[[ $# -gt 0 ]] || exit 125
exec "$@"
EOF

cat >"$BIN/pkcheck" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'pkcheck|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
expected_pid=$(awk -F'|' -v executable="${DESKTOP_SHELL_POLKIT_AGENT:?}" '$3 == executable { print $2; exit }' "${PROCESS_STATE:?}")
expected_start=$(awk -F'|' -v executable="${DESKTOP_SHELL_POLKIT_AGENT:?}" '$3 == executable { print $5; exit }' "${PROCESS_STATE:?}")
expected_uid=$(awk -F'|' -v executable="${DESKTOP_SHELL_POLKIT_AGENT:?}" '$3 == executable { print $6; exit }' "${PROCESS_STATE:?}")
[[ ${1:-} == -a && ${2:-} == org.freedesktop.policykit.exec &&
  ${3:-} == -p && ${4:-} == "$expected_pid,$expected_start,$expected_uid" &&
  ${5:-} == -d && ${6:-} == program && ${7:-} == /usr/bin/true &&
  ${8:-} == -u && $# == 8 ]] || exit 125
if ((PKCHECK_STATUS == 0)) && [[ ${DROP_MAKO_AFTER_PROBE:?} == true ]]; then
  temporary_file="${PROCESS_STATE}.tmp"
  awk -F'|' '$2 != 1101' "${PROCESS_STATE:?}" >"$temporary_file"
  mv -- "$temporary_file" "${PROCESS_STATE:?}"
fi
exit "$PKCHECK_STATUS"
EOF

cat >"$BIN/busctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'busctl|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == --user && ${2:-} == call && ${3:-} == org.freedesktop.DBus && \
  ${4:-} == /org/freedesktop/DBus && ${5:-} == org.freedesktop.DBus && \
  ${6:-} == GetConnectionUnixProcessID && ${7:-} == s && \
  ${8:-} == org.freedesktop.Notifications && $# == 8 ]] || exit 125
if [[ ${DROP_MAKO_BEFORE_OWNER:?} == true ]]; then
  temporary_file="${PROCESS_STATE}.tmp"
  awk -F'|' '$2 != 1101' "${PROCESS_STATE:?}" >"$temporary_file"
  mv -- "$temporary_file" "${PROCESS_STATE:?}"
fi
owner=${BUS_OWNER_RESPONSE:-}
if [[ -z $owner ]]; then
  owner=$(<"${BUS_OWNER_STATE:?}")
fi
case $owner in
  desktop-shell|mako) printf 'u %s\n' "$([[ $owner == desktop-shell ]] && printf 5001 || printf 1101)" ;;
  prefix) printf 'u 50010\n' ;;
  ppid) printf 'PPID=5001\n' ;;
  wrapper) printf 'u 5002\n' ;;
  *) printf 'u 9999\n' ;;
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
if [[ $path == /usr/bin/mako || $path == /usr/bin/swayosd-server ||
  $path == "${DESKTOP_SHELL_MAKO:?}" || $path == "${DESKTOP_SHELL_SWAYOSD_SERVER:?}" ||
  $path == "${DESKTOP_SHELL_POLKIT_AGENT:?}" ]]; then
  printf '%s\n' "$path"
  exit 0
fi
[[ $path == /proc/*/exe ]] || exit 125
pid=${path#/proc/}
pid=${pid%/exe}

if [[ -s ${READLINK_FLIP_PID:?} && $(<"$READLINK_FLIP_PID") == "$pid" ]]; then
  calls=$(awk -F'|' -v pid="$pid" '$1 == pid { print $2; exit }' "${READLINK_CALLS_FILE:?}")
  calls=${calls:-0}
  calls=$((calls + 1))
  temporary_file="${READLINK_CALLS_FILE}.tmp"
  awk -F'|' -v pid="$pid" '$1 != pid' "$READLINK_CALLS_FILE" >"$temporary_file"
  printf '%s\n' "$pid|$calls" >>"$temporary_file"
  mv -- "$temporary_file" "$READLINK_CALLS_FILE"
  if ((calls >= $(<"${READLINK_FLIP_AFTER:?}"))); then
    temporary_file="${PROCESS_STATE}.tmp"
    awk -F'|' -v pid="$pid" '$2 != pid' "$PROCESS_STATE" >"$temporary_file"
    printf '%s\n' "${POLKIT_COMM:?}|$pid|/usr/bin/argv-spoof|${DESKTOP_SHELL_POLKIT_AGENT:?}" >>"$temporary_file"
    mv -- "$temporary_file" "$PROCESS_STATE"
    printf '%s\n' /usr/bin/argv-spoof
    exit 0
  fi
fi
while IFS='|' read -r comm process_pid executable argv; do
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
target_pid=''
if [[ ${1:-} == --pid ]]; then
  [[ $# == 3 ]] || exit 125
  target_pid=$2
  shift 2
fi

if [[ ${FORGED_ANY_DISPLAY_RESPONDER:-false} == true && -z $target_pid ]]; then
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
  exit 0
fi

[[ ${FORGED_ANY_DISPLAY_RESPONDER:-false} != true ]] || exit 1
[[ $target_pid == 5001 ]] || exit 1
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
((POLKIT_AGENT_STATUS == 0)) || exit "$POLKIT_AGENT_STATUS"
[[ ${POLKIT_AGENT_REGISTER:?} == true ]] || exit 0
printf '%s\n' "polkit-gnome-au|1103|${DESKTOP_SHELL_POLKIT_AGENT:?}|${DESKTOP_SHELL_POLKIT_AGENT:?}|11103|1000" >>"${PROCESS_STATE:?}"
if [[ ${DROP_MAKO_AFTER_POLKIT:?} == true ]]; then
  temporary_file="${PROCESS_STATE}.tmp"
  awk -F'|' '$2 != 1101' "${PROCESS_STATE:?}" >"$temporary_file"
  mv -- "$temporary_file" "${PROCESS_STATE:?}"
fi
exit 0
EOF

chmod 0700 "$BIN"/*

export MOCK_LOG FALLTHROUGH_LOG SIGNAL_LOG PROCESS_STATE SERVICE_STATE SERVICE_PID_STATE BUS_OWNER_STATE
export BUS_OWNER_RESPONSE PGREP_ERROR_NAME PGREP_ERROR_STATUS SIGNAL_READD_DECOY INJECT_UNEXPECTED_LIFECYCLE
export FORGED_ANY_DISPLAY_RESPONDER
export READLINK_CALLS_FILE
export READLINK_FLIP_PID READLINK_FLIP_AFTER SIGNAL_COMMAND
export MAKO_MODE_ATTEMPTS_FILE MAKO_MODE_RESPONDS_FILE MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS=0 MAKO_MODE_ERROR_STATUS
export MAKO_MODE_APPLY_ERROR_STATUS MAKO_MODE_READBACK_ERROR_STATUS MAKO_MODE_QUERY_COUNT_FILE MAKO_MODE_STATE
export SYSTEMCTL_STOP_ADAPTER_STATUS SYSTEMCTL_STOP_SHELL_STATUS SYSTEMCTL_START_ADAPTER_STATUS
export SYSTEMCTL_ADAPTER_ACTIVE_STATUS UWSM_MAKO_STATUS UWSM_SWAYOSD_STATUS PKCHECK_STATUS TIMEOUT_STATUS
export POLKIT_AGENT_STATUS POLKIT_AGENT_REGISTER
export DROP_MAKO_AFTER_HIDDEN DROP_MAKO_AFTER_ADAPTER DROP_MAKO_AFTER_SWAYOSD
export DROP_MAKO_AFTER_POLKIT DROP_MAKO_AFTER_PROBE DROP_MAKO_BEFORE_OWNER
export HEALTH_FILE CUE_FILE POLKIT_COMM DESKTOP_SHELL_POLKIT_AGENT="$POLKIT_AGENT"
export DESKTOP_SHELL_MAKO="$MAKO_EXECUTABLE" DESKTOP_SHELL_SWAYOSD_SERVER="$SWAYOSD_SERVER_EXECUTABLE"
export XDG_RUNTIME_DIR="$RUNTIME_DIR" XDG_STATE_HOME="$STATE_HOME"

write_services() {
  local adapter_state=${1-inactive}

  printf '%s\n' \
    'desktop-shell.service=inactive' \
    "desktop-shell-mako-route.service=$adapter_state" >"$SERVICE_STATE"
  : >"$SERVICE_PID_STATE"
}

write_processes() {
  printf '%s\n' \
    "mako|1001|$MAKO_EXECUTABLE|mako|11001|1000" \
    "swayosd-server|1002|$SWAYOSD_SERVER_EXECUTABLE|swayosd-server|11002|1000" \
    "${POLKIT_COMM}|1003|$POLKIT_AGENT|$POLKIT_AGENT|11003|1000" \
    "${POLKIT_COMM}|1005|/usr/bin/unrelated-polkit|$POLKIT_AGENT|11005|1000" \
    'quickshell|1004|/usr/bin/quickshell|quickshell|11004|1000' >"$PROCESS_STATE"
}

write_health() {
  printf '%s\n' "$1" >"$HEALTH_FILE"
}

reset_log() {
  : >"$MOCK_LOG"
  : >"$FALLTHROUGH_LOG"
  : >"$SIGNAL_LOG"
  BUS_OWNER_RESPONSE=''
  : >"$PGREP_ERROR_NAME"
  printf '%s\n' 2 >"$PGREP_ERROR_STATUS"
  SIGNAL_READD_DECOY=false
  INJECT_UNEXPECTED_LIFECYCLE=false
  FORGED_ANY_DISPLAY_RESPONDER=false
  : >"$READLINK_CALLS_FILE"
  : >"$READLINK_FLIP_PID"
  printf '%s\n' 2 >"$READLINK_FLIP_AFTER"
  printf '%s\n' 0 >"$MAKO_MODE_ATTEMPTS_FILE"
  printf '%s\n' 0 >"$MAKO_MODE_QUERY_COUNT_FILE"
  MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS=0
  printf '%s\n' true >"$MAKO_MODE_RESPONDS_FILE"
  MAKO_MODE_ERROR_STATUS=0
  MAKO_MODE_APPLY_ERROR_STATUS=0
  MAKO_MODE_READBACK_ERROR_STATUS=0
  SYSTEMCTL_STOP_ADAPTER_STATUS=0
  SYSTEMCTL_STOP_SHELL_STATUS=0
  SYSTEMCTL_START_ADAPTER_STATUS=0
  SYSTEMCTL_ADAPTER_ACTIVE_STATUS=0
  UWSM_MAKO_STATUS=0
  UWSM_SWAYOSD_STATUS=0
  POLKIT_AGENT_STATUS=0
  POLKIT_AGENT_REGISTER=true
  PKCHECK_STATUS=0
  TIMEOUT_STATUS=0
  DROP_MAKO_AFTER_HIDDEN=false
  DROP_MAKO_AFTER_ADAPTER=false
  DROP_MAKO_AFTER_SWAYOSD=false
  DROP_MAKO_AFTER_POLKIT=false
  DROP_MAKO_AFTER_PROBE=false
  DROP_MAKO_BEFORE_OWNER=false
  printf '%s\n' 'unrelated-mode rustdesk-route-DVI-D-1 rustdesk-route-HDMI-A-1 rustdesk-route-DP-2 rustdesk-route-hidden rustdesk-cue' >"$MAKO_MODE_STATE"
}

run_helper() {
  local helper=$1
  shift

  env \
    PATH="$MOCK_PATH" \
    HOME="$TEST_ROOT/home" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    XDG_STATE_HOME="$XDG_STATE_HOME" \
    MOCK_LOG="$MOCK_LOG" \
    FALLTHROUGH_LOG="$FALLTHROUGH_LOG" \
    SIGNAL_LOG="$SIGNAL_LOG" \
    PROCESS_STATE="$PROCESS_STATE" \
    SERVICE_STATE="$SERVICE_STATE" \
    SERVICE_PID_STATE="$SERVICE_PID_STATE" \
    BUS_OWNER_STATE="$BUS_OWNER_STATE" \
    BUS_OWNER_RESPONSE="$BUS_OWNER_RESPONSE" \
    MAKO_MODE_ATTEMPTS_FILE="$MAKO_MODE_ATTEMPTS_FILE" \
    MAKO_MODE_RESPONDS_FILE="$MAKO_MODE_RESPONDS_FILE" \
    MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS="$MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS" \
    MAKO_MODE_ERROR_STATUS="$MAKO_MODE_ERROR_STATUS" \
    MAKO_MODE_APPLY_ERROR_STATUS="$MAKO_MODE_APPLY_ERROR_STATUS" \
    MAKO_MODE_READBACK_ERROR_STATUS="$MAKO_MODE_READBACK_ERROR_STATUS" \
    MAKO_MODE_QUERY_COUNT_FILE="$MAKO_MODE_QUERY_COUNT_FILE" \
    MAKO_MODE_STATE="$MAKO_MODE_STATE" \
    PGREP_ERROR_NAME="$PGREP_ERROR_NAME" \
    PGREP_ERROR_STATUS="$PGREP_ERROR_STATUS" \
    SIGNAL_READD_DECOY="$SIGNAL_READD_DECOY" \
    INJECT_UNEXPECTED_LIFECYCLE="$INJECT_UNEXPECTED_LIFECYCLE" \
    FORGED_ANY_DISPLAY_RESPONDER="$FORGED_ANY_DISPLAY_RESPONDER" \
    READLINK_CALLS_FILE="$READLINK_CALLS_FILE" \
    READLINK_FLIP_PID="$READLINK_FLIP_PID" \
    READLINK_FLIP_AFTER="$READLINK_FLIP_AFTER" \
    DESKTOP_SHELL_SIGNAL_COMMAND="$SIGNAL_COMMAND" \
    DESKTOP_SHELL_MAKO="$DESKTOP_SHELL_MAKO" \
    DESKTOP_SHELL_SWAYOSD_SERVER="$DESKTOP_SHELL_SWAYOSD_SERVER" \
    HEALTH_FILE="$HEALTH_FILE" \
    CUE_FILE="$CUE_FILE" \
    POLKIT_COMM="$POLKIT_COMM" \
    DESKTOP_SHELL_POLKIT_AGENT="$DESKTOP_SHELL_POLKIT_AGENT" \
    SYSTEMCTL_STOP_ADAPTER_STATUS="$SYSTEMCTL_STOP_ADAPTER_STATUS" \
    SYSTEMCTL_STOP_SHELL_STATUS="$SYSTEMCTL_STOP_SHELL_STATUS" \
    SYSTEMCTL_START_ADAPTER_STATUS="$SYSTEMCTL_START_ADAPTER_STATUS" \
    SYSTEMCTL_ADAPTER_ACTIVE_STATUS="$SYSTEMCTL_ADAPTER_ACTIVE_STATUS" \
    UWSM_MAKO_STATUS="$UWSM_MAKO_STATUS" \
    UWSM_SWAYOSD_STATUS="$UWSM_SWAYOSD_STATUS" \
    POLKIT_AGENT_STATUS="$POLKIT_AGENT_STATUS" \
    POLKIT_AGENT_REGISTER="$POLKIT_AGENT_REGISTER" \
    PKCHECK_STATUS="$PKCHECK_STATUS" \
    TIMEOUT_STATUS="$TIMEOUT_STATUS" \
    DROP_MAKO_AFTER_HIDDEN="$DROP_MAKO_AFTER_HIDDEN" \
    DROP_MAKO_AFTER_ADAPTER="$DROP_MAKO_AFTER_ADAPTER" \
    DROP_MAKO_AFTER_SWAYOSD="$DROP_MAKO_AFTER_SWAYOSD" \
    DROP_MAKO_AFTER_POLKIT="$DROP_MAKO_AFTER_POLKIT" \
    DROP_MAKO_AFTER_PROBE="$DROP_MAKO_AFTER_PROBE" \
    DROP_MAKO_BEFORE_OWNER="$DROP_MAKO_BEFORE_OWNER" \
    "$helper" "$@"
}

assert_no_fallthrough() {
  [[ ! -s $FALLTHROUGH_LOG ]] || fail "helper fell through to the live quickshell binary"
  assert_log_contains "path|$MOCK_PATH" 'helper did not use the closed mock PATH'
  assert_log_not_contains 'pkill|' 'helper invoked forbidden pkill'
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

normalize_lifecycle_trace() {
  awk -F'|' '
    $1 == "path" || index($1, "systemctl-shell-start-cue=") == 1 { next }
    $1 == "pgrep" && $2 == "-x" && $3 == "--" { next }
    $1 == "readlink" && ($2 == "--" || $2 == "-f") { next }
    $1 == "busctl" && $2 == "--user" && $3 == "call" && $4 == "org.freedesktop.DBus" &&
      $5 == "/org/freedesktop/DBus" && $6 == "org.freedesktop.DBus" &&
      $7 == "GetConnectionUnixProcessID" && $8 == "s" && $9 == "org.freedesktop.Notifications" { next }
    $1 == "makoctl" && $2 == "mode" { next }
    $1 == "timeout" || $1 == "pkcheck" { next }
    $1 == "desktop-shell" && ($2 == "ping" || $2 == "health" ||
      ($2 == "--pid" && ($4 == "ping" || $4 == "health"))) { next }
    $1 == "systemctl" && $2 == "--user" && ($3 == "is-active" || $3 == "show") { next }
    $1 == "systemctl" || $1 == "kill" || $1 == "uwsm-app" || $1 == "polkit-agent" || $1 == "rm" {
      print
      next
    }
    { print "unexpected|" $0 }
  ' "$MOCK_LOG"
}

assert_exact_trace() {
  local trace_name=$1
  shift
  local -a expected=("$@")
  local -a actual=()

  mapfile -t actual < <(normalize_lifecycle_trace)
  (( ${#actual[@]} == ${#expected[@]} )) || {
    printf '%s trace mismatch\nexpected: %s\nactual: %s\n' \
      "$trace_name" "${expected[*]}" "${actual[*]}" >&2
    return 1
  }
  for index in "${!expected[@]}"; do
    [[ ${actual[index]} == "${expected[index]}" ]] || {
      printf '%s trace mismatch at %s: expected %s, got %s\n' \
        "$trace_name" "$index" "${expected[index]}" "${actual[index]}" >&2
      return 1
    }
  done
}

expect_activation_owner_failure() {
  local response=$1
  local status=0

  reset_log
  write_services
  write_processes
  write_health '{"notificationsOwned":true,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":""}'
  BUS_OWNER_RESPONSE=$response
  run_helper "$ACTIVATE" >"$activation_output" 2>"$activation_error" || status=$?
  ((status != 0)) || fail "activation accepted forged D-Bus owner response: $response"
  assert_log_contains 'busctl|--user|call|org.freedesktop.DBus' \
    "activation did not query D-Bus owner for $response"
  assert_log_not_contains 'desktop-shell|ping' "activation pinged after forged owner response: $response"
  assert_no_fallthrough
}

expect_rollback_owner_failure() {
  local response=$1
  local status=0

  reset_log
  write_services
  write_processes
  BUS_OWNER_RESPONSE=$response
  run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
  ((status != 0)) || fail "rollback accepted forged D-Bus owner response: $response"
  assert_log_contains 'busctl|--user|call|org.freedesktop.DBus' \
    "rollback did not query D-Bus owner for $response"
  assert_no_fallthrough
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
    assert_not_contains "$source" '/kill' "$helper must use PATH kill"
    assert_not_contains "$source" 'pkill' "$helper must signal discovered PIDs directly"
    assert_not_contains "$source" '/uwsm-app' "$helper must use PATH uwsm-app"
    assert_not_contains "$source" '/makoctl' "$helper must use PATH makoctl"
    assert_not_contains "$source" '/busctl' "$helper must use PATH busctl"
    assert_not_contains "$source" 'pkill quickshell' "$helper must not broadly kill Quickshell"
    assert_not_contains "$source" 'pkill -TERM -f' "$helper must not use command-line regex termination"
    assert_not_contains "$source" 'systemctl --user disable' "$helper must not disable units"
    assert_not_contains "$source" 'systemctl --user enable' "$helper must not enable units"
  done
  assert_contains "$(<"$ACTIVATE")" 'GetConnectionUnixProcessID' 'activation D-Bus PID lookup'
  assert_contains "$(<"$ROLLBACK")" 'GetConnectionUnixProcessID' 'rollback D-Bus PID lookup'
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
SIGNAL_READD_DECOY=true
activation_output="$TEST_ROOT/activation.out"
activation_error="$TEST_ROOT/activation.err"
if ! run_helper "$ACTIVATE" >"$activation_output" 2>"$activation_error"; then
  fail "activation unexpectedly failed: $(<"$activation_error")"
fi

assert_log_order \
  'systemctl|--user|stop|desktop-shell.service|desktop-shell-mako-route.service' \
  'kill|-TERM|1001' \
  'kill|-TERM|1002' \
  'kill|-TERM|1003' \
  'rm|-f|--|' \
  'systemctl|--user|start|desktop-shell.service' \
  'systemctl-shell-start-cue=absent' \
  'systemctl|--user|is-active|--quiet|desktop-shell.service' \
  'busctl|--user|call|org.freedesktop.DBus' \
  'desktop-shell|--pid|5001|ping' \
  'desktop-shell|--pid|5001|health'
assert_exact_trace activation \
  'systemctl|--user|stop|desktop-shell.service|desktop-shell-mako-route.service' \
  'kill|-TERM|1001' 'kill|-TERM|1002' 'kill|-TERM|1003' \
  "rm|-f|--|$CUE_FILE" 'systemctl|--user|start|desktop-shell.service'
assert_log_contains "pgrep|-x|--|$POLKIT_COMM" 'polkit comm lookup is truncated to Linux comm length'
assert_log_contains 'readlink|' 'polkit executable was verified'
assert_process_absent mako
assert_process_absent swayosd-server
if awk -F'|' -v name="$POLKIT_COMM" -v executable="$POLKIT_AGENT" \
  '$1 == name && $3 == executable { found = 1; exit } END { exit !found }' "$PROCESS_STATE"; then
  fail 'exact polkit executable survived activation'
fi
if ! awk -F'|' -v name="$POLKIT_COMM" -v argv="$POLKIT_AGENT" \
  '$1 == name && $3 == "/usr/bin/unrelated-polkit" && $4 == argv { found = 1; exit } END { exit !found }' \
  "$PROCESS_STATE"; then
  fail 'activation terminated a decoy process sharing polkit comm prefix'
fi
assert_process_present quickshell
assert_log_contains 'kill|-TERM|1003' 'activation did not signal the discovered polkit PID'
assert_log_not_contains 'kill|-TERM|1005' 'activation signaled the same-comm polkit decoy'
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
write_services
write_processes
write_health '{"notificationsOwned":true,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":""}'
FORGED_ANY_DISPLAY_RESPONDER=true
forged_activation_output="$TEST_ROOT/forged-activation.out"
forged_activation_error="$TEST_ROOT/forged-activation.err"
status=0
run_helper "$ACTIVATE" >"$forged_activation_output" 2>"$forged_activation_error" || status=$?
((status != 0)) || fail 'activation accepted an any-display forged responder'
assert_log_contains 'desktop-shell|--pid|5001|ping' \
  'activation did not bind ping to the verified MainPID'
assert_log_not_contains 'desktop-shell|ping' \
  'activation used an any-display responder for ping'
assert_no_fallthrough

reset_log
write_services
write_processes
write_health '{"notificationsOwned":true,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":""}'
INJECT_UNEXPECTED_LIFECYCLE=true
if ! run_helper "$ACTIVATE" >"$activation_output" 2>"$activation_error"; then
  fail "activation unexpectedly failed during generic lifecycle trace coverage: $(<"$activation_error")"
fi
if assert_exact_trace activation \
  'systemctl|--user|stop|desktop-shell.service|desktop-shell-mako-route.service' \
  'kill|-TERM|1001' 'kill|-TERM|1002' 'kill|-TERM|1003' \
  "rm|-f|--|$CUE_FILE" 'systemctl|--user|start|desktop-shell.service' 2>/dev/null; then
  fail 'lifecycle trace normalizer filtered an unexpected mutation'
fi
assert_no_fallthrough

expect_activation_owner_failure ppid
expect_activation_owner_failure prefix
expect_activation_owner_failure wrapper

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
assert_log_contains 'desktop-shell|--pid|5001|health' 'failed activation did not inspect health'
assert_process_present quickshell
assert_no_fallthrough

reset_log
write_services
write_processes
write_health '{"notificationsOwned":true,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":""}'
printf '%s\n' mako >"$PGREP_ERROR_NAME"
status=0
run_helper "$ACTIVATE" >"$activation_output" 2>"$activation_error" || status=$?
((status != 0)) || fail 'activation accepted a pgrep error as process absence'
assert_log_not_contains 'kill|' 'activation signaled after a pgrep error'
assert_log_not_contains 'systemctl|--user|start|desktop-shell.service' \
  'activation started the shell after a pgrep error'
assert_no_fallthrough

reset_log
write_services
write_processes
write_health '{"notificationsOwned":true,"polkitRegistered":true,"osdAvailable":true,"notificationRouteError":""}'
printf '%s\n' 1003 >"$READLINK_FLIP_PID"
printf '%s\n' 2 >"$READLINK_FLIP_AFTER"
if ! run_helper "$ACTIVATE" >"$activation_output" 2>"$activation_error"; then
  fail "activation rejected a polkit PID that disappeared before signaling: $(<"$activation_error")"
fi
assert_log_not_contains 'kill|-TERM|1003' 'activation signaled a polkit PID after executable revalidation failed'
if ! awk -F'|' -v name="$POLKIT_COMM" -v argv="$POLKIT_AGENT" \
  '$1 == name && $2 == 1003 && $3 == "/usr/bin/argv-spoof" && $4 == argv { found = 1; exit } END { exit !found }' \
  "$PROCESS_STATE"; then
  fail 'polkit PID revalidation did not preserve the replacement process'
fi
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
  'systemctl|--user|stop|desktop-shell-mako-route.service' \
  'systemctl|--user|stop|desktop-shell.service' \
  "uwsm-app|--|$DESKTOP_SHELL_MAKO" \
  'makoctl|mode' \
  'systemctl|--user|start|desktop-shell-mako-route.service' \
  "uwsm-app|--|$DESKTOP_SHELL_SWAYOSD_SERVER" \
  'polkit-agent|' \
  'pkcheck|' \
  'busctl|--user|call|org.freedesktop.DBus'
assert_exact_trace rollback \
  'systemctl|--user|stop|desktop-shell-mako-route.service' \
  'systemctl|--user|stop|desktop-shell.service' \
  "uwsm-app|--|$DESKTOP_SHELL_MAKO" 'systemctl|--user|start|desktop-shell-mako-route.service' \
  "uwsm-app|--|$DESKTOP_SHELL_SWAYOSD_SERVER" 'polkit-agent|'
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
assert_contains "$(<"$rollback_output")" 'polkit-process: present' 'rollback polkit status'
assert_equal preserved "$(<"$HISTORY_FILE")" 'rollback deleted notification history'
assert_no_fallthrough

uwsm_count_before=$(awk 'index($0, "uwsm-app|") { count++ } END { print count + 0 }' "$MOCK_LOG")
polkit_start_count_before=$(awk 'index($0, "polkit-agent|") { count++ } END { print count + 0 }' "$MOCK_LOG")
adapter_start_count_before=$(awk 'index($0, "systemctl|--user|start|desktop-shell-mako-route.service") { count++ } END { print count + 0 }' "$MOCK_LOG")
expect_rollback_owner_failure ppid
expect_rollback_owner_failure prefix
expect_rollback_owner_failure wrapper

write_services active
printf '%s\n' \
  "mako|1101|$MAKO_EXECUTABLE|mako|11101|1000" \
  "swayosd-server|1102|$SWAYOSD_SERVER_EXECUTABLE|swayosd-server|11102|1000" \
  "${POLKIT_COMM}|1103|$POLKIT_AGENT|$POLKIT_AGENT|11103|1000" \
  'quickshell|1004|/usr/bin/quickshell|quickshell|11004|1000' >"$PROCESS_STATE"
printf '%s\n' mako >"$BUS_OWNER_STATE"
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
assert_equal 1 "$adapter_start_count_after" 'idempotent rollback did not restart the isolated adapter'
assert_equal 2 "$uwsm_count_before" 'rollback did not start both missing legacy services once'
assert_equal 1 "$polkit_start_count_before" 'rollback did not start polkit once'
assert_equal 1 "$adapter_start_count_before" 'rollback did not start the adapter once'
assert_no_fallthrough

reset_log
write_services active
: >"$PROCESS_STATE"
printf '%s\n' false >"$MAKO_MODE_RESPONDS_FILE"
status=0
run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
((status != 0)) || fail 'rollback accepted absent Mako with an active adapter'
assert_log_order \
  'systemctl|--user|stop|desktop-shell-mako-route.service' \
  'systemctl|--user|stop|desktop-shell.service' \
  "uwsm-app|--|$DESKTOP_SHELL_MAKO"
assert_log_not_contains 'systemctl|--user|start|desktop-shell-mako-route.service' \
  'rollback restarted the adapter after unresponsive Mako'
if ! awk -F= '$1 == "desktop-shell-mako-route.service" && $2 == "inactive" { found = 1; exit } END { exit !found }' "$SERVICE_STATE"; then
  fail 'active adapter remained active during absent-Mako rollback probing'
fi
assert_no_fallthrough

reset_log
write_services active
printf '%s\n' "mako|1101|$MAKO_EXECUTABLE|mako|11101|1000" >"$PROCESS_STATE"
printf '%s\n' false >"$MAKO_MODE_RESPONDS_FILE"
status=0
run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
((status != 0)) || fail 'rollback accepted unresponsive Mako with an active adapter'
assert_log_contains 'makoctl|mode|adapter=inactive' 'rollback probed Mako while the active adapter was isolated'
assert_log_not_contains 'systemctl|--user|start|desktop-shell-mako-route.service' \
  'rollback restarted the adapter after unresponsive Mako'
assert_no_fallthrough

reset_log
write_services active
write_processes
printf '%s\n' mako >"$BUS_OWNER_STATE"
printf '%s\n' mako >"$PGREP_ERROR_NAME"
printf '%s\n' 2 >"$PGREP_ERROR_STATUS"
status=0
run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
((status != 0)) || fail 'rollback accepted an active-adapter pgrep error'
assert_log_order \
  'systemctl|--user|stop|desktop-shell-mako-route.service' \
  'systemctl|--user|stop|desktop-shell.service'
assert_log_not_contains 'uwsm-app|' 'rollback recovered after an active-adapter pgrep error'
assert_log_not_contains 'polkit-agent|' 'rollback restarted polkit after an active-adapter pgrep error'
assert_log_not_contains 'systemctl|--user|start|desktop-shell-mako-route.service' \
  'rollback restarted the adapter after a pgrep error'
assert_no_fallthrough

reset_log
write_services active
write_processes
printf '%s\n' mako >"$BUS_OWNER_STATE"
MAKO_MODE_ERROR_STATUS=7
status=0
run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
((status != 0)) || fail 'rollback accepted a non-1 Mako readiness error'
assert_log_order \
  'systemctl|--user|stop|desktop-shell-mako-route.service' \
  'systemctl|--user|stop|desktop-shell.service' \
  'makoctl|mode|adapter=inactive' \
  'systemctl|--user|stop|desktop-shell-mako-route.service'
assert_log_not_contains 'uwsm-app|' 'rollback recovered after a non-1 Mako readiness error'
assert_log_not_contains 'polkit-agent|' 'rollback restarted polkit after a non-1 Mako readiness error'
assert_log_not_contains 'systemctl|--user|start|desktop-shell-mako-route.service' \
  'rollback restarted the adapter after a Mako readiness error'
assert_no_fallthrough

reset_log
write_services
: >"$PROCESS_STATE"
printf '%s\n' mako >"$PGREP_ERROR_NAME"
status=0
run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
((status != 0)) || fail 'rollback accepted a pgrep error as process absence'
assert_log_not_contains "uwsm-app|--|$DESKTOP_SHELL_MAKO" 'rollback launched Mako after a pgrep error'
assert_no_fallthrough

reset_log
write_services
printf '%s\n' \
  "mako|1101|$MAKO_EXECUTABLE|mako|11101|1000" \
  "swayosd-server|1102|$SWAYOSD_SERVER_EXECUTABLE|swayosd-server|11102|1000" \
  "${POLKIT_COMM}|1103|$POLKIT_AGENT|$POLKIT_AGENT|11103|1000" \
  'quickshell|1004|/usr/bin/quickshell|quickshell|11004|1000' >"$PROCESS_STATE"
printf '%s\n' other >"$BUS_OWNER_STATE"
status=0
run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
((status != 0)) || fail 'rollback accepted an incorrect notification owner'
assert_log_contains 'busctl|--user|call|org.freedesktop.DBus' 'rollback ownership failure did not query D-Bus'
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

assert_exact_process_path_present() {
  local expected_path=$1

  awk -F'|' -v expected_path="$expected_path" '$3 == expected_path { found = 1; exit } END { exit !found }' \
    "$PROCESS_STATE" || fail "exact process path is absent: $expected_path"
}

assert_exact_process_path_absent() {
  local expected_path=$1

  if awk -F'|' -v expected_path="$expected_path" '$3 == expected_path { found = 1; exit } END { exit found }' \
    "$PROCESS_STATE"; then
    return 0
  fi
  fail "exact process path is present: $expected_path"
}

assert_service_state() {
  local unit=$1
  local expected_state=$2
  local actual

  actual=$(awk -F= -v unit="$unit" '$1 == unit { print $2; exit }' "$SERVICE_STATE")
  assert_equal "$expected_state" "$actual" "service state for $unit"
}

assert_safe_hidden_adapter() {
  local modes

  modes=$(<"$MAKO_MODE_STATE")
  assert_contains "$modes" 'rustdesk-route-hidden' 'safe rollback state lacks hidden Mako mode'
  assert_not_contains "$modes" 'rustdesk-route-DVI-D-1' 'safe rollback state exposes DVI-D-1 route'
  assert_not_contains "$modes" 'rustdesk-route-HDMI-A-1' 'safe rollback state exposes HDMI-A-1 route'
  assert_not_contains "$modes" 'rustdesk-route-DP-2' 'safe rollback state exposes DP-2 route'
  assert_not_contains "$modes" 'rustdesk-cue' 'safe rollback state exposes cue mode'
  assert_service_state desktop-shell-mako-route.service active
  assert_exact_process_path_present "$DESKTOP_SHELL_MAKO"
}

assert_no_rollback_success_status() {
  assert_not_contains "$(<"$rollback_output")" 'desktop-shell rollback status' \
    'failed rollback printed a success status'
  assert_not_contains "$(<"$rollback_output")" 'polkit-process: present' \
    'failed rollback claimed polkit registration'
}

prepare_clean_rollback_state() {
  reset_log
  write_services
  : >"$PROCESS_STATE"
  printf '%s\n' none >"$BUS_OWNER_STATE"
  rollback_output="$TEST_ROOT/task4c2-rollback.out"
  rollback_error="$TEST_ROOT/task4c2-rollback.err"
}

expect_pre_adapter_failure() {
  local label=$1
  local expect_mako_start=$2
  local status=0

  prepare_clean_rollback_state
  case $label in
    adapter-stop) SYSTEMCTL_STOP_ADAPTER_STATUS=7 ;;
    shell-stop) SYSTEMCTL_STOP_SHELL_STATUS=7 ;;
    mako-start) UWSM_MAKO_STATUS=7 ;;
    mako-readiness) printf '%s\n' false >"$MAKO_MODE_RESPONDS_FILE" ;;
    hidden-apply) MAKO_MODE_APPLY_ERROR_STATUS=7 ;;
    hidden-verify) MAKO_MODE_READBACK_ERROR_STATUS=7 ;;
    adapter-start) SYSTEMCTL_START_ADAPTER_STATUS=7 ;;
    adapter-active) SYSTEMCTL_ADAPTER_ACTIVE_STATUS=7 ;;
    *) fail "unknown pre-adapter failure injection: $label" ;;
  esac

  run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
  ((status != 0)) || fail "pre-adapter failure was accepted: $label"
  assert_exact_process_path_absent "$DESKTOP_SHELL_MAKO"
  assert_service_state desktop-shell-mako-route.service inactive
  assert_not_contains "$(<"$PROCESS_STATE")" "$SWAYOSD_SERVER_EXECUTABLE" \
    "pre-adapter failure started SwayOSD: $label"
  assert_not_contains "$(<"$PROCESS_STATE")" "$POLKIT_AGENT" \
    "pre-adapter failure started polkit: $label"
  if [[ $expect_mako_start == true ]]; then
    assert_log_contains 'kill|-TERM|1101' "pre-adapter failure did not terminate exact Mako: $label"
  fi
  assert_log_not_contains "kill|-TERM|1201" "pre-adapter failure signalled a Mako decoy: $label"
  assert_no_fallthrough
}

expect_post_adapter_failure() {
  local label=$1
  local status=0

  prepare_clean_rollback_state
  case $label in
    swayosd-start) UWSM_SWAYOSD_STATUS=7 ;;
    polkit-start) POLKIT_AGENT_REGISTER=false ;;
    polkit-probe) PKCHECK_STATUS=7 ;;
    polkit-timeout) TIMEOUT_STATUS=124 ;;
    owner) BUS_OWNER_RESPONSE=other ;;
    *) fail "unknown post-adapter failure injection: $label" ;;
  esac

  run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
  ((status != 0)) || fail "post-adapter failure was accepted: $label"
  assert_safe_hidden_adapter
  assert_no_rollback_success_status
  assert_log_not_contains 'kill|-TERM|1101' "post-adapter failure tore down safe Mako: $label"
  if [[ $label == polkit-start ]]; then
    assert_log_not_contains 'pkcheck|' 'polkit probe accepted a process-only forged agent'
  fi
  assert_no_fallthrough
}

expect_mako_disappearance() {
  local label=$1
  local status=0

  prepare_clean_rollback_state
  case $label in
    after-hidden) DROP_MAKO_AFTER_HIDDEN=true ;;
    after-adapter) DROP_MAKO_AFTER_ADAPTER=true ;;
    after-swayosd) DROP_MAKO_AFTER_SWAYOSD=true ;;
    after-polkit) DROP_MAKO_AFTER_POLKIT=true ;;
    after-probe) DROP_MAKO_AFTER_PROBE=true ;;
    before-owner) DROP_MAKO_BEFORE_OWNER=true ;;
    *) fail "unknown Mako disappearance injection: $label" ;;
  esac

  run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
  ((status != 0)) || fail "Mako disappearance was accepted: $label"
  assert_exact_process_path_absent "$DESKTOP_SHELL_MAKO"
  assert_service_state desktop-shell-mako-route.service inactive
  assert_log_not_contains 'kill|-TERM|1201' "Mako disappearance signalled a decoy: $label"
  assert_no_fallthrough
}

prepare_clean_rollback_state
printf '%s\n' \
  "mako|1201|/usr/bin/mako-decoy|mako|11201|1000" \
  "swayosd-server|1202|/usr/bin/swayosd-decoy|swayosd-server|11202|1000" >"$PROCESS_STATE"
MAKO_MODE_ATTEMPTS_BEFORE_SUCCESS=1
if ! run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error"; then
  fail "exact rollback path unexpectedly failed: $(<"$rollback_error")"
fi
assert_log_order \
  'systemctl|--user|stop|desktop-shell-mako-route.service' \
  'systemctl|--user|stop|desktop-shell.service' \
  "uwsm-app|--|$DESKTOP_SHELL_MAKO" \
  'makoctl|mode|adapter=inactive' \
  'makoctl|mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden' \
  'systemctl|--user|start|desktop-shell-mako-route.service' \
  "uwsm-app|--|$DESKTOP_SHELL_SWAYOSD_SERVER" \
  'polkit-agent|' \
  'pkcheck|' \
  'busctl|--user|call|org.freedesktop.DBus'
assert_safe_hidden_adapter
assert_exact_process_path_present "$DESKTOP_SHELL_SWAYOSD_SERVER"
assert_contains "$(<"$rollback_output")" 'swayosd-server.pid: 1102' 'rollback SwayOSD status is missing'
assert_log_order 'polkit-agent|' 'pkcheck|'
assert_log_contains 'pkcheck|-a|org.freedesktop.policykit.exec|-p|1103,11103,1000|-d|program|/usr/bin/true|-u' \
  'functional polkit probe arguments'
assert_log_contains "uwsm-app|--|$DESKTOP_SHELL_MAKO" 'rollback did not launch exact Mako path'
assert_log_contains "uwsm-app|--|$DESKTOP_SHELL_SWAYOSD_SERVER" 'rollback did not launch exact SwayOSD path'
assert_log_not_contains 'kill|-TERM|1201' 'successful rollback signalled a Mako decoy'
assert_log_not_contains 'kill|-TERM|1202' 'successful rollback signalled a SwayOSD decoy'
assert_contains "$(<"$rollback_output")" 'desktop-shell rollback status' 'rollback success status is missing'
assert_contains "$(<"$rollback_output")" 'polkit-process: present' 'rollback polkit status is missing'
assert_no_fallthrough

for failure in adapter-stop shell-stop mako-start mako-readiness hidden-apply hidden-verify adapter-start adapter-active; do
  if [[ $failure == adapter-stop || $failure == shell-stop || $failure == mako-start ]]; then
    expect_pre_adapter_failure "$failure" false
  else
    expect_pre_adapter_failure "$failure" true
  fi
done

for failure in swayosd-start polkit-start polkit-probe polkit-timeout owner; do
  expect_post_adapter_failure "$failure"
done

for disappearance in after-hidden after-adapter after-swayosd after-polkit after-probe before-owner; do
  expect_mako_disappearance "$disappearance"
done

prepare_clean_rollback_state
for invalid_override in mako swayosd; do
  case $invalid_override in
    mako)
      DESKTOP_SHELL_MAKO=relative
      ;;
    swayosd)
      DESKTOP_SHELL_SWAYOSD_SERVER=relative
      ;;
  esac
  status=0
  run_helper "$ROLLBACK" >"$rollback_output" 2>"$rollback_error" || status=$?
  DESKTOP_SHELL_MAKO="$MAKO_EXECUTABLE"
  DESKTOP_SHELL_SWAYOSD_SERVER="$SWAYOSD_SERVER_EXECUTABLE"
  ((status != 0)) || fail "relative $invalid_override override was accepted"
  assert_log_not_contains 'systemctl|' "relative $invalid_override override performed lifecycle commands"
  [[ ! -s $FALLTHROUGH_LOG ]] || fail "relative $invalid_override override reached a live fallback"
done

printf '%s\n' 'PASS: mocked desktop service activation and rollback lifecycle contract'
