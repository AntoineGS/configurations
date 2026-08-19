#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
STATE_HELPER="$ROOT/Linux/os/helpers/desktop-hardware-state"
BLUEZ_FIXTURE="$ROOT/Linux/os/tests/fixtures/bluez-split-keyboard.json"
tmp_dir=$(mktemp -d)
fake_bin="$tmp_dir/fake-bin"
state_dir="$tmp_dir/state"
call_log="$tmp_dir/call.log"

trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$STATE_HELPER" ]] || fail "$STATE_HELPER must exist and be executable"
[[ -f "$BLUEZ_FIXTURE" ]] || fail "$BLUEZ_FIXTURE must exist"
command -v jq >/dev/null 2>&1 || fail 'jq is required'

mkdir -p -- "$fake_bin" "$state_dir"
: >"$call_log"

cat >"$fake_bin/busctl" <<'FAKE_BUSCTL'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"$CALL_LOG"

if [[ $* == *GetManagedObjects* ]]; then
  if [[ ${STUB_BLUEZ_MODE:-valid} == malformed ]]; then
    printf '%s\n' 'not-json'
  elif [[ ${STUB_BLUEZ_MODE:-valid} == nested-malformed ]]; then
    jq -cn --slurpfile objects "$BLUEZ_FIXTURE" \
      '{type:"a{oa{sa{sv}}}",data:[$objects[0] + {"/org/bluez/hci0/dev_MALFORMED":"not-an-interface-map"}]}'
  elif [[ ${STUB_BLUEZ_MODE:-valid} == malformed-interface ]]; then
    jq -cn --slurpfile objects "$BLUEZ_FIXTURE" \
      '{type:"a{oa{sa{sv}}}",data:[$objects[0] + {
        "/org/bluez/hci0/dev_BAD_INTERFACE":{"org.bluez.Device1":"not-an-interface-map"},
        "/org/bluez/hci0/dev_SPLIT/serviceBAD":{"org.bluez.GattService1":"not-a-service"},
        "/org/bluez/hci0/dev_SPLIT/serviceBAD/charBAD":{"org.bluez.GattCharacteristic1":{
          "UUID":{"type":"s","data":"00002a19-0000-1000-8000-00805f9b34fb"},
          "Service":{"type":"o","data":"/org/bluez/hci0/dev_SPLIT/serviceBAD"}
        }},
        "/org/bluez/hci0/dev_SPLIT/service0015/descBAD":{"org.bluez.GattDescriptor1":"not-a-descriptor"}
      }]}'
  elif [[ ${STUB_BLUEZ_MODE:-valid} == wrong-signature ]]; then
    jq -cn --slurpfile objects "$BLUEZ_FIXTURE" \
      '{type:"s",data:[$objects[0]]}'
  elif [[ ${STUB_BLUEZ_MODE:-valid} == no-gatt ]]; then
    jq -cn --slurpfile objects "$BLUEZ_FIXTURE" \
      '{type:"a{oa{sa{sv}}}",data:[($objects[0] | with_entries(select(.value | has("org.bluez.Device1"))))]}'
  elif [[ ${STUB_BLUEZ_MODE:-valid} == slow-gatt ]]; then
    jq -cn --slurpfile objects "$BLUEZ_FIXTURE" \
      '{type:"a{oa{sa{sv}}}",data:[($objects[0] + {
        "/org/bluez/hci0/dev_GATT_ONLY/service0030/char0032":{"org.bluez.GattCharacteristic1":{
          "UUID":{"type":"s","data":"00002a19-0000-1000-8000-00805f9b34fb"},
          "Service":{"type":"o","data":"/org/bluez/hci0/dev_GATT_ONLY/service0030"}
        }},
        "/org/bluez/hci0/dev_GATT_ONLY/service0030/char0033":{"org.bluez.GattCharacteristic1":{
          "UUID":{"type":"s","data":"00002a19-0000-1000-8000-00805f9b34fb"},
          "Service":{"type":"o","data":"/org/bluez/hci0/dev_GATT_ONLY/service0030"}
        }},
        "/org/bluez/hci0/dev_GATT_ONLY/service0030/char0034":{"org.bluez.GattCharacteristic1":{
          "UUID":{"type":"s","data":"00002a19-0000-1000-8000-00805f9b34fb"},
          "Service":{"type":"o","data":"/org/bluez/hci0/dev_GATT_ONLY/service0030"}
        }}
      })]}'
  else
    jq -cn --slurpfile objects "$BLUEZ_FIXTURE" \
      '{type:"a{oa{sa{sv}}}",data:[$objects[0]]}'
  fi
  exit 0
