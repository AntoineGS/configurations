#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
STATE_HELPER="$ROOT/Linux/os/helpers/desktop-hardware-state"
ACTION_HELPER="$ROOT/Linux/os/helpers/desktop-hardware-action"
TMP_DIR="$(mktemp -d)"
CALL_LOG="$TMP_DIR/calls.log"

trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$STATE_HELPER" ]] || fail "$STATE_HELPER must exist and be executable"
[[ -x "$ACTION_HELPER" ]] || fail "$ACTION_HELPER must exist and be executable"

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/helpers" \
  "$TMP_DIR/sys/class/power_supply/BAT0" \
  "$TMP_DIR/sys/class/backlight/intel_backlight" \
  "$TMP_DIR/sys/class/leds/thinkpad::kbd_backlight" \
  "$TMP_DIR/state"

printf '1\n' >"$TMP_DIR/sys/class/power_supply/BAT0/present"
printf 'Battery\n' >"$TMP_DIR/sys/class/power_supply/BAT0/type"
printf '50\n' >"$TMP_DIR/sys/class/backlight/intel_backlight/brightness"
printf '100\n' >"$TMP_DIR/sys/class/backlight/intel_backlight/max_brightness"
printf '2\n' >"$TMP_DIR/sys/class/leds/thinkpad::kbd_backlight/brightness"
printf '3\n' >"$TMP_DIR/sys/class/leds/thinkpad::kbd_backlight/max_brightness"

cat >"$TMP_DIR/helpers/battery-present" <<'EOF'
#!/usr/bin/env bash
[[ ${STUB_BATTERY_PRESENT:-yes} == yes ]]
EOF

cat >"$TMP_DIR/helpers/battery-status" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'Battery 73%'
EOF

cat >"$TMP_DIR/helpers/battery-capacity" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '58'
EOF

cat >"$TMP_DIR/helpers/battery-remaining-time" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '2h 15m'
EOF

cat >"$TMP_DIR/helpers/brightness-display" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'brightness-display' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
EOF

cat >"$TMP_DIR/helpers/brightness-keyboard" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'brightness-keyboard' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
EOF

cat >"$TMP_DIR/bin/powerprofilesctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case ${1:-} in
  get) printf '%s\n' balanced ;;
  list)
    printf '%s\n' '* balanced' '  power-saver' '  performance'
    ;;
  set)
    printf 'powerprofilesctl' >>"$CALL_LOG"
    printf ' %q' "$@" >>"$CALL_LOG"
    printf '\n' >>"$CALL_LOG"
    ;;
  *) exit 2 ;;
esac
EOF

cat >"$TMP_DIR/bin/brightnessctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
device=''
while (($# > 0)); do
  case $1 in
    -d) device=$2; shift 2 ;;
    -m) printf 'intel_backlight,backlight,50,100,50%\n'; exit 0 ;;
    get) printf '%s\n' "$([[ $device == intel_backlight ]] && printf '50' || printf '2')"; exit 0 ;;
    max) printf '%s\n' "$([[ $device == intel_backlight ]] && printf '100' || printf '3')"; exit 0 ;;
    set)
      printf 'brightnessctl' >>"$CALL_LOG"
      printf ' %q' "$@" >>"$CALL_LOG"
      printf '\n' >>"$CALL_LOG"
      exit 0
      ;;
    *) shift ;;
  esac
done
EOF

cat >"$TMP_DIR/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == -j && ${2:-} == monitors ]]; then
  case ${STUB_HYPR_MODE:-valid} in
    valid)
      printf '%s\n' '[
        {"id":0,"name":"eDP-1","description":"Internal Panel","width":1920,"height":1080,"scale":1.25,"focused":true,"disabled":false},
        {"id":1,"name":"DP-1","description":"External Panel","width":2560,"height":1440,"scale":1.5,"focused":false,"disabled":false}
      ]'
      ;;
    malformed) printf '%s\n' '{malformed' ;;
    *) exit 1 ;;
  esac
  exit 0
fi

printf 'hyprctl' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
EOF

cat >"$TMP_DIR/bin/tailscale" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == status && ${2:-} == --json ]]; then
  case ${STUB_TAILSCALE_MODE:-running} in
    missing) exit 127 ;;
    inactive)
      printf '%s\n' '{"BackendState":"NeedsLogin","Self":{"HostName":"desktop"}}'
      exit 1
      ;;
    malformed) printf '%s\n' '{malformed' ;;
    running)
      printf '%s\n' '{"BackendState":"Running","Self":{"HostName":"desktop","DNSName":"desktop.example.ts.net.","TailscaleIPs":["100.64.0.10","fd7a:115c:a1e0::10"],"ExitNode":false},"Peer":{"node-key":{"HostName":"peer","DNSName":"peer.example.ts.net.","TailscaleIPs":["100.64.0.11"],"Online":true,"ExitNodeOption":true,"ExitNode":true,"OS":"linux","UnlistedField":"fixture-marker"}}}'
      ;;
    *) exit 2 ;;
  esac
  exit 0
