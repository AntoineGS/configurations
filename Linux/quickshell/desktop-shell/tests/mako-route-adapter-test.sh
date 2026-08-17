#!/usr/bin/env bash
# shellcheck disable=SC2317 # Cleanup functions are invoked through EXIT traps.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ADAPTER="$SCRIPT_DIR/../../../os/helpers/desktop-shell-mako-route"
ADAPTER_UNIT="$SCRIPT_DIR/../systemd/desktop-shell-mako-route.service"
SHELL_UNIT="$SCRIPT_DIR/../systemd/desktop-shell.service"
TIDYDOTS="$SCRIPT_DIR/../../../../tidydots.yaml"

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

assert_file_mode() {
  local expected=$1
  local path=$2
  local actual

  [[ -e $path ]] || fail "missing path for mode assertion: $path"
  actual=$(stat -c '%a' -- "$path") || fail "could not inspect mode for $path"
  assert_equal "${expected#0}" "${actual#0}" "mode for $path"
}

process_start_time() {
  local pid=$1

  [[ $pid =~ ^[0-9]+$ ]] || return 1
  [[ -r /proc/$pid/stat ]] || return 1
  awk '{print $22}' "/proc/$pid/stat"
}

process_parent_pid() {
  local pid=$1

  [[ $pid =~ ^[0-9]+$ ]] || return 1
  [[ -r /proc/$pid/status ]] || return 1
  awk '/^PPid:/ {print $2; exit}' "/proc/$pid/status"
}

process_state() {
  local pid=$1

  [[ $pid =~ ^[0-9]+$ ]] || return 1
  [[ -r /proc/$pid/status ]] || return 1
  awk '/^State:/ {print $2; exit}' "/proc/$pid/status"
}

process_identity_is_live() {
  local pid=$1
  local expected_start_time=$2
  local actual_start_time
  local state

  [[ $pid =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  actual_start_time=$(process_start_time "$pid") || return 1
  [[ $actual_start_time == "$expected_start_time" ]] || return 1
  state=$(process_state "$pid") || return 1
  case $state in
    R|S|D|I|T|t|W) return 0 ;;
    Z|X|*) return 1 ;;
  esac
}

assert_process_identity() {
  local pid=$1
  local expected_start_time=$2
  local message=$3
  local state

  process_identity_is_live "$pid" "$expected_start_time" || {
    state=$(process_state "$pid" 2>/dev/null || printf 'unavailable')
    fail "$message: fake Mako is not a live process (state: $state)"
  }
}

assert_route_modes() {
  local expected=$1
  local actual

  actual=$(<"$MAKO_MODE_STATE")
  assert_equal "$expected" "$actual" 'Mako mode state'
}

assert_cue() {
  local expected=$1
  local actual

  [[ -f $CUE_FILE ]] || fail "missing cue file: $CUE_FILE"
  actual=$(<"$CUE_FILE")
  assert_equal "$expected" "$actual" 'cue contents'
  assert_file_mode 0600 "$CUE_FILE"
}

assert_no_cue() {
  [[ ! -e $CUE_FILE && ! -L $CUE_FILE ]] || fail "unexpected cue file: $CUE_FILE"
}

log_count() {
  wc -l <"$MAKOCTL_LOG"
}