fi

if [[ ${STUB_BLUEZ_MODE:-valid} == slow-gatt ]]; then
  sleep 2.1
fi

case $* in
  *char0011*) printf '%s\n' '{"type":"ay","data":[[41]]}' ;;
  *char0016*)
    [[ ${STUB_BLUEZ_MODE:-valid} != peripheral-failure ]] || exit 1
    if [[ ${STUB_BLUEZ_MODE:-valid} == extra-gatt-byte ]]; then
      printf '%s\n' '{"type":"ay","data":[[56,57]]}'
    elif [[ ${STUB_BLUEZ_MODE:-valid} == wrong-gatt-type ]]; then
      printf '%s\n' '{"type":"s","data":[[56]]}'
    else
      printf '%s\n' '{"type":"ay","data":[[56]]}'
    fi
    ;;
  *char0031*|*char0032*|*char0033*|*char0034*) printf '%s\n' '{"type":"ay","data":[[61]]}' ;;
  *) exit 2 ;;
esac
FAKE_BUSCTL
chmod +x -- "$fake_bin/busctl"

export BLUEZ_FIXTURE CALL_LOG="$call_log"

state=$(PATH="$fake_bin:$PATH" DESKTOP_HARDWARE_STATE_DIR="$state_dir" \
  "$STATE_HELPER" bluetooth)

jq -e '
  .available == true and .stale == false and
  .data.devices["/org/bluez/hci0/dev_SPLIT"] == {central:43, peripheral:56} and
  .data.devices["/org/bluez/hci0/dev_NORMAL"] == {central:72, peripheral:null} and
  .data.devices["/org/bluez/hci0/dev_GATT_ONLY"] == {central:61, peripheral:null} and
  (.data.devices | has("/org/bluez/hci0/dev_UNRESOLVED") | not) and
  (.data.devices | has("/org/bluez/hci0/dev_DISCONNECTED") | not)
' <<<"$state" >/dev/null || fail "split battery state was not collected"

jq -e '.updatedAt | type == "number"' <<<"$state" >/dev/null \
  || fail "available Bluetooth state omitted updatedAt"

grep -Fq -- '--timeout=2 call org.bluez /org/bluez/hci0/dev_SPLIT/service0015/char0016' \
  "$call_log" || fail "peripheral GATT read did not use the two-second timeout"
if grep -Fq -- '/org/bluez/hci0/dev_SPLIT/service0010/char0011 org.bluez.GattCharacteristic1 ReadValue' \
    "$call_log"; then
  fail "authoritative Battery1 central value still triggered a non-peripheral GATT read"
fi

