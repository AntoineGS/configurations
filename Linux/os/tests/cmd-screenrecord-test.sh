#!/usr/bin/env bash

set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
screenrecord="$repo_root/Linux/os/helpers/cmd-screenrecord"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

bin_dir="$test_root/bin"
videos_dir="$test_root/videos"
runtime_dir="$test_root/runtime"
state_dir="$runtime_dir/desktop-shell"
state_file="$state_dir/recording.json"
owner_file="$state_dir/recording.owner"
log_file="$test_root/screenrecord.log"
args_file="$test_root/args"
stdin_file="$test_root/stdin"
done_file="$test_root/done"
release_file="$test_root/release"
exit_file="$test_root/exit"
pid_file="$test_root/recorder.pid"
notify_file="$test_root/notify"
ffmpeg_file="$test_root/ffmpeg"
chmod_hook_file="$test_root/state-chmod-hook"
launch_count_file="$test_root/launch-count"
ffmpeg_block_file="$test_root/ffmpeg-block"
ffmpeg_release_file="$test_root/ffmpeg-release"
probe_barrier_file="$test_root/probe-barrier"
probe_release_file="$test_root/probe-release"
lock_failure_runtime="$test_root/lock-failure-runtime"
flock_failure_runtime="$test_root/flock-failure-runtime"
mkdir -p "$bin_dir" "$videos_dir" "$runtime_dir"
export TEST_LAUNCH_COUNT_FILE="$launch_count_file"

cat >"$bin_dir/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_PGREP_FORCE_INACTIVE:-0} == 1 ]] && exit 1
if [[ ${TEST_PROBE_BARRIER:-0} == 1 && ! -e $TEST_PROBE_RELEASE_FILE ]]; then
  : >"$TEST_PROBE_BARRIER_FILE"
  while [[ ! -e $TEST_PROBE_RELEASE_FILE ]]; do sleep 0.01; done
fi
pid=""
[[ -f $TEST_PID_FILE ]] && pid=$(<"$TEST_PID_FILE")
if [[ -n $pid && -e "/proc/$pid" && $(ps -o stat= -p "$pid" 2>/dev/null) != Z* && ${TEST_PGREP_ERROR:-0} != 1 ]]; then
  printf '%s\n' "$pid"
  exit 0
fi
[[ ${TEST_PGREP_ERROR:-0} == 1 ]] && exit 2
exit 1
EOF

cat >"$bin_dir/pkill" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == -SIGINT ]]; then
  : >"$TEST_RELEASE_FILE"
  : >"$TEST_EXIT_FILE"
  exit 0
fi
exit 0
EOF

cat >"$bin_dir/flock" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_FLOCK_FAIL:-0} == 1 ]] && exit 75
exec /usr/bin/flock "$@"
EOF

cat >"$bin_dir/date" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '2026-08-26_00-00-00'
EOF

cat >"$bin_dir/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '[{"focused":true,"width":1920,"height":1080}]'
EOF

cat >"$bin_dir/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TEST_NOTIFY_FILE"
EOF

cat >"$bin_dir/ffmpeg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_FFMPEG_FILE"
if [[ ${TEST_FFMPEG_BLOCK:-0} == 1 ]]; then
  : >"$TEST_FFMPEG_BLOCK_FILE"
  while [[ ! -e $TEST_FFMPEG_RELEASE_FILE ]]; do sleep 0.01; done
fi
output=""
previous=""
for arg in "$@"; do
  [[ $arg == -loglevel ]] && output=$previous
  previous=$arg
done
touch "$output"
EOF

cat >"$bin_dir/chmod" <<'EOF'
#!/usr/bin/env bash
if [[ ${TEST_STATE_CHMOD_FAIL:-0} == 1 && ${1:-} == 600 && ${2:-} == *".recording.state."* ]]; then
  : >"$TEST_CHMOD_HOOK_FILE"
  exit 1
fi
if [[ ${1:-} == 600 && ${2:-} == "${TEST_CHMOD_FAIL_PATH:-}" ]]; then
  exit 1
