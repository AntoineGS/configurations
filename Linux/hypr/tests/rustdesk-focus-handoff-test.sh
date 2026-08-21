#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HANDOFF="$SCRIPT_DIR/../rustdesk-focus-handoff.sh"

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

TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
TEST_BIN="$TEST_ROOT/bin"
mkdir -p -- "$TEST_BIN"

ACTIVE_WINDOW_FILE="$TEST_ROOT/active-window"
ACTIVE_CLASS_FILE="$TEST_ROOT/active-class"
ACTIVE_TITLE_FILE="$TEST_ROOT/active-title"
HYPR_DISPATCH_FILE="$TEST_ROOT/hypr-dispatch"
SOCAT_PAYLOAD_FILE="$TEST_ROOT/socat-payload"
SOCAT_ADDRESS_FILE="$TEST_ROOT/socat-address"
export ACTIVE_WINDOW_FILE ACTIVE_CLASS_FILE ACTIVE_TITLE_FILE HYPR_DISPATCH_FILE
export SOCAT_PAYLOAD_FILE SOCAT_ADDRESS_FILE

cat >"$TEST_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case "$*" in
  'activewindow -j')
    jq -cn \
      --arg address "$(<"$ACTIVE_WINDOW_FILE")" \
      --arg class "$(<"$ACTIVE_CLASS_FILE")" \
      --arg title "$(<"$ACTIVE_TITLE_FILE")" \
      '{address: $address, class: $class, title: $title}'
    ;;
  '-r eval hl.dispatch(hl.dsp.focus({ direction = "left" }))')
    if [[ ${MOVE_FOCUS_CHANGES:-false} == true ]]; then
      printf '0x2\n' >"$ACTIVE_WINDOW_FILE"
    fi
    ;;
  '--instance 0 activewindow -j')
    jq -cn \
      --arg address "$(<"$ACTIVE_WINDOW_FILE")" \
      --arg class "$(<"$ACTIVE_CLASS_FILE")" \
      --arg title "$(<"$ACTIVE_TITLE_FILE")" \
      '{address: $address, class: $class, title: $title}'
    ;;
  '--instance 0 eval hl.dispatch(hl.dsp.focus({ monitor = "l" }))')
    printf 'focus monitor left\n' >>"$HYPR_DISPATCH_FILE"
    ;;
  *)
    printf 'unexpected hyprctl arguments: %s\n' "$*" >&2
    exit 125
    ;;
esac
EOF

cat >"$TEST_BIN/socat" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >"$SOCAT_ADDRESS_FILE"
cat >"$SOCAT_PAYLOAD_FILE"
EOF

cat >"$TEST_BIN/tailscale" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ $* == 'status --json' ]] || exit 125
cat <<'JSON'
{
  "Self": {
    "HostName": "DESKTOP-E07VTRN",
    "TailscaleIPs": ["100.97.74.117", "fd7a:115c:a1e0::2d01:4a77"]
  },
  "Peer": {
    "host": {
      "HostName": "antoinews-linux",
      "TailscaleIPs": ["100.126.24.93", "fd7a:115c:a1e0::f35:185e"]
    },
    "other": {
      "HostName": "unrelated",
      "TailscaleIPs": ["100.64.0.9"]
    }
  }
}
JSON
EOF

chmod 0700 "$TEST_BIN/hyprctl" "$TEST_BIN/socat" "$TEST_BIN/tailscale"
export PATH="$TEST_BIN:/usr/bin:/bin"

[[ -x $HANDOFF ]] || fail "$HANDOFF must exist and be executable"

printf 'Alacritty\n' >"$ACTIVE_CLASS_FILE"
printf 'Terminal\n' >"$ACTIVE_TITLE_FILE"
printf '0x1\n' >"$ACTIVE_WINDOW_FILE"
rm -f -- "$SOCAT_PAYLOAD_FILE" "$SOCAT_ADDRESS_FILE"
MOVE_FOCUS_CHANGES=true "$HANDOFF" send
assert_equal '0x2' "$(<"$ACTIVE_WINDOW_FILE")" 'local left focus destination'
[[ ! -e $SOCAT_PAYLOAD_FILE ]] || fail 'local focus move emitted a handoff message'

printf '0x1\n' >"$ACTIVE_WINDOW_FILE"
rm -f -- "$SOCAT_PAYLOAD_FILE" "$SOCAT_ADDRESS_FILE"
MOVE_FOCUS_CHANGES=false \
  RUSTDESK_HANDOFF_TARGET=desktop-e07vtrn \
  RUSTDESK_HANDOFF_PORT=45973 \
  "$HANDOFF" send
assert_equal '0x1' "$(<"$ACTIVE_WINDOW_FILE")" 'left-edge focus destination'
assert_equal 'focus-left' "$(<"$SOCAT_PAYLOAD_FILE")" 'left-edge handoff payload'
assert_equal '-u -T 1 - TCP4-CONNECT:desktop-e07vtrn:45973,connect-timeout=0.5' \
  "$(<"$SOCAT_ADDRESS_FILE")" 'left-edge handoff destination'

rm -f -- "$HYPR_DISPATCH_FILE"
printf 'RustDesk\n' >"$ACTIVE_CLASS_FILE"
printf 'Remote Desktop\n' >"$ACTIVE_TITLE_FILE"
printf 'focus-left\n' | "$HANDOFF" receive
assert_equal 'focus monitor left' "$(<"$HYPR_DISPATCH_FILE")" 'focused RustDesk handoff action'

rm -f -- "$HYPR_DISPATCH_FILE"
printf 'not-a-command\n' | "$HANDOFF" receive
[[ ! -e $HYPR_DISPATCH_FILE ]] || fail 'unknown command moved client focus'

printf 'Alacritty\n' >"$ACTIVE_CLASS_FILE"
printf 'Terminal\n' >"$ACTIVE_TITLE_FILE"
printf 'focus-left\n' | "$HANDOFF" receive
[[ ! -e $HYPR_DISPATCH_FILE ]] || fail 'handoff moved focus outside RustDesk'

rm -f -- "$SOCAT_PAYLOAD_FILE" "$SOCAT_ADDRESS_FILE"
RUSTDESK_HANDOFF_PORT=45973 "$HANDOFF" listen
assert_equal \
  "-u TCP4-LISTEN:45973,bind=100.97.74.117,range=100.126.24.93/32,reuseaddr,fork,max-children=4 EXEC:$HANDOFF receive" \
  "$(<"$SOCAT_ADDRESS_FILE")" 'Tailscale-only listener address'

printf 'PASS: RustDesk focus handoff tests\n'
