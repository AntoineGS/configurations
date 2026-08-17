#!/usr/bin/env bash
# shellcheck disable=SC2250
set -Eeuo pipefail
shopt -s inherit_errexit

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)"
HELPER="$ROOT/Linux/os/helpers/desktop-osd"
DISPLAY_HELPER="$ROOT/Linux/os/helpers/brightness-display"
APPLE_DISPLAY_HELPER="$ROOT/Linux/os/helpers/brightness-display-apple"
KEYBOARD_HELPER="$ROOT/Linux/os/helpers/brightness-keyboard"
AUDIO_SWITCH_HELPER="$ROOT/Linux/os/helpers/cmd-audio-switch"
TMP_DIR="$(mktemp -d)"
CALL_LOG="$TMP_DIR/mutations.log"
IPC_LOG="$TMP_DIR/ipc.log"
PAYLOAD_FILE="$TMP_DIR/payload.json"
LOCALE_LOG="$TMP_DIR/locales.log"
SYSFS_ROOT="$TMP_DIR/sys"
BACKLIGHT_ROOT="$TMP_DIR/backlight"
STATE_DIR="$TMP_DIR/state"
ASD_VALUE_FILE="$STATE_DIR/asd-value"
AUDIO_DEFAULT_FILE="$STATE_DIR/audio-default"
AUDIO_SINKS_FILE="$STATE_DIR/audio-sinks.json"
AUDIO_SINKS_AFTER_FILE="$STATE_DIR/audio-sinks-after.json"
AUDIO_LIST_COUNT_FILE="$STATE_DIR/audio-list-count"

active_route_files=(
  "$ROOT/Linux/hypr/bindings/media.lua"
  "$DISPLAY_HELPER"
  "$APPLE_DISPLAY_HELPER"
  "$KEYBOARD_HELPER"
  "$AUDIO_SWITCH_HELPER"
  "$HELPER"
)

trap 'rm -rf -- "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$HELPER" ]] || fail "$HELPER must exist and be executable"
command -v jq >/dev/null 2>&1 || fail 'jq is required'

mkdir -p "$TMP_DIR/bin" "$SYSFS_ROOT/class/leds/thinkpad::kbd_backlight" \
  "$BACKLIGHT_ROOT/class/backlight/intel_backlight" "$STATE_DIR"
printf '1\n' >"$SYSFS_ROOT/class/leds/thinkpad::kbd_backlight/brightness"
printf '3\n' >"$SYSFS_ROOT/class/leds/thinkpad::kbd_backlight/max_brightness"

SINK_VOLUME_FILE="$STATE_DIR/sink-volume"
SINK_MUTED_FILE="$STATE_DIR/sink-muted"
SOURCE_VOLUME_FILE="$STATE_DIR/source-volume"
SOURCE_MUTED_FILE="$STATE_DIR/source-muted"
DISPLAY_CURRENT_FILE="$STATE_DIR/display-current"
DISPLAY_MAX_FILE="$STATE_DIR/display-max"
KEYBOARD_CURRENT_FILE="$STATE_DIR/keyboard-current"
KEYBOARD_MAX_FILE="$STATE_DIR/keyboard-max"

export CALL_LOG IPC_LOG PAYLOAD_FILE LOCALE_LOG
export SINK_VOLUME_FILE SINK_MUTED_FILE SOURCE_VOLUME_FILE SOURCE_MUTED_FILE
export DISPLAY_CURRENT_FILE DISPLAY_MAX_FILE KEYBOARD_CURRENT_FILE KEYBOARD_MAX_FILE
export ASD_VALUE_FILE AUDIO_DEFAULT_FILE AUDIO_SINKS_FILE AUDIO_SINKS_AFTER_FILE AUDIO_LIST_COUNT_FILE
export BRIGHTNESS_DISPLAY_SYSFS_ROOT="$BACKLIGHT_ROOT"

cat >"$TMP_DIR/bin/wpctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "${LC_ALL:-unset}" >>"$LOCALE_LOG"
[[ ${LC_ALL:-} == C ]] || exit 125

log_mutation() {
  printf 'wpctl' >>"$CALL_LOG"
  printf ' %q' "$@" >>"$CALL_LOG"
  printf '\n' >>"$CALL_LOG"
}