fi
exec /usr/bin/chmod "$@"
EOF

cat >"$bin_dir/gpu-screen-recorder" <<'EOF'
#!/usr/bin/env bash

printf '%s\n' "$@" >"$TEST_ARGS_FILE"
printf '%s\n' launched >>"$TEST_LAUNCH_COUNT_FILE"
readlink "/proc/$$/fd/0" >"$TEST_STDIN_FILE"
: >"$TEST_PID_FILE"
printf '%s\n' "$$" >"$TEST_PID_FILE"
trap ': >"$TEST_EXIT_FILE"; : >"$TEST_RELEASE_FILE"; exit 130' INT TERM

if [[ ${TEST_RECORDER_FAIL:-0} == 1 ]]; then
  exit 1
fi

output=""
previous=""
for arg in "$@"; do
  [[ $previous == "-o" ]] && output=$arg
  previous=$arg
done

: >"$output"
if [[ ${TEST_PREPUBLICATION_BLOCK:-0} == 1 ]]; then
  while [[ ! -e $TEST_RELEASE_FILE ]]; do sleep 0.01; done
fi
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -e $TEST_RELEASE_FILE ]] && break
  sleep 0.01
done
[[ -e $TEST_RELEASE_FILE ]] || exit 124
printf '%s\n' 'late recorder stdout'
printf '%s\n' 'late recorder stderr' >&2
: >"$TEST_DONE_FILE"
while [[ ! -e $TEST_EXIT_FILE ]]; do sleep 0.01; done
EOF

cat >"$bin_dir/v4l2-ctl" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --list-formats-ext ]]; then
  printf '%s\n' '640x360'
else
  printf '%s\n' '/dev/video0'
fi
EOF

cat >"$bin_dir/ffplay" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$TEST_WEBCAM_PID_FILE"
trap 'exit 130' INT TERM
while :; do sleep 0.01; done
EOF

chmod +x "$bin_dir/pgrep" "$bin_dir/pkill" "$bin_dir/flock" "$bin_dir/date" "$bin_dir/hyprctl" "$bin_dir/notify-send" "$bin_dir/ffmpeg" "$bin_dir/chmod" \
  "$bin_dir/gpu-screen-recorder" "$bin_dir/v4l2-ctl" "$bin_dir/ffplay"

PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  SCREENRECORD_LOG_FILE="$log_file" \
  TEST_ARGS_FILE="$args_file" \
  TEST_STDIN_FILE="$stdin_file" \
  TEST_DONE_FILE="$done_file" \
  TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" \
  TEST_PID_FILE="$pid_file" \
  TEST_NOTIFY_FILE="$notify_file" \
  TEST_FFMPEG_FILE="$ffmpeg_file" \
  TEST_WEBCAM_PID_FILE="$test_root/webcam.pid" \
  TEST_CHMOD_HOOK_FILE="$chmod_hook_file" \
  "$screenrecord" --resolution=0x0

[[ ! -e $done_file ]] || {
  printf '%s\n' 'helper waited for the background recorder to exit' >&2
  exit 1
}

[[ -d $state_dir ]] || {
  printf '%s\n' 'recording state directory was not created' >&2
  exit 1
}
[[ $(stat -c '%a' "$state_dir") == 700 ]] || {
  printf 'expected recording state directory mode 700, got %s\n' "$(stat -c '%a' "$state_dir")" >&2
  exit 1
}
[[ -f $state_file ]] || {
  printf '%s\n' 'recording state file was not published' >&2
  exit 1
}
[[ $(stat -c '%a' "$state_file") == 600 ]] || {
  printf 'expected recording state mode 600, got %s\n' "$(stat -c '%a' "$state_file")" >&2
  exit 1
}
jq -e --arg output_prefix "$videos_dir/screenrecording-2026-08-26_00-00-00-" \
  '.version == 1 and .active == true and (.output | startswith($output_prefix)) and (keys == ["active", "output", "version"])' "$state_file" >/dev/null || {
  printf '%s\n' 'recording state JSON did not describe the active output' >&2
  exit 1
}
[[ -f $owner_file && $(stat -c '%a' "$owner_file") == 600 ]] || {
  printf '%s\n' 'recording owner sidecar was not securely published' >&2
  exit 1
}

