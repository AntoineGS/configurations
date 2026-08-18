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

process_executable() {
  local pid=$1

  [[ $pid =~ ^[0-9]+$ ]] || return 1
  if [[ (${PROCESS_EXECUTABLE_FAIL_PID:-} == "$pid" || ${PROCESS_EXECUTABLE_FAIL_PID:-} == '*') && -n ${PROCESS_EXECUTABLE_FAIL_FILE:-} ]]; then
    if [[ -e $PROCESS_EXECUTABLE_FAIL_FILE ]]; then
      rm -f -- "$PROCESS_EXECUTABLE_FAIL_FILE"
      return 1
    fi
  fi
  [[ -L /proc/$pid/exe ]] || return 1
  readlink -f -- "/proc/$pid/exe"
}

process_identity_is_live() {
  local pid=$1
  local expected_start_time=$2
  local expected_executable=$3
  local actual_start_time
  local actual_executable
  local state

  [[ $pid =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  actual_start_time=$(process_start_time "$pid") || return 1
  [[ $actual_start_time == "$expected_start_time" ]] || return 1
  actual_executable=$(process_executable "$pid") || return 1
  [[ $actual_executable == "$expected_executable" ]] || return 1
  state=$(process_state "$pid") || return 1
  case $state in
    R|S|D|I|T|t|W) return 0 ;;
    Z|X|*) return 1 ;;
  esac
}