volume_file_for() {
  case "$1" in
    @DEFAULT_AUDIO_SINK@) printf '%s\n' "$SINK_VOLUME_FILE" ;;
    @DEFAULT_AUDIO_SOURCE@) printf '%s\n' "$SOURCE_VOLUME_FILE" ;;
    *) return 1 ;;
  esac
}

muted_file_for() {
  case "$1" in
    @DEFAULT_AUDIO_SINK@) printf '%s\n' "$SINK_MUTED_FILE" ;;
    @DEFAULT_AUDIO_SOURCE@) printf '%s\n' "$SOURCE_MUTED_FILE" ;;
    *) return 1 ;;
  esac
}

print_volume() {
  local target=$1 volume_file muted_file volume scalar muted_suffix=''

  volume_file=$(volume_file_for "$target")
  muted_file=$(muted_file_for "$target")
  volume=$(<"$volume_file")
  if [[ -n ${STUB_VOLUME_SCALAR:-} ]]; then
    scalar=$STUB_VOLUME_SCALAR
  elif (( volume >= 100 )); then
    scalar='1.00'
  else
    printf -v scalar '0.%02d' "$volume"
  fi
  if [[ $(<"$muted_file") == 1 ]]; then
    muted_suffix=' [MUTED]'
  fi
  printf 'Volume: %s%s\n' "$scalar" "$muted_suffix"
}