: >"$release_file"
for ((attempt = 0; attempt < 50; attempt++)); do
  [[ -e $done_file ]] && break
  sleep 0.01
done

[[ -e $done_file ]] || {
  printf '%s\n' 'recorder did not survive the helper process exiting' >&2
  exit 1
}

[[ -e $state_file ]] || {
  printf '%s\n' 'natural recorder exit test requires active state' >&2
  exit 1
}
: >"$exit_file"
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ ! -e $state_file ]] && break
  sleep 0.01
done
[[ ! -e $state_file ]] || {
  printf '%s\n' 'natural recorder exit did not remove its state' >&2
  exit 1
}

[[ $(<"$stdin_file") == /dev/null ]] || {
  printf 'expected recorder stdin to be /dev/null, got %s\n' "$(<"$stdin_file")" >&2
  exit 1
}

codec=$(grep -A1 '^-k$' "$args_file" | tail -n1)
[[ $codec == auto ]] || {
  printf 'expected automatic codec selection, got %s\n' "$codec" >&2
  exit 1
}

expected_log=$'late recorder stdout\nlate recorder stderr'
[[ $(<"$log_file") == "$expected_log" ]] || {
  printf '%s\n' 'recorder output was not written to the configured log' >&2
  exit 1
}

rm -f "$done_file" "$exit_file" "$release_file"
PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  SCREENRECORD_LOG_FILE="$log_file" \
  TEST_ARGS_FILE="$args_file" \
  TEST_STDIN_FILE="$stdin_file" \
  TEST_DONE_FILE="$done_file" \
  TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" \
  TEST_PID_FILE="$pid_file" \
  TEST_NOTIFY_FILE="$notify_file" \
  TEST_FFMPEG_FILE="$ffmpeg_file" \
  TEST_CHMOD_HOOK_FILE="$chmod_hook_file" \
  "$screenrecord" --resolution=0x0
: >"$release_file"
for ((attempt = 0; attempt < 50; attempt++)); do
  [[ -e $done_file ]] && break
  sleep 0.01
done
[[ -f $state_file ]] || {
  printf '%s\n' 'active stop test state was not published' >&2
  exit 1
}

PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  SCREENRECORD_LOG_FILE="$log_file" \
  TEST_ARGS_FILE="$args_file" \
  TEST_STDIN_FILE="$stdin_file" \
  TEST_DONE_FILE="$done_file" \
  TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" \
  TEST_PID_FILE="$pid_file" \
  TEST_NOTIFY_FILE="$notify_file" \
  TEST_FFMPEG_FILE="$ffmpeg_file" \
  TEST_CHMOD_HOOK_FILE="$chmod_hook_file" \
  "$screenrecord" --stop-recording

[[ ! -e $state_file ]] || {
  printf '%s\n' 'recording state file survived stop' >&2
  exit 1
}

grep -Fq "$videos_dir/screenrecording-2026-08-26_00-00-00-" "$ffmpeg_file" || {
  printf '%s\n' 'stop path did not parse JSON output for trim/preview' >&2
  exit 1
}

rm -f "$done_file" "$exit_file" "$release_file"
PATH="$bin_dir:$PATH" SCREENRECORD_DIR="$videos_dir" XDG_RUNTIME_DIR="$runtime_dir" \
  TEST_ARGS_FILE="$args_file" TEST_STDIN_FILE="$stdin_file" TEST_DONE_FILE="$done_file" TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" TEST_PID_FILE="$pid_file" TEST_NOTIFY_FILE="$notify_file" TEST_FFMPEG_FILE="$ffmpeg_file" \
  "$screenrecord" --resolution=0x0
