#!/usr/bin/env bash
set -Eeuo pipefail

quickshell=${QUICKSHELL_BIN:-quickshell}
if ! command -v "$quickshell" >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "SKIP: quickshell or jq unavailable"
  exit 0
fi

runtime_dir=${XDG_RUNTIME_DIR:-}
wayland_display=${WAYLAND_DISPLAY:-wayland-0}

if ! command -v timeout >/dev/null 2>&1; then
  printf '%s\n' "FAIL: timeout unavailable" >&2
  exit 1
fi

shell_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture_dir="$shell_dir/tests/fixtures/monitor"
tmp_dir=$(mktemp -d "/tmp/opencode/monitor-native-runner.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

write_control() {
  printf '%s\n' "$2" >"$tmp_dir/$1"
}

generate_state() {
  local mode=$1
  local percent=$2
  local output=$3
  write_control state-mode "$mode"
  MONITOR_FIXTURE_STATE_MODE="$tmp_dir/state-mode" \
    MONITOR_FIXTURE_STATE_OUTPUT='' \
    MONITOR_FIXTURE_STATE_HOLD='' \
    MONITOR_FIXTURE_STATE_RELEASE='' \
    MONITOR_FIXTURE_STATE_LOG='' \
    "$fixture_dir/fake-state" monitor '{}' \
    | jq --argjson percent "$percent" \
      '.data.brightnessSnapshot.monitors["DP-1"].current = $percent
       | .data.brightnessSnapshot.monitors["DP-1"].percent = $percent
       | .data.brightness.percent = $percent' >"$output"
}

prepare_fixture() {
  write_control state-mode initial
  write_control action-mode hold
  write_control action-release wait
  write_control old-state-hold hold
  write_control old-state-release wait
  write_control same-state-old-hold hold
  write_control same-state-old-release wait
  write_control same-state-new-hold hold
  write_control same-state-new-release wait
  write_control state-log-start wait
  write_control action-log-start wait
  write_control workspace-log-start wait
  : >"$tmp_dir/state-log"
  : >"$tmp_dir/action-log"
  : >"$tmp_dir/workspace-log"
  : >"$tmp_dir/old-state-entered"
  : >"$tmp_dir/new-state-entered"
  : >"$tmp_dir/same-state-old-entered"
  : >"$tmp_dir/same-state-new-entered"
  printf '%s\n' '[{"name":"eDP-1","activeWorkspace":{"id":4}},{"name":"DP-1","activeWorkspace":{"id":7}}]' \
    >"$tmp_dir/workspace-output"

  generate_state old 40 "$tmp_dir/old-state-output"
  generate_state old 40 "$tmp_dir/same-state-old-output"
  generate_state new 80 "$tmp_dir/replacement-state-output"
  generate_state new 90 "$tmp_dir/same-state-new-output"
  write_control state-mode initial
}

run_fixture() {
  local window_smoke=$1
  local -a env_args=(
    "MONITOR_NATIVE_WINDOW_SMOKE=$window_smoke"
    "MONITOR_FIXTURE_STATE_MODE=$tmp_dir/state-mode"
    "MONITOR_FIXTURE_STATE_LOG=$tmp_dir/state-log"
    "MONITOR_FIXTURE_ACTION_MODE=$tmp_dir/action-mode"
    "MONITOR_FIXTURE_ACTION_RELEASE=$tmp_dir/action-release"
    "MONITOR_FIXTURE_ACTION_LOG=$tmp_dir/action-log"
    "MONITOR_FIXTURE_OLD_STATE_HOLD=$tmp_dir/old-state-hold"
    "MONITOR_FIXTURE_OLD_STATE_RELEASE=$tmp_dir/old-state-release"
    "MONITOR_FIXTURE_OLD_STATE_OUTPUT=$tmp_dir/old-state-output"
    "MONITOR_FIXTURE_OLD_STATE_ENTERED=$tmp_dir/old-state-entered"
    "MONITOR_FIXTURE_REPLACEMENT_STATE_OUTPUT=$tmp_dir/replacement-state-output"
    "MONITOR_FIXTURE_SAME_STATE_OLD_HOLD=$tmp_dir/same-state-old-hold"
    "MONITOR_FIXTURE_SAME_STATE_OLD_RELEASE=$tmp_dir/same-state-old-release"
    "MONITOR_FIXTURE_SAME_STATE_OLD_OUTPUT=$tmp_dir/same-state-old-output"
    "MONITOR_FIXTURE_SAME_STATE_OLD_ENTERED=$tmp_dir/same-state-old-entered"
    "MONITOR_FIXTURE_SAME_STATE_NEW_HOLD=$tmp_dir/same-state-new-hold"
    "MONITOR_FIXTURE_SAME_STATE_NEW_RELEASE=$tmp_dir/same-state-new-release"
    "MONITOR_FIXTURE_SAME_STATE_NEW_OUTPUT=$tmp_dir/same-state-new-output"
    "MONITOR_FIXTURE_SAME_STATE_NEW_ENTERED=$tmp_dir/same-state-new-entered"
    "WORKSPACE_FIXTURE_OUTPUT=$tmp_dir/workspace-output"
    "WORKSPACE_FIXTURE_LOG=$tmp_dir/workspace-log"
  )
  env "${env_args[@]}" timeout --foreground --kill-after=2s 45s "$quickshell" -n -p monitor-native-runtime-test.qml
}

if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' "FAIL: node unavailable for native monitor model checks" >&2
  exit 1
fi
node tests/monitor-model-test.js
printf 'PASS: native monitor independent model checks\n'
bash tests/monitor-service-lifecycle-runtime-test.sh
printf 'PASS: native monitor independent service checks\n'

if [[ ! -S "$runtime_dir/$wayland_display" ]]; then
  printf '%s\n' "SKIP: native window smoke: no live Wayland socket"
  exit 0
fi
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} || ! -S "$runtime_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]]; then
  printf '%s\n' "SKIP: native window smoke: no live Hyprland socket"
  exit 0
fi

prepare_fixture
run_fixture 1
printf 'PASS: native monitor, panel, and workspace window fixture\n'
