#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
helper="$repo_root/Linux/os/helpers/desktop-monitor-brightness"
fixture_root="$repo_root/Linux/os/tests/fixtures/monitor-brightness"
test_root=$(mktemp -d)
bin="$test_root/bin"
missing_bin="$test_root/missing-bin"
sysfs_root="$test_root/sys"
home_dir="$test_root/home"
state_dir="$test_root/state"
ddc_values="$test_root/ddc-values"
ddc_log="$test_root/ddc.log"
brightness_log="$test_root/brightness.log"
detect_output="$test_root/detect.txt"
child_pid_file="$test_root/ddc-child.pid"
system_path=$PATH
readonly DETECT_EXTENSION_HEX=02030000d4e1eefb0815222f3c495663707d8a97a4b1becbd8e5f2ff0c192633404d5a6774818e9ba8b5c2cfdce9f603101d2a3744515e6b7885929facb9c6d3e0edfa0714212e3b4855626f7c8996a3b0bdcad7e4f1fe0b1825323f4c596673808d9aa7b4c1cedbe8f5020f1c293643505d6a7784919eabb8c5d2dfecf9061c

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

log_command() {
  {
    printf '%q ' "$@"
    printf '\n'
  } >>"${DDC_LOG:?}"
}

log_command "$@"
mode=${DDC_MODE:-normal}

if [[ ${1:-} == detect ]]; then
  cat "${DDC_DETECT_OUTPUT:?}"
  exit 0
fi

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
    if [[ $mode == stall ]]; then
      child=''
      terminate() {
        if [[ -n $child ]]; then
          kill "$child" 2>/dev/null || true
          wait "$child" 2>/dev/null || true
        fi
        exit 143
      }
      trap terminate TERM INT
      sleep 30 &
      child=$!
      printf '%s\n' "$child" >"${DDC_CHILD_PID_FILE:?}"
      wait "$child"
      exit 1
    fi
    [[ $mode != permission ]] || exit 13
    [[ -z ${DDC_FAIL_SELECTOR:-} || $selector != "$DDC_FAIL_SELECTOR" ]] || exit 13
    if [[ $mode == unsupported ]]; then
      printf '%s\n' 'VCP 10 ERR'
      exit 0
    fi
    if [[ $mode == malformed ]]; then
      printf '%s\n' "${DDC_MALFORMED_OUTPUT:?}"
      exit 0
    fi
    [[ -r $value_file && -r $maximum_file ]] || exit 1
    printf 'VCP 10 C %s %s\n' "$(<"$value_file")" "$(<"$maximum_file")"
    ;;
  setvcp)
    [[ ${2:-} == 10 && ${3:-} =~ ^[0-9]+$ ]] || exit 64
    printf '%s\n' "${3}" >"$value_file"
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
action=''
value=''
while (($# > 0)); do
  case $1 in
    -d)
      device=$2
      shift 2
      ;;
    -m)
      action=read
      shift
      ;;
    set)
      action=set
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
case $action in
  read)
    current=$(<"$brightness_file")
    maximum=$(<"$maximum_file")
    percent=$((current * 100 / maximum))
    printf '%s,raw,%s,%s,%s%%\n' "$device" "$current" "$maximum" "$percent"
    ;;
  set)
    [[ $value =~ ^[0-9]+$ ]] || exit 64
    printf '%s\n' "$value" >"$brightness_file"
    ;;
  *)
    exit 64
    ;;
esac
EOF

  chmod 0755 "$bin/ddcutil" "$bin/brightnessctl"
}

write_missing_path() {
  local command
  local resolved

  mkdir -p -- "$missing_bin"
  for command in bash jq od readlink sha256sum sort timeout; do
    resolved=$(command -v "$command") || fail "required test command is missing: $command"
    ln -s -- "$resolved" "$missing_bin/$command"
  done
}