: >"$release_file"
for ((attempt = 0; attempt < 50; attempt++)); do [[ -e $done_file ]] && break; sleep 0.01; done
printf '%s\n' '{broken-owner' >"$owner_file"
PATH="$bin_dir:$PATH" SCREENRECORD_DIR="$videos_dir" XDG_RUNTIME_DIR="$runtime_dir" \
  TEST_ARGS_FILE="$args_file" TEST_STDIN_FILE="$stdin_file" TEST_DONE_FILE="$done_file" TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" TEST_PID_FILE="$pid_file" TEST_NOTIFY_FILE="$notify_file" TEST_FFMPEG_FILE="$ffmpeg_file" \
  "$screenrecord" --stop-recording
[[ ! -e "$state_file" && ! -e "$owner_file" ]] || exit 1

rm -f "$done_file" "$exit_file" "$release_file" "$ffmpeg_block_file" "$ffmpeg_release_file"
PATH="$bin_dir:$PATH" SCREENRECORD_DIR="$videos_dir" XDG_RUNTIME_DIR="$runtime_dir" \
  TEST_ARGS_FILE="$args_file" TEST_STDIN_FILE="$stdin_file" TEST_DONE_FILE="$done_file" TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" TEST_PID_FILE="$pid_file" TEST_NOTIFY_FILE="$notify_file" TEST_FFMPEG_FILE="$ffmpeg_file" \
  "$screenrecord" --resolution=0x0
: >"$release_file"
for ((attempt = 0; attempt < 50; attempt++)); do [[ -e $done_file ]] && break; sleep 0.01; done
PATH="$bin_dir:$PATH" SCREENRECORD_DIR="$videos_dir" XDG_RUNTIME_DIR="$runtime_dir" \
  TEST_ARGS_FILE="$args_file" TEST_STDIN_FILE="$stdin_file" TEST_DONE_FILE="$done_file" TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" TEST_PID_FILE="$pid_file" TEST_NOTIFY_FILE="$notify_file" TEST_FFMPEG_FILE="$ffmpeg_file" \
  TEST_FFMPEG_BLOCK=1 TEST_FFMPEG_BLOCK_FILE="$ffmpeg_block_file" TEST_FFMPEG_RELEASE_FILE="$ffmpeg_release_file" \
  "$screenrecord" --stop-recording 2>"$test_root/signal-stop.err" &
signal_stop=$!
for ((attempt = 0; attempt < 100; attempt++)); do [[ -e $ffmpeg_block_file ]] && break; sleep 0.01; done
[[ -e $ffmpeg_block_file ]] || exit 1
kill -TERM "$signal_stop"
: >"$ffmpeg_release_file"
wait "$signal_stop" 2>/dev/null || true
[[ ! -e "$state_file" && ! -e "$owner_file" ]] || {
  printf '%s\n' 'signal-interrupted stop left recording state' >&2
  exit 1
}

failed_runtime_dir="$test_root/failed-runtime"
mkdir "$failed_runtime_dir"
rm -f "$pid_file"
status=0
PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  XDG_RUNTIME_DIR="$failed_runtime_dir" \
  SCREENRECORD_LOG_FILE="$log_file" \
  TEST_ARGS_FILE="$args_file" \
  TEST_STDIN_FILE="$stdin_file" \
  TEST_DONE_FILE="$done_file" \
  TEST_RELEASE_FILE="$release_file" \
  TEST_PID_FILE="$pid_file" \
  TEST_NOTIFY_FILE="$notify_file" \
  TEST_CHMOD_HOOK_FILE="$chmod_hook_file" \
  TEST_PGREP_FORCE_INACTIVE=1 \
  TEST_RECORDER_FAIL=1 \
  "$screenrecord" --resolution=0x0 || status=$?

((status != 0)) || {
  printf '%s\n' 'failed recorder launch unexpectedly succeeded' >&2
  exit 1
}
[[ ! -e "$failed_runtime_dir/desktop-shell/recording.json" ]] || {
  printf '%s\n' 'failed recorder launch published recording state' >&2
  exit 1
}

