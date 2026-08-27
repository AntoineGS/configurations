#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR
readonly MARKER_SCRIPT="$SCRIPT_DIR/../rustdesk-cm-marker"
TEST_DIR=$(mktemp -d)
readonly TEST_DIR
readonly BIN_DIR="$TEST_DIR/bin"
readonly CALL_LOG="$TEST_DIR/calls"
readonly HOST_ENABLED="$TEST_DIR/host-enabled"
readonly HOST_ACTIVE="$TEST_DIR/host-active"
readonly RUSTDESK_EXECUTABLE=/usr/bin/true
readonly RUSTDESK_CONFIG_DIR="$TEST_DIR/config/rustdesk"
readonly RUSTDESK_CONFIG="$RUSTDESK_CONFIG_DIR/RustDesk2.toml"

marker_pid=

cleanup() {
  if [[ -n $marker_pid ]]; then
    kill "$marker_pid" 2>/dev/null || true
    wait "$marker_pid" 2>/dev/null || true
  fi
  rm -rf -- "$TEST_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "$BIN_DIR"
mkdir -p -- "$RUSTDESK_CONFIG_DIR"
printf "stop-service = 'Y'\n" > "$RUSTDESK_CONFIG"

cat > "$BIN_DIR/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'systemctl %s\n' "$*" >> "$CALL_LOG"

case $* in
  'show rustdesk.service --property=ExecStart --value')
    printf '{ path=%s ; argv[]=%s --service ; ignore_errors=no ; }\n' \
      "$RUSTDESK_EXECUTABLE" "$RUSTDESK_EXECUTABLE"
    ;;
  'is-enabled --quiet rustdesk.service')
    [[ -f $HOST_ENABLED ]]
    ;;
  'is-active --quiet rustdesk.service')
    [[ -f $HOST_ACTIVE ]]
    ;;
  '--user show rustdesk-cm-marker.service --property=MainPID --value')
    if [[ -f $TEST_DIR/marker-restarted ]]; then
      attempts=$(<"$TEST_DIR/main-pid-attempts")
      printf '%s\n' "$((attempts + 1))" > "$TEST_DIR/main-pid-attempts"
      if ((attempts < 2)); then
        printf '0\n'
        exit 0
      fi
    fi
    printf '%s\n' "$MARKER_PID"
    ;;
  '--user is-enabled --quiet rustdesk-cm-marker.service' | '--user is-active --quiet rustdesk-cm-marker.service')
    ;;
  '--user show rustdesk-cm-marker.service --property=NeedDaemonReload --value')
    printf '%s\n' no
    ;;
  '--user daemon-reload' | '--user enable rustdesk-cm-marker.service')
    ;;
  '--user restart rustdesk-cm-marker.service')
    : > "$TEST_DIR/marker-restarted"
    printf '0\n' > "$TEST_DIR/main-pid-attempts"
    ;;
  *)
    printf 'Unexpected systemctl call: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

cat > "$BIN_DIR/pkexec" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'pkexec %s\n' "$*" >> "$CALL_LOG"
if [[ ${1:-} == "$RUSTDESK_EXECUTABLE" && ${2:-} == --option && ${3:-} == stop-service ]]; then
  if (($# == 4)); then
    [[ -z $4 ]]
    : > "$TEST_DIR/stop-service-cleared"
  else
    [[ -f $TEST_DIR/stop-service-cleared ]] || printf 'Y\n'
  fi
elif [[ $* == '/usr/bin/systemctl enable --now rustdesk.service' ]]; then
  [[ -f $TEST_DIR/stop-service-cleared ]] || {
    printf 'RustDesk host was enabled before stop-service was cleared\n' >&2
    exit 1
  }
  if grep -Fq "stop-service = 'Y'" "$RUSTDESK_CONFIG"; then
    printf 'RustDesk host was enabled before the user config was repaired\n' >&2
    exit 1
  fi
  touch "$HOST_ENABLED" "$HOST_ACTIVE"
else
  printf 'Unexpected pkexec call: %s\n' "$*" >&2
  exit 1
fi
EOF

chmod +x "$BIN_DIR/systemctl" "$BIN_DIR/pkexec"

bash -c 'exec -a "$1 --cm" /usr/bin/sleep 30' _ "$RUSTDESK_EXECUTABLE" &
marker_pid=$!
export CALL_LOG HOST_ACTIVE HOST_ENABLED RUSTDESK_CONFIG RUSTDESK_EXECUTABLE TEST_DIR
export MARKER_PID=$marker_pid
export PATH="$BIN_DIR:/usr/bin"
export XDG_CONFIG_HOME="$TEST_DIR/config"

# Resolved from this test's directory above.
# shellcheck disable=SC1090,SC1091
source "$MARKER_SCRIPT"
systemctl_cmd() {
  "$BIN_DIR/systemctl" "$@"
}
pkexec_cmd() {
  "$BIN_DIR/pkexec" "$@"
}
sleep_cmd() {
  /usr/bin/sleep "$@"
}

if check_setup; then
  fail '--check accepted a disabled and stopped RustDesk host service'
fi

apply_setup
check_setup || fail '--apply did not produce a complete working setup'
if grep -Fq "stop-service = 'Y'" "$RUSTDESK_CONFIG"; then
  fail '--apply left stop-service enabled in the user RustDesk config'
fi
grep -Fqx "stop-service = 'N'" "$RUSTDESK_CONFIG" ||
  fail '--apply corrupted the stop-service setting while disabling it'

grep -Fqx 'pkexec /usr/bin/systemctl enable --now rustdesk.service' "$CALL_LOG" ||
  fail '--apply did not enable and start the RustDesk host through polkit'
grep -Fqx "pkexec $RUSTDESK_EXECUTABLE --option stop-service " "$CALL_LOG" ||
  fail '--apply did not clear RustDesk stop-service before enabling the host'
grep -Fqx 'systemctl --user restart rustdesk-cm-marker.service' "$CALL_LOG" ||
  fail '--apply did not restart the marker service'

printf 'PASS: stopped RustDesk host is restored before marker setup\n'