reset_fixture() {
  rm -rf -- "$sysfs_root" "$home_dir" "$state_dir" "$ddc_values"
  mkdir -p -- "$bin" "$sysfs_root/class/drm" "$sysfs_root/class/backlight" \
    "$home_dir" "$state_dir" "$ddc_values"
  : >"$ddc_log"
  : >"$brightness_log"
  : >"$detect_output"
  rm -f -- "$child_pid_file"
  DDC_MODE=normal
  DDC_MALFORMED_OUTPUT='VCP 10 C 10 100 trailing'
  DDC_FAIL_SELECTOR=''
  write_fake_tools
}

make_connector() {
  make_connector_on_card 0 "$@"
}

make_connector_on_card() {
  local card=$1
  local connector=$2
  local fixture=$3
  local bus=${4:-}
  local connector_dir="$sysfs_root/class/drm/card${card}-$connector"

  mkdir -p -- "$connector_dir"
  printf '%s\n' connected >"$connector_dir/status"
  hex_to_binary "$fixture_root/$fixture.edid.hex" "$connector_dir/edid"
  if [[ -n $bus ]]; then
    mkdir -p -- "$sysfs_root/i2c-$bus"
    ln -s -- "$sysfs_root/i2c-$bus" "$connector_dir/ddc"
  fi
}

make_backlight() {
  local device=$1
  local current=$2
  local maximum=$3
  local device_dir="$sysfs_root/class/backlight/$device"

  mkdir -p -- "$device_dir"
  printf '%s\n' "$current" >"$device_dir/brightness"
  printf '%s\n' "$maximum" >"$device_dir/max_brightness"
  ln -s -- "$device_dir" "$sysfs_root/class/drm/card0-eDP-1/backlight"
}

make_ddc_value() {
  local kind=$1
  local selector=$2
  local current=$3
  local maximum=$4
  local key=$selector

  if [[ $kind == edid ]]; then
    key=${selector:0:24}
  fi
  printf '%s\n' "$current" >"$ddc_values/$kind-$key.value"
  printf '%s\n' "$maximum" >"$ddc_values/$kind-$key.maximum"
}