fi

printf 'tailscale' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
EOF

chmod +x "$TMP_DIR/bin/powerprofilesctl" "$TMP_DIR/bin/brightnessctl" "$TMP_DIR/bin/hyprctl" \
  "$TMP_DIR/bin/tailscale" "$TMP_DIR/helpers"/*

export CALL_LOG
export PATH="$TMP_DIR/bin:$PATH"
export DESKTOP_HARDWARE_SYSFS_ROOT="$TMP_DIR/sys"
export DESKTOP_HARDWARE_HELPER_DIR="$TMP_DIR/helpers"
export DESKTOP_HARDWARE_STATE_DIR="$TMP_DIR/state"

assert_status() {
  local expected=$1
  shift
  local status

  if "$@" >/dev/null 2>&1; then
    status=0
  else
    status=$?
  fi
  [[ $status -eq $expected ]] || fail "expected status $expected for $*, got $status"
}

assert_envelope() {
  local payload=$1
  jq -e 'type == "object" and (.available | type == "boolean") and (.stale | type == "boolean") and (.updatedAt | type == "number") and (.error == null or (.error | type == "string")) and (.data | type == "object")' <<<"$payload" >/dev/null \
    || fail "invalid hardware state envelope: $payload"
}

state=''

export STUB_BATTERY_PRESENT=no
state=$("$STATE_HELPER" power)
assert_envelope "$state"
jq -e '.available == false and .error == null' <<<"$state" >/dev/null || fail 'missing battery was not reported as unavailable'

export STUB_BATTERY_PRESENT=yes
state=$("$STATE_HELPER" power)
assert_envelope "$state"
jq -e '.available == true and .data.battery.status == "Battery 73%" and .data.profile.active == "balanced"' <<<"$state" >/dev/null \
  || fail 'power state did not compose repository helpers and profiles'

state=$("$STATE_HELPER" monitor)
assert_envelope "$state"
jq -e '.available == true and .data.brightness.available == true and .data.monitors[0].name == "eDP-1" and .data.monitors[0].scale == 1.25 and .data.monitors[1].name == "DP-1" and .data.monitors[1].scale == 1.5' <<<"$state" >/dev/null \
  || fail 'monitor state did not preserve names/scales or brightness capability'

export STUB_TAILSCALE_MODE=missing
state=$("$STATE_HELPER" tailscale)
assert_envelope "$state"
jq -e '.available == false and .error == null' <<<"$state" >/dev/null || fail 'missing Tailscale was not optional'

export STUB_TAILSCALE_MODE=inactive
state=$("$STATE_HELPER" tailscale)
assert_envelope "$state"
jq -e '.available == false and .error == null' <<<"$state" >/dev/null || fail 'inactive Tailscale was not optional'

export STUB_TAILSCALE_MODE=running
state=$("$STATE_HELPER" tailscale)
assert_envelope "$state"
jq -e '.available == true and .data.self.name == "desktop" and .data.self.addresses == ["100.64.0.10"] and .data.peers[0].name == "peer" and .data.peers[0].exitNode == true and (tostring | contains("UnlistedField") | not)' <<<"$state" >/dev/null \
  || fail 'Tailscale state did not expose only safe validated fields'

export STUB_HYPR_MODE=malformed
if state=$("$STATE_HELPER" monitor); then
  fail 'malformed monitor JSON unexpectedly returned success'
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "malformed monitor JSON returned $status instead of runtime failure"
assert_envelope "$state"
jq -e '.stale == true and (.error | length > 0) and .data.monitors[0].name == "eDP-1"' <<<"$state" >/dev/null \
  || fail 'malformed monitor JSON did not return the atomic stale fallback'

assert_status 2 "$ACTION_HELPER" power unknown
assert_status 2 "$ACTION_HELPER" 'power;touch' set-profile balanced
assert_status 2 "$ACTION_HELPER" monitor set-display-brightness '50%;touch'
assert_status 2 "$ACTION_HELPER" tailscale set-exit-node 'peer;touch'

: >"$CALL_LOG"
"$ACTION_HELPER" power set-profile performance
"$ACTION_HELPER" monitor set-display-brightness 42
"$ACTION_HELPER" monitor set-keyboard-brightness cycle
"$ACTION_HELPER" tailscale down
grep -Fxq 'powerprofilesctl set performance' "$CALL_LOG" || fail 'power profile was not passed as direct argv'
grep -Fxq 'brightness-display 42%' "$CALL_LOG" || fail 'display brightness was not passed as direct argv'
grep -Fxq 'brightness-keyboard cycle' "$CALL_LOG" || fail 'keyboard brightness was not passed as direct argv'
grep -Fxq 'tailscale down' "$CALL_LOG" || fail 'Tailscale action was not passed as direct argv'

printf 'PASS: hardware adapters\n'
