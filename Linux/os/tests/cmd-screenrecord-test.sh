#!/usr/bin/env bash

set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
screenrecord="$repo_root/Linux/os/helpers/cmd-screenrecord"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

bin_dir="$test_root/bin"
videos_dir="$test_root/videos"
state_file="$test_root/screenrecord-filename"
log_file="$test_root/screenrecord.log"
args_file="$test_root/args"
stdin_file="$test_root/stdin"
done_file="$test_root/done"
release_file="$test_root/release"
notify_file="$test_root/notify"
mkdir -p "$bin_dir" "$videos_dir"

cat >"$bin_dir/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
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

cat >"$bin_dir/chmod" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == 600 && ${2:-} == "${TEST_CHMOD_FAIL_PATH:-}" ]]; then
  exit 1
fi
exec /usr/bin/chmod "$@"
EOF

cat >"$bin_dir/gpu-screen-recorder" <<'EOF'
#!/usr/bin/env bash

printf '%s\n' "$@" >"$TEST_ARGS_FILE"
readlink "/proc/$$/fd/0" >"$TEST_STDIN_FILE"

output=""
previous=""
for arg in "$@"; do
  [[ $previous == "-o" ]] && output=$arg
  previous=$arg
done

: >"$output"
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -e $TEST_RELEASE_FILE ]] && break
  sleep 0.01
done
[[ -e $TEST_RELEASE_FILE ]] || exit 124
printf '%s\n' 'late recorder stdout'
printf '%s\n' 'late recorder stderr' >&2
: >"$TEST_DONE_FILE"
EOF

chmod +x "$bin_dir/pgrep" "$bin_dir/date" "$bin_dir/hyprctl" "$bin_dir/notify-send" "$bin_dir/chmod" \
  "$bin_dir/gpu-screen-recorder"

PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  SCREENRECORD_STATE_FILE="$state_file" \
  SCREENRECORD_LOG_FILE="$log_file" \
  TEST_ARGS_FILE="$args_file" \
  TEST_STDIN_FILE="$stdin_file" \
  TEST_DONE_FILE="$done_file" \
  TEST_RELEASE_FILE="$release_file" \
  TEST_NOTIFY_FILE="$notify_file" \
  "$screenrecord" --resolution=0x0

[[ ! -e $done_file ]] || {
  printf '%s\n' 'helper waited for the background recorder to exit' >&2
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

[[ $(stat -c '%a' "$log_file") == 600 ]] || {
  printf 'expected recorder log mode 600, got %s\n' "$(stat -c '%a' "$log_file")" >&2
  exit 1
}

bad_log="$test_root/log-directory"
mkdir "$bad_log"
status=0
PATH="$bin_dir:$PATH" \
  SCREENRECORD_DIR="$videos_dir" \
  SCREENRECORD_STATE_FILE="$state_file" \
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
  SCREENRECORD_STATE_FILE="$state_file" \
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