make_detect_record() {
  local display=$1
  local bus=$2
  local edid=$3
  local offset
  local byte
  local dump
  local ascii='|..cer...........|'
  local style=${4:-plus}

  printf 'Display %s\n  I2C bus: /dev/i2c-%s\n  EDID hex dump:\n' "$display" "$bus" >>"$detect_output"
  printf '              +0          +4          +8          +c            0   4   8   c\n' >>"$detect_output"
  dump=$edid$DETECT_EXTENSION_HEX
  for ((offset = 0; offset < ${#dump}; offset += 32)); do
    if [[ $style == plus ]]; then
      printf '      +%04x   ' "$((offset / 2))" >>"$detect_output"
    else
      printf '    %04x: ' "$((offset / 2))" >>"$detect_output"
    fi
    for ((byte = 0; byte < 32; byte += 2)); do
      printf '%s ' "${dump:offset+byte:2}" >>"$detect_output"
    done
    printf '  %s\n' "$ascii" >>"$detect_output"
  done
  printf '\n' >>"$detect_output"
}

run_helper() {
  local path=$1
  shift

  HOME="$home_dir" \
    PATH="$path" \
    DESKTOP_MONITOR_BRIGHTNESS_SYSFS_ROOT="$sysfs_root" \
    DDC_LOG="$ddc_log" \
    DDC_VALUES="$ddc_values" \
    DDC_DETECT_OUTPUT="$detect_output" \
    DDC_CHILD_PID_FILE="$child_pid_file" \
    BRIGHTNESS_LOG="$brightness_log" \
    BRIGHTNESS_SYSFS_ROOT="$sysfs_root" \
    DDC_MODE="${DDC_MODE:-normal}" \
    DDC_FAIL_SELECTOR="${DDC_FAIL_SELECTOR:-}" \
    DDC_MALFORMED_OUTPUT="${DDC_MALFORMED_OUTPUT:-VCP 10 C 10 100 trailing}" \
    "$helper" "$@"
}

run_default() {
  run_helper "$bin:$system_path" "$@"
}

assert_jq() {
  local expression=$1
  local payload=$2

  jq -e "$expression" <<<"$payload" >/dev/null || fail "jq assertion failed: $expression\n$payload"
}

assert_no_set() {
  local log

  log=$(<"$ddc_log")
  [[ $log != *setvcp* ]] || fail "unexpected DDC write:\n$log"
  [[ ! -s $brightness_log ]] || fail "unexpected backlight write:\n$(<"$brightness_log")"
}

setup_external_pair() {
  local edid_a
  local edid_b

  reset_fixture
  make_connector DP-2 display-a
  make_connector HDMI-A-1 display-b
  edid_a=$(fixture_hex display-a)
  edid_b=$(fixture_hex display-b)
  make_ddc_value edid "$edid_a" 75 255
  make_ddc_value edid "$edid_b" 75 100
  cp -- "$fixture_root/ddcutil-detect-verbose.txt" "$detect_output"
  make_detect_record 2 8 "$edid_b" colon
}

count_getvcp_queries() {
  local count=0
  local line

  while IFS= read -r line; do
    if [[ $line == *getvcp* ]]; then
      ((count += 1))
    fi
  done <"$ddc_log"
  printf '%s\n' "$count"
}

test_targeting_and_scaling() {
  local edid_a
  local edid_b
  local monitors
  local snapshot
  local second_snapshot
  local target
  local result
  local detect_count=0
  local line

  reset_fixture
  make_connector eDP-1 display-c
  make_connector DP-2 display-a
  make_connector HDMI-A-1 display-b
  make_backlight intel_backlight 40 100
  edid_a=$(fixture_hex display-a)
  edid_b=$(fixture_hex display-b)
  make_ddc_value edid "$edid_a" 75 255
  make_ddc_value edid "$edid_b" 75 100
  make_detect_record 1 7 "$edid_a"
  make_detect_record 2 8 "$edid_b"
  monitors='[{"name":"eDP-1","disabled":false},{"name":"DP-2","disabled":false},{"name":"HDMI-A-1","disabled":false}]'

  snapshot=$(run_default snapshot '{}' "$monitors")
  assert_jq '.version == 1 and (.monitors | length) == 3' "$snapshot"
  assert_jq '.monitors["eDP-1"].backend == "backlight" and .monitors["eDP-1"].selector.kind == "backlight"' "$snapshot"
  assert_jq '.monitors["DP-2"].available == true and .monitors["DP-2"].selector.kind == "edid"' "$snapshot"
  assert_jq '.monitors["HDMI-A-1"].maximum == 100' "$snapshot"

  while IFS= read -r line; do
    [[ $line == detect* ]] && ((detect_count += 1))
  done <"$ddc_log"
  [[ $detect_count -eq 1 ]] || fail "expected one DDC discovery, found $detect_count"

  second_snapshot=$(run_default snapshot "$snapshot" "$monitors")
  assert_jq '.monitors["DP-2"].available == true and .monitors["HDMI-A-1"].available == true' "$second_snapshot"
  snapshot=$second_snapshot
  detect_count=0
  while IFS= read -r line; do
    [[ $line == detect* ]] && ((detect_count += 1))
  done <"$ddc_log"
  [[ $detect_count -eq 1 ]] || fail 'a valid prior discovery was not reused'

  target=$(jq -ce '.monitors["DP-2"]' <<<"$snapshot")
  result=$(run_default set '50%' "$target")
  assert_jq '.connector == "DP-2" and .current == 128 and .maximum == 255 and .percent == 50' "$result"
  [[ $(<"$ddc_values/edid-${edid_a:0:24}.value") == 128 ]] || fail 'display A was not scaled using its actual maximum'
  [[ $(<"$ddc_values/edid-${edid_b:0:24}.value") == 75 ]] || fail 'display B was changed by display A'
  [[ $result == *'"selector":{"kind":"edid"'* ]] || fail 'the no-link path did not return an EDID selector'
  [[ $(<"$ddc_log") != *--bus* ]] || fail 'the no-link path used an unchecked bus selector'
}

test_targeted_snapshot_reads_one_monitor() {
  local edid_b
  local monitors
  local snapshot
  local query_count

  setup_external_pair
  edid_b=$(fixture_hex display-b)
  monitors='[{"name":"DP-2","disabled":false},{"name":"HDMI-A-1","disabled":false}]'

  snapshot=$(run_default snapshot '{}' "$monitors" DP-2)
  assert_jq '.monitors | length == 1 and has("DP-2") and .["DP-2"].available == true' "$snapshot"
  query_count=$(count_getvcp_queries)
  [[ $query_count -eq 1 ]] || fail "targeted snapshot performed $query_count DDC reads"
  [[ $(<"$ddc_log") != *"$edid_b"* ]] || fail 'targeted snapshot queried the unselected monitor'
}

test_mixed_healthy_and_failing_snapshot() {
  local edid_b
  local monitors
  local snapshot

  setup_external_pair
  edid_b=$(fixture_hex display-b)
  DDC_FAIL_SELECTOR=$edid_b
  monitors='[{"name":"DP-2","disabled":false},{"name":"HDMI-A-1","disabled":false}]'

  snapshot=$(run_default snapshot '{}' "$monitors")
  assert_jq '.monitors["DP-2"].available == true and .monitors["HDMI-A-1"].available == false and .monitors["HDMI-A-1"].current == null' "$snapshot"
  assert_no_set
}

test_indistinguishable_edids_are_rejected() {
  local edid_a
  local monitors
  local snapshot

  reset_fixture
  make_connector DP-2 display-a
  make_connector HDMI-A-1 display-a
  edid_a=$(fixture_hex display-a)
  make_ddc_value bus 7 75 255
  make_ddc_value bus 8 75 255
  make_detect_record 1 7 "$edid_a"
  make_detect_record 2 8 "$edid_a"
  monitors='[{"name":"DP-2","disabled":false},{"name":"HDMI-A-1","disabled":false}]'

  snapshot=$(run_default snapshot '{}' "$monitors")
  assert_jq '.monitors["DP-2"].available == false and .monitors["HDMI-A-1"].available == false and (.monitors[].error | test("ambiguous"; "i"))' "$snapshot"
  assert_no_set
}

test_ambiguous_multi_card_connector_is_rejected() {
  local monitors
  local snapshot
  local duplicate_dir="$sysfs_root/class/drm/card1-DP-2"

  reset_fixture
  make_connector DP-2 display-a
  mkdir -p -- "$duplicate_dir"
  printf '%s\n' connected >"$duplicate_dir/status"
  hex_to_binary "$fixture_root/display-b.edid.hex" "$duplicate_dir/edid"
  monitors='[{"name":"DP-2","disabled":false}]'

  snapshot=$(run_default snapshot '{}' "$monitors")
  assert_jq '.monitors["DP-2"].available == false and (.monitors["DP-2"].error | test("unique|ambiguous"; "i"))' "$snapshot"
  assert_no_set
}

test_relative_scaling_and_native_backlight() {
  local monitors
  local snapshot
  local target
  local result

  reset_fixture
  make_connector eDP-1 display-c
  make_backlight intel_backlight 0 100
  monitors='[{"name":"eDP-1","disabled":false}]'

  snapshot=$(run_default snapshot '{}' "$monitors")
  assert_jq '.monitors["eDP-1"].available == true and .monitors["eDP-1"].current == 0 and .monitors["eDP-1"].maximum == 100 and .monitors["eDP-1"].percent == 0' "$snapshot"
  target=$(jq -ce '.monitors["eDP-1"]' <<<"$snapshot")
  result=$(run_default set '+5%' "$target")
  assert_jq '.backend == "backlight" and .current == 5 and .maximum == 100 and .percent == 5' "$result"
  [[ $(<"$sysfs_root/class/backlight/intel_backlight/brightness") == 5 ]] || fail 'native backlight relative set was not applied'

  result=$(run_default set '-50%' "$result")
  assert_jq '.current == 1 and .maximum == 100 and .percent == 1' "$result"
  [[ $(<"$sysfs_root/class/backlight/intel_backlight/brightness") == 1 ]] || fail 'native backlight lower clamp was not applied'
  [[ ! -s $ddc_log ]] || fail 'native backlight targeting invoked DDC'
}

test_native_maximum_above_vcp_range() {
  local monitors
  local snapshot
  local target
  local result

  reset_fixture
  make_connector eDP-1 display-c
  make_backlight intel_backlight 35000 70000
  monitors='[{"name":"eDP-1","disabled":false}]'

  snapshot=$(run_default snapshot '{}' "$monitors")
  assert_jq '.monitors["eDP-1"].available == true and .monitors["eDP-1"].maximum == 70000' "$snapshot"
  target=$(jq -ce '.monitors["eDP-1"]' <<<"$snapshot")
  result=$(run_default set '50%' "$target")
  assert_jq '.current == 35000 and .maximum == 70000 and .percent == 50' "$result"
}

test_stale_retention_requires_valid_current_identity_and_values() {
  local edid_a
  local monitors
  local fresh
  local stale
  local invalid
  local variant

  setup_external_pair
  edid_a=$(fixture_hex display-a)
  monitors='[{"name":"DP-2","disabled":false},{"name":"HDMI-A-1","disabled":false}]'
  fresh=$(run_default snapshot '{}' "$monitors")
  DDC_MODE=permission

  stale=$(run_default snapshot "$fresh" "$monitors")
  assert_jq '.monitors["DP-2"].available == false and .monitors["DP-2"].stale == true and .monitors["DP-2"].current == 75 and .monitors["DP-2"].maximum == 255 and .monitors["DP-2"].percent == 29' "$stale"
  assert_jq '.monitors["HDMI-A-1"].available == false and .monitors["HDMI-A-1"].stale == true' "$stale"

  for variant in connector backend identity range percent; do
    case $variant in
      connector) invalid=$(jq '.monitors["DP-2"].connector = "HDMI-A-1"' <<<"$fresh") ;;
      backend) invalid=$(jq '.monitors["DP-2"].backend = "backlight"' <<<"$fresh") ;;
      identity) invalid=$(jq '.monitors["DP-2"].identity = ("0" * 64)' <<<"$fresh") ;;
      range) invalid=$(jq '.monitors["DP-2"].current = 256' <<<"$fresh") ;;
      percent) invalid=$(jq '.monitors["DP-2"].percent = 99' <<<"$fresh") ;;
      *) fail "unknown stale-record variant: $variant" ;;
    esac
    stale=$(run_default snapshot "$invalid" "$monitors")
    assert_jq '.monitors["DP-2"].available == false and .monitors["DP-2"].stale == false and .monitors["DP-2"].current == null and .monitors["DP-2"].maximum == null and .monitors["DP-2"].percent == null' "$stale"
  done

  [[ $(<"$ddc_values/edid-${edid_a:0:24}.value") == 75 ]] || fail 'stale validation caused a write'
}

