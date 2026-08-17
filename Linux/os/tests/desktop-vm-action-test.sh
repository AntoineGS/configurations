#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
ACTION_HELPER="$ROOT/Linux/os/helpers/desktop-hardware-action"
TMP_DIR="$(mktemp -d)"
FAKE_BIN="$TMP_DIR/bin"
HELPER_DIR="$TMP_DIR/helpers"
VM_ACTION_TRACE="$TMP_DIR/action.trace"
VM_ACTION_COUNT="$TMP_DIR/action.count"
ACTION_STDOUT="$TMP_DIR/action.stdout"
ACTION_STDERR="$TMP_DIR/action.stderr"
INJECTED_FILE="$TMP_DIR/injected"

trap 'rm -rf -- "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_status() {
  local expected=$1
  local label=$2

  [[ $RUN_STATUS -eq $expected ]] || fail "$label: expected status $expected, got $RUN_STATUS (stderr: $ACTION_STDERR_CONTENT)"
}

assert_stderr_contains() {
  local label=$1
  local expected=$2

  [[ $ACTION_STDERR_CONTENT == *"$expected"* ]] || fail "$label: stderr did not contain $expected (got: $ACTION_STDERR_CONTENT)"
}

assert_no_action_trace() {
  local label=$1

  [[ ! -s $VM_ACTION_TRACE ]] || fail "$label: virsh was invoked unexpectedly"
  [[ ! -s $VM_ACTION_COUNT ]] || fail "$label: virsh invocation count was unexpected"
}

assert_invocation_count() {
  local expected=$1
  local label=$2
  local actual

  actual=$(<"$VM_ACTION_COUNT")
  [[ $actual == "$expected" ]] || fail "$label: expected $expected virsh invocation(s), got ${actual:-0}"
}

assert_no_injection() {
  [[ ! -e $INJECTED_FILE ]] || fail 'domain name was interpreted as shell syntax'
}

run_action() {
  : >"$VM_ACTION_TRACE"
  : >"$VM_ACTION_COUNT"
  : >"$ACTION_STDOUT"
  : >"$ACTION_STDERR"

  if (cd -- "$TMP_DIR" && "$ACTION_HELPER" "$@" >"$ACTION_STDOUT" 2>"$ACTION_STDERR"); then
    RUN_STATUS=0
  else
    RUN_STATUS=$?
  fi
  ACTION_STDERR_CONTENT=$(<"$ACTION_STDERR")
}