publication_failure_runtime="$test_root/publication-failure-runtime"
mkdir "$publication_failure_runtime"
rm -f "$release_file" "$exit_file" "$done_file" "$chmod_hook_file"
status=0
PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  XDG_RUNTIME_DIR="$publication_failure_runtime" \
  SCREENRECORD_LOG_FILE="$log_file" \
  TEST_ARGS_FILE="$args_file" \
  TEST_STDIN_FILE="$stdin_file" \
  TEST_DONE_FILE="$done_file" \
  TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" \
  TEST_PID_FILE="$pid_file" \
  TEST_NOTIFY_FILE="$notify_file" \
  TEST_CHMOD_HOOK_FILE="$chmod_hook_file" \
  TEST_STATE_CHMOD_FAIL=1 \
  "$screenrecord" --resolution=0x0 || status=$?
((status != 0)) || {
  printf '%s\n' 'publication failure unexpectedly succeeded' >&2
  exit 1
}
[[ -e "$chmod_hook_file" ]] || {
  printf '%s\n' 'publication failure did not reach state chmod failure' >&2
  exit 1
}
publication_pid=$(<"$pid_file")
[[ ! -e "/proc/$publication_pid" ]] || {
  printf '%s\n' 'publication failure left recorder running' >&2
  exit 1
}
[[ ! -e "$publication_failure_runtime/desktop-shell/recording.json" ]] || {
  printf '%s\n' 'publication failure left state published' >&2
  exit 1
}
[[ ! -e "$publication_failure_runtime/desktop-shell/recording.owner" ]] || exit 1
compgen -G "$publication_failure_runtime/desktop-shell/.recording.state.*" >/dev/null && exit 1 || true

relative_status=0
PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR=relative-videos \
  XDG_RUNTIME_DIR="$runtime_dir" \
  TEST_NOTIFY_FILE="$notify_file" \
  "$screenrecord" --resolution=0x0 || relative_status=$?
((relative_status != 0)) || {
  printf '%s\n' 'relative recording directory was accepted' >&2
  exit 1
}

concurrent_runtime="$test_root/concurrent-runtime"
mkdir "$concurrent_runtime"
rm -f "$release_file" "$exit_file" "$done_file" "$pid_file" "$launch_count_file" "$probe_barrier_file" "$probe_release_file"
PATH="$bin_dir:$PATH" XDG_RUNTIME_DIR="$concurrent_runtime" SCREENRECORD_DIR="$videos_dir" \
  TEST_ARGS_FILE="$args_file" TEST_STDIN_FILE="$stdin_file" TEST_DONE_FILE="$done_file" TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" TEST_PID_FILE="$pid_file" TEST_NOTIFY_FILE="$notify_file" TEST_FFMPEG_FILE="$ffmpeg_file" \
  TEST_PROBE_BARRIER=1 TEST_PROBE_BARRIER_FILE="$probe_barrier_file" TEST_PROBE_RELEASE_FILE="$probe_release_file" \
  "$screenrecord" --resolution=0x0 &
start_a=$!
PATH="$bin_dir:$PATH" XDG_RUNTIME_DIR="$concurrent_runtime" SCREENRECORD_DIR="$videos_dir" \
  TEST_ARGS_FILE="$args_file" TEST_STDIN_FILE="$stdin_file" TEST_DONE_FILE="$done_file" TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" TEST_PID_FILE="$pid_file" TEST_NOTIFY_FILE="$notify_file" TEST_FFMPEG_FILE="$ffmpeg_file" \
  TEST_PROBE_BARRIER=1 TEST_PROBE_BARRIER_FILE="$probe_barrier_file" TEST_PROBE_RELEASE_FILE="$probe_release_file" \
  "$screenrecord" --resolution=0x0 &