test_repeated_failure_retains_last_good_measurement() {
  local edid_a
  local monitors
  local fresh
  local first_stale
  local second_stale

  setup_external_pair
  edid_a=$(fixture_hex display-a)
  monitors='[{"name":"DP-2","disabled":false},{"name":"HDMI-A-1","disabled":false}]'
  fresh=$(run_default snapshot '{}' "$monitors")
  DDC_MODE=permission

  first_stale=$(run_default snapshot "$fresh" "$monitors")
  second_stale=$(run_default snapshot "$first_stale" "$monitors")
  assert_jq '.monitors["DP-2"].available == false and .monitors["DP-2"].stale == true and .monitors["DP-2"].current == 75 and .monitors["DP-2"].maximum == 255 and .monitors["DP-2"].percent == 29' "$second_stale"
  assert_jq '.monitors["HDMI-A-1"].available == false and .monitors["HDMI-A-1"].stale == true and .monitors["HDMI-A-1"].current == 75 and .monitors["HDMI-A-1"].maximum == 100 and .monitors["HDMI-A-1"].percent == 75' "$second_stale"
  [[ $(<"$ddc_values/edid-${edid_a:0:24}.value") == 75 ]] || fail 'repeated stale validation caused a write'
  assert_no_set
}

test_malformed_vcp_is_rejected() {
  local edid_a
  local monitors
  local snapshot

  setup_external_pair
  edid_a=$(fixture_hex display-a)
  printf '%s\n' 'VCP 10 C 75 255 trailing' >"$test_root/malformed-vcp.txt"
  monitors='[{"name":"DP-2","disabled":false}]'
  DDC_MODE=malformed
  DDC_MALFORMED_OUTPUT='VCP 10 C 75 255 trailing'
  snapshot=$(run_default snapshot '{}' "$monitors")
  assert_jq '.monitors["DP-2"].available == false and (.monitors["DP-2"].error | test("VCP|read|malformed"; "i"))' "$snapshot"
  [[ $(<"$ddc_values/edid-${edid_a:0:24}.value") == 75 ]] || fail 'malformed VCP caused a write'
  assert_no_set
}

