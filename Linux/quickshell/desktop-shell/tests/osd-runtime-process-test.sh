#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PROCESS_HELPER="$ROOT/Linux/quickshell/desktop-shell/tests/osd-runtime-process.sh"

# shellcheck source=osd-runtime-process.sh
# shellcheck disable=SC1091
source "$PROCESS_HELPER"

TMP_DIR=$(mktemp -d)
FIXTURE_PIDS=()
FIXTURE_START_TIMES=()
FIXTURE_EXECUTABLES=()
FIXTURE_PARENTS=()
READLINK_MODE=normal

trap 'cleanup' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_status_failure() {
  local description=$1
  shift
  if "$@"; then
    fail "$description unexpectedly succeeded"
  fi
}

assert_alive() {
  local pid=$1
  local description=$2
  kill -0 "$pid" 2>/dev/null || fail "$description"
}

assert_reaped() {
  local pid=$1
  local description=$2
  [[ ! -e "/proc/$pid/stat" ]] || fail "$description"
}

osd_runtime_readlink_executable() {
  [[ $READLINK_MODE == fail ]] && return 1
  readlink -f -- "$1"
}

register_fixture() {
  local pid=$1
  local identity=$2
  local start_time executable parent_pid

  IFS=$'\t' read -r start_time executable parent_pid <<<"$identity"
  FIXTURE_PIDS+=("$pid")
  FIXTURE_START_TIMES+=("$start_time")
  FIXTURE_EXECUTABLES+=("$executable")
  FIXTURE_PARENTS+=("$parent_pid")
}

cleanup() {
  local index pid

  trap - EXIT
  for index in "${!FIXTURE_PIDS[@]}"; do
    pid=${FIXTURE_PIDS[index]}
    osd_runtime_cleanup_child \
      "$pid" "${FIXTURE_START_TIMES[index]}" "${FIXTURE_EXECUTABLES[index]}" "${FIXTURE_PARENTS[index]}" \
      >/dev/null 2>&1 || true
  done
  rm -rf -- "$TMP_DIR"
}

harness_pid=$BASHPID
sleep_executable=$(osd_runtime_resolve_executable sleep) || fail 'sleep executable lookup failed'

mkdir -p -- "$TMP_DIR/no-bin"
READLINK_MODE=fail
assert_status_failure 'expected executable lookup failure' osd_runtime_resolve_executable sleep
READLINK_MODE=normal
PATH="$TMP_DIR/no-bin" assert_status_failure 'missing quickshell lookup' osd_runtime_resolve_executable quickshell

sleep 30 &
lookup_failure_pid=$!
READLINK_MODE=fail
lookup_failure_started=$SECONDS
assert_status_failure 'pending identity lookup failure' osd_runtime_capture_pending_identity "$lookup_failure_pid" "$harness_pid"
((SECONDS - lookup_failure_started <= 3)) || fail 'pending identity lookup failure exceeded its bounded wait'
READLINK_MODE=normal
lookup_failure_identity=$(osd_runtime_capture_pending_identity "$lookup_failure_pid" "$harness_pid") || \
  fail 'pending identity could not be recovered after lookup failure'
register_fixture "$lookup_failure_pid" "$lookup_failure_identity"
osd_runtime_cleanup_pending_identity "$lookup_failure_pid" "$harness_pid" "$sleep_executable" || \
  fail 'lookup-failure child cleanup failed'
assert_reaped "$lookup_failure_pid" 'lookup-failure child leaked after cleanup'
unset 'FIXTURE_PIDS[-1]' 'FIXTURE_START_TIMES[-1]' 'FIXTURE_EXECUTABLES[-1]' 'FIXTURE_PARENTS[-1]'

true &
setup_failure_pid=$!
READLINK_MODE=fail
setup_failure_started=$SECONDS
assert_status_failure 'setup-failure identity lookup' osd_runtime_capture_pending_identity "$setup_failure_pid" "$harness_pid"
((SECONDS - setup_failure_started <= 3)) || fail 'setup-failure identity lookup exceeded its bounded wait'
if ! osd_runtime_cleanup_pending_identity "$setup_failure_pid" "$harness_pid" "$sleep_executable"; then
  fail 'setup-failure cleanup did not reap an exited child after capture failure'
