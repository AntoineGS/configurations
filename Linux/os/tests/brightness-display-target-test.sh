#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
action="$repo_root/Linux/os/helpers/desktop-hardware-action"
display_helper="$repo_root/Linux/os/helpers/brightness-display"
brightness_helper="$repo_root/Linux/os/helpers/desktop-monitor-brightness"
state_helper="$repo_root/Linux/os/helpers/desktop-hardware-state"
fixture_root="$repo_root/Linux/os/tests/fixtures/monitor-brightness"
test_root=$(mktemp -d)
bin="$test_root/bin"
helper_dir="$test_root/helpers"
sysfs_root="$test_root/sys"
home_dir="$test_root/home"
state_dir="$test_root/state"
ddc_values="$test_root/ddc-values"
ddc_log="$test_root/ddc.log"
brightness_log="$test_root/brightness.log"
osd_file="$test_root/osd.json"
hypr_log="$test_root/hyprctl.log"
system_path=$PATH

trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

fixture_hex() {
  local value

  value=$(<"$fixture_root/$1.edid.hex")
  value=${value//[[:space:]]/}
  printf '%s\n' "$value"
}

hex_to_binary() {
  local source=$1
  local destination=$2
  local hex
  local byte

  hex=$(<"$source")
  hex=${hex//[[:space:]]/}
  [[ $hex =~ ^[[:xdigit:]]{256}$ ]] || fail "invalid EDID fixture: $source"
  : >"$destination"
  for ((byte = 0; byte < ${#hex}; byte += 2)); do
    printf '%b' "\\x${hex:byte:2}" >>"$destination"
  done
}

write_fake_tools() {
  cat >"$bin/ddcutil" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

{
  printf '%q ' "$@"
  printf '\n'
} >>"${DDC_LOG:?}"

selector_kind=''
selector=''
while (($# > 0)); do
  case $1 in
    --bus|--edid)
      selector_kind=${1#--}
      selector=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

[[ -n $selector_kind && -n $selector ]] || exit 64
key="$selector_kind-$selector"
if [[ $selector_kind == edid ]]; then
  key="$selector_kind-${selector:0:24}"
fi
value_file="${DDC_VALUES:?}/$key.value"
maximum_file="${DDC_VALUES:?}/$key.maximum"

case ${1:-} in
  getvcp)
    [[ ${2:-} == 10 && ${3:-} == --terse ]] || exit 64
    [[ -r $value_file && -r $maximum_file ]] || exit 1
    printf 'VCP 10 C %s %s\n' "$(<"$value_file")" "$(<"$maximum_file")"
    ;;
  setvcp)
    [[ ${2:-} == 10 && ${3:-} =~ ^[0-9]+$ ]] || exit 64
    printf '%s\n' "$3" >"$value_file"
    ;;
  *)
    exit 64
    ;;
esac
EOF

  cat >"$bin/brightnessctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

{
  printf '%q ' "$@"
  printf '\n'
} >>"${BRIGHTNESS_LOG:?}"

device=''
operation=''
value=''
while (($# > 0)); do
  case $1 in
    -d)
      device=$2
      shift 2
      ;;
    -m)
      operation=read
      shift
      ;;
    set)
      operation=set
      value=$2
      shift 2
      ;;
    *)
      exit 64
      ;;
  esac
done

[[ $device =~ ^[[:alnum:]_.+-]+$ ]] || exit 64
brightness_file="${BRIGHTNESS_SYSFS_ROOT:?}/class/backlight/$device/brightness"
maximum_file="${BRIGHTNESS_SYSFS_ROOT:?}/class/backlight/$device/max_brightness"
current=$(<"$brightness_file")
maximum=$(<"$maximum_file")
case $operation in
  read)
    percent=$((current * 100 / maximum))
    printf '%s,raw,%s,%s,%s%%\n' "$device" "$current" "$maximum" "$percent"
    ;;
  set)
    if [[ $value =~ ^([+-])([0-9]+)%$ ]]; then
      delta=$((maximum * ${BASH_REMATCH[2]} / 100))
      if [[ ${BASH_REMATCH[1]} == + ]]; then
        value=$((current + delta))
      else
        value=$((current - delta))
      fi
    elif [[ $value =~ ^([0-9]+)%$ ]]; then
      value=$((maximum * ${BASH_REMATCH[1]} / 100))
    else
      exit 64
    fi
    ((value < 0)) && value=0
    ((value > maximum)) && value=$maximum
    printf '%s\n' "$value" >"$brightness_file"
    ;;
  *)
    exit 64
    ;;
