#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HELPER="$ROOT/Linux/os/helpers/desktop-connectivity-action"
TMP_DIR="$(mktemp -d)"
CALL_LOG="$TMP_DIR/calls.log"

trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$HELPER" ]] || fail "$HELPER must exist and be executable"

mkdir -p "$TMP_DIR/bin"

cat >"$TMP_DIR/bin/wpctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

{
  printf '%s' "${0##*/}"
  printf ' %q' "$@"
  printf '\n'
} >>"$CALL_LOG"

if [[ ${STUB_FAIL:-0} == 1 ]]; then
  exit 1
fi
EOF

cat >"$TMP_DIR/bin/nmcli" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

{
  printf '%s' "${0##*/}"
  printf ' %q' "$@"
  printf '\n'
} >>"$CALL_LOG"

if [[ ${1:-} == --ask ]]; then
  password=''
  IFS= read -r password || true
  printf 'nmcli-stdin-length %s\n' "${#password}" >>"$CALL_LOG"
fi

if [[ ${STUB_FAIL:-0} == 1 ]]; then
  exit 1
fi
EOF

cat >"$TMP_DIR/bin/bluetoothctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

{
  printf '%s' "${0##*/}"
  printf ' %q' "$@"
  printf '\n'
} >>"$CALL_LOG"

if [[ ${1:-} == show ]]; then
  if [[ ${STUB_POWERED:-no} == yes ]]; then
    printf 'Powered: yes\n'
  else
    printf 'Powered: no\n'
  fi
fi

if [[ ${STUB_FAIL:-0} == 1 ]]; then
  exit 1
fi
EOF

cat >"$TMP_DIR/bin/rfkill" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

{
  printf '%s' "${0##*/}"
  printf ' %q' "$@"
  printf '\n'
} >>"$CALL_LOG"

if [[ ${STUB_FAIL:-0} == 1 ]]; then
  exit 1
fi
EOF

chmod +x "$TMP_DIR/bin/wpctl" "$TMP_DIR/bin/nmcli" \
  "$TMP_DIR/bin/bluetoothctl" "$TMP_DIR/bin/rfkill"

export CALL_LOG
export PATH="$TMP_DIR/bin:$PATH"

clear_log() {
  : >"$CALL_LOG"
}

assert_calls() {
  local expected=$1
  local actual

  actual=$(<"$CALL_LOG")
  [[ $actual == "$expected" ]] || fail "expected calls $expected, got $actual"
}

assert_call() {
  local expected_binary=$1
  shift
  local expected=$expected_binary
  local argument escaped actual

  for argument in "$@"; do
    printf -v escaped '%q' "$argument"
    expected+=" $escaped"
  done

  actual=$(<"$CALL_LOG")
  [[ $actual == "$expected" ]] || fail "expected call $expected, got $actual"
}

assert_status() {
  local expected=$1
  shift
  local status

  if "$HELPER" "$@" >/dev/null 2>&1; then
    status=0
  else
    status=$?
  fi
  [[ $status -eq $expected ]] || fail "expected status $expected for $*, got $status"
}

clear_log
"$HELPER" audio set-default-output 42 'Built-in Output'
assert_call wpctl set-default 42

clear_log
"$HELPER" audio set-default-input 43 'USB Microphone'
assert_call wpctl set-default 43

clear_log
"$HELPER" audio set-volume 42 0.75
assert_call wpctl set-volume 42 0.75

clear_log
"$HELPER" audio toggle-output-mute 42
assert_call wpctl set-mute 42 toggle

clear_log
"$HELPER" audio toggle-input-mute 43
assert_call wpctl set-mute 43 toggle

ssid='Cafe Wi Fi'
password='secret password'
clear_log
output=$(printf '%s\n' "$password" | "$HELPER" network connect "$ssid" 2>&1)
[[ $output != *"$password"* ]] || fail 'network password was printed'
assert_calls $'nmcli --ask device wifi connect Cafe\\ Wi\\ Fi\nnmcli-stdin-length 15'

profile='Profile With Spaces'
clear_log
"$HELPER" network disconnect "$profile"
assert_call nmcli connection down id "$profile"

clear_log
"$HELPER" network forget "$profile"
assert_call nmcli connection delete id "$profile"

clear_log
"$HELPER" network set-dns "$profile" Cloudflare
assert_call nmcli connection modify "$profile" ipv4.ignore-auto-dns yes ipv4.dns 1.1.1.1,1.0.0.1 ipv6.ignore-auto-dns yes ipv6.dns '2606:4700:4700::1111,2606:4700:4700::1001'

clear_log
"$HELPER" bluetooth power on
assert_calls $'rfkill unblock bluetooth\nbluetoothctl power on'

clear_log
"$HELPER" bluetooth power off
assert_calls $'bluetoothctl power off\nrfkill block bluetooth'

clear_log
STUB_POWERED=yes "$HELPER" bluetooth power toggle
assert_calls $'bluetoothctl show\nbluetoothctl power off\nrfkill block bluetooth'

clear_log
STUB_POWERED=no "$HELPER" bluetooth power toggle
assert_calls $'bluetoothctl show\nrfkill unblock bluetooth\nbluetoothctl power on'

address='AA:BB:CC:DD:EE:FF'
clear_log
"$HELPER" bluetooth scan on
assert_call bluetoothctl scan on

clear_log
"$HELPER" bluetooth pair "$address"
assert_call bluetoothctl pair "$address"

clear_log
"$HELPER" bluetooth connect "$address"
assert_call bluetoothctl connect "$address"

clear_log
"$HELPER" bluetooth disconnect "$address"
assert_call bluetoothctl disconnect "$address"

clear_log
"$HELPER" bluetooth remove "$address"
assert_call bluetoothctl remove "$address"

assert_status 2 audio unknown
assert_status 2 unknown action
assert_status 2 audio set-volume 42
assert_status 2 network set-dns "$profile" Custom
assert_status 2 bluetooth power on extra
assert_status 2 bluetooth connect 'not-an-address'

clear_log
if STUB_FAIL=1 "$HELPER" audio set-volume 42 0.5 >/dev/null 2>&1; then
  fail 'runtime command failure was accepted'
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "runtime command failure returned $status"

printf 'PASS: connectivity action helper\n'