fi
assert_reaped "$setup_failure_pid" 'setup-failure child leaked after capture failure'
READLINK_MODE=normal

preexec_script="$TMP_DIR/preexec-quickshell"
printf '%s\n' '#!/usr/bin/env bash' 'sleep 0.2' >"$preexec_script"
printf 'exec %q 30\n' "$sleep_executable" >>"$preexec_script"
chmod 700 -- "$preexec_script"
"$preexec_script" &
preexec_pid=$!
pending_identity=$(osd_runtime_capture_pending_identity "$preexec_pid" "$harness_pid") || \
  fail 'pre-exec pending identity capture failed'
IFS=$'\t' read -r pending_start pending_executable pending_parent <<<"$pending_identity"
[[ $pending_parent == "$harness_pid" ]] || fail 'pre-exec child was not a direct harness child'
[[ -n $pending_executable ]] || fail 'pre-exec child did not expose a pending executable'
promoted_identity=$(osd_runtime_promote_child_identity \
  "$preexec_pid" "$harness_pid" "$sleep_executable" "$pending_start") || \
  fail 'pre-exec child was not promoted after reaching Quickshell executable'
IFS=$'\t' read -r promoted_start promoted_executable promoted_parent <<<"$promoted_identity"
[[ $promoted_start == "$pending_start" ]] || fail 'pre-exec promotion changed start identity'
[[ $promoted_executable == "$sleep_executable" ]] || fail 'pre-exec promotion accepted the wrong executable'
[[ $promoted_parent == "$harness_pid" ]] || fail 'pre-exec promotion accepted the wrong parent'
register_fixture "$preexec_pid" "$promoted_identity"
osd_runtime_cleanup_child "$preexec_pid" "$promoted_start" "$promoted_executable" "$promoted_parent" || \
  fail 'pre-exec child cleanup failed'
assert_reaped "$preexec_pid" 'pre-exec child leaked after successful reap'
unset 'FIXTURE_PIDS[-1]' 'FIXTURE_START_TIMES[-1]' 'FIXTURE_EXECUTABLES[-1]' 'FIXTURE_PARENTS[-1]'

sleep 30 &
mismatch_pid=$!
mismatch_identity=$(osd_runtime_capture_pending_identity "$mismatch_pid" "$harness_pid") || \
  fail 'mismatch fixture identity capture failed'
IFS=$'\t' read -r mismatch_start mismatch_executable mismatch_parent <<<"$mismatch_identity"
register_fixture "$mismatch_pid" "$mismatch_identity"
wrong_start=$((mismatch_start + 1))
osd_runtime_cleanup_child "$mismatch_pid" "$wrong_start" "$mismatch_executable" "$mismatch_parent"
assert_alive "$mismatch_pid" 'start-time mismatch signalled the fixture child'
osd_runtime_cleanup_child "$mismatch_pid" "$mismatch_start" /usr/bin/false "$mismatch_parent"
assert_alive "$mismatch_pid" 'executable mismatch signalled the fixture child'
osd_runtime_cleanup_child "$mismatch_pid" "$mismatch_start" "$mismatch_executable" "$((harness_pid + 1))"
assert_alive "$mismatch_pid" 'parent mismatch signalled the fixture child'
osd_runtime_cleanup_child "$mismatch_pid" "$mismatch_start" "$mismatch_executable" "$mismatch_parent" || \
  fail 'matching identity cleanup failed'
assert_reaped "$mismatch_pid" 'matching identity cleanup did not reap the fixture child'
unset 'FIXTURE_PIDS[-1]' 'FIXTURE_START_TIMES[-1]' 'FIXTURE_EXECUTABLES[-1]' 'FIXTURE_PARENTS[-1]'

printf 'PASS: OSD runtime process identity fixtures\n'