test_missing_ddcutil_does_not_fall_through() {
  local monitors
  local snapshot

  setup_external_pair
  write_missing_path
  monitors='[{"name":"DP-2","disabled":false}]'
  snapshot=$(run_helper "$missing_bin" snapshot '{}' "$monitors")
  assert_jq '.monitors["DP-2"].available == false and (.monitors["DP-2"].error | test("ddcutil|timeout|executable"; "i"))' "$snapshot"
  [[ ! -s $ddc_log ]] || fail 'missing ddcutil fell through to the fake/default command path'
  snapshot=$(run_default snapshot "$snapshot" "$monitors")
  assert_jq '.monitors["DP-2"].available == true and .monitors["DP-2"].stale == false' "$snapshot"
}

test_permission_denial_is_operational_failure() {
  local monitors
  local snapshot

  setup_external_pair
  monitors='[{"name":"DP-2","disabled":false}]'
  DDC_MODE=permission
  snapshot=$(run_default snapshot '{}' "$monitors")
  assert_jq '.monitors["DP-2"].available == false and (.monitors["DP-2"].error | test("read|permission|DDC"; "i"))' "$snapshot"
  assert_no_set
}

test_unsupported_feature_is_not_zero() {
  local monitors
  local snapshot

  setup_external_pair
  monitors='[{"name":"DP-2","disabled":false}]'
  DDC_MODE=unsupported
  snapshot=$(run_default snapshot '{}' "$monitors")
  assert_jq '.monitors["DP-2"].available == false and .monitors["DP-2"].current == null and .monitors["DP-2"].maximum == null' "$snapshot"
  assert_no_set
}