esac
EOF

  cat >"$bin/desktop-shell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${1:-} == call && ${2:-} == desktop.osd && ${3:-} == show ]] || exit 64
printf '%s\n' "${4:?}" >"${OSD_FILE:?}"
if [[ ${OSD_MODE:-normal} == fail ]]; then
  exit 1
fi
printf '%s\n' ok
EOF

  cat >"$bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"${HYPR_LOG:?}"
[[ $* == '-j monitors all' ]] || exit 64
printf '%s\n' "${HYPR_MONITORS:?}"
EOF

  chmod 0755 "$bin/ddcutil" "$bin/brightnessctl" "$bin/desktop-shell" "$bin/hyprctl"
}

reset_fixture() {
  rm -rf -- "$sysfs_root" "$home_dir" "$state_dir" "$ddc_values"
  mkdir -p -- "$bin" "$helper_dir" "$sysfs_root/class/drm" "$sysfs_root/class/backlight" \
    "$home_dir" "$state_dir" "$ddc_values"
  : >"$ddc_log"
  : >"$brightness_log"
  : >"$hypr_log"
  rm -f -- "$osd_file"
  OSD_MODE=normal
  write_fake_tools
}

make_connector() {
  local connector=$1
  local fixture=$2
  local bus=$3
  local connector_dir="$sysfs_root/class/drm/card0-$connector"

  mkdir -p -- "$connector_dir" "$sysfs_root/i2c-$bus"
  printf '%s\n' connected >"$connector_dir/status"
  hex_to_binary "$fixture_root/$fixture.edid.hex" "$connector_dir/edid"
  ln -s -- "$sysfs_root/i2c-$bus" "$connector_dir/ddc"
}

make_backlight() {
  local device=$1
  local current=$2
  local maximum=$3
  local device_dir="$sysfs_root/class/backlight/$device"

  mkdir -p -- "$device_dir"
  printf '%s\n' "$current" >"$device_dir/brightness"
  printf '%s\n' "$maximum" >"$device_dir/max_brightness"
  mkdir -p -- "$sysfs_root/class/drm/card0-eDP-1"
  ln -s -- "$device_dir" "$sysfs_root/class/drm/card0-eDP-1/backlight"
}

make_ddc_value() {
  local bus=$1
  local current=$2
  local maximum=$3

  printf '%s\n' "$current" >"$ddc_values/bus-$bus.value"
  printf '%s\n' "$maximum" >"$ddc_values/bus-$bus.maximum"
}

link_helpers() {
  ln -s -- "$display_helper" "$helper_dir/brightness-display"
  ln -s -- "$brightness_helper" "$helper_dir/desktop-monitor-brightness"
  ln -s -- "$state_helper" "$helper_dir/desktop-hardware-state"
}