assert_process_identity() {
  local pid=$1
  local expected_start_time=$2
  local expected_executable=$3
  local message=$4
  local state

  process_identity_is_live "$pid" "$expected_start_time" "$expected_executable" || {
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

await_file() {
  local path=$1
  local deadline=$((SECONDS + 3))

  while ((SECONDS < deadline)); do
    [[ -f $path ]] && return 0
    /usr/bin/sleep 0.01
  done

  return 1
}

wait_for_file() {
  local path=$1

  await_file "$path" || fail "timed out waiting for file: $path"
}

await_process_executable() {
  local pid=$1
  local expected_executable=$2
  local deadline=$((SECONDS + 3))
  local actual_executable

  while ((SECONDS < deadline)); do
    actual_executable=$(process_executable "$pid" 2>/dev/null || true)
    [[ $actual_executable == "$expected_executable" ]] && return 0
    /usr/bin/sleep 0.01
  done

  return 1
}

wait_for_process_executable() {
  local pid=$1
  local expected_executable=$2

  await_process_executable "$pid" "$expected_executable" || fail "timed out waiting for $pid to exec $expected_executable"
}

capture_process_identity() {
  local pid=$1
  local deadline=$((SECONDS + 3))
  local observed_start_time
  local observed_executable

  while ((SECONDS < deadline)); do
    observed_start_time=$(process_start_time "$pid" 2>/dev/null || true)
    observed_executable=$(process_executable "$pid" 2>/dev/null || true)
    if [[ -n $observed_start_time && -n $observed_executable ]]; then
      printf -v "$2" '%s' "$observed_start_time"
      printf -v "$3" '%s' "$observed_executable"
      return 0
    fi
    /usr/bin/sleep 0.01
  done

  return 1
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

write_lease() {
  local refreshed_at=$1
  local expires_at=$2
  local route_updated_at=$3
  local temporary_file

  temporary_file=$(mktemp "$ROUTE_DIR/.test-notification-route-lease.XXXXXX")
  jq -cn \
    --argjson refreshed_at "$refreshed_at" \
    --argjson expires_at "$expires_at" \
    --argjson route_updated_at "$route_updated_at" \
    '{version: 1, refreshedAt: $refreshed_at,
      expiresAt: $expires_at, routeUpdatedAt: $route_updated_at}' >"$temporary_file"
  chmod 0600 -- "$temporary_file"
  mv -f -- "$temporary_file" "$LEASE_FILE"
}

write_raw_lease() {
  local content=$1
  local temporary_file

  temporary_file=$(mktemp "$ROUTE_DIR/.test-notification-route-lease.XXXXXX")
  printf '%s\n' "$content" >"$temporary_file"
  chmod 0600 -- "$temporary_file"
  mv -f -- "$temporary_file" "$LEASE_FILE"
}

run_reconcile_once() (
  # shellcheck disable=SC1091
  # shellcheck source=../../../os/helpers/desktop-shell-mako-route
  source "$ADAPTER"
  reconcile_route
)

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

register_owned_child() {
  local pid=$1
  local start_time=$2
  local executable=$3

  OWNED_CHILDREN+=("$pid:$start_time:$executable")
}

register_pending_owned_child() {
  local pid=$1
  local start_time=$2
  local executable=$3
  local expected_parent_pid=$4

  PENDING_OWNED_CHILDREN+=("$pid:$start_time:$executable:$expected_parent_pid")
}

pending_owned_child_entry() {
  local pid=$1
  local entry
  local entry_pid

  for entry in "${PENDING_OWNED_CHILDREN[@]}"; do
    entry_pid=${entry%%:*}
    [[ $entry_pid == "$pid" ]] && {
      printf '%s\n' "$entry"
      return 0
    }
  done

  return 1
}

promote_pending_owned_child() {
  local pid=$1
  local entry
  local remainder
  local stored_start_time
  local stored_executable
  local stored_parent_pid
  local parent_pid

  entry=$(pending_owned_child_entry "$pid") || return 1
  remainder=${entry#*:}
  stored_start_time=${remainder%%:*}
  remainder=${remainder#*:}
  stored_executable=${remainder%%:*}
  stored_parent_pid=${remainder##*:}
  parent_pid=$(process_parent_pid "$pid") || return 1
  [[ $parent_pid == "$stored_parent_pid" ]] || return 1
  process_identity_is_live "$pid" "$stored_start_time" "$stored_executable" || return 1
  register_owned_child "$pid" "$stored_start_time" "$stored_executable"
  forget_pending_owned_child "$pid"
}

cleanup_spawn_failure() {
  local pid=$1
  local parent_pid
  local current_start_time
  local current_executable

  [[ $pid =~ ^[0-9]+$ ]] || return 0
  parent_pid=$(process_parent_pid "$pid" 2>/dev/null) || {
    wait "$pid" 2>/dev/null || true
    return 0
  }
  [[ $parent_pid == "$$" ]] || return 0
  capture_process_identity "$pid" current_start_time current_executable || return 0
  cleanup_owned_child "$pid" "$current_start_time" "$current_executable"
}

start_fake_mako_process() {
  local process_pid
  local process_start_time
  local process_executable_path

  rm -f -- "$FAKE_MAKO_READY_FILE"
  "$TEST_BIN/fake-mako" &
  process_pid=$!
  await_file "$FAKE_MAKO_READY_FILE" || {
    cleanup_spawn_failure "$process_pid"
    fail 'fake Mako ready file did not appear'
  }
  await_process_executable "$process_pid" "$FAKE_MAKO_EXECUTABLE_PATH" || {
    cleanup_spawn_failure "$process_pid"
    fail 'fake Mako executable did not reach the expected path'
  }
  process_start_time=$(process_start_time "$process_pid") || {
    cleanup_spawn_failure "$process_pid"
    fail 'fake Mako start identity is unavailable'
  }
  process_executable_path=$(process_executable "$process_pid") || {
    cleanup_spawn_failure "$process_pid"
    fail 'fake Mako executable is unavailable'
  }
  printf -v "$1" '%s' "$process_pid"
  printf -v "$2" '%s' "$process_start_time"
  printf -v "$3" '%s' "$process_executable_path"
}

assert_pending_owned_child_registration_preserves_observed_identity() {
  local pid=12345
  local start_time=67890
  local executable=/usr/bin/sleep
  local expected_parent_pid=24680

  PENDING_OWNED_CHILDREN=()
  register_pending_owned_child "$pid" "$start_time" "$executable" "$expected_parent_pid"
  assert_equal "$pid:$start_time:$executable:$expected_parent_pid" "${PENDING_OWNED_CHILDREN[0]-}" \
    'pending child registration stored the originally observed identity'
  PENDING_OWNED_CHILDREN=()
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

forget_pending_owned_child() {
  local pid=$1
  local entry
  local entry_pid
  local retained=()

  for entry in "${PENDING_OWNED_CHILDREN[@]}"; do
    entry_pid=${entry%%:*}
    [[ $entry_pid == "$pid" ]] || retained+=("$entry")
  done
  PENDING_OWNED_CHILDREN=("${retained[@]}")
}

start_owned_fake_mako() {
  local child_pid
  local child_start_time
  local child_executable

  start_fake_mako_process child_pid child_start_time child_executable
  register_pending_owned_child "$child_pid" "$child_start_time" "$child_executable" "$$"
  promote_pending_owned_child "$child_pid" "$child_start_time" "$child_executable" "$$" ||
    fail 'fake Mako pending child promotion failed'
  printf -v "$1" '%s' "$child_pid"
  printf -v "$2" '%s' "$child_start_time"
  printf -v "$3" '%s' "$child_executable"
}

cleanup_child_process() {
  local expected_parent_pid=$1
  local pid=$2
  local expected_start_time=$3
  local expected_executable=$4
  local parent_pid
  local current_start_time
  local current_executable

  [[ $pid =~ ^[0-9]+$ ]] || return 0
  [[ -n $expected_start_time && -n $expected_executable ]] || return 0
  if ! parent_pid=$(process_parent_pid "$pid" 2>/dev/null); then
    wait "$pid" 2>/dev/null || true
    return 0
  fi
  [[ $parent_pid == "$expected_parent_pid" ]] || return 0
  current_start_time=$(process_start_time "$pid" 2>/dev/null) || return 0
  [[ $current_start_time == "$expected_start_time" ]] || return 0
  current_executable=$(process_executable "$pid" 2>/dev/null) || return 0
  [[ $current_executable == "$expected_executable" ]] || return 0

  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup_owned_child() {
  cleanup_child_process "$$" "$1" "$2" "$3"
}

cleanup_owned_children() {
  local entry
  local pid
  local expected_start_time
  local expected_executable

  for entry in "${OWNED_CHILDREN[@]}"; do
    pid=${entry%%:*}
    expected_start_time=${entry#*:}
    expected_start_time=${expected_start_time%%:*}
    expected_executable=${entry#*:*:}
    cleanup_owned_child "$pid" "$expected_start_time" "$expected_executable"
  done
  OWNED_CHILDREN=()
}

cleanup_pending_owned_children() {
  local entry
  local pid
  local remainder
  local start_time
  local executable
  local expected_parent_pid

  for entry in "${PENDING_OWNED_CHILDREN[@]}"; do
    pid=${entry%%:*}
    remainder=${entry#*:}
    start_time=${remainder%%:*}
    remainder=${remainder#*:}
    executable=${remainder%%:*}
    expected_parent_pid=${remainder##*:}
    if ! process_parent_pid "$pid" >/dev/null 2>&1; then
      wait "$pid" 2>/dev/null || true
      continue
    fi
    cleanup_process_tree "$pid" "$start_time" "$executable"
    cleanup_child_process "$expected_parent_pid" "$pid" "$start_time" "$executable"
  done
  PENDING_OWNED_CHILDREN=()
}

start_adapter() {
  local initial_start_time
  local initial_executable

  bash "$ADAPTER" >"$ADAPTER_STDOUT" 2>"$ADAPTER_STDERR" &
  adapter_pid=$!
  initial_start_time=$(process_start_time "$adapter_pid") || {
    cleanup_spawn_failure "$adapter_pid"
    return 1
  }
  initial_executable=$(process_executable "$adapter_pid") || {
    cleanup_spawn_failure "$adapter_pid"
    return 1
  }
  register_pending_owned_child "$adapter_pid" "$initial_start_time" "$initial_executable" "$$"
  promote_pending_owned_child "$adapter_pid" "$initial_start_time" "$initial_executable" "$$" || {
    cleanup_pending_owned_children
    adapter_pid=""
    return 1
  }
  ADAPTER_START_TIME=$initial_start_time
  ADAPTER_EXECUTABLE=$initial_executable
}

cleanup_process_tree() {
  local parent_pid=$1
  local expected_parent_start_time=$2
  local expected_parent_executable=$3
  local child
  local child_start_time
  local child_executable
  local children=()

  [[ -n $expected_parent_start_time && -n $expected_parent_executable ]] || return 0
  process_identity_is_live "$parent_pid" "$expected_parent_start_time" "$expected_parent_executable" || return 0

  mapfile -t children < <(pgrep -P "$parent_pid" 2>/dev/null || true)
  for child in "${children[@]}"; do
    child_start_time=$(process_start_time "$child" 2>/dev/null) || continue
    child_executable=$(process_executable "$child" 2>/dev/null) || continue
    cleanup_process_tree "$child" "$child_start_time" "$child_executable"
    cleanup_child_process "$parent_pid" "$child" "$child_start_time" "$child_executable"
  done
}

cleanup_adapter() {
  local status=0

  if [[ -n ${adapter_pid:-} ]] && kill -0 "$adapter_pid" 2>/dev/null; then
    cleanup_process_tree "$adapter_pid" "$ADAPTER_START_TIME" "$ADAPTER_EXECUTABLE"
    cleanup_owned_child "$adapter_pid" "$ADAPTER_START_TIME" "$ADAPTER_EXECUTABLE"
    wait "$adapter_pid" || status=$?
    [[ $status -ne 0 ]] || true
  fi
  adapter_pid=""
}

cleanup() {
  cleanup_adapter
  cleanup_pending_owned_children
  cleanup_owned_children
  rm -rf -- "$TEST_RUNTIME_DIR"
}

assert_setup_failure_cleanup() {
  local setup_failure_pid
  local setup_failure_start_time
  local setup_failure_executable

  start_owned_fake_mako setup_failure_pid setup_failure_start_time setup_failure_executable
  cleanup_owned_child "$setup_failure_pid" "$setup_failure_start_time" "$setup_failure_executable"
  forget_owned_child "$setup_failure_pid"
  [[ ! -e /proc/$setup_failure_pid/status ]] || \
    fail 'setup-failure cleanup did not reap the owned fake Mako child'
}

assert_pending_owned_child_cleanup_reaps_started_child() {
  local pid
  local start_time
  local executable

  start_fake_mako_process pid start_time executable
  register_pending_owned_child "$pid" "$start_time" "$executable" "$$"
  assert_process_identity "$pid" "$start_time" "$executable" 'pending child started'
  cleanup_pending_owned_children
  [[ ! -e /proc/$pid/status ]] || fail 'pending child cleanup did not reap the owned fake Mako child'
}

assert_pending_cleanup_revalidates_stored_identity() {
  local pid
  local start_time
  local executable

  start_fake_mako_process pid start_time executable

  PENDING_OWNED_CHILDREN=()
  register_pending_owned_child "$pid" "$start_time" '/usr/bin/false' "$$"
  cleanup_pending_owned_children
  assert_process_identity "$pid" "$start_time" "$executable" 'pending cleanup must skip mismatched stored identity'

  cleanup_owned_child "$pid" "$start_time" "$executable"
}

assert_pending_cleanup_revalidates_stored_parent() {
  local pid
  local start_time
  local executable

  start_fake_mako_process pid start_time executable

  PENDING_OWNED_CHILDREN=()
  register_pending_owned_child "$pid" "$start_time" "$executable" 999999
  cleanup_pending_owned_children
  assert_process_identity "$pid" "$start_time" "$executable" 'pending cleanup must skip mismatched stored parent'

  cleanup_owned_child "$pid" "$start_time" "$executable"
}

assert_pending_promotion_reuses_stored_identity() {
  local pid
  local start_time
  local executable

  start_fake_mako_process pid start_time executable

  OWNED_CHILDREN=()
  PENDING_OWNED_CHILDREN=()
  register_pending_owned_child "$pid" "$start_time" '/usr/bin/false' "$$"
  promote_pending_owned_child "$pid" "$start_time" "$executable" "$$" &&
    fail 'pending promotion accepted a caller-supplied identity instead of the stored pending identity'
  [[ ${#OWNED_CHILDREN[@]} -eq 0 ]] || fail 'pending promotion incorrectly registered an owned child'
  assert_process_identity "$pid" "$start_time" "$executable" 'pending promotion must leave mismatched stored identity alive'

  PENDING_OWNED_CHILDREN=()
  cleanup_owned_child "$pid" "$start_time" "$executable"

  start_fake_mako_process pid start_time executable

  OWNED_CHILDREN=()
  PENDING_OWNED_CHILDREN=()
  register_pending_owned_child "$pid" "$start_time" "$executable" "$$"
  promote_pending_owned_child "$pid" 999999 '/usr/bin/false' "$$" ||
    fail 'pending promotion rejected the stored pending identity in favor of caller-supplied identity'
  assert_equal "$pid:$start_time:$executable" "${OWNED_CHILDREN[0]-}" \
    'pending promotion registered the stored pending identity'

  forget_owned_child "$pid"
  cleanup_owned_child "$pid" "$start_time" "$executable"
}

assert_adapter_startup_cleans_up_initial_identity_failure() {
  local failed_pid

  PROCESS_EXECUTABLE_FAIL_PID="*"
  PROCESS_EXECUTABLE_FAIL_FILE="$TEST_RUNTIME_DIR/process-executable-initial-fail"
  : >"$PROCESS_EXECUTABLE_FAIL_FILE"
  export PROCESS_EXECUTABLE_FAIL_PID PROCESS_EXECUTABLE_FAIL_FILE
  start_adapter && fail 'adapter startup unexpectedly succeeded during initial identity lookup failure'
  failed_pid=$adapter_pid
  PROCESS_EXECUTABLE_FAIL_PID=""
  PROCESS_EXECUTABLE_FAIL_FILE=""
  export PROCESS_EXECUTABLE_FAIL_PID PROCESS_EXECUTABLE_FAIL_FILE
  [[ -n $failed_pid ]] || fail 'initial adapter identity failure did not expose the failed pid'
  [[ ! -e /proc/$failed_pid/status ]] || fail 'initial adapter identity failure left the adapter running'
  adapter_pid=""
}

assert_adapter_pending_registration_cleans_up_on_identity_lookup_failure() {
  local failed_pid
  local initial_start_time
  local initial_executable

  PROCESS_EXECUTABLE_FAIL_PID=""
  PROCESS_EXECUTABLE_FAIL_FILE=""
  export PROCESS_EXECUTABLE_FAIL_PID PROCESS_EXECUTABLE_FAIL_FILE
  bash "$ADAPTER" >"$ADAPTER_STDOUT" 2>"$ADAPTER_STDERR" &
  adapter_pid=$!
  initial_start_time=$(process_start_time "$adapter_pid") || {
    cleanup_spawn_failure "$adapter_pid"
    fail 'adapter initial start identity is unavailable'
  }
  initial_executable=$(process_executable "$adapter_pid") || {
    cleanup_spawn_failure "$adapter_pid"
    fail 'adapter initial executable is unavailable'
  }
  register_pending_owned_child "$adapter_pid" "$initial_start_time" "$initial_executable" "$$"
  PROCESS_EXECUTABLE_FAIL_PID=$adapter_pid
  PROCESS_EXECUTABLE_FAIL_FILE="$TEST_RUNTIME_DIR/process-executable-fail"
  : >"$PROCESS_EXECUTABLE_FAIL_FILE"
  export PROCESS_EXECUTABLE_FAIL_PID PROCESS_EXECUTABLE_FAIL_FILE
  promote_pending_owned_child "$adapter_pid" "$initial_start_time" "$initial_executable" "$$" &&
    fail 'adapter identity promotion unexpectedly succeeded during injected lookup failure'
  failed_pid=$adapter_pid
  cleanup_pending_owned_children
  wait "$failed_pid" 2>/dev/null || true
  PROCESS_EXECUTABLE_FAIL_PID=""
  PROCESS_EXECUTABLE_FAIL_FILE=""
  export PROCESS_EXECUTABLE_FAIL_PID PROCESS_EXECUTABLE_FAIL_FILE
  adapter_pid=""
  [[ ! -e /proc/$failed_pid/status ]] || fail 'failed adapter startup cleanup did not reap the pending adapter process'
  [[ ! -n ${adapter_pid:-} ]] || fail 'failed adapter startup left an untracked adapter process behind'
}

assert_adapter_pending_cleanup_reaps_descendants_on_promotion_failure() {
  local failed_pid
  local initial_start_time
  local initial_executable
  local descendant_pid
  local descendant_start_time

  rm -f -- "$ADAPTER_DESCENDANT_PID_FILE"
  export SPAWN_ADAPTER_DESCENDANT_PID_FILE="$ADAPTER_DESCENDANT_PID_FILE"
  bash "$ADAPTER" >"$ADAPTER_STDOUT" 2>"$ADAPTER_STDERR" &
  adapter_pid=$!
  initial_start_time=$(process_start_time "$adapter_pid") || {
    cleanup_spawn_failure "$adapter_pid"
    fail 'descendant adapter initial start identity is unavailable'
  }
  initial_executable=$(process_executable "$adapter_pid") || {
    cleanup_spawn_failure "$adapter_pid"
    fail 'descendant adapter initial executable is unavailable'
  }
  register_pending_owned_child "$adapter_pid" "$initial_start_time" "$initial_executable" "$$"
  wait_for_file "$ADAPTER_DESCENDANT_PID_FILE"
  descendant_pid=$(<"$ADAPTER_DESCENDANT_PID_FILE")
  descendant_start_time=$(process_start_time "$descendant_pid") || fail 'adapter descendant start identity is unavailable'
  assert_process_identity "$descendant_pid" "$descendant_start_time" '/usr/bin/sleep' 'adapter descendant startup'

  PROCESS_EXECUTABLE_FAIL_PID=$adapter_pid
  PROCESS_EXECUTABLE_FAIL_FILE="$TEST_RUNTIME_DIR/process-executable-fail"
  : >"$PROCESS_EXECUTABLE_FAIL_FILE"
  export PROCESS_EXECUTABLE_FAIL_PID PROCESS_EXECUTABLE_FAIL_FILE
  promote_pending_owned_child "$adapter_pid" "$initial_start_time" "$initial_executable" "$$" &&
    fail 'adapter descendant promotion unexpectedly succeeded during injected lookup failure'
  failed_pid=$adapter_pid
  cleanup_pending_owned_children
  wait "$failed_pid" 2>/dev/null || true
  PROCESS_EXECUTABLE_FAIL_PID=""
  PROCESS_EXECUTABLE_FAIL_FILE=""
  SPAWN_ADAPTER_DESCENDANT_PID_FILE=""
  export PROCESS_EXECUTABLE_FAIL_PID PROCESS_EXECUTABLE_FAIL_FILE SPAWN_ADAPTER_DESCENDANT_PID_FILE
  adapter_pid=""
  [[ ! -e /proc/$failed_pid/status ]] || fail 'failed adapter descendant cleanup left the adapter running'
  [[ ! -e /proc/$descendant_pid/status ]] || fail 'failed adapter cleanup left its descendant running'
}

assert_incomplete_identity_cleanup_skips_child() {
  local pid
  local start_time
  local executable

  start_owned_fake_mako pid start_time executable

  cleanup_owned_child "$pid" '' "$executable"
  assert_process_identity "$pid" "$start_time" "$executable" 'empty start time must skip cleanup'

  cleanup_owned_child "$pid" "$start_time" ''
  assert_process_identity "$pid" "$start_time" "$executable" 'empty executable must skip cleanup'

  forget_owned_child "$pid"
  cleanup_owned_child "$pid" "$start_time" "$executable"
}

assert_mismatched_identity_cleanup_skips_child() {
  local mismatched_pid
  local mismatched_start_time
  local fake_mako_executable

  start_owned_fake_mako mismatched_pid mismatched_start_time fake_mako_executable
  forget_owned_child "$mismatched_pid"
  register_owned_child "$mismatched_pid" "$mismatched_start_time" '/usr/bin/false'
  cleanup_owned_child "$mismatched_pid" "$mismatched_start_time" '/usr/bin/false'
  assert_process_identity "$mismatched_pid" "$mismatched_start_time" "$fake_mako_executable" 'mismatched child survived cleanup'
  forget_owned_child "$mismatched_pid"
  cleanup_owned_child "$mismatched_pid" "$mismatched_start_time" "$fake_mako_executable"
}

assert_descendant_cleanup_revalidates_identity() {
  local parent_pid
  local parent_start_time
  local parent_executable
  local child_pid
  local child_start_time
  local child_executable
  local children=()

  rm -f -- "$FAKE_MAKO_READY_FILE"
  bash -c 'child=""; trap '\''[[ -n $child ]] && kill -TERM "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 0'\'' TERM; "$1" & child=$!; wait "$child"' _ "$TEST_BIN/fake-mako" &
  parent_pid=$!
  await_file "$FAKE_MAKO_READY_FILE" || {
    cleanup_spawn_failure "$parent_pid"
    fail 'descendant fake Mako ready file did not appear'
  }
  await_process_executable "$parent_pid" '/usr/bin/bash' || {
    cleanup_spawn_failure "$parent_pid"
    fail 'descendant parent executable did not reach /usr/bin/bash'
  }
  parent_start_time=$(process_start_time "$parent_pid") || {
    cleanup_spawn_failure "$parent_pid"
    fail 'descendant parent start identity is unavailable'
  }
  parent_executable=$(process_executable "$parent_pid") || {
    cleanup_spawn_failure "$parent_pid"
    fail 'descendant parent executable is unavailable'
  }
  register_pending_owned_child "$parent_pid" "$parent_start_time" "$parent_executable" "$$"
  mapfile -t children < <(pgrep -P "$parent_pid" 2>/dev/null || true)
  [[ ${#children[@]} -eq 1 ]] || fail 'descendant child pid is unavailable'
  child_pid=${children[0]}
  wait_for_process_executable "$child_pid" "$FAKE_MAKO_EXECUTABLE_PATH"
  child_start_time=$(process_start_time "$child_pid") || fail 'descendant child start identity is unavailable'
  child_executable=$(process_executable "$child_pid") || fail 'descendant child executable is unavailable'

  cleanup_child_process "$parent_pid" "$child_pid" "$child_start_time" '/usr/bin/false'
  assert_process_identity "$child_pid" "$child_start_time" "$child_executable" 'mismatched descendant survived cleanup'

  cleanup_child_process "$parent_pid" "$child_pid" "$child_start_time" "$child_executable"
  forget_pending_owned_child "$parent_pid"
  wait "$parent_pid" 2>/dev/null || true
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
LEASE_FILE="$ROUTE_DIR/notification-route-lease.json"
CUE_FILE="$TEST_RUNTIME_DIR/rustdesk-notification-cue"
MAKOCTL_LOG="$TEST_RUNTIME_DIR/makoctl.log"
MAKO_MODE_STATE="$TEST_RUNTIME_DIR/mako-modes"
MV_LOG="$TEST_RUNTIME_DIR/mv.log"
ADAPTER_STDOUT="$TEST_RUNTIME_DIR/adapter.stdout"
ADAPTER_STDERR="$TEST_RUNTIME_DIR/adapter.stderr"
FAKE_NOW=1786930000
FAKE_MAKO_EXECUTABLE_PATH="/usr/bin/sleep"
FAKE_ITERATION_COMPLETION_LOG="$TEST_RUNTIME_DIR/iteration-completions.log"
FAKE_MAKO_PID=""
FAKE_MAKO_START_TIME=""
FAKE_MAKO_EXECUTABLE=""
OWNED_CHILDREN=()
PENDING_OWNED_CHILDREN=()
adapter_pid=""
ADAPTER_START_TIME=""
ADAPTER_EXECUTABLE=""

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

cat >"$TEST_BIN/stat" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${1:-} == -c ]] || exec /usr/bin/stat "$@"
format=${2:-}
path=${4:-${3:-}}

case "$format|$path" in
  '%u %a|'"${ROUTE_DIR:?}")
    [[ -n ${STAT_ROUTE_DIR_OWNER_MODE_OVERRIDE:-} ]] && {
      printf '%s\n' "$STAT_ROUTE_DIR_OWNER_MODE_OVERRIDE"
      exit 0
    }
    ;;
  '%u %a|'"${ROUTE_FILE:?}")
    [[ -n ${STAT_ROUTE_FILE_OWNER_MODE_OVERRIDE:-} ]] && {
      printf '%s\n' "$STAT_ROUTE_FILE_OWNER_MODE_OVERRIDE"
      exit 0
    }
    ;;
  '%u %a|'"${LEASE_FILE:?}")
    [[ -n ${STAT_LEASE_FILE_OWNER_MODE_OVERRIDE:-} ]] && {
      printf '%s\n' "$STAT_LEASE_FILE_OWNER_MODE_OVERRIDE"
      exit 0
    }
    ;;
esac

exec /usr/bin/stat "$@"
EOF

cat >"$TEST_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -n ${SPAWN_ADAPTER_DESCENDANT_PID_FILE:-} && ! -e $SPAWN_ADAPTER_DESCENDANT_PID_FILE ]]; then
  trap 'exit 143' TERM
  /usr/bin/sleep 2147483647 &
  descendant_pid=$!
  printf '%s\n' "$descendant_pid" >"$SPAWN_ADAPTER_DESCENDANT_PID_FILE"
  /usr/bin/sleep "${1:-0.01}"
  wait "$descendant_pid"
  exit 0
fi

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
ADAPTER_DESCENDANT_PID_FILE="$TEST_RUNTIME_DIR/adapter-descendant.pid"
export MAKOCTL_LOG MAKO_MODE_STATE MV_LOG FAKE_NOW FAKE_ITERATION_COMPLETION_LOG FAKE_MAKO_READY_FILE POLL_INTERVAL=0.01
export ROUTE_DIR ROUTE_FILE LEASE_FILE CUE_FILE ADAPTER_DESCENDANT_PID_FILE
trap cleanup EXIT

assert_pending_owned_child_registration_preserves_observed_identity
assert_setup_failure_cleanup
assert_pending_owned_child_cleanup_reaps_started_child
assert_pending_cleanup_revalidates_stored_identity
assert_pending_cleanup_revalidates_stored_parent
assert_pending_promotion_reuses_stored_identity
assert_incomplete_identity_cleanup_skips_child
assert_mismatched_identity_cleanup_skips_child
assert_descendant_cleanup_revalidates_identity
assert_adapter_startup_cleans_up_initial_identity_failure
assert_adapter_pending_registration_cleans_up_on_identity_lookup_failure
assert_adapter_pending_cleanup_reaps_descendants_on_promotion_failure

rm -f -- "$ROUTE_FILE" "$LEASE_FILE"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 null null "$FAKE_NOW"
rm -f -- "$LEASE_FILE"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1'
assert_no_cue

write_route true DVI-D-1 HDMI-A-1 left "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1 rustdesk-cue'
assert_cue 'HDMI-A-1|left'

write_route false null DP-2 left "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden rustdesk-cue'
assert_cue 'DP-2|left'

write_route true DVI-D-1 null null "$FAKE_NOW"
write_lease "$FAKE_NOW" "$FAKE_NOW" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 null null "$((FAKE_NOW - 45))"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$((FAKE_NOW - 45))"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1'
assert_no_cue

write_raw_route '{'
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 null null "$FAKE_NOW"
write_raw_lease '{'
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 null null "$FAKE_NOW"
write_lease "$((FAKE_NOW - 3))" "$((FAKE_NOW - 1))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'

write_route true DVI-D-1 null null "$FAKE_NOW"
write_lease "$((FAKE_NOW + 1))" "$((FAKE_NOW + 3))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'

write_route true DVI-D-1 null null "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 3))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'

write_route true DVI-D-1 null null "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$((FAKE_NOW - 1))"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'

write_raw_route '{"version":2,"visible":true,"output":"DVI-D-1","cueOutput":null,"direction":null,"updatedAt":1786930000}'
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 null null "$((FAKE_NOW + 1))"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$((FAKE_NOW + 1))"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 null null "$((FAKE_NOW - 46))"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$((FAKE_NOW - 46))"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 HDMI-A-1 sideways "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_raw_route '{"version":1,"visible":true,"output":null,"cueOutput":null,"direction":null,"updatedAt":1786930000}'
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

for unsupported_output in UNKNOWN-1 DVI-D-2 HDMI-A-2 DP-1; do
  write_route true "$unsupported_output" null null "$FAKE_NOW"
  write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
  run_reconcile_once
  assert_route_modes 'unrelated-mode rustdesk-route-hidden'
  assert_no_cue

  write_route true DVI-D-1 "$unsupported_output" left "$FAKE_NOW"
  write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
  run_reconcile_once
  assert_route_modes 'unrelated-mode rustdesk-route-hidden'
  assert_no_cue
done

write_route true 'DVI-D-1;touch' null null "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue
[[ ! -e "$TEST_RUNTIME_DIR/touch" ]] || fail 'metacharacter route output caused a side effect'

write_route false null DP-2 null "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden rustdesk-cue'
assert_cue 'DP-2|none'

write_route true DVI-D-1 null null "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
chmod 0755 -- "$ROUTE_DIR"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
chmod 0700 -- "$ROUTE_DIR"

STAT_ROUTE_DIR_OWNER_MODE_OVERRIDE="999999 700"
export STAT_ROUTE_DIR_OWNER_MODE_OVERRIDE
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
unset STAT_ROUTE_DIR_OWNER_MODE_OVERRIDE

chmod 0644 -- "$ROUTE_FILE"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
chmod 0600 -- "$ROUTE_FILE"

STAT_ROUTE_FILE_OWNER_MODE_OVERRIDE="999999 600"
export STAT_ROUTE_FILE_OWNER_MODE_OVERRIDE
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
unset STAT_ROUTE_FILE_OWNER_MODE_OVERRIDE

chmod 0644 -- "$LEASE_FILE"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
chmod 0600 -- "$LEASE_FILE"

STAT_LEASE_FILE_OWNER_MODE_OVERRIDE="999999 600"
export STAT_LEASE_FILE_OWNER_MODE_OVERRIDE
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
unset STAT_LEASE_FILE_OWNER_MODE_OVERRIDE

rm -f -- "$LEASE_FILE"
ln -s /dev/null "$LEASE_FILE"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
rm -f -- "$LEASE_FILE"

rm -f -- "$ROUTE_FILE"
ln -s /dev/null "$ROUTE_FILE"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
rm -f -- "$ROUTE_FILE"
write_route true DVI-D-1 null null "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"

rm -rf -- "$ROUTE_DIR"
ln -s "$TEST_RUNTIME_DIR" "$ROUTE_DIR"
run_reconcile_once
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
rm -f -- "$ROUTE_DIR"
mkdir -p -- "$ROUTE_DIR"
chmod 0700 -- "$ROUTE_DIR"

: >"$MAKOCTL_LOG"
: >"$MV_LOG"
: >"$FAKE_ITERATION_COMPLETION_LOG"
printf '%s\n' 'unrelated-mode rustdesk-route-DVI-D-1 rustdesk-route-HDMI-A-1 rustdesk-route-DP-2 rustdesk-route-hidden rustdesk-cue' \
  >"$MAKO_MODE_STATE"
rm -f -- "$ROUTE_FILE" "$LEASE_FILE" "$CUE_FILE"

start_owned_fake_mako FAKE_MAKO_PID FAKE_MAKO_START_TIME FAKE_MAKO_EXECUTABLE
assert_process_identity "$FAKE_MAKO_PID" "$FAKE_MAKO_START_TIME" "$FAKE_MAKO_EXECUTABLE" 'fake Mako startup'
export FAKE_MAKO_PID FAKE_MAKO_START_TIME FAKE_MAKO_EXECUTABLE

start_adapter || fail 'adapter startup identity tracking failed'

wait_for_log_count 1
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden'
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 null null "$FAKE_NOW"
iteration_completions_after_write=$(iteration_completion_count)
assert_no_new_mako_call_after_iterations 1 "$((iteration_completions_after_write + 2))"
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
wait_for_log_count 2
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-DVI-D-1'
assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1'
assert_no_cue

write_route true DVI-D-1 null null "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
iteration_completions_after_write=$(iteration_completion_count)
assert_no_new_mako_call_after_iterations 2 "$((iteration_completions_after_write + 2))"

write_route true DVI-D-1 HDMI-A-1 left "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
wait_for_log_count 3
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-DVI-D-1|-a|rustdesk-cue'
assert_route_modes 'unrelated-mode rustdesk-route-DVI-D-1 rustdesk-cue'
assert_cue 'HDMI-A-1|left'
assert_atomic_cue_rename

write_route false null DP-2 left "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
wait_for_log_count 4
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden|-a|rustdesk-cue'
assert_route_modes 'unrelated-mode rustdesk-route-hidden rustdesk-cue'
assert_cue 'DP-2|left'

write_route false null DP-2 null "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
wait_for_log_count 5
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden|-a|rustdesk-cue'
assert_route_modes 'unrelated-mode rustdesk-route-hidden rustdesk-cue'
assert_cue 'DP-2|none'

rm -f -- "$ROUTE_FILE"
iteration_completions_after_write=$(iteration_completion_count)
wait_for_log_count 6
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden'
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue

write_route true DVI-D-1 HDMI-A-1 left "$FAKE_NOW"
write_lease "$FAKE_NOW" "$((FAKE_NOW + 2))" "$FAKE_NOW"
wait_for_log_count 7
assert_cue 'HDMI-A-1|left'
assert_file_mode 0600 "$CUE_FILE"

cleanup_adapter
assert_route_modes 'unrelated-mode rustdesk-route-hidden'
assert_no_cue
assert_last_call 'mode|-r|rustdesk-route-DVI-D-1|-r|rustdesk-route-HDMI-A-1|-r|rustdesk-route-DP-2|-r|rustdesk-route-hidden|-r|rustdesk-cue|-a|rustdesk-route-hidden'
assert_process_identity "$FAKE_MAKO_PID" "$FAKE_MAKO_START_TIME" "$FAKE_MAKO_EXECUTABLE" 'fake Mako survived adapter cleanup'

printf 'PASS: fail-closed Mako route adapter contract\n'