state=$(STUB_BLUEZ_MODE=peripheral-failure PATH="$fake_bin:$PATH" \
  DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$STATE_HELPER" bluetooth)
jq -e '
  .available == true and .stale == false and
  .data.devices["/org/bluez/hci0/dev_SPLIT"] == {central:43, peripheral:null} and
  .data.devices["/org/bluez/hci0/dev_NORMAL"] == {central:72, peripheral:null} and
  .data.devices["/org/bluez/hci0/dev_GATT_ONLY"] == {central:61, peripheral:null}
' \
  <<<"$state" >/dev/null || fail "partial GATT failure discarded the central battery"

if ! state=$(STUB_BLUEZ_MODE=no-gatt PATH="$fake_bin:$PATH" \
    DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$STATE_HELPER" bluetooth); then
  fail "valid BlueZ state without GATT characteristics failed"
fi
jq -e '
  .available == true and .stale == false and
  .data.devices["/org/bluez/hci0/dev_SPLIT"] == {central:43, peripheral:null} and
  .data.devices["/org/bluez/hci0/dev_NORMAL"] == {central:72, peripheral:null} and
  .data.devices["/org/bluez/hci0/dev_GATT_ONLY"] == {central:null, peripheral:null} and
  (.data.devices | has("/org/bluez/hci0/dev_UNRESOLVED") | not) and
  (.data.devices | has("/org/bluez/hci0/dev_DISCONNECTED") | not)
' <<<"$state" >/dev/null || fail "valid no-GATT BlueZ state was not collected"

if ! state=$(STUB_BLUEZ_MODE=nested-malformed PATH="$fake_bin:$PATH" \
    DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$STATE_HELPER" bluetooth); then
  fail "malformed individual BlueZ object discarded valid devices"
fi
jq -e '
  .available == true and .stale == false and
  .data.devices["/org/bluez/hci0/dev_SPLIT"] == {central:43, peripheral:56} and
  .data.devices["/org/bluez/hci0/dev_NORMAL"] == {central:72, peripheral:null} and
  .data.devices["/org/bluez/hci0/dev_GATT_ONLY"] == {central:61, peripheral:null} and
  (.data.devices | has("/org/bluez/hci0/dev_MALFORMED") | not)
' <<<"$state" >/dev/null || fail "valid devices did not survive malformed object"

if ! state=$(STUB_BLUEZ_MODE=malformed-interface PATH="$fake_bin:$PATH" \
    DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$STATE_HELPER" bluetooth); then
  fail "malformed individual BlueZ interfaces discarded valid devices"
fi
jq -e '
  .available == true and .stale == false and
  .data.devices["/org/bluez/hci0/dev_SPLIT"] == {central:43, peripheral:56} and
  .data.devices["/org/bluez/hci0/dev_NORMAL"] == {central:72, peripheral:null} and
  .data.devices["/org/bluez/hci0/dev_GATT_ONLY"] == {central:61, peripheral:null} and
  (.data.devices | has("/org/bluez/hci0/dev_BAD_INTERFACE") | not)
' <<<"$state" >/dev/null || fail "valid devices did not survive malformed interfaces"

for invalid_mode in extra-gatt-byte wrong-gatt-type; do
  state=$(STUB_BLUEZ_MODE="$invalid_mode" PATH="$fake_bin:$PATH" \
    DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$STATE_HELPER" bluetooth)
  jq -e '
    .available == true and .stale == false and
    .data.devices["/org/bluez/hci0/dev_SPLIT"] == {central:43, peripheral:null} and
    .data.devices["/org/bluez/hci0/dev_NORMAL"] == {central:72, peripheral:null} and
    .data.devices["/org/bluez/hci0/dev_GATT_ONLY"] == {central:61, peripheral:null}
  ' <<<"$state" >/dev/null || fail "invalid GATT reply was accepted: $invalid_mode"
done

: >"$call_log"
if ! state=$(STUB_BLUEZ_MODE=slow-gatt PATH="$fake_bin:$PATH" \
    DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$STATE_HELPER" bluetooth); then
  fail "slow partial GATT collection failed"
fi
jq -e '
  .available == true and .stale == false and
  .data.devices["/org/bluez/hci0/dev_SPLIT"] == {central:43, peripheral:null} and
  .data.devices["/org/bluez/hci0/dev_NORMAL"] == {central:72, peripheral:null}
' <<<"$state" >/dev/null || fail "slow GATT collection discarded unaffected devices"
slow_read_count=$(grep -c -- 'GattCharacteristic1 ReadValue' "$call_log" || true)
(( slow_read_count <= 2 )) || fail "GATT collection exceeded its two full-call budget"

if state=$(STUB_BLUEZ_MODE=wrong-signature PATH="$fake_bin:$PATH" \
    DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$STATE_HELPER" bluetooth); then
  fail "malformed ObjectManager signature unexpectedly succeeded"
fi
jq -e '.stale == true and (.error | type == "string")' <<<"$state" >/dev/null \
  || fail "malformed ObjectManager signature did not return a stale envelope"

if state=$(STUB_BLUEZ_MODE=malformed PATH="$fake_bin:$PATH" \
    DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$STATE_HELPER" bluetooth); then
  fail "malformed BlueZ state unexpectedly succeeded"
fi
jq -e '.stale == true and (.error | type == "string")' <<<"$state" >/dev/null \
  || fail "malformed BlueZ state did not return a stale envelope"

missing_bin="$tmp_dir/missing-bin"
mkdir -p -- "$missing_bin"
for command_name in bash jq date mkdir mktemp chmod mv rm; do
  ln -s -- "$(command -v "$command_name")" "$missing_bin/$command_name"
done
state=$(PATH="$missing_bin" DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$STATE_HELPER" bluetooth)
jq -e '.available == false and .stale == false and .data.devices == {}' <<<"$state" >/dev/null \
  || fail "missing busctl did not produce an unavailable envelope"

printf 'PASS: Bluetooth hardware state\n'