run_env() {
  env \
    HOME="$home_dir" \
    PATH="$bin:$system_path" \
    DESKTOP_HARDWARE_HELPER_DIR="$helper_dir" \
    DESKTOP_HARDWARE_SYSFS_ROOT="$sysfs_root" \
    DESKTOP_HARDWARE_STATE_DIR="$state_dir" \
    DESKTOP_MONITOR_BRIGHTNESS_SYSFS_ROOT="$sysfs_root" \
    BRIGHTNESS_DISPLAY_SYSFS_ROOT="$sysfs_root" \
    DDC_LOG="$ddc_log" \
    DDC_VALUES="$ddc_values" \
    BRIGHTNESS_LOG="$brightness_log" \
    BRIGHTNESS_SYSFS_ROOT="$sysfs_root" \
    OSD_FILE="$osd_file" \
    OSD_MODE="${OSD_MODE:-normal}" \
    HYPR_LOG="$hypr_log" \
    HYPR_MONITORS="${HYPR_MONITORS:-[]}" \
    "$@"
}

assert_jq() {
  local expression=$1
  local payload=$2

  jq -e "$expression" <<<"$payload" >/dev/null || fail "jq assertion failed: $expression\n$payload"
}

assert_no_hardware_write() {
  [[ $(<"$ddc_log") != *setvcp* ]] || fail "unexpected DDC write:\n$(<"$ddc_log")"
  [[ ! -s $brightness_log ]] || fail "unexpected backlight write:\n$(<"$brightness_log")"
}

setup_external_pair() {
  reset_fixture
  make_connector DP-2 display-a 7
  make_connector HDMI-A-1 display-b 8
  make_ddc_value 7 75 255
  make_ddc_value 8 75 100
  HYPR_MONITORS="[{
    \"name\":\"DP-2\",\"description\":\"A\",\"width\":1920,\"height\":1080,\"scale\":1,\"focused\":false,\"disabled\":false,\"mirrorOf\":\"none\"
  },{
    \"name\":\"HDMI-A-1\",\"description\":\"B\",\"width\":1920,\"height\":1080,\"scale\":1,\"focused\":true,\"disabled\":false,\"mirrorOf\":\"none\"
  }]"
}

test_targeted_chain_scales_only_target_and_confirms_native_values() {
  local monitors
  local snapshot
  local target
  local result

  setup_external_pair
  monitors='[{"name":"DP-2","disabled":false},{"name":"HDMI-A-1","disabled":false}]'
  snapshot=$(run_env "$brightness_helper" snapshot '{}' "$monitors")
  target=$(jq -ce '.monitors["DP-2"]' <<<"$snapshot")

  result=$(run_env "$action" monitor set-display-brightness 50 "$target")
  assert_jq '.connector == "DP-2" and .current == 128 and .maximum == 255 and .percent == 50' "$result"
  [[ $(<"$ddc_values/bus-7.value") == 128 ]] || fail 'target display was not written at its actual native maximum'
  [[ $(<"$ddc_values/bus-8.value") == 75 ]] || fail 'unselected display was changed'
  assert_jq '.icon == "brightness" and .value == 128 and .max == 255' "$(<"$osd_file")"
}

test_osd_failure_keeps_confirmed_result_and_exit_three() {
  local monitors
  local snapshot
  local target
  local result
  local status

  setup_external_pair
  monitors='[{"name":"DP-2","disabled":false},{"name":"HDMI-A-1","disabled":false}]'
  snapshot=$(run_env "$brightness_helper" snapshot '{}' "$monitors")
  target=$(jq -ce '.monitors["DP-2"]' <<<"$snapshot")
  OSD_MODE=fail

  if result=$(run_env "$action" monitor set-display-brightness 50 "$target" 2>"$test_root/osd-failure.err"); then
    status=0
  else
    status=$?
  fi
  [[ $status -eq 3 ]] || fail "OSD failure returned $status instead of 3"
  assert_jq '.connector == "DP-2" and .current == 128 and .maximum == 255' "$result"
  [[ $(<"$ddc_values/bus-7.value") == 128 ]] || fail 'OSD failure did not retain the successful hardware write'
  [[ $(<"$ddc_values/bus-8.value") == 75 ]] || fail 'OSD failure changed the unselected display'
}