test_bus_reuse_rejects_old_target() {
  local edid_a
  local edid_b
  local monitors
  local snapshot
  local target

  reset_fixture
  make_connector DP-2 display-a 7
  make_connector HDMI-A-1 display-b 8
  edid_a=$(fixture_hex display-a)
  edid_b=$(fixture_hex display-b)
  make_ddc_value bus 7 75 255
  make_ddc_value bus 8 75 100
  make_detect_record 1 7 "$edid_a"
  make_detect_record 2 8 "$edid_b"
  monitors='[{"name":"DP-2","disabled":false},{"name":"HDMI-A-1","disabled":false}]'

  snapshot=$(run_default snapshot '{}' "$monitors")
  target=$(jq -ce '.monitors["DP-2"]' <<<"$snapshot")
  rm -f -- "$sysfs_root/class/drm/card0-DP-2/ddc"
  ln -s -- "$sysfs_root/i2c-8" "$sysfs_root/class/drm/card0-DP-2/ddc"

  if run_default set '50%' "$target" >/dev/null 2>&1; then
    fail 'a reused bus accepted the old target'
  fi
  [[ $(<"$ddc_values/bus-7.value") == 75 ]] || fail 'bus reuse caused a write'
  [[ $(<"$ddc_values/bus-8.value") == 75 ]] || fail 'bus reuse changed the other display'
  assert_no_set
}