start_b=$!
for ((attempt = 0; attempt < 100; attempt++)); do [[ -e $probe_barrier_file ]] && break; sleep 0.01; done
[[ -e $probe_barrier_file ]] || exit 1
[[ ! -e "$concurrent_runtime/desktop-shell/recording.json" ]] || exit 1
: >"$probe_release_file"
for ((attempt = 0; attempt < 100; attempt++)); do [[ -e "$concurrent_runtime/desktop-shell/recording.json" ]] && break; sleep 0.01; done
[[ -e "$concurrent_runtime/desktop-shell/recording.json" ]] || exit 1
[[ $(wc -l <"$launch_count_file") == 1 ]] || {
  printf '%s\n' 'concurrent inactive invocations started multiple recorders' >&2
  exit 1
}
wait "$start_a"
wait "$start_b"
[[ ! -e "$concurrent_runtime/desktop-shell/recording.json" ]] || exit 1

stale_runtime="$test_root/stale-runtime"
mkdir -p "$stale_runtime/desktop-shell"
printf '%s\n' '{"version":1,"active":true,"output":"/tmp/stale.mp4"}' >"$stale_runtime/desktop-shell/recording.json"
printf '%s\n' '{"session":"stale","pid":123}' >"$stale_runtime/desktop-shell/recording.owner"
PATH="$bin_dir:$PATH" XDG_RUNTIME_DIR="$stale_runtime" SCREENRECORD_DIR="$videos_dir" \
  TEST_PID_FILE="$pid_file" TEST_PGREP_FORCE_INACTIVE=1 "$screenrecord" --stop-recording || true
[[ ! -e "$stale_runtime/desktop-shell/recording.json" && ! -e "$stale_runtime/desktop-shell/recording.owner" ]] || {
  printf '%s\n' 'explicit stop retained stale valid state' >&2
  exit 1
}

malformed_state_runtime="$test_root/malformed-runtime"
mkdir -p "$malformed_state_runtime/desktop-shell"
printf '%s\n' '{not-json' >"$malformed_state_runtime/desktop-shell/recording.json"
PATH="$bin_dir:$PATH" \
  XDG_RUNTIME_DIR="$malformed_state_runtime" \
  SCREENRECORD_DIR="$videos_dir" \
  TEST_PID_FILE="$pid_file" \
  "$screenrecord" --reconcile-state
[[ ! -e "$malformed_state_runtime/desktop-shell/recording.json" ]] || {
  printf '%s\n' 'inactive malformed state was not removed' >&2
  exit 1
}

reconcile_runtime="$test_root/reconcile-runtime"
mkdir -p "$reconcile_runtime/desktop-shell"
reconcile_output="$videos_dir/video with spaces.mp4"
bash -c 'exec -a gpu-screen-recorder bash -c "sleep 5; :" -- -o "$1"' _ "$reconcile_output" &
reconcile_pid=$!
printf '%s\n' "$reconcile_pid" >"$pid_file"
printf '%s\n' '{"version":1,"active":true,"output":"'"$reconcile_output"'"}' >"$reconcile_runtime/desktop-shell/recording.json"
printf '%s\n' '{"session":"old-session","pid":1}' >"$reconcile_runtime/desktop-shell/recording.owner"
PATH="$bin_dir:$PATH" \
  XDG_RUNTIME_DIR="$reconcile_runtime" \
  SCREENRECORD_DIR="$videos_dir" \
  TEST_PID_FILE="$pid_file" \
  "$screenrecord" --reconcile-state
jq -e --arg output "$reconcile_output" '.version == 1 and .active == true and .output == $output' \
  "$reconcile_runtime/desktop-shell/recording.json" >/dev/null || {
  printf '%s\n' 'reconciliation did not preserve spaces in recorder output' >&2
  exit 1
}
[[ $(jq -r '.pid' "$reconcile_runtime/desktop-shell/recording.owner") == "$reconcile_pid" ]] || exit 1
[[ $(stat -c '%a' "$reconcile_runtime/desktop-shell") == 700 ]] || exit 1
[[ $(stat -c '%a' "$reconcile_runtime/desktop-shell/recording.json") == 600 ]] || exit 1
status=0
PATH="$bin_dir:$PATH" \
  XDG_RUNTIME_DIR="$reconcile_runtime" \
  SCREENRECORD_DIR="$videos_dir" \
  TEST_PID_FILE="$pid_file" \
  TEST_PGREP_ERROR=1 \
  "$screenrecord" --reconcile-state || status=$?