assert_trace() {
  local label=$1
  shift
  local -a expected=("$@")
  local -a actual=()

  mapfile -d '' -t actual <"$VM_ACTION_TRACE" || true
  ((${#actual[@]} == ${#expected[@]})) || fail "$label: expected ${#expected[@]} argv entries, got ${#actual[@]}"
  for ((index = 0; index < ${#expected[@]}; index++)); do
    [[ ${actual[index]} == "${expected[index]}" ]] || fail "$label: argv[$index]=${actual[index]@Q}, expected ${expected[index]@Q}"
  done
}

[[ -x $ACTION_HELPER ]] || fail "$ACTION_HELPER must exist and be executable"
command -v jq >/dev/null 2>&1 || fail 'jq is required'

mkdir -p -- "$FAKE_BIN" "$HELPER_DIR"

cat >"$HELPER_DIR/desktop-hardware-state" <<'FAKE_STATE'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${1:-} == vm ]] || exit 2
printf '%s\n' "${VM_STATE_PAYLOAD:?}"
exit "${VM_STATE_STATUS:-0}"
FAKE_STATE

cat >"$FAKE_BIN/virsh" <<'FAKE_VIRSH'
#!/usr/bin/env bash
set -Eeuo pipefail

count=0
if [[ -s ${VM_ACTION_COUNT:?} ]]; then
  count=$(<"$VM_ACTION_COUNT")
fi
printf '%s\n' "$((count + 1))" >"$VM_ACTION_COUNT"
: >"${VM_ACTION_TRACE:?}"
printf '%s\0' "$@" >>"$VM_ACTION_TRACE"
if [[ ${VM_SETMEM_FAIL:-0} == 1 ]]; then
  printf '%s\n' 'libvirt rejected memory resize' >&2
  exit 1
fi
FAKE_VIRSH

chmod +x -- "$HELPER_DIR/desktop-hardware-state" "$FAKE_BIN/virsh"

export DESKTOP_HARDWARE_HELPER_DIR="$HELPER_DIR"
export PATH="$FAKE_BIN:$PATH"
export VM_ACTION_TRACE
export VM_ACTION_COUNT
export VM_STATE_STATUS=0
export VM_SETMEM_FAIL=0

export VM_STATE_PAYLOAD
printf -v VM_STATE_PAYLOAD '%s' '{"available":true,"stale":false,"updatedAt":1,"error":null,"data":{"name":"vm; touch injected","memory":{"allocationAvailable":true,"maximumKiB":25165824}}}'

run_action vm set-memory 12
assert_status 0 'successful memory resize'
assert_trace 'successful memory resize' \
  setmem \
  --domain \
  'vm; touch injected' \
  --size \
  12GiB \
  --live \
  --config
assert_invocation_count 1 'successful memory resize'
assert_no_injection

run_action vm set-memory
assert_status 2 'missing memory argument'
assert_stderr_contains 'missing memory argument' 'usage:'
assert_no_action_trace 'missing memory argument'

for invalid_memory in 0 -1 1.5; do
  run_action vm set-memory "$invalid_memory"
  assert_status 2 "invalid memory value $invalid_memory"
  assert_stderr_contains "invalid memory value $invalid_memory" 'usage:'
  assert_no_action_trace "invalid memory value $invalid_memory"
done

oversized_memory=9223372036854775808
run_action vm set-memory "$oversized_memory"
assert_status 2 'oversized memory value'
assert_stderr_contains 'oversized memory value' 'usage:'
assert_no_action_trace 'oversized memory value'

run_action vm set-memory 25
assert_status 1 'memory above maximum'
assert_stderr_contains 'memory above maximum' 'desktop-hardware-action: requested 25 GiB exceeds maximum 24 GiB'
assert_no_action_trace 'memory above maximum'

printf -v VM_STATE_PAYLOAD '%s' '{"available":true,"stale":true,"updatedAt":1,"error":"stale","data":{"name":"vm; touch injected","memory":{"allocationAvailable":true,"maximumKiB":25165824}}}'
export VM_STATE_STATUS=0
run_action vm set-memory 12
assert_status 1 'stale VM state'
assert_stderr_contains 'stale VM state' 'desktop-hardware-action: no fresh running VM allocation is available'
assert_no_action_trace 'stale VM state'

printf -v VM_STATE_PAYLOAD '%s' '{"available":false,"stale":false,"updatedAt":1,"error":null,"data":{"name":"vm; touch injected","memory":{"allocationAvailable":false,"maximumKiB":25165824}}}'
export VM_STATE_STATUS=0
run_action vm set-memory 12
assert_status 1 'unavailable VM state'
assert_stderr_contains 'unavailable VM state' 'desktop-hardware-action: no fresh running VM allocation is available'
assert_no_action_trace 'unavailable VM state'

printf -v VM_STATE_PAYLOAD '%s' '{"available":true,"stale":false,"updatedAt":1,"error":null,"data":{"name":"vm; touch injected","memory":{"allocationAvailable":true}}}'
run_action vm set-memory 12
assert_status 1 'VM state without maximum'
[[ -n $ACTION_STDERR_CONTENT ]] || fail 'VM state without maximum: rejection did not reach stderr'
assert_no_action_trace 'VM state without maximum'

printf -v VM_STATE_PAYLOAD '%s' '{"available":true,"stale":false,"updatedAt":1,"error":null,"data":{"name":"vm; touch injected","memory":{"allocationAvailable":true,"maximumKiB":25165824}}}'
export VM_SETMEM_FAIL=1
run_action vm set-memory 12
assert_status 1 'virsh memory resize failure'
assert_stderr_contains 'virsh memory resize failure' 'desktop-hardware-action: memory resize failed: libvirt rejected memory resize'
assert_invocation_count 1 'virsh memory resize failure'
assert_no_injection

printf 'PASS: VM action validation, fresh-state gating, and NUL-safe argv dispatch\n'
