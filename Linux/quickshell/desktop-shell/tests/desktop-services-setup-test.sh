#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CONFIG="$ROOT/tidydots.yaml"
TEST_ROOT="$(mktemp -d)"
BIN="$TEST_ROOT/bin"
MOCK_LOG="$TEST_ROOT/mock.log"
SERVICE_STATE="$TEST_ROOT/service-state"
ENABLED_STATE="$TEST_ROOT/enabled-state"
NEED_RELOAD_STATE="$TEST_ROOT/need-reload-state"
FAIL_DAEMON_RELOAD=false

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  rm -rf -- "$TEST_ROOT"
  exit "$status"
}

trap cleanup EXIT HUP INT TERM
mkdir -p -- "$BIN"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local message=$3

  [[ $actual == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_log_not_contains() {
  local needle=$1
  local message=$2

  if grep -Fqx -- "$needle" "$MOCK_LOG"; then
    fail "$message: found '$needle'"
  fi
}

assert_systemctl_trace() {
  local trace_name=$1
  shift
  local -a expected=("$@")
  local -a actual=()

  mapfile -t actual < <(grep -F 'systemctl|' "$MOCK_LOG" || true)
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

extract_linux_command() {
  local key=$1

  awk -v key="$key" '
    /^  - / {
      if (in_app) exit
      next
    }
    $0 == "    name: desktop-shell" {
      in_app = 1
      next
    }
    !in_app { next }
    $0 == "      - " key ":" || $0 == "        " key ":" {
      in_section = 1
      next
    }
    in_section && $0 ~ /^        (run|name):/ {
      exit
    }
    in_section && $0 == "          linux: >-" {
      folded = 1
      next
    }
    in_section && folded && $0 ~ /^            / {
      line = $0
      sub(/^            /, "", line)
      if (command != "") command = command " "
      command = command line
      next
    }
    in_section && $0 ~ /^          linux: / {
      command = $0
      sub(/^          linux: /, "", command)
      exit
    }
    END { print command }
  ' "$CONFIG"
}

CHECK_COMMAND="$(extract_linux_command check)"
RUN_COMMAND="$(extract_linux_command run)"
[[ $CHECK_COMMAND == *'is-enabled --quiet desktop-shell.service'* ]] || fail 'tidydots check was not extracted'
[[ $RUN_COMMAND == *'desktop-shell.service'* ]] || fail 'tidydots repair command was not extracted'

cat >"$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'systemctl|%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${MOCK_LOG:?}"
[[ ${1:-} == --user ]] || exit 125
shift

set_service_state() {
  printf '%s\n' "$2" >"${SERVICE_STATE:?}"
}

service_state() {
  cat "${SERVICE_STATE:?}"
}

case ${1:-} in
  is-enabled)
    [[ ${2:-} == --quiet && ${3:-} == desktop-shell.service && $# == 3 ]] || exit 125
    [[ $(<"${ENABLED_STATE:?}") == enabled ]]
    ;;
  is-active)
    [[ ${2:-} == --quiet && ${3:-} == desktop-shell.service && $# == 3 ]] || exit 125
    [[ $(service_state) == active ]]
    ;;
  show)
    [[ ${2:-} == desktop-shell.service && ${3:-} == --property=NeedDaemonReload && \
      ${4:-} == --value && $# == 4 ]] || exit 125
    cat "${NEED_RELOAD_STATE:?}"
    ;;
  stop)
    [[ ${2:-} == desktop-shell.service && $# == 2 ]] || exit 125
    set_service_state desktop-shell.service inactive
    ;;
  daemon-reload)
    [[ $# == 1 ]] || exit 125
    if [[ ${FAIL_DAEMON_RELOAD:?} == true ]]; then
      if [[ $(service_state) == active ]]; then
        printf '%s\n' 'restart-on-failure|desktop-shell.service' >>"${MOCK_LOG:?}"
      fi
      exit 7
    fi
    printf '%s\n' no >"${NEED_RELOAD_STATE:?}"
    ;;
  enable)
    [[ ${2:-} == desktop-shell.service && $# == 2 ]] || exit 125
    printf '%s\n' enabled >"${ENABLED_STATE:?}"
    ;;
  start|restart|try-restart)
    printf 'unexpected-lifecycle|%s\n' "$*" >>"${MOCK_LOG:?}"
    exit 125
    ;;
  *)
    exit 125
    ;;
esac
EOF
chmod 0700 "$BIN/systemctl"

export MOCK_LOG SERVICE_STATE ENABLED_STATE NEED_RELOAD_STATE FAIL_DAEMON_RELOAD

write_state() {
  local service_state=$1
  local need_reload=$2
  local enabled_state=${3-enabled}

  printf '%s\n' "$service_state" >"$SERVICE_STATE"
  printf '%s\n' "$enabled_state" >"$ENABLED_STATE"
  printf '%s\n' "$need_reload" >"$NEED_RELOAD_STATE"
}

run_restore() {
  local status=0

  if ! PATH="$BIN:$PATH" bash -c "$CHECK_COMMAND"; then
    PATH="$BIN:$PATH" bash -c "$RUN_COMMAND" || status=$?
  fi
  return "$status"
}

write_state active no
: >"$MOCK_LOG"
run_restore || fail 'unchanged active service repair failed'
assert_systemctl_trace unchanged-active \
  'systemctl|--user|is-enabled|--quiet|desktop-shell.service' \
  'systemctl|--user|show|desktop-shell.service|--property=NeedDaemonReload|--value'
assert_log_not_contains 'systemctl|--user|stop|desktop-shell.service' \
  'unchanged active service was stopped'

write_state inactive yes disabled
FAIL_DAEMON_RELOAD=false
: >"$MOCK_LOG"
run_restore || fail 'inactive disabled service repair failed'
assert_equal inactive "$(<"$SERVICE_STATE")" 'inactive disabled service was not left stopped'
assert_systemctl_trace inactive-disabled \
  'systemctl|--user|is-enabled|--quiet|desktop-shell.service' \
  'systemctl|--user|stop|desktop-shell.service' \
  'systemctl|--user|daemon-reload' \
  'systemctl|--user|enable|desktop-shell.service'

write_state active yes
FAIL_DAEMON_RELOAD=false
: >"$MOCK_LOG"
run_restore || fail 'changed active service repair failed'
assert_equal inactive "$(<"$SERVICE_STATE")" 'changed service was not left stopped'
assert_systemctl_trace changed-active \
  'systemctl|--user|is-enabled|--quiet|desktop-shell.service' \
  'systemctl|--user|show|desktop-shell.service|--property=NeedDaemonReload|--value' \
  'systemctl|--user|stop|desktop-shell.service' \
  'systemctl|--user|daemon-reload' \
  'systemctl|--user|enable|desktop-shell.service'
assert_log_not_contains 'unexpected-lifecycle|' \
  'changed service repair started the service'
assert_log_not_contains 'unexpected-lifecycle|' \
  'changed service repair restarted the service'

write_state active yes
FAIL_DAEMON_RELOAD=true
: >"$MOCK_LOG"
status=0
run_restore || status=$?
((status != 0)) || fail 'daemon-reload failure was accepted'
assert_equal inactive "$(<"$SERVICE_STATE")" 'failed cutover did not leave the service stopped'
assert_systemctl_trace failed-cutover \
  'systemctl|--user|is-enabled|--quiet|desktop-shell.service' \
  'systemctl|--user|show|desktop-shell.service|--property=NeedDaemonReload|--value' \
  'systemctl|--user|stop|desktop-shell.service' \
  'systemctl|--user|daemon-reload'
assert_log_not_contains 'restart-on-failure|desktop-shell.service' \
  'failed cutover launched Restart=on-failure'
assert_log_not_contains 'systemctl|--user|enable|desktop-shell.service' \
  'failed cutover enabled the service after reload failure'

printf '%s\n' 'PASS: tidydots desktop service setup lifecycle contract'