(( $# >= 1 )) || exit 2

case "$1" in
  get-volume)
    (( $# == 2 )) || exit 2
    if [[ ${STUB_READBACK_FAILURE:-} == wpctl ]]; then
      exit 1
    fi
    print_volume "$2"
    ;;
  set-volume)
    (( $# >= 3 )) || exit 2
    target=$2
    step=$3
    volume_file=$(volume_file_for "$target")
    [[ $step =~ ^([0-9]+)%([+-])$ ]] || exit 2
    log_mutation "$@"
    if [[ ${STUB_MUTATION_FAILURE:-} == wpctl ]]; then
      exit 1
    fi
    volume=$(<"$volume_file")
    amount=${BASH_REMATCH[1]}
    if [[ ${BASH_REMATCH[2]} == + ]]; then
      volume=$((volume + amount))
    else
      volume=$((volume - amount))
    fi
    (( volume < 0 )) && volume=0
    (( volume > 100 )) && volume=100
    printf '%s\n' "$volume" >"$volume_file"
    ;;
  set-mute)
    [[ $# -eq 3 && $3 == toggle ]] || exit 2
    muted_file=$(muted_file_for "$2")
    log_mutation "$@"
    if [[ ${STUB_MUTATION_FAILURE:-} == wpctl ]]; then
      exit 1
    fi
    if [[ $(<"$muted_file") == 1 ]]; then
      printf '0\n' >"$muted_file"
    else
      printf '1\n' >"$muted_file"
    fi
    ;;
  status)
    printf '%s\n' "${STUB_WPCTL_STATUS:-}"
    ;;
  *)
    exit 2
    ;;
esac
EOF

cat >"$TMP_DIR/bin/brightnessctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "${LC_ALL:-unset}" >>"$LOCALE_LOG"
[[ ${LC_ALL:-} == C ]] || exit 125

log_mutation() {
  printf 'brightnessctl' >>"$CALL_LOG"
  printf ' %q' "$@" >>"$CALL_LOG"
  printf '\n' >>"$CALL_LOG"
}

original=("$@")
device=''

while (($# > 0)); do
  case "$1" in
    -d)
      (( $# >= 2 )) || exit 2
      device=$2
      shift 2
      ;;
    -m)
      if [[ ${STUB_READBACK_FAILURE:-} == brightnessctl ]]; then
        exit 1
      fi
      if [[ -n ${STUB_BRIGHTNESS_OUTPUT:-} ]]; then
        printf '%s\n' "$STUB_BRIGHTNESS_OUTPUT"
        exit 0
      fi
      if [[ -n $device && $device == ${STUB_DISPLAY_DEVICE:-intel_backlight} ]]; then
        current=$(<"$DISPLAY_CURRENT_FILE")
        maximum=$(<"$DISPLAY_MAX_FILE")
        percent=$((current * 100 / maximum))
        printf '%s,%s,%s,%s,%s%%\n' "$device" backlight "$current" "$maximum" "$percent"
      elif [[ -n $device ]]; then
        current=$(<"$KEYBOARD_CURRENT_FILE")
        maximum=$(<"$KEYBOARD_MAX_FILE")
        percent=$((current * 100 / maximum))
        printf '%s,%s,%s,%s,%s%%\n' "$device" leds "$current" "$maximum" "$percent"
      else
        current=$(<"$DISPLAY_CURRENT_FILE")
        maximum=$(<"$DISPLAY_MAX_FILE")
        percent=$((current * 100 / maximum))
        printf '%s,%s,%s,%s,%s%%\n' intel_backlight backlight "$current" "$maximum" "$percent"
      fi
      exit 0
      ;;
    set)
      (( $# == 2 )) || exit 2
      operation=$2
      log_mutation "${original[@]}"
      if [[ ${STUB_MUTATION_FAILURE:-} == brightnessctl ]]; then
        exit 1
      fi
      if [[ -n $device && $device == ${STUB_DISPLAY_DEVICE:-intel_backlight} ]]; then
        current_file=$DISPLAY_CURRENT_FILE
        maximum=$(<"$DISPLAY_MAX_FILE")
        if [[ $operation =~ ^[0-9]+%$ ]]; then
          current=${operation%\%}
        elif [[ $operation =~ ^\+([0-9]+)%$ ]]; then
          current=$(( $(<"$current_file") + BASH_REMATCH[1] ))
        elif [[ $operation =~ ^-([0-9]+)%$ ]]; then
          current=$(( $(<"$current_file") - BASH_REMATCH[1] ))
        else
          exit 2
        fi
        (( current < 0 )) && current=0
        (( current > maximum )) && current=$maximum
      elif [[ -n $device ]]; then
        current_file=$KEYBOARD_CURRENT_FILE
        maximum=$(<"$KEYBOARD_MAX_FILE")
        if [[ $operation =~ ^[0-9]+$ ]]; then
          current=$operation
        elif [[ $operation =~ ^\+([0-9]+)$ ]]; then
          current=$(( $(<"$current_file") + BASH_REMATCH[1] ))
        elif [[ $operation =~ ^-([0-9]+)$ ]]; then
          current=$(( $(<"$current_file") - BASH_REMATCH[1] ))
        else
          exit 2
        fi
        (( current < 0 )) && current=0
        (( current > maximum )) && current=$maximum
      else
        current_file=$DISPLAY_CURRENT_FILE
        maximum=$(<"$DISPLAY_MAX_FILE")
        [[ $operation =~ ^([0-9]+)%([+-])$ ]] || exit 2
        current=$(<"$current_file")
        amount=${BASH_REMATCH[1]}
        if [[ ${BASH_REMATCH[2]} == + ]]; then
          current=$((current + amount))
        else
          current=$((current - amount))
        fi
        (( current < 0 )) && current=0
        (( current > maximum )) && current=$maximum
      fi
      printf '%s\n' "$current" >"$current_file"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

exit 2
EOF

cat >"$TMP_DIR/bin/playerctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "${LC_ALL:-unset}" >>"$LOCALE_LOG"
[[ ${LC_ALL:-} == C ]] || exit 125

printf 'playerctl' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
if [[ ${STUB_MUTATION_FAILURE:-} == playerctl ]]; then
  exit 1
fi
case "$*" in
  next|previous|play-pause) exit 0 ;;
  *) exit 2 ;;
esac
EOF

cat >"$TMP_DIR/bin/desktop-osd" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'desktop-osd' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
if [[ ${STUB_DESKTOP_OSD_EXIT:-0} != 0 ]]; then
  exit "$STUB_DESKTOP_OSD_EXIT"
fi
EOF

cat >"$TMP_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

(( $# >= 1 )) || exit 2
if [[ $1 == asdcontrol ]]; then
  shift
  exec asdcontrol "$@"
fi
exec "$@"
EOF

cat >"$TMP_DIR/bin/asdcontrol" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${1:-} == --detect ]]; then
  if [[ ${STUB_ASD_NO_DEVICE:-0} == 1 ]]; then
    exit 1
  fi
  printf '/dev/usb/hiddev0: Apple Studio Display\n'
  exit 0
fi

device=${1:-}
if [[ ${2:-} == -- ]]; then
  [[ -n $device && -n ${3:-} ]] || exit 2
  printf 'asdcontrol %q -- %q\n' "$device" "$3" >>"$CALL_LOG"
  [[ ${STUB_ASD_MUTATION_FAILURE:-0} == 1 ]] && exit 1
  printf '%s\n' "${STUB_ASD_VALUE:-30000}" >"$ASD_VALUE_FILE"
  exit 0
fi

[[ -n $device ]] || exit 2
printf 'BRIGHTNESS=%s\n' "$(<"$ASD_VALUE_FILE")"
EOF

cat >"$TMP_DIR/bin/pactl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}" in
  -f)
    [[ ${2:-} == json && ${3:-} == list && ${4:-} == sinks ]] || exit 2
    list_count=$(<"$AUDIO_LIST_COUNT_FILE")
    list_count=$((list_count + 1))
    printf '%s\n' "$list_count" >"$AUDIO_LIST_COUNT_FILE"
    if (( list_count > 1 )) && [[ -s $AUDIO_SINKS_AFTER_FILE ]]; then
      cat "$AUDIO_SINKS_AFTER_FILE"
    else
      cat "$AUDIO_SINKS_FILE"
    fi
    ;;
  get-default-sink)
    cat "$AUDIO_DEFAULT_FILE"
    ;;
  set-default-sink)
    [[ $# -eq 2 ]] || exit 2
    printf 'pactl set-default-sink %q\n' "$2" >>"$CALL_LOG"
    [[ ${STUB_PACTL_MUTATION_FAILURE:-0} == 1 ]] && exit 1
    printf '%s\n' "$2" >"$AUDIO_DEFAULT_FILE"
    ;;
  *)
    exit 2
    ;;
esac
EOF

cat >"$TMP_DIR/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ $* == 'monitors -j' ]] || exit 2
printf '%s\n' '[{"name":"DP-1","focused":true}]'
EOF

cat >"$TMP_DIR/bin/desktop-shell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "${LC_ALL:-unset}" >>"$LOCALE_LOG"
[[ ${LC_ALL:-} == C ]] || exit 125

(( $# == 4 )) || exit 2
[[ $1 == call && $2 == desktop.osd && $3 == show ]] || exit 2
printf 'desktop-shell call desktop.osd show\n' >>"$IPC_LOG"
printf '%s\n' "$4" >"$PAYLOAD_FILE"
if [[ ${STUB_IPC_EXIT:-0} != 0 ]]; then
  exit "$STUB_IPC_EXIT"
fi
if [[ ${STUB_IPC_FAILURE:-} == 1 ]]; then
  exit 1
fi
printf '%s\n' "${STUB_IPC_RESPONSE:-ok}"
EOF

chmod +x "$TMP_DIR/bin/wpctl" "$TMP_DIR/bin/brightnessctl" "$TMP_DIR/bin/playerctl" \
  "$TMP_DIR/bin/desktop-osd" "$TMP_DIR/bin/sudo" "$TMP_DIR/bin/asdcontrol" \
  "$TMP_DIR/bin/pactl" "$TMP_DIR/bin/hyprctl" "$TMP_DIR/bin/desktop-shell"

export PATH="$TMP_DIR/bin:$PATH"
export DESKTOP_OSD_SYSFS_ROOT="$SYSFS_ROOT"

reset_fixture() {
  printf '42\n' >"$SINK_VOLUME_FILE"
  printf '0\n' >"$SINK_MUTED_FILE"
  printf '61\n' >"$SOURCE_VOLUME_FILE"
  printf '0\n' >"$SOURCE_MUTED_FILE"
  printf '50\n' >"$DISPLAY_CURRENT_FILE"
  printf '100\n' >"$DISPLAY_MAX_FILE"
  printf '1\n' >"$KEYBOARD_CURRENT_FILE"
  printf '3\n' >"$KEYBOARD_MAX_FILE"
  printf '30000\n' >"$ASD_VALUE_FILE"
  printf 'sink-a\n' >"$AUDIO_DEFAULT_FILE"
  printf '%s\n' '[]' >"$AUDIO_SINKS_FILE"
  : >"$AUDIO_SINKS_AFTER_FILE"
  printf '0\n' >"$AUDIO_LIST_COUNT_FILE"
  : >"$CALL_LOG"
  : >"$IPC_LOG"
  : >"$PAYLOAD_FILE"
  : >"$LOCALE_LOG"
  export STUB_MUTATION_FAILURE=''
  export STUB_READBACK_FAILURE=''
  export STUB_VOLUME_SCALAR=''
  export STUB_BRIGHTNESS_OUTPUT=''
  export STUB_IPC_FAILURE=''
  export STUB_IPC_RESPONSE='ok'
  export STUB_IPC_EXIT=0
  export STUB_ASD_NO_DEVICE=0
  export STUB_ASD_MUTATION_FAILURE=0
  export STUB_ASD_VALUE=30000
  export STUB_PACTL_MUTATION_FAILURE=0
  export STUB_DESKTOP_OSD_EXIT=0
  export STUB_WPCTL_STATUS=''
}

run_helper() {
  local status

  if "$HELPER" "$@" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
    status=0
  else
    status=$?
  fi
  LAST_STATUS=$status
  LAST_STDERR=$(<"$TMP_DIR/stderr")
}

run_specialized() {
  local helper=$1
  shift
  local status

  if "$helper" "$@" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
    status=0
  else
    status=$?
  fi
  LAST_STATUS=$status
  LAST_STDERR=$(<"$TMP_DIR/stderr")
}

assert_status() {
  local expected=$1
  [[ $LAST_STATUS -eq $expected ]] || fail "expected exit $expected, got $LAST_STATUS: $LAST_STDERR"
}

assert_mutation() {
  local expected=$1 actual
  actual=$(<"$CALL_LOG")
  [[ $actual == "$expected" ]] || fail "mutation mismatch: expected <$expected>, got <$actual>"
}

assert_one_mutation() {
  local -a mutations=()
  mapfile -t mutations <"$CALL_LOG"
  (( ${#mutations[@]} == 1 )) || fail "expected exactly one mutation, got ${#mutations[@]}"
}

assert_no_mutation() {
  [[ ! -s "$CALL_LOG" ]] || fail "unexpected mutation: $(<"$CALL_LOG")"
}

assert_no_ipc() {
  [[ ! -s "$IPC_LOG" ]] || fail 'unexpected OSD IPC delivery'
  [[ ! -s "$PAYLOAD_FILE" ]] || fail 'unexpected OSD payload'
}

assert_no_legacy_routes() {
  local file

  for file in "${active_route_files[@]}"; do
    [[ -f $file ]] || fail "active route file is missing: $file"
    if grep -Eiq 'swayosd' "$file"; then
      fail "legacy SwayOSD route remains active in $file"
    fi
  done
}

assert_no_legacy_routes

assert_payload() {
  local expression=$1
  jq -e "$expression" "$PAYLOAD_FILE" >/dev/null || fail "payload assertion failed: $(<"$PAYLOAD_FILE")"
}

assert_pinned_locale() {
  local locale

  [[ -s "$LOCALE_LOG" ]] || fail 'external command locale was not recorded'
  while IFS= read -r locale; do
    [[ $locale == C ]] || fail "external command locale was not pinned: $locale"
  done <"$LOCALE_LOG"
}

write_audio_transition_fixture() {
  printf '%s\n' '[
  {"name":"sink-a","description":"Built-in Audio","ports":[],"properties":{},"volume":{"front-left":{"value_percent":"50%"}},"mute":false},
  {"name":"sink-b","description":"Before default","ports":[],"properties":{},"volume":{"front-left":{"value_percent":"20%"}},"mute":false}
]' >"$AUDIO_SINKS_FILE"
  printf '%s\n' '[
  {"name":"sink-a","description":"Built-in Audio","ports":[],"properties":{},"volume":{"front-left":{"value_percent":"50%"}},"mute":false},
  {"name":"sink-b","description":"After default","ports":[],"properties":{},"volume":{"front-left":{"value_percent":"5%"}},"mute":true}
]' >"$AUDIO_SINKS_AFTER_FILE"
}

reset_fixture
run_helper volume-up 5
assert_status 0
assert_mutation 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ --limit 1'
assert_payload '.icon == "volume-medium" and .message == "" and .value == 47 and .max == 100 and .progressText == "47%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'
assert_pinned_locale

reset_fixture
export STUB_VOLUME_SCALAR=0.07
run_helper volume-up 5
assert_status 0
assert_payload '.icon == "volume-low" and .message == "" and .value == 7 and .max == 100 and .progressText == "7%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
export STUB_VOLUME_SCALAR=1.25
run_helper volume-up 5
assert_status 0
assert_payload '.icon == "volume-high" and .message == "" and .value == 100 and .max == 100 and .progressText == "100%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
run_helper volume-down 5
assert_status 0
assert_mutation 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-'
assert_payload '.icon == "volume-medium" and .message == "" and .value == 37 and .max == 100 and .progressText == "37%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
run_helper volume-toggle
assert_status 0
assert_mutation 'wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle'
assert_payload '.icon == "volume-muted" and .message == "" and .value == 42 and .max == 100 and .progressText == "42%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
run_helper mic-toggle
assert_status 0
assert_mutation 'wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle'
assert_payload '.icon == "microphone-muted" and .message == "" and .value == 61 and .max == 100 and .progressText == "61%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
run_helper brightness-up 5
assert_status 0
assert_mutation 'brightnessctl set 5%+'
assert_payload '.icon == "brightness" and .message == "" and .value == 55 and .max == 100 and .progressText == "55%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
run_helper brightness-down 5
assert_status 0
assert_mutation 'brightnessctl set 5%-'
assert_payload '.icon == "brightness" and .message == "" and .value == 45 and .max == 100 and .progressText == "45%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
run_helper keyboard-up
assert_status 0
assert_mutation 'brightnessctl -d thinkpad::kbd_backlight set 2'
assert_payload '.icon == "keyboard" and .message == "" and .value == 2 and .max == 3 and .progressText == "66%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
run_helper keyboard-down
assert_status 0
assert_mutation 'brightnessctl -d thinkpad::kbd_backlight set 0'
assert_payload '.icon == "keyboard" and .message == "" and .value == 0 and .max == 3 and .progressText == "0%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
printf '3\n' >"$KEYBOARD_CURRENT_FILE"
run_helper keyboard-cycle
assert_status 0
assert_mutation 'brightnessctl -d thinkpad::kbd_backlight set 0'
assert_payload '.icon == "keyboard" and .message == "" and .value == 0 and .max == 3 and .progressText == "0%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
run_helper media-next
assert_status 0
assert_mutation 'playerctl next'
assert_payload '.icon == "media-next" and .message == "Next track" and (.value == null) and (.max == null) and (.progressText == null) and (keys | sort) == ["icon", "message"]'

reset_fixture
run_helper media-previous
assert_status 0
assert_mutation 'playerctl previous'
assert_payload '.icon == "media-previous" and .message == "Previous track" and (.value == null) and (.max == null) and (.progressText == null) and (keys | sort) == ["icon", "message"]'

reset_fixture
run_helper media-play-pause
assert_status 0
assert_mutation 'playerctl play-pause'
assert_payload '.icon == "media" and .message == "Play/Pause" and (.value == null) and (.max == null) and (.progressText == null) and (keys | sort) == ["icon", "message"]'

invalid_cases=(
  'volume-up'
  'volume-up 0'
  'volume-up 21'
  'volume-up 1.5'
  'volume-up 024'
  'volume-up 999999999999999999999999999999999999999999999999999999999999999999'
  'brightness-up'
  'volume-toggle extra'
  'unknown-operation'
)
for invalid_args in "${invalid_cases[@]}"; do
  reset_fixture
  read -r -a argv <<<"$invalid_args"
  run_helper "${argv[@]}"
  assert_status 2
  assert_no_mutation
  assert_no_ipc
done

reset_fixture
run_helper ''
assert_status 2
assert_no_mutation
assert_no_ipc

reset_fixture
run_helper volume-up ''
assert_status 2
assert_no_mutation
assert_no_ipc

reset_fixture
export STUB_MUTATION_FAILURE=wpctl
run_helper volume-up 5
assert_status 1
assert_no_ipc

reset_fixture
export STUB_MUTATION_FAILURE=brightnessctl
run_helper brightness-up 5
assert_status 1
assert_no_ipc

reset_fixture
export STUB_MUTATION_FAILURE=playerctl
run_helper media-next
assert_status 1
assert_no_ipc

reset_fixture
export STUB_READBACK_FAILURE=wpctl
run_helper volume-up 5
assert_status 1
assert_one_mutation
assert_no_ipc

reset_fixture
export STUB_READBACK_FAILURE=brightnessctl
run_helper brightness-up 5
assert_status 1
assert_one_mutation
assert_no_ipc

reset_fixture
export STUB_BRIGHTNESS_OUTPUT='intel_backlight,backlight,120,100,80%'
run_helper brightness-up 5
assert_status 1
assert_one_mutation
assert_no_ipc

reset_fixture
export DESKTOP_OSD_SYSFS_ROOT="$TMP_DIR/no-keyboard-sys"
run_helper keyboard-up
assert_status 1
assert_no_mutation
assert_no_ipc
export DESKTOP_OSD_SYSFS_ROOT="$SYSFS_ROOT"

reset_fixture
export STUB_IPC_FAILURE=1
run_helper volume-up 5
assert_status 3
assert_one_mutation
[[ -s "$IPC_LOG" ]] || fail 'IPC was not attempted after a successful mutation'
[[ -s "$PAYLOAD_FILE" ]] || fail 'payload was not built after a successful mutation'

reset_fixture
export STUB_IPC_RESPONSE=not-ok
run_helper media-next
assert_status 3
assert_mutation 'playerctl next'
[[ -s "$IPC_LOG" ]] || fail 'IPC response was not validated'

reset_fixture
run_specialized "$DISPLAY_HELPER" +5%
assert_status 0
assert_mutation 'brightnessctl -d intel_backlight set +5%'
assert_payload '.icon == "brightness" and .message == "" and .value == 55 and .max == 100 and .progressText == "55%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
run_specialized "$DISPLAY_HELPER" 42%
assert_status 0
assert_mutation 'brightnessctl -d intel_backlight set 42%'
assert_payload '.icon == "brightness" and .message == "" and .value == 42 and .max == 100 and .progressText == "42%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

for direction in up down cycle; do
  reset_fixture
  run_specialized "$KEYBOARD_HELPER" "$direction"
  assert_status 0
  assert_mutation "desktop-osd keyboard-$direction"
done

reset_fixture
export STUB_ASD_NO_DEVICE=1
run_specialized "$APPLE_DISPLAY_HELPER" +5000
assert_status 1
assert_no_mutation
assert_no_ipc

reset_fixture
run_specialized "$APPLE_DISPLAY_HELPER" +5000
assert_status 0
assert_mutation 'asdcontrol /dev/usb/hiddev0 -- +5000'
assert_payload '.icon == "brightness" and .message == "" and .value == 50 and .max == 100 and .progressText == "50%" and (keys | sort) == ["icon", "max", "message", "progressText", "value"]'

reset_fixture
export STUB_IPC_EXIT=3
run_specialized "$APPLE_DISPLAY_HELPER" +5000
assert_status 0
assert_mutation 'asdcontrol /dev/usb/hiddev0 -- +5000'
[[ -s "$IPC_LOG" ]] || fail 'Apple display feedback was not attempted'

reset_fixture
export STUB_IPC_RESPONSE=not-ok
run_specialized "$APPLE_DISPLAY_HELPER" +5000
assert_status 1
assert_mutation 'asdcontrol /dev/usb/hiddev0 -- +5000'

reset_fixture
export STUB_IPC_RESPONSE=not-ok
run_specialized "$DISPLAY_HELPER" +5%
assert_status 1
assert_mutation 'brightnessctl -d intel_backlight set +5%'

reset_fixture
export STUB_IPC_EXIT=3
run_specialized "$DISPLAY_HELPER" +5%
assert_status 3
assert_mutation 'brightnessctl -d intel_backlight set +5%'

reset_fixture
printf '%s\n' '[]' >"$AUDIO_SINKS_FILE"
run_specialized "$AUDIO_SWITCH_HELPER"
assert_status 1
assert_no_mutation
assert_payload '.icon == "volume-muted" and .message == "No audio devices found" and (keys | sort) == ["icon", "message"]'

reset_fixture
printf '%s\n' '[
  {"name":"sink-a","description":"Built-in Audio","ports":[],"properties":{},"volume":{"front-left":{"value_percent":"50%"}},"mute":false},
  {"name":"sink-b","description":"Headphones","ports":[],"properties":{},"volume":{"front-left":{"value_percent":"20%"}},"mute":true}
]' >"$AUDIO_SINKS_FILE"
run_specialized "$AUDIO_SWITCH_HELPER"
assert_status 0
assert_mutation 'pactl set-default-sink sink-b'
assert_payload '.icon == "volume-muted" and .message == "Headphones" and (keys | sort) == ["icon", "message"]'

reset_fixture
printf '%s\n' '[
  {"name":"sink-a","description":"Built-in Audio","ports":[],"properties":{},"volume":{"front-left":{"value_percent":"50%"}},"mute":false},
  {"name":"sink-b","description":"Headphones","ports":[],"properties":{},"volume":{"front-left":{"value_percent":"80%"}},"mute":false}
]' >"$AUDIO_SINKS_FILE"
export STUB_IPC_EXIT=3
run_specialized "$AUDIO_SWITCH_HELPER"
assert_status 0
assert_mutation 'pactl set-default-sink sink-b'
[[ -s "$IPC_LOG" ]] || fail 'audio switch feedback was not attempted'

reset_fixture
write_audio_transition_fixture
run_specialized "$AUDIO_SWITCH_HELPER"
assert_status 0
assert_mutation 'pactl set-default-sink sink-b'
assert_payload '.icon == "volume-muted" and .message == "After default" and (keys | sort) == ["icon", "message"]'

reset_fixture
write_audio_transition_fixture
export STUB_IPC_RESPONSE=not-ok
run_specialized "$AUDIO_SWITCH_HELPER"
assert_status 1
assert_mutation 'pactl set-default-sink sink-b'
assert_payload '.icon == "volume-muted" and .message == "After default" and (keys | sort) == ["icon", "message"]'

reset_fixture
write_audio_transition_fixture
export STUB_IPC_EXIT=1
run_specialized "$AUDIO_SWITCH_HELPER"
assert_status 1
assert_mutation 'pactl set-default-sink sink-b'
assert_payload '.icon == "volume-muted" and .message == "After default" and (keys | sort) == ["icon", "message"]'

reset_fixture
write_audio_transition_fixture
export STUB_IPC_EXIT=3
run_specialized "$AUDIO_SWITCH_HELPER"
assert_status 0
assert_mutation 'pactl set-default-sink sink-b'
assert_payload '.icon == "volume-muted" and .message == "After default" and (keys | sort) == ["icon", "message"]'

for missing_description in null '"null"' '"(null)"'; do
  reset_fixture
  printf '%s\n' "[\
  {\"name\":\"sink-a\",\"description\":\"Built-in Audio\",\"ports\":[],\"properties\":{},\"volume\":{\"front-left\":{\"value_percent\":\"50%\"}},\"mute\":false},\
  {\"name\":\"sink-b\",\"description\":$missing_description,\"ports\":[],\"properties\":{\"device.id\":\"2\",\"object.id\":\"202\"},\"volume\":{\"front-left\":{\"value_percent\":\"20%\"}},\"mute\":false}\
]" >"$AUDIO_SINKS_FILE"
  printf '%s\n' "[\
  {\"name\":\"sink-a\",\"description\":\"Built-in Audio\",\"ports\":[],\"properties\":{},\"volume\":{\"front-left\":{\"value_percent\":\"50%\"}},\"mute\":false},\
  {\"name\":\"sink-b\",\"description\":$missing_description,\"ports\":[],\"properties\":{\"device.id\":\"2\",\"object.id\":\"202\"},\"volume\":{\"front-left\":{\"value_percent\":\"20%\"}},\"mute\":false}\
]" >"$AUDIO_SINKS_AFTER_FILE"
  export STUB_WPCTL_STATUS=$'  12. Wrong Device [alsa]\n  2. Correct Device [alsa]'
  run_specialized "$AUDIO_SWITCH_HELPER"
  assert_status 0
  assert_mutation 'pactl set-default-sink sink-b'
  assert_payload '.icon == "volume-low" and .message == "Correct Device" and (keys | sort) == ["icon", "message"]'
done

printf 'PASS: desktop OSD helper behavior\n'
