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

wait_for_file() {
  local path=$1

  for _ in {1..100}; do
    [[ -e $path ]] && return 0
    sleep 0.01
  done
  fail "timed out waiting for fixture file: $path"
}

osd_runtime_readlink_executable() {
  [[ $READLINK_MODE == fail ]] && return 1
  readlink -f -- "$1"
}

register_fixture() {
  local identity=$1
  local pid start_time parent_pid

  IFS=$'\t' read -r pid start_time parent_pid <<<"$identity"
  FIXTURE_PIDS+=("$pid")
  FIXTURE_START_TIMES+=("$start_time")
  FIXTURE_PARENTS+=("$parent_pid")
}

cleanup() {
  local index pid

  trap - EXIT
  for index in "${!FIXTURE_PIDS[@]}"; do
    pid=${FIXTURE_PIDS[index]}
    osd_runtime_cleanup_child \
      "$pid" "${FIXTURE_START_TIMES[index]}" "${FIXTURE_PARENTS[index]}" \
      >/dev/null 2>&1 || true
  done
  rm -rf -- "$TMP_DIR"
}

harness_pid=$BASHPID
sleep_executable=$(osd_runtime_resolve_executable sleep) || fail 'sleep executable lookup failed'
unexpected_executable=$(osd_runtime_resolve_executable bash) || fail 'bash executable lookup failed'

mkdir -p -- "$TMP_DIR/no-bin"
READLINK_MODE=fail
assert_status_failure 'expected executable lookup failure' osd_runtime_resolve_executable sleep
READLINK_MODE=normal
PATH="$TMP_DIR/no-bin" assert_status_failure 'missing quickshell lookup' osd_runtime_resolve_executable quickshell

sleep 30 &
readlink_failure_pid=$!
READLINK_MODE=fail
readlink_failure_identity=$(osd_runtime_capture_pending_identity "$readlink_failure_pid" "$harness_pid") || \
  fail 'pending identity depended on executable lookup'
register_fixture "$readlink_failure_identity"
IFS=$'\t' read -r captured_pid captured_start captured_parent <<<"$readlink_failure_identity"
[[ $captured_pid == "$readlink_failure_pid" ]] || fail 'pending identity did not preserve the direct-child PID'
[[ $captured_parent == "$harness_pid" ]] || fail 'pending identity did not preserve the direct parent'
osd_runtime_cleanup_pending_identity "$readlink_failure_identity" || \
  fail 'readlink-failure child cleanup failed'
assert_reaped "$readlink_failure_pid" 'readlink-failure child leaked after cleanup'
READLINK_MODE=normal

sleep 0.2 &
setup_failure_pid=$!
READLINK_MODE=fail
setup_failure_identity=$(osd_runtime_capture_pending_identity "$setup_failure_pid" "$harness_pid") || \
  fail 'setup-failure pending identity capture failed'
register_fixture "$setup_failure_identity"
osd_runtime_cleanup_pending_identity "$setup_failure_identity" || \
  fail 'setup-failure cleanup did not reap an exited child'
assert_reaped "$setup_failure_pid" 'setup-failure child leaked after capture'
READLINK_MODE=normal

preexec_ready="$TMP_DIR/preexec.ready"
preexec_release="$TMP_DIR/preexec.release"
preexec_script="$TMP_DIR/preexec-quickshell"
printf '%s\n' '#!/usr/bin/env bash' \
  "printf ready >$(printf '%q' "$preexec_ready")" \
  "while [[ ! -e $(printf '%q' "$preexec_release") ]]; do sleep 0.01; done" \
  "exec $(printf '%q' "$sleep_executable") 30" >"$preexec_script"
chmod 700 -- "$preexec_script"
"$preexec_script" &
preexec_pid=$!
wait_for_file "$preexec_ready"
pending_identity=$(osd_runtime_capture_pending_identity "$preexec_pid" "$harness_pid") || \
  fail 'pre-exec pending identity capture failed'
register_fixture "$pending_identity"
IFS=$'\t' read -r pending_pid pending_start pending_parent <<<"$pending_identity"
[[ $pending_pid == "$preexec_pid" ]] || fail 'pre-exec pending PID was not recorded from the direct child'
[[ $pending_parent == "$harness_pid" ]] || fail 'pre-exec pending parent was not the harness'
pending_executable=$(osd_runtime_process_executable "$preexec_pid") || fail 'pre-exec executable lookup failed'
[[ $pending_executable != "$sleep_executable" ]] || fail 'pre-exec fixture reached target before release'
touch -- "$preexec_release"
promoted_identity=$(osd_runtime_promote_child_identity "$pending_identity" "$sleep_executable") || \
  fail 'pre-exec child was not promoted after the release barrier'
IFS=$'\t' read -r promoted_pid promoted_start promoted_executable promoted_parent <<<"$promoted_identity"
[[ $promoted_pid == "$preexec_pid" ]] || fail 'promotion changed the child PID'
[[ $promoted_start == "$pending_start" ]] || fail 'pre-exec promotion changed start identity'
[[ $promoted_executable == "$sleep_executable" ]] || fail 'pre-exec promotion accepted the wrong executable'
[[ $promoted_parent == "$harness_pid" ]] || fail 'pre-exec promotion accepted the wrong parent'
osd_runtime_cleanup_child "$promoted_pid" "$promoted_start" "$promoted_parent" || \
  fail 'pre-exec child cleanup failed'
assert_reaped "$preexec_pid" 'pre-exec child leaked after successful reap'

sleep 30 &
mismatch_pid=$!
mismatch_identity=$(osd_runtime_capture_pending_identity "$mismatch_pid" "$harness_pid") || \
  fail 'mismatch fixture identity capture failed'
register_fixture "$mismatch_identity"
IFS=$'\t' read -r mismatch_pid captured_start mismatch_parent <<<"$mismatch_identity"
wrong_start=$((captured_start + 1))
osd_runtime_cleanup_child "$mismatch_pid" "$wrong_start" "$mismatch_parent"
assert_alive "$mismatch_pid" 'start-time mismatch signalled the fixture child'
osd_runtime_cleanup_child "$mismatch_pid" "$captured_start" "$((harness_pid + 1))"
assert_alive "$mismatch_pid" 'parent mismatch signalled the fixture child'
assert_status_failure 'unexpected executable was promoted' \
  osd_runtime_promote_child_identity "$mismatch_identity" "$unexpected_executable"
READLINK_MODE=fail
osd_runtime_cleanup_child "$mismatch_pid" "$captured_start" "$mismatch_parent" || \
  fail 'stable identity cleanup failed with unreadable executable'
assert_reaped "$mismatch_pid" 'stable identity cleanup did not reap the fixture child'
READLINK_MODE=normal

printf 'PASS: OSD runtime process identity fixtures\n'