last_mako_call() {
  local lines=()
  mapfile -t lines <"$MAKOCTL_LOG"
  [[ ${#lines[@]} -gt 0 ]] || fail 'expected at least one makoctl call'
  printf '%s' "${lines[${#lines[@]} - 1]}"
}

wait_for_log_count() {
  local expected=$1
  local deadline=$((SECONDS + 3))
  local actual

  while ((SECONDS < deadline)); do
    actual=$(log_count)
    [[ $actual -ge $expected ]] && return 0
    /usr/bin/sleep 0.01
  done

  fail "timed out waiting for $expected Mako calls; got $(log_count)"
}

wait_for_file() {
  local path=$1
  local deadline=$((SECONDS + 3))

  while ((SECONDS < deadline)); do
    [[ -f $path ]] && return 0
    /usr/bin/sleep 0.01
  done

  fail "timed out waiting for file: $path"
}

iteration_completion_count() {
  [[ -f $FAKE_ITERATION_COMPLETION_LOG ]] || {
    printf '0\n'
    return 0
  }
  wc -l <"$FAKE_ITERATION_COMPLETION_LOG"
}

wait_for_iteration_completions() {
  local expected=$1
  local deadline=$((SECONDS + 3))
  local actual

  while ((SECONDS < deadline)); do
    actual=$(iteration_completion_count)
    [[ $actual -ge $expected ]] && return 0
    /usr/bin/sleep 0.01
  done

  fail "timed out waiting for $expected completed adapter iterations; got $(iteration_completion_count)"
}

assert_no_new_mako_call_after_iterations() {
  local expected_calls=$1
  local expected_completions=$2

  wait_for_iteration_completions "$expected_completions"
  assert_equal "$expected_calls" "$(log_count)" 'unchanged route did not call makoctl'
}

assert_last_call() {
  local expected=$1

  assert_equal "$expected" "$(last_mako_call)" 'makoctl mode arguments'
}

assert_atomic_cue_rename() {
  local log

  log=$(<"$MV_LOG")
  [[ $log == *"rustdesk-notification-cue."*" $CUE_FILE"* ]] || \
    fail 'cue file was not replaced with an atomic temporary-file rename'
  [[ $log != *"> $CUE_FILE"* ]] || fail 'cue file was written through shell redirection'
}

write_route() {
  local visible=$1
  local output=$2
  local cue_output=$3
  local direction=$4
  local updated_at=$5
  local temporary_file

  temporary_file=$(mktemp "$ROUTE_DIR/.test-notification-route.XXXXXX")
  jq -cn \
    --argjson visible "$visible" \
    --arg output "$output" \
    --arg cue_output "$cue_output" \
    --arg direction "$direction" \
    --argjson updated_at "$updated_at" \
    '{version: 1, visible: $visible,
      output: (if $output == "null" then null else $output end),
      cueOutput: (if $cue_output == "null" then null else $cue_output end),
      direction: (if $direction == "null" then null else $direction end),
      updatedAt: $updated_at}' >"$temporary_file"
  chmod 0600 -- "$temporary_file"
  mv -f -- "$temporary_file" "$ROUTE_FILE"
}

write_raw_route() {
  local content=$1
  local temporary_file

  temporary_file=$(mktemp "$ROUTE_DIR/.test-notification-route.XXXXXX")
  printf '%s\n' "$content" >"$temporary_file"
  chmod 0600 -- "$temporary_file"
  mv -f -- "$temporary_file" "$ROUTE_FILE"
}

force_visible_route() {
  local expected_count=$1

  write_route true DVI-D-1 null null "$FAKE_NOW"
  wait_for_log_count "$expected_count"
  assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1'
  assert_no_cue
}

expect_hidden_for_raw_route() {
  local content=$1
  local expected_count=$2

  force_visible_route "$((expected_count - 1))"
  write_raw_route "$content"
  wait_for_log_count "$expected_count"
  assert_route_modes 'unrelated-mode rustdesk-route-hidden'
  assert_no_cue
}

kill_descendants() {
  local root=$1
  local child
  local children=()

  mapfile -t children < <(pgrep -P "$root" 2>/dev/null || true)
  for child in "${children[@]}"; do
    kill_descendants "$child"
    kill -TERM "$child" 2>/dev/null || true
  done
}

register_owned_child() {
  local pid=$1
  local start_time=$2

  OWNED_CHILDREN+=("$pid:$start_time")
}

update_owned_child_start_time() {
  local pid=$1
  local start_time=$2
  local entry
  local entry_pid
  local updated=()

  for entry in "${OWNED_CHILDREN[@]}"; do
    entry_pid=${entry%%:*}
    if [[ $entry_pid == "$pid" ]]; then
      updated+=("$pid:$start_time")
    else
      updated+=("$entry")
    fi
  done
  OWNED_CHILDREN=("${updated[@]}")
}

forget_owned_child() {
  local pid=$1
  local entry
  local entry_pid
  local retained=()

  for entry in "${OWNED_CHILDREN[@]}"; do
    entry_pid=${entry%%:*}
    [[ $entry_pid == "$pid" ]] || retained+=("$entry")
  done
  OWNED_CHILDREN=("${retained[@]}")
}

cleanup_owned_child() {
  local pid=$1
  local expected_start_time=$2
  local parent_pid
  local current_start_time

  [[ $pid =~ ^[0-9]+$ ]] || return 0
  if ! parent_pid=$(process_parent_pid "$pid" 2>/dev/null); then
    wait "$pid" 2>/dev/null || true
    return 0
  fi
  [[ $parent_pid == "$$" ]] || return 0
  if [[ -n $expected_start_time ]]; then
    current_start_time=$(process_start_time "$pid" 2>/dev/null) || return 0
    [[ $current_start_time == "$expected_start_time" ]] || return 0
  fi

  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup_owned_children() {
  local entry
  local pid
  local expected_start_time

  for entry in "${OWNED_CHILDREN[@]}"; do
    pid=${entry%%:*}
    expected_start_time=${entry#*:}
    cleanup_owned_child "$pid" "$expected_start_time"
  done
  OWNED_CHILDREN=()
}

cleanup_adapter() {
  local status=0

  if [[ -n ${adapter_pid:-} ]] && kill -0 "$adapter_pid" 2>/dev/null; then
    kill_descendants "$adapter_pid"
    kill -TERM "$adapter_pid" 2>/dev/null || true
    wait "$adapter_pid" || status=$?
    [[ $status -ne 0 ]] || true
  fi
  adapter_pid=""
}

cleanup() {
  cleanup_adapter
  cleanup_owned_children
  rm -rf -- "$TEST_RUNTIME_DIR"
}

assert_setup_failure_cleanup() {
  local setup_failure_pid

  "$TEST_BIN/fake-mako" &
  setup_failure_pid=$!
  register_owned_child "$setup_failure_pid" ""
  cleanup_owned_child "$setup_failure_pid" ""
  forget_owned_child "$setup_failure_pid"
  [[ ! -e /proc/$setup_failure_pid/status ]] || \
    fail 'setup-failure cleanup did not reap the owned fake Mako child'
}

[[ -f $ADAPTER ]] || fail "adapter helper is missing: $ADAPTER"
[[ -f $ADAPTER_UNIT ]] || fail "adapter unit is missing: $ADAPTER_UNIT"

adapter_unit_text=$(<"$ADAPTER_UNIT")
shell_unit_text=$(<"$SHELL_UNIT")
tidydots_text=$(<"$TIDYDOTS")

assert_contains "$adapter_unit_text" 'Description=Rollback Mako adapter for desktop-shell notification routes' \
  'adapter unit description'
assert_contains "$adapter_unit_text" 'PartOf=graphical-session.target' 'adapter unit session relationship'
assert_contains "$adapter_unit_text" 'Conflicts=desktop-shell.service' 'adapter unit conflict'
assert_contains "$adapter_unit_text" 'Type=simple' 'adapter unit type'
assert_contains "$adapter_unit_text" 'ExecStart=%h/.local/share/helpers/desktop-shell-mako-route' \
  'adapter unit executable'
assert_contains "$adapter_unit_text" 'Restart=on-failure' 'adapter unit restart policy'
assert_contains "$adapter_unit_text" 'RestartSec=2' 'adapter unit restart delay'
assert_not_contains "$adapter_unit_text" '[Install]' 'adapter unit must remain dormant'
assert_not_contains "$adapter_unit_text" 'WantedBy=' 'adapter unit must not be enabled'
assert_contains "$shell_unit_text" 'Conflicts=desktop-shell-mako-route.service' 'desktop shell conflict'
assert_contains "$tidydots_text" '          - desktop-shell.service' 'tidydots maps desktop shell service'
assert_contains "$tidydots_text" '          - desktop-shell-mako-route.service' 'tidydots maps adapter service'
assert_not_contains "$tidydots_text" 'is-enabled --quiet desktop-shell-mako-route.service' \
  'tidydots must not enable the adapter'
assert_not_contains "$tidydots_text" 'enable --now desktop-shell-mako-route.service' \
  'tidydots must not start the adapter'

TEST_RUNTIME_DIR=$(mktemp -d)
TEST_BIN="$TEST_RUNTIME_DIR/bin"
ROUTE_DIR="$TEST_RUNTIME_DIR/desktop-shell"
ROUTE_FILE="$ROUTE_DIR/notification-route.json"
CUE_FILE="$TEST_RUNTIME_DIR/rustdesk-notification-cue"
MAKOCTL_LOG="$TEST_RUNTIME_DIR/makoctl.log"
MAKO_MODE_STATE="$TEST_RUNTIME_DIR/mako-modes"
MV_LOG="$TEST_RUNTIME_DIR/mv.log"
ADAPTER_STDOUT="$TEST_RUNTIME_DIR/adapter.stdout"
ADAPTER_STDERR="$TEST_RUNTIME_DIR/adapter.stderr"
FAKE_NOW=1786930000
FAKE_ITERATION_COMPLETION_LOG="$TEST_RUNTIME_DIR/iteration-completions.log"
FAKE_MAKO_PID=""
FAKE_MAKO_START_TIME=""
OWNED_CHILDREN=()
adapter_pid=""

mkdir -p -- "$TEST_BIN" "$ROUTE_DIR"
chmod 0700 -- "$ROUTE_DIR"
: >"$MAKOCTL_LOG"
: >"$MV_LOG"
: >"$FAKE_ITERATION_COMPLETION_LOG"
printf '%s\n' 'unrelated-mode rustdesk-route-DVI-D-1 rustdesk-route-HDMI-A-1 rustdesk-route-DP-2 rustdesk-route-hidden rustdesk-cue' \
  >"$MAKO_MODE_STATE"

cat >"$TEST_BIN/makoctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${1:-} == mode ]] || {
  printf 'unexpected makoctl command: %s\n' "$*" >&2
  exit 125
}
shift
mode_arguments=("$@")

state=$(<"${MAKO_MODE_STATE:?}")
while (($# > 0)); do
  case $1 in
    -r|-a)
      [[ $# -ge 2 ]] || exit 125
      mode=$2
      read -r -a modes <<<"$state"
      next=()
      for existing in "${modes[@]}"; do
        [[ $existing == "$mode" && $1 == -r ]] && continue
        next+=("$existing")
      done
      state="${next[*]}"
      [[ $1 == -a ]] || {
        shift 2
        continue
      }
      read -r -a modes <<<"$state"
      present=false
      for existing in "${modes[@]}"; do
        [[ $existing == "$mode" ]] && present=true
      done
      [[ $present == true ]] || state="$state $mode"
      ;;
    *)
      printf 'unexpected makoctl mode argument: %s\n' "$1" >&2
      exit 125
      ;;
  esac
  shift 2
done

printf '%s\n' "$state" >"${MAKO_MODE_STATE:?}"
printf 'mode' >>"${MAKOCTL_LOG:?}"
for argument in "${mode_arguments[@]}"; do
  printf '|%s' "$argument" >>"${MAKOCTL_LOG:?}"
done
printf '\n' >>"${MAKOCTL_LOG:?}"
EOF

cat >"$TEST_BIN/fake-mako" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

: >"${FAKE_MAKO_READY_FILE:?}"
exec /usr/bin/sleep 2147483647
EOF

cat >"$TEST_BIN/date" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${1:-} == +%s ]] || exit 125
printf '%s\n' "${FAKE_NOW:?}"
EOF

cat >"$TEST_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

/usr/bin/sleep "${1:-0.01}"
printf '%s\n' "${BASHPID:?}" >>"${FAKE_ITERATION_COMPLETION_LOG:?}"
EOF

cat >"$TEST_BIN/mv" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"${MV_LOG:?}"
exec /usr/bin/mv "$@"
EOF

for forbidden_command in systemctl pkill killall mako swayosd-server; do
  cat >"$TEST_BIN/$forbidden_command" <<EOF
#!/usr/bin/env bash
printf 'forbidden command invoked: %s %s\n' '$forbidden_command' "\$*" >&2
exit 125
EOF
done

chmod 0700 -- "$TEST_BIN"/*
export XDG_RUNTIME_DIR="$TEST_RUNTIME_DIR"
export PATH="$TEST_BIN:/usr/bin:/bin"
FAKE_MAKO_READY_FILE="$TEST_RUNTIME_DIR/fake-mako.ready"
export MAKOCTL_LOG MAKO_MODE_STATE MV_LOG FAKE_NOW FAKE_ITERATION_COMPLETION_LOG FAKE_MAKO_READY_FILE POLL_INTERVAL=0.01
export ROUTE_FILE CUE_FILE
trap cleanup EXIT

assert_setup_failure_cleanup

"$TEST_BIN/fake-mako" &
FAKE_MAKO_PID=$!
register_owned_child "$FAKE_MAKO_PID" ""
wait_for_file "$FAKE_MAKO_READY_FILE"
FAKE_MAKO_START_TIME=$(process_start_time "$FAKE_MAKO_PID") || fail 'fake Mako start identity is unavailable'
update_owned_child_start_time "$FAKE_MAKO_PID" "$FAKE_MAKO_START_TIME"
assert_process_identity "$FAKE_MAKO_PID" "$FAKE_MAKO_START_TIME" 'fake Mako startup'
export FAKE_MAKO_PID FAKE_MAKO_START_TIME

bash "$ADAPTER" >"$ADAPTER_STDOUT" 2>"$ADAPTER_STDERR" &
adapter_pid=$!

wait_for_log_count 1
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden'
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 null null "$FAKE_NOW"
wait_for_log_count 2
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-DVI-D-1'
assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1'
assert_no_cue

write_route true DVI-D-1 null null "$FAKE_NOW"
iteration_completions_after_write=$(iteration_completion_count)
assert_no_new_mako_call_after_iterations 2 "$((iteration_completions_after_write + 2))"

write_route true DVI-D-1 HDMI-A-1 left "$FAKE_NOW"
wait_for_log_count 3
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-DVI-D-1|-a|rustdesk-cue'
assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1 rustdesk-cue'
assert_cue 'HDMI-A-1|left'
assert_atomic_cue_rename

write_route false null DP-2 null "$FAKE_NOW"
wait_for_log_count 4
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden|-a|rustdesk-cue'
assert_route_modes 'unrelated-mode rustdesk-route-hidden rustdesk-cue'
assert_cue 'DP-2|none'

rm -f -- "$ROUTE_FILE"
wait_for_log_count 5
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden'
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

expect_hidden_for_raw_route '{' 7
expect_hidden_for_raw_route '{"version":2,"visible":true,"output":"DVI-D-1","updatedAt":1786930000}' 9
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":"DVI-D-1;touch","updatedAt":1786930000}' 11
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":"DVI-D-1","updatedAt":1786930001}' 13
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":"DVI-D-1","updatedAt":1786929954}' 15
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":"DVI-D-1","cueOutput":"HDMI-A-1","direction":"sideways","updatedAt":1786930000}' 17
expect_hidden_for_raw_route '{"version":1,"visible":true,"output":null,"updatedAt":1786930000}' 19

write_route true DVI-D-1 HDMI-A-1 left "$FAKE_NOW"
wait_for_log_count 20
assert_cue 'HDMI-A-1|left'
assert_file_mode 0600 "$CUE_FILE"

cleanup_adapter
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden'
assert_process_identity "$FAKE_MAKO_PID" "$FAKE_MAKO_START_TIME" 'fake Mako survived adapter cleanup'

printf 'PASS: fail-closed Mako route adapter contract\n'