((status != 0)) || exit 1
[[ -f "$reconcile_runtime/desktop-shell/recording.json" ]] || exit 1
kill "$reconcile_pid" 2>/dev/null || true
wait "$reconcile_pid" 2>/dev/null || true
PATH="$bin_dir:$PATH" \
  XDG_RUNTIME_DIR="$reconcile_runtime" \
  SCREENRECORD_DIR="$videos_dir" \
  TEST_PID_FILE="$pid_file" \
  "$screenrecord" --reconcile-state
[[ ! -e "$reconcile_runtime/desktop-shell/recording.json" ]] || {
  printf '%s\n' 'inactive reconciliation retained state' >&2
  exit 1
}

malformed_stop_runtime="$test_root/malformed-stop-runtime"
mkdir -p "$malformed_stop_runtime/desktop-shell"
printf '%s\n' '{broken' >"$malformed_stop_runtime/desktop-shell/recording.json"
status=0
PATH="$bin_dir:$PATH" \
  XDG_RUNTIME_DIR="$malformed_stop_runtime" \
  SCREENRECORD_DIR="$videos_dir" \
  TEST_PID_FILE="$pid_file" \
  TEST_PGREP_FORCE_INACTIVE=1 \
  "$screenrecord" --stop-recording || status=$?
((status != 0)) || exit 1
[[ ! -e "$malformed_stop_runtime/desktop-shell/recording.json" ]] || {
  printf '%s\n' 'malformed explicit stop retained state' >&2
  exit 1
}

generation_runtime="$test_root/generation-runtime"
mkdir -p "$generation_runtime/desktop-shell"
old_output="$videos_dir/screenrecording-same-second.mp4"
new_output="$videos_dir/screenrecording-same-second.mp4"
jq -cn --arg output "$new_output" \
  '{version:1,active:true,output:$output}' \
  >"$generation_runtime/desktop-shell/recording.json"
printf '%s\n' '{"session":"new-session","pid":99999}' >"$generation_runtime/desktop-shell/recording.owner"
chmod 600 "$generation_runtime/desktop-shell/recording.owner"
PATH="$bin_dir:$PATH" \
  XDG_RUNTIME_DIR="$generation_runtime" \
  SCREENRECORD_DIR="$videos_dir" \
  "$screenrecord" --cleanup-if-identity old-session 11111 "$old_output"
jq -e 'keys == ["active", "output", "version"]' \
  "$generation_runtime/desktop-shell/recording.json" >/dev/null || {
  printf '%s\n' 'old generation cleanup touched newer state' >&2
  exit 1
}

mkdir -p "$lock_failure_runtime/desktop-shell"
printf '%s\n' '{"version":1,"active":true,"output":"/tmp/current.mp4","session":"current","pid":1}' \
  >"$lock_failure_runtime/desktop-shell/recording.json"
mkdir "$lock_failure_runtime/desktop-shell/.recording.lock"
status=0
PATH="$bin_dir:$PATH" \
  XDG_RUNTIME_DIR="$lock_failure_runtime" \
  SCREENRECORD_DIR="$videos_dir" \
  TEST_FLOCK_FAIL=1 \
  "$screenrecord" --reconcile-state || status=$?
((status != 0)) || exit 1
[[ -f "$lock_failure_runtime/desktop-shell/recording.json" ]] || exit 1

mkdir -p "$flock_failure_runtime/desktop-shell"
printf '%s\n' '{"version":1,"active":true,"output":"/tmp/current.mp4","session":"current","pid":1}' \
  >"$flock_failure_runtime/desktop-shell/recording.json"
status=0
PATH="$bin_dir:$PATH" \
  XDG_RUNTIME_DIR="$flock_failure_runtime" \
  SCREENRECORD_DIR="$videos_dir" \
  TEST_FLOCK_FAIL=1 \
  "$screenrecord" --reconcile-state || status=$?
((status != 0)) || exit 1
[[ -f "$flock_failure_runtime/desktop-shell/recording.json" ]] || exit 1

