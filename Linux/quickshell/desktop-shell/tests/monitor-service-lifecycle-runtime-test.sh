#!/usr/bin/env bash
set -Eeuo pipefail

quickshell=${QUICKSHELL_BIN:-quickshell}
if ! command -v "$quickshell" >/dev/null 2>&1; then
  printf '%s\n' "SKIP: quickshell unavailable"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
  printf '%s\n' "FAIL: jq and timeout are required" >&2
  exit 1
fi

shell_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture_dir="$shell_dir/tests/fixtures/monitor"
tmp_dir=$(mktemp -d "/tmp/opencode/monitor-service-lifecycle-runner.XXXXXX")
log_file="$tmp_dir/quickshell.log"
trap 'rm -rf -- "$tmp_dir"' EXIT

write_control() {
  printf '%s\n' "$2" >"$tmp_dir/$1"
}

generate_state() {
  local mode=$1
  local output=$2
  write_control state-mode "$mode"
  MONITOR_FIXTURE_STATE_MODE="$tmp_dir/state-mode" \
    MONITOR_FIXTURE_STATE_OUTPUT='' \
    MONITOR_FIXTURE_STATE_HOLD='' \
    MONITOR_FIXTURE_STATE_RELEASE='' \
    MONITOR_FIXTURE_STATE_LOG='' \
    "$fixture_dir/fake-state" monitor '{}' >"$output"
}

write_control state-mode initial
write_control same-state-old-hold wait
write_control same-state-old-release wait
write_control same-state-new-hold wait
write_control same-state-new-release wait
write_control action-mode hold
write_control action-release wait
: >"$tmp_dir/same-state-old-entered"
: >"$tmp_dir/same-state-new-entered"

generate_state old "$tmp_dir/same-state-old-output"
generate_state new "$tmp_dir/same-state-new-output"
write_control state-mode initial

if timeout --foreground --kill-after=2s 45s env \
  QT_QPA_PLATFORM=offscreen \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  MONITOR_FIXTURE_STATE_MODE="$tmp_dir/state-mode" \
  MONITOR_FIXTURE_SAME_STATE_OLD_HOLD="$tmp_dir/same-state-old-hold" \
  MONITOR_FIXTURE_SAME_STATE_OLD_RELEASE="$tmp_dir/same-state-old-release" \
  MONITOR_FIXTURE_SAME_STATE_OLD_ENTERED="$tmp_dir/same-state-old-entered" \
  MONITOR_FIXTURE_SAME_STATE_OLD_OUTPUT="$tmp_dir/same-state-old-output" \
  MONITOR_FIXTURE_SAME_STATE_NEW_HOLD="$tmp_dir/same-state-new-hold" \
  MONITOR_FIXTURE_SAME_STATE_NEW_RELEASE="$tmp_dir/same-state-new-release" \
  MONITOR_FIXTURE_SAME_STATE_NEW_ENTERED="$tmp_dir/same-state-new-entered" \
  MONITOR_FIXTURE_SAME_STATE_NEW_OUTPUT="$tmp_dir/same-state-new-output" \
  MONITOR_FIXTURE_ACTION_MODE="$tmp_dir/action-mode" \
  MONITOR_FIXTURE_ACTION_RELEASE="$tmp_dir/action-release" \
  "$quickshell" -n -p "$shell_dir/monitor-service-lifecycle-runtime-test.qml" \
  >"$log_file" 2>&1; then
  exit_code=0
else
  exit_code=$?
fi

if ((exit_code != 0)); then
  printf 'FAIL: monitor service lifecycle fixture exited with %s\n' "$exit_code" >&2
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line"
  done <"$log_file" >&2
  exit 1
fi

log_text=$(<"$log_file")
if [[ $log_text != *'Monitor service lifecycle fixture passed'* ]]; then
  printf '%s\n' 'FAIL: monitor service lifecycle fixture did not report success' >&2
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line"
  done <"$log_file" >&2
  exit 1
fi

while IFS= read -r line || [[ -n $line ]]; do
  if [[ $line == *'Monitor service lifecycle fixture passed'* ]]; then
    printf '%s\n' "$line"
  fi
done <"$log_file"
