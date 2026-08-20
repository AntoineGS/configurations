#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
STATE_HELPER="$ROOT/Linux/os/helpers/desktop-hardware-state"
TMP_DIR="$(mktemp -d)"
FAKE_BIN="$TMP_DIR/bin"
STATE_DIR="$TMP_DIR/state"
VM_VIRSH_TRACE="$TMP_DIR/virsh.trace"
NO_VIRSH_PATH="$TMP_DIR/no-virsh"

trap 'rm -rf -- "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_json() {
  local payload=$1
  local expression=$2
  local message=$3

  jq -e "$expression" <<<"$payload" >/dev/null || fail "$message: $payload"
}

run_vm() {
  local expected_status=$1
  local actual_status

  if VM_OUTPUT=$("$STATE_HELPER" vm 2>"$TMP_DIR/helper.stderr"); then
    actual_status=0
  else
    actual_status=$?
  fi
  [[ $actual_status -eq $expected_status ]] || fail "expected desktop-hardware-state vm status $expected_status, got $actual_status"
}

[[ -x "$STATE_HELPER" ]] || fail "$STATE_HELPER must exist and be executable"
command -v jq >/dev/null 2>&1 || fail 'jq is required'
grep -Fq '/proc/uptime' "$STATE_HELPER" || fail 'VM sampling does not use a monotonic uptime source'
if grep -Fq 'date +%s%N' "$STATE_HELPER"; then
  fail 'VM sampling still uses wall-clock nanoseconds'
fi

mkdir -p -- "$FAKE_BIN" "$STATE_DIR"

cat >"$FAKE_BIN/virsh" <<'FAKE_VIRSH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\0' "$@" >>"$VM_VIRSH_TRACE"
if [[ ${1:-} == --connect ]]; then
  [[ ${2:-} == qemu:///system ]] || exit 65
  shift 2
fi
case ${1:-} in
  list)
    (( ${VM_LIST_FAIL:-0} == 0 )) || { printf 'mock list failed\n' >&2; exit 1; }
    printf '%s' "${VM_LIST_OUTPUT:-}"
    ;;
  domstats)
    (( ${VM_STATS_FAIL:-0} == 0 )) || { printf 'mock domstats failed\n' >&2; exit 1; }
    printf '%s' "${VM_STATS_OUTPUT:-}"
    ;;
  *) printf 'unexpected virsh command: %s\n' "${1:-}" >&2; exit 64 ;;
esac
FAKE_VIRSH
chmod +x -- "$FAKE_BIN/virsh"

export PATH="$FAKE_BIN:$PATH"
export DESKTOP_HARDWARE_STATE_DIR="$STATE_DIR"
export VM_VIRSH_TRACE
export VM_STATS_FAIL=0
export VM_LIST_FAIL=0

mkdir -p -- "$NO_VIRSH_PATH"
for command_name in bash chmod date env jq mkdir mktemp mv rm; do
  ln -s -- "$(command -v "$command_name")" "$NO_VIRSH_PATH/$command_name"
done

saved_path=$PATH
PATH=$NO_VIRSH_PATH
run_vm 0
PATH=$saved_path
assert_json "$VM_OUTPUT" \
  '.available == false and .stale == false and .error == null and .data.name == ""' \
  'missing virsh was not reported as a clean unavailable state'

export VM_LIST_OUTPUT=$'win11 gaming\n'
export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 1000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=1000000000
run_vm 0
first=$VM_OUTPUT
assert_json "$first" \
  '.available == true and .stale == false and .error == null and
   .data.name == "win11 gaming" and .data.vcpus == 4 and
   .data.cpu.available == false and
   .data.memory.usageAvailable == true and
   .data.memory.currentKiB == 12582912 and
   .data.memory.maximumKiB == 25165824 and
   .data.memory.usedKiB == 5242880 and
   .data.memory.percent == 42' \
  'first VM sample was not normalized as required'

export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 6000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=6000000000
run_vm 0
second=$VM_OUTPUT
assert_json "$second" \
  '.data.cpu.available == true and .data.cpu.percent == 25 and
   .data.cpuTimeNs == 6000000000 and .data.sampledAtNs == 6000000000' \
  'second VM sample did not compute the CPU delta'

trace=$(tr '\0' '\n' <"$VM_VIRSH_TRACE")
expected_trace=$'--connect\nqemu:///system\nlist\n--state-running\n--name\n--connect\nqemu:///system\ndomstats\n--domain\nwin11 gaming\n--state\n--cpu-total\n--balloon\n--vcpu\n--nowait\n--connect\nqemu:///system\nlist\n--state-running\n--name\n--connect\nqemu:///system\ndomstats\n--domain\nwin11 gaming\n--state\n--cpu-total\n--balloon\n--vcpu\n--nowait\n'
expected_trace=${expected_trace%$'\n'}
[[ $trace == "$expected_trace" ]] || fail "virsh argv trace was unexpected: $(printf '%q' "$trace")"