test_invalid_target_json_is_rejected_before_write() {
  local status

  setup_external_pair
  if run_env "$action" monitor set-display-brightness 50 '{"connector":"DP-2"' >"$test_root/invalid.out" 2>"$test_root/invalid.err"; then
    status=0
  else
    status=$?
  fi
  [[ $status -eq 2 ]] || fail "invalid target returned $status instead of 2"
  [[ $(<"$ddc_values/bus-7.value") == 75 ]] || fail 'invalid target changed display A'
  [[ $(<"$ddc_values/bus-8.value") == 75 ]] || fail 'invalid target changed display B'
  assert_no_hardware_write
}

test_legacy_laptop_relative_adjustment_stays_quiet() {
  local output

  reset_fixture
  make_connector eDP-1 display-c 0
  make_backlight intel_backlight 40 100
  output=$(run_env "$display_helper" '+5%')
  [[ -z $output ]] || fail 'legacy no-target brightness output changed on stdout'
  [[ $(<"$sysfs_root/class/backlight/intel_backlight/brightness") == 45 ]] \
    || fail 'legacy relative laptop adjustment was not preserved'
  [[ $(<"$brightness_log") == *'-d intel_backlight set +5%'* ]] \
    || fail 'legacy brightnessctl step/device preference changed'
  assert_jq '.value == 45 and .max == 100' "$(<"$osd_file")"
}

test_external_no_target_uses_focused_connector_once() {
  local status

  setup_external_pair
  if run_env "$action" monitor set-display-brightness 50 >"$test_root/external.out" 2>"$test_root/external.err"; then
    status=0
  else
    status=$?
  fi
  [[ $status -eq 0 ]] || fail "focused external adjustment returned $status"
  [[ $(<"$ddc_values/bus-7.value") == 75 ]] || fail 'external no-target adjustment changed the first display'
  [[ $(<"$ddc_values/bus-8.value") == 50 ]] || fail 'external no-target adjustment ignored the focused display'
  [[ $(<"$hypr_log") == '-j monitors all' ]] || fail 'focused connector was not captured with one native monitor query'
  assert_jq '.value == 50 and .max == 100' "$(<"$osd_file")"
  [[ ! -s $test_root/external.out ]] || fail 'external no-target action emitted confirmation stdout'
}

test_external_no_target_without_focus_does_not_fall_back() {
  local status

  setup_external_pair
  HYPR_MONITORS='[{"name":"DP-2","description":"A","width":1920,"height":1080,"scale":1,"focused":false,"disabled":false,"mirrorOf":"none"},{"name":"HDMI-A-1","description":"B","width":1920,"height":1080,"scale":1,"focused":false,"disabled":false,"mirrorOf":"none"}]'
  if run_env "$action" monitor set-display-brightness 50 >"$test_root/no-focus.out" 2>"$test_root/no-focus.err"; then
    status=0
  else
    status=$?
  fi
  [[ $status -ne 0 ]] || fail 'external no-target adjustment succeeded without a focused connector'
  [[ $(<"$ddc_values/bus-7.value") == 75 ]] || fail 'missing focus changed the first display'
  [[ $(<"$ddc_values/bus-8.value") == 75 ]] || fail 'missing focus changed the second display'
  [[ ! -e $osd_file ]] || fail 'missing focus displayed an OSD after no hardware operation'
}

[[ -x $action && -x $display_helper && -x $brightness_helper && -x $state_helper ]] \
  || fail 'required helper is missing or not executable'
mkdir -p -- "$helper_dir"
link_helpers

test_targeted_chain_scales_only_target_and_confirms_native_values
test_osd_failure_keeps_confirmed_result_and_exit_three
test_invalid_target_json_is_rejected_before_write
test_legacy_laptop_relative_adjustment_stays_quiet
test_external_no_target_uses_focused_connector_once
test_external_no_target_without_focus_does_not_fall_back

printf '%s\n' 'PASS: brightness display target and OSD regressions'