test_replacement_edid_rejects_old_target() {
  local edid_a
  local monitors
  local snapshot
  local target

  reset_fixture
  make_connector DP-2 display-a
  edid_a=$(fixture_hex display-a)
  make_ddc_value edid "$edid_a" 75 255
  make_detect_record 1 7 "$edid_a"
  monitors='[{"name":"DP-2","disabled":false}]'
  snapshot=$(run_default snapshot '{}' "$monitors")
  target=$(jq -ce '.monitors["DP-2"]' <<<"$snapshot")
  hex_to_binary "$fixture_root/display-c.edid.hex" "$sysfs_root/class/drm/card0-DP-2/edid"

  if run_default set '50%' "$target" >/dev/null 2>&1; then
    fail 'an old EDID target was accepted after replacement'
  fi
  [[ $(<"$ddc_values/edid-${edid_a:0:24}.value") == 75 ]] || fail 'EDID replacement caused a write'
  assert_no_set
}

test_tampered_selector_rejects_without_io() {
  local edid_a
  local monitors
  local snapshot
  local target
  local tampered

  reset_fixture
  make_connector DP-2 display-a
  edid_a=$(fixture_hex display-a)
  make_ddc_value edid "$edid_a" 75 255
  make_detect_record 1 7 "$edid_a"
  monitors='[{"name":"DP-2","disabled":false}]'
  snapshot=$(run_default snapshot '{}' "$monitors")
  target=$(jq -ce '.monitors["DP-2"]' <<<"$snapshot")
  tampered=$(jq -c '.selector.value = "7"' <<<"$target")

  if run_default set '50%' "$tampered" >/dev/null 2>&1; then
    fail 'a tampered selector was accepted'
  fi
  [[ $(<"$ddc_values/edid-${edid_a:0:24}.value") == 75 ]] || fail 'tampered selector caused a write'
  assert_no_set
}

test_timeout_terminates_stalled_child() {
  local edid_a
  local monitors
  local snapshot
  local target
  local child_pid
  local attempt

  reset_fixture
  make_connector DP-2 display-a
  edid_a=$(fixture_hex display-a)
  make_ddc_value edid "$edid_a" 75 255
  make_detect_record 1 7 "$edid_a"
  monitors='[{"name":"DP-2","disabled":false}]'
  snapshot=$(run_default snapshot '{}' "$monitors")
  target=$(jq -ce '.monitors["DP-2"]' <<<"$snapshot")

  DDC_MODE=stall
  if run_default set '50%' "$target" >/dev/null 2>&1; then
    fail 'a stalled DDC read unexpectedly succeeded'
  fi
  [[ -r $child_pid_file ]] || fail 'stalled fake did not start its child'
  child_pid=$(<"$child_pid_file")
  [[ $child_pid =~ ^[0-9]+$ ]] || fail 'stalled fake recorded an invalid child PID'
  for ((attempt = 0; attempt < 100; attempt++)); do
    if ! kill -0 "$child_pid" 2>/dev/null; then
      break
    fi
    sleep 0.05
  done
  ! kill -0 "$child_pid" 2>/dev/null || fail 'timeout left the stalled child alive'
  [[ $(<"$ddc_values/edid-${edid_a:0:24}.value") == 75 ]] || fail 'timeout path caused a write'
  assert_no_set
}

test_targeting_and_scaling
test_targeted_snapshot_reads_one_monitor
test_mixed_healthy_and_failing_snapshot
test_indistinguishable_edids_are_rejected
test_ambiguous_multi_card_connector_is_rejected
test_relative_scaling_and_native_backlight
test_native_maximum_above_vcp_range
test_stale_retention_requires_valid_current_identity_and_values
test_repeated_failure_retains_last_good_measurement
test_malformed_vcp_is_rejected
test_missing_ddcutil_does_not_fall_through
test_permission_denial_is_operational_failure
test_unsupported_feature_is_not_zero
test_bus_reuse_rejects_old_target
test_replacement_edid_rejects_old_target
test_tampered_selector_rejects_without_io
test_timeout_terminates_stalled_child

printf '%s\n' 'PASS: desktop monitor brightness targeting regressions'
