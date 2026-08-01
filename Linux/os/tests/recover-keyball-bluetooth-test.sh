#!/bin/bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
helper="$repo_root/Linux/os/helpers/recover-keyball-bluetooth"
tmp_dir="$(mktemp -d)"
input_devices="$tmp_dir/input-devices"
sudo_log="$tmp_dir/sudo.log"
logger_log="$tmp_dir/logger.log"

trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"

cat > "$tmp_dir/bin/busctl" <<'EOF'
#!/bin/bash
set -u

case "${1:-}" in
  tree)
    printf '/\n/org/bluez/hci0/dev_C4_EB_3B_49_AC_73\n'
    ;;
  get-property)
    case "${5:-}" in
      Name) printf 's "%s"\n' "${BUSCTL_DEVICE_NAME:-Keyball44}" ;;
      Connected) printf 'b %s\n' "${BUSCTL_CONNECTED:-false}" ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

cat > "$tmp_dir/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SUDO_LOG"
exit "${SUDO_EXIT_CODE:-0}"
EOF

cat > "$tmp_dir/bin/logger" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$LOGGER_LOG"
EOF

chmod +x "$tmp_dir/bin/busctl" "$tmp_dir/bin/sudo" "$tmp_dir/bin/logger"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_helper() {
  local connected="$1"
  local device_name="${2:-Keyball44}"
  local sudo_exit_code="${3:-0}"

  : > "$sudo_log"
  : > "$logger_log"
  BUSCTL_CONNECTED="$connected" \
    BUSCTL_DEVICE_NAME="$device_name" \
    SUDO_EXIT_CODE="$sudo_exit_code" \
    SUDO_LOG="$sudo_log" \
    LOGGER_LOG="$logger_log" \
    KEYBALL_RECOVERY_DELAY_SECONDS=0 \
    KEYBALL_INPUT_DEVICES_FILE="$input_devices" \
    PATH="$tmp_dir/bin:$PATH" \
    "$helper"
}

assert_no_restart() {
  [[ ! -s "$sudo_log" ]] || fail "unexpected restart: $(<"$sudo_log")"
}

[[ -x "$helper" ]] || fail "$helper must exist and be executable"

printf 'N: Name="Keyball44 Keyboard"\n' > "$input_devices"
run_helper true
assert_no_restart

: > "$input_devices"
run_helper false
assert_no_restart

run_helper true OtherKeyboard
assert_no_restart

BUSCTL_CONNECTED=true \
  BUSCTL_DEVICE_NAME=OtherKeyboard \
  SUDO_LOG="$sudo_log" \
  LOGGER_LOG="$logger_log" \
  KEYBALL_DEVICE_NAME=OtherKeyboard \
  KEYBALL_RECOVERY_DELAY_SECONDS=0 \
  KEYBALL_INPUT_DEVICES_FILE="$input_devices" \
  PATH="$tmp_dir/bin:$PATH" \
  "$helper"
assert_no_restart

run_helper true
[[ "$(<"$sudo_log")" == "-n /usr/bin/systemctl restart bluetooth.service" ]] ||
  fail "ghost connection did not request the exact restart command"

run_helper true Keyball44 1 || fail "restart failure propagated"
[[ -s "$logger_log" ]] || fail "restart failure was not logged"

rm "$input_devices"
run_helper true
assert_no_restart

printf 'PASS: Keyball Bluetooth recovery helper\n'
