#!/usr/bin/env bash
set -eu

scenario=${1:-}
if [ -z "$scenario" ]; then
  printf '%s\n' "usage: $0 full|panel|budget|ordinary-failure|cached-stale|targeted-failure|timeout|action-timeout|malformed-confirmation|failed-start|generation" >&2
  exit 64
fi

if ! command -v timeout >/dev/null 2>&1; then
  printf '%s\n' "timeout is required for the monitor brightness runtime runner" >&2
  exit 1
fi

desktop_shell=$(cd -- "$(dirname "$0")/.." && pwd -P)
quickshell=${QUICKSHELL_BIN:-quickshell}
tmp=$(mktemp -d "/tmp/opencode/monitor-brightness-runner-$scenario.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

write_control() {
  printf '%s\n' "$2" >"$tmp/$1"
}

run_full() {
  write_control state-mode initial
  write_control state-hold no
  write_control state-release wait
  write_control state-final-hold hold
  write_control state-final-release wait
  write_control action-mode hold
  write_control action-hold no
  write_control action-release wait
  MONITOR_BRIGHTNESS_STATE_MODE="$tmp/state-mode" \
    MONITOR_BRIGHTNESS_STATE_HOLD="$tmp/state-hold" \
    MONITOR_BRIGHTNESS_STATE_RELEASE="$tmp/state-release" \
    MONITOR_BRIGHTNESS_STATE_FINAL_HOLD="$tmp/state-final-hold" \
    MONITOR_BRIGHTNESS_STATE_FINAL_RELEASE="$tmp/state-final-release" \
    MONITOR_BRIGHTNESS_STATE_ENTERED="$tmp/state-entered" \
    MONITOR_BRIGHTNESS_STATE_LOG="$tmp/state-log" \
    MONITOR_BRIGHTNESS_ACTION_MODE="$tmp/action-mode" \
    MONITOR_BRIGHTNESS_ACTION_HOLD="$tmp/action-hold" \
    MONITOR_BRIGHTNESS_ACTION_RELEASE="$tmp/action-release" \
    MONITOR_BRIGHTNESS_ACTION_ENTERED="$tmp/action-entered" \
    MONITOR_BRIGHTNESS_ACTION_LOG="$tmp/action-log" \
    timeout --foreground --kill-after=2s 45s "$quickshell" -n -p monitor-brightness-runtime-test.qml
  printf 'scenario=%s state_workers=%s action_workers=%s\n' "$scenario" \
    "$(wc -l <"$tmp/state-log")" "$(wc -l <"$tmp/action-log")"
}

run_failure() {
  write_control state-mode initial
  write_control state-entered initial
  write_control action-entered initial
  write_control action-mode "$action_mode"
  : >"$tmp/state-log"
  : >"$tmp/action-log"
  MONITOR_BRIGHTNESS_FAILURE_CASE="$scenario" \
    MONITOR_BRIGHTNESS_STATE_MODE="$tmp/state-mode" \
    MONITOR_BRIGHTNESS_STATE_ENTERED="$tmp/state-entered" \
    MONITOR_BRIGHTNESS_STATE_LOG="$tmp/state-log" \
    MONITOR_BRIGHTNESS_ACTION_MODE="$tmp/action-mode" \
    MONITOR_BRIGHTNESS_ACTION_ENTERED="$tmp/action-entered" \
    MONITOR_BRIGHTNESS_ACTION_LOG="$tmp/action-log" \
    MONITOR_BRIGHTNESS_ACTION_EXECUTABLE="$action_executable" \
    timeout --foreground --kill-after=2s 45s "$quickshell" -n -p monitor-brightness-failure-runtime-test.qml
  printf 'scenario=%s state_workers=%s action_workers=%s\n' "$scenario" \
    "$(wc -l <"$tmp/state-log" 2>/dev/null || printf '0')" \
    "$(wc -l <"$tmp/action-log" 2>/dev/null || printf '0')"
}

run_generation() {
  write_control state-mode initial
  write_control state-hold no
  write_control state-release wait
  write_control state-new-release wait
  write_control state-old-release wait
  write_control state-old-callback initial
  write_control action-mode hold
  write_control action-hold no
  write_control action-release wait
  write_control action-new-release wait
  write_control action-old-release wait
  write_control action-old-callback initial
  : >"$tmp/state-entered"
  : >"$tmp/action-entered"
  : >"$tmp/state-helper-entered"
  : >"$tmp/action-helper-entered"
  MONITOR_BRIGHTNESS_STATE_MODE="$tmp/state-mode" \
    MONITOR_BRIGHTNESS_STATE_HOLD="$tmp/state-hold" \
    MONITOR_BRIGHTNESS_STATE_RELEASE="$tmp/state-release" \
    MONITOR_BRIGHTNESS_STATE_NEW_RELEASE="$tmp/state-new-release" \
    MONITOR_BRIGHTNESS_STATE_OLD_CALLBACK_RELEASE="$tmp/state-old-release" \
    MONITOR_BRIGHTNESS_STATE_OLD_CALLBACK="$tmp/state-old-callback" \
    MONITOR_BRIGHTNESS_STATE_ENTERED="$tmp/state-entered" \
    MONITOR_BRIGHTNESS_STATE_HELPER_ENTERED="$tmp/state-helper-entered" \
    MONITOR_BRIGHTNESS_ACTION_MODE="$tmp/action-mode" \
    MONITOR_BRIGHTNESS_ACTION_HOLD="$tmp/action-hold" \
    MONITOR_BRIGHTNESS_ACTION_RELEASE="$tmp/action-release" \
    MONITOR_BRIGHTNESS_ACTION_NEW_RELEASE="$tmp/action-new-release" \
    MONITOR_BRIGHTNESS_ACTION_OLD_CALLBACK_RELEASE="$tmp/action-old-release" \
    MONITOR_BRIGHTNESS_ACTION_OLD_CALLBACK="$tmp/action-old-callback" \
    MONITOR_BRIGHTNESS_ACTION_ENTERED="$tmp/action-entered" \
    MONITOR_BRIGHTNESS_ACTION_HELPER_ENTERED="$tmp/action-helper-entered" \
    timeout --foreground --kill-after=2s 45s "$quickshell" -n -p monitor-brightness-generation-runtime-test.qml
}

run_panel() {
  write_control state-mode initial
  write_control state-hold no
  write_control state-release wait
  write_control action-mode hold
  write_control action-hold no
  write_control action-release wait
  : >"$tmp/state-entered"
  : >"$tmp/action-entered"
  : >"$tmp/state-log"
  : >"$tmp/action-log"
  MONITOR_BRIGHTNESS_STATE_MODE="$tmp/state-mode" \
    MONITOR_BRIGHTNESS_STATE_HOLD="$tmp/state-hold" \
    MONITOR_BRIGHTNESS_STATE_RELEASE="$tmp/state-release" \
    MONITOR_BRIGHTNESS_STATE_ENTERED="$tmp/state-entered" \
    MONITOR_BRIGHTNESS_STATE_LOG="$tmp/state-log" \
    MONITOR_BRIGHTNESS_ACTION_MODE="$tmp/action-mode" \
    MONITOR_BRIGHTNESS_ACTION_HOLD="$tmp/action-hold" \
    MONITOR_BRIGHTNESS_ACTION_RELEASE="$tmp/action-release" \
    MONITOR_BRIGHTNESS_ACTION_ENTERED="$tmp/action-entered" \
    MONITOR_BRIGHTNESS_ACTION_LOG="$tmp/action-log" \
  MONITOR_BRIGHTNESS_SCENARIO=panel \
    timeout --foreground --kill-after=2s 45s "$quickshell" -n -p monitor-brightness-runtime-test.qml
}

run_budget() {
  write_control state-mode budget-unknown
  write_control state-entered initial
  : >"$tmp/state-log"
  : >"$tmp/action-log"
  MONITOR_BRIGHTNESS_SCENARIO=budget \
    MONITOR_BRIGHTNESS_STATE_DELAY=0.55 \
    MONITOR_BRIGHTNESS_STATE_MODE="$tmp/state-mode" \
    MONITOR_BRIGHTNESS_STATE_ENTERED="$tmp/state-entered" \
    MONITOR_BRIGHTNESS_STATE_LOG="$tmp/state-log" \
    MONITOR_BRIGHTNESS_ACTION_MODE="$tmp/action-mode" \
    MONITOR_BRIGHTNESS_ACTION_ENTERED="$tmp/action-entered" \
    MONITOR_BRIGHTNESS_ACTION_LOG="$tmp/action-log" \
    timeout --foreground --kill-after=2s 45s "$quickshell" -n -p monitor-brightness-runtime-test.qml
}

cd "$desktop_shell"
case "$scenario" in
  full)
    run_full
    ;;
  panel)
    run_panel
    ;;
  budget)
    run_budget
    ;;
  ordinary-failure|cached-stale|targeted-failure)
    action_mode=success
    action_executable="$desktop_shell/tests/fixtures/monitor-brightness/fake-action"
    run_failure
    ;;
  timeout)
    action_mode=success
    action_executable="$desktop_shell/tests/fixtures/monitor-brightness/fake-action"
    run_failure
    ;;
  action-timeout)
    action_mode=timeout
    action_executable="$desktop_shell/tests/fixtures/monitor-brightness/fake-action"
    run_failure
    ;;
  malformed-confirmation)
    action_mode=success
    action_executable="$desktop_shell/tests/fixtures/monitor-brightness/fake-action"
    run_failure
    ;;
  failed-start)
    action_mode=success
    action_executable="$tmp/missing-action"
    run_failure
    ;;
  generation)
    run_generation
    ;;
  *)
    printf '%s\n' "unknown scenario: $scenario" >&2
    exit 64
    ;;
esac