export VM_LIST_FAIL=1
run_vm 1
assert_json "$VM_OUTPUT" \
  '.available == true and .stale == true and .data.name == "win11 gaming" and (.error | length > 0)' \
  'virsh list failure did not preserve the last successful VM state'
export VM_LIST_FAIL=0

export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = malformed\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
run_vm 1
assert_json "$VM_OUTPUT" \
  '.available == true and .stale == true and .data.name == "win11 gaming" and .data.cpuTimeNs == 6000000000' \
  'malformed numeric telemetry did not preserve the last successful VM state'
export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 6000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'

export VM_STATS_FAIL=1
run_vm 1
assert_json "$VM_OUTPUT" \
  '.available == true and .stale == true and (.error | length > 0) and
   .data.name == "win11 gaming" and .data.cpuTimeNs == 6000000000' \
  'domstats failure did not return the fresh cached payload as stale'
export VM_STATS_FAIL=0

export VM_LIST_OUTPUT=''
export DESKTOP_HARDWARE_NOW_NS=7000000000
run_vm 0
assert_json "$VM_OUTPUT" \
  '.available == false and .stale == false and .error == null and
   .data.name == "" and .data.cpu.available == false and
   .data.memory.allocationAvailable == false' \
  'no running VM was not reported as unavailable'

export VM_LIST_OUTPUT=$'win11 gaming\n'
export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 7000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=8000000000
run_vm 0
assert_json "$VM_OUTPUT" \
  '.data.cpu.available == false and .data.memory.usageAvailable == true' \
  'a new VM sample did not start a fresh CPU baseline'

export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 8000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\n'
export DESKTOP_HARDWARE_NOW_NS=9000000000
run_vm 0
assert_json "$VM_OUTPUT" \
  '.data.memory.allocationAvailable == true and
   .data.memory.usageAvailable == false and
   .data.memory.currentKiB == 12582912 and
   .data.memory.maximumKiB == 25165824 and
   .data.memory.usedKiB == null and .data.memory.percent == null' \
  'missing balloon.usable was not reflected in memory availability'

export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 7000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=10000000000
run_vm 0
assert_json "$VM_OUTPUT" \
  '.data.cpu.available == false and .data.cpu.percent == null' \
  'a decreasing CPU counter was treated as a valid delta'

export VM_LIST_OUTPUT=$'replacement\n'
export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 8000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=11000000000
run_vm 0
assert_json "$VM_OUTPUT" \
  '.data.name == "replacement" and .data.cpu.available == false' \
  'a changed VM name did not reset the CPU delta'

export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 13000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=16000000000
run_vm 0
assert_json "$VM_OUTPUT" \
  '.data.name == "replacement" and .data.cpu.available == true and .data.cpu.percent == 25' \
  'the replacement VM did not establish a new CPU baseline'

cache_before=$(<"$STATE_DIR/vm.json")
export VM_STATS_OUTPUT=$'state.state = 3\ncpu.time = 14000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=17000000000
run_vm 1
assert_json "$VM_OUTPUT" \
  '.available == true and .stale == true and (.error | length > 0) and
   .data.name == "replacement" and .data.cpuTimeNs == 13000000000 and
   .data.sampledAtNs == 16000000000' \
  'a paused VM race did not return the previous payload as stale'
cache_after=$(<"$STATE_DIR/vm.json")
[[ $cache_after == "$cache_before" ]] || fail 'a non-running VM race mutated the fresh cache'

export VM_LIST_OUTPUT=$'one\ntwo\n'
run_vm 1
assert_json "$VM_OUTPUT" \
  '.available == true and .stale == true and (.error | length > 0) and
    .data.name == "replacement"' \
  'multiple running VMs did not return the cached payload as stale'

export VM_LIST_OUTPUT=$'replacement\n'
export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 14000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=16000000000
run_vm 0
assert_json "$VM_OUTPUT" \
  '.data.cpu.available == false and .data.sampledAtNs == 16000000000' \
  'an equal sample timestamp was treated as a valid CPU delta'

export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 14000000001\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=16000000001
run_vm 0
assert_json "$VM_OUTPUT" \
  '.data.cpu.available == true and .data.cpu.percent == 25' \
  'a short positive monotonic delta was not accepted'

export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 15000000001\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=16000000000
run_vm 0
assert_json "$VM_OUTPUT" \
  '.data.cpu.available == false and .data.sampledAtNs == 16000000000' \
  'a backward sample timestamp was treated as a valid CPU delta'

export VM_LIST_OUTPUT=$'replacement\n'
export VM_STATS_OUTPUT=$'state.state = 1\ncpu.time = 14000000000\nvcpu.current = 4\nballoon.current = 12582912\nballoon.maximum = 25165824\nballoon.usable = 7340032\n'
export DESKTOP_HARDWARE_NOW_NS=invalid
run_vm 1
assert_json "$VM_OUTPUT" \
  '.available == true and .stale == true and .error == "invalid VM sample timestamp" and
   .data.name == "replacement"' \
  'an invalid VM timestamp did not return a stale cached payload'

printf 'PASS: VM state-helper coverage\n'