[[ $(stat -c '%a' "$log_file") == 600 ]] || {
  printf 'expected recorder log mode 600, got %s\n' "$(stat -c '%a' "$log_file")" >&2
  exit 1
}

prepublication_runtime="$test_root/prepublication-runtime"
prepublication_state="$prepublication_runtime/desktop-shell"
prepublication_pid_file="$test_root/prepublication.pid"
prepublication_webcam_pid_file="$test_root/prepublication-webcam.pid"
mkdir -p "$prepublication_runtime"
set +e
PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  XDG_RUNTIME_DIR="$prepublication_runtime" \
  TEST_PID_FILE="$prepublication_pid_file" \
  TEST_WEBCAM_PID_FILE="$prepublication_webcam_pid_file" \
  TEST_ARGS_FILE="$args_file" \
  TEST_STDIN_FILE="$stdin_file" \
  TEST_DONE_FILE="$done_file" \
  TEST_RELEASE_FILE="$release_file" \
  TEST_EXIT_FILE="$exit_file" \
  TEST_NOTIFY_FILE="$notify_file" \
  TEST_LAUNCH_COUNT_FILE="$launch_count_file" \
  TEST_PREPUBLICATION_BLOCK=1 \
  "$screenrecord" --with-webcam --webcam-device=/dev/video0 --resolution=0x0 &
prepublication_helper_pid=$!
set -e
for _ in {1..100}; do [[ -f "$prepublication_pid_file" && -f "$prepublication_webcam_pid_file" ]] && break; sleep 0.01; done
[[ -f "$prepublication_pid_file" && -f "$prepublication_webcam_pid_file" ]] || exit 1
kill -TERM "$prepublication_helper_pid"
wait "$prepublication_helper_pid" 2>/dev/null || true
recorder_pid=$(<"$prepublication_pid_file")
webcam_pid=$(<"$prepublication_webcam_pid_file")
[[ ! -e "/proc/$recorder_pid" && ! -e "/proc/$webcam_pid" ]] || {
  printf '%s\n' 'pre-publication signal left an owned child alive' >&2
  exit 1
}
[[ ! -e "$prepublication_state/recording.json" && ! -e "$prepublication_state/recording.owner" ]] || {
  printf '%s\n' 'pre-publication signal left recording state behind' >&2
  exit 1
}

bad_log="$test_root/log-directory"
mkdir "$bad_log"
status=0
PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  SCREENRECORD_LOG_FILE="$bad_log" \
  TEST_ARGS_FILE="$args_file" \
  TEST_STDIN_FILE="$stdin_file" \
  TEST_DONE_FILE="$done_file" \
  TEST_RELEASE_FILE="$release_file" \
  TEST_NOTIFY_FILE="$notify_file" \
  "$screenrecord" --resolution=0x0 || status=$?
chmod 700 "$bad_log"

((status != 0)) || {
  printf '%s\n' 'directory log path did not fail recorder startup' >&2
  exit 1
}

grep -q 'Could not prepare recorder log' "$notify_file" || {
  printf '%s\n' 'invalid log path did not produce an error notification' >&2
  exit 1
}

chmod_log="$test_root/chmod-failure.log"
status=0
rm -f "$notify_file"
PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  SCREENRECORD_LOG_FILE="$chmod_log" \
  TEST_ARGS_FILE="$args_file" \
  TEST_STDIN_FILE="$stdin_file" \
  TEST_DONE_FILE="$done_file" \
  TEST_RELEASE_FILE="$release_file" \
  TEST_NOTIFY_FILE="$notify_file" \
  TEST_CHMOD_FAIL_PATH="$chmod_log" \
  "$screenrecord" --resolution=0x0 || status=$?

((status != 0)) || {
  printf '%s\n' 'recorder startup ignored private log permission failure' >&2
  exit 1
}

grep -q 'Could not prepare recorder log' "$notify_file" || {
  printf '%s\n' 'log permission failure did not produce an error notification' >&2
  exit 1
}

printf '%s\n' 'screenrecord lifecycle test passed'
