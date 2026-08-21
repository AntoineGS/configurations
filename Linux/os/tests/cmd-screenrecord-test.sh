#!/bin/bash

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
SCREENRECORD="$REPO_ROOT/Linux/os/helpers/cmd-screenrecord"
MENU="$REPO_ROOT/Linux/os/helpers/menu"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

if grep -Eiq 'waybar|restart-waybar|RTMIN\+[0-9]+' "$SCREENRECORD"; then
  printf '%s\n' 'screenrecord still contains legacy desktop indicator behavior' >&2
  exit 1
fi

BIN="$TEST_ROOT/bin"
HOME_DIR="$TEST_ROOT/home"
VIDEOS="$TEST_ROOT/videos"
GSR_ARGS="$TEST_ROOT/gpu-screen-recorder-args"
MENU_ARGS="$TEST_ROOT/menu-args"
NOTIFY_ARGS="$TEST_ROOT/notify-args"
WEBCAM_STARTED="$TEST_ROOT/webcam-started"
STATE_FILE="$TEST_ROOT/screenrecord-filename"
mkdir -p "$BIN" "$HOME_DIR/.config" "$VIDEOS"
printf 'XDG_VIDEOS_DIR="%s"\n' "$VIDEOS" >"$HOME_DIR/.config/user-dirs.dirs"

cat >"$BIN/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$BIN/pkill" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$BIN/notify-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_NOTIFY_ARGS"
EOF

cat >"$BIN/date" <<'EOF'
#!/bin/bash
printf '%s\n' "${TEST_DATE_VALUE:-2026-07-25_00-00-00}"
EOF

cat >"$BIN/slurp" <<'EOF'
#!/bin/bash
[[ ${TEST_SLURP_CANCEL:-false} == "true" ]] && exit 1
printf '%s\n' "${TEST_SLURP_RESULT:-640x480+100+200}"
EOF

cat >"$BIN/hyprctl" <<'EOF'
#!/bin/bash
printf '%s\n' '[{"focused":true,"scale":1}]'
EOF

cat >"$BIN/v4l2-ctl" <<'EOF'
#!/bin/bash
printf '%s\n' 'Size: Discrete 640x360'
EOF

cat >"$BIN/ffplay" <<'EOF'
#!/bin/bash
: >"$TEST_WEBCAM_STARTED"
EOF

cat >"$BIN/gpu-screen-recorder" <<'EOF'
#!/bin/bash

args_tmp="${TEST_GSR_ARGS}.tmp"
printf '%s\n' "$@" >"$args_tmp"
mv -- "$args_tmp" "$TEST_GSR_ARGS"

output=""
previous=""
for arg in "$@"; do
  [[ $previous == "-o" ]] && output="$arg"
  previous="$arg"
done

sleep 0.05
: >"$output"
sleep 0.2
EOF

chmod +x "$BIN/pgrep" "$BIN/pkill" "$BIN/notify-send" "$BIN/date" "$BIN/slurp" "$BIN/hyprctl" \
  "$BIN/v4l2-ctl" "$BIN/ffplay" "$BIN/gpu-screen-recorder"

assert_equal() {
  if [[ $1 != "$2" ]]; then
    printf 'expected:\n%s\nactual:\n%s\n' "$2" "$1" >&2
    exit 1
  fi
}

wait_for_notification() {
  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    [[ -e $NOTIFY_ARGS ]] && return 0
    sleep 0.01
  done
  printf 'notification stub was not called\n' >&2
  exit 1
}

wait_for_file() {
  local file=$1
  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    [[ -e $file ]] && return 0
    sleep 0.01
  done
  printf 'expected test output was not created: %s\n' "$file" >&2
  exit 1
}

run_screenrecord() {
  local date_value=$1
  shift
  rm -f "$GSR_ARGS"
  PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_DATE_VALUE="$date_value" \
    TEST_GSR_ARGS="$GSR_ARGS" TEST_NOTIFY_ARGS="$NOTIFY_ARGS" \
    SCREENRECORD_STATE_FILE="$STATE_FILE" SCREENRECORD_DIR="$VIDEOS" \
    "$SCREENRECORD" "$@"
}

run_screenrecord 2026-07-25_00-00-01 --region --resolution=0x0
wait_for_file "$GSR_ARGS"
expected="-w
640x480+100+200
-k
auto
-s
0x0
-f
60
-fm
cfr
-fallback-cpu-encoding
yes
-o
$VIDEOS/screenrecording-2026-07-25_00-00-01.mp4"
assert_equal "$(<"$GSR_ARGS")" "$expected"
[[ -f "$VIDEOS/screenrecording-2026-07-25_00-00-01.mp4" ]] || {
  printf '%s\n' 'first recording fixture was not created' >&2
  exit 1
}
[[ -f $STATE_FILE ]] || {
  printf 'screen recording state was not written to the isolated test path\n' >&2
  exit 1
}

run_screenrecord 2026-07-25_00-00-02 --resolution=0x0
wait_for_file "$GSR_ARGS"
expected="-w
portal
-k
auto
-s
0x0
-f
60
-fm
cfr
-fallback-cpu-encoding
yes
-o
$VIDEOS/screenrecording-2026-07-25_00-00-02.mp4"
assert_equal "$(<"$GSR_ARGS")" "$expected"
[[ -f "$VIDEOS/screenrecording-2026-07-25_00-00-01.mp4" &&
  -f "$VIDEOS/screenrecording-2026-07-25_00-00-02.mp4" ]] || {
  printf '%s\n' 'unique recording fixtures were not both created' >&2
  exit 1
}

rm -f "$GSR_ARGS"
PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_GSR_ARGS="$GSR_ARGS" TEST_SLURP_CANCEL=true SCREENRECORD_DIR="$VIDEOS" \
  TEST_WEBCAM_STARTED="$WEBCAM_STARTED" SCREENRECORD_STATE_FILE="$STATE_FILE" \
  "$SCREENRECORD" --region --with-webcam --webcam-device=/dev/video0 --resolution=0x0 || true
[[ ! -e $GSR_ARGS ]] || {
  printf 'region cancellation started gpu-screen-recorder\n' >&2
  exit 1
}
[[ ! -e $WEBCAM_STARTED ]] || {
  printf 'region cancellation started the webcam\n' >&2
  exit 1
}

cat >"$BIN/desktop-shell" <<'EOF'
#!/bin/bash

: >"$TEST_MENU_ARGS"
printf '%s\n' "$@" >>"$TEST_MENU_ARGS"
EOF

chmod +x "$BIN/desktop-shell"

PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_MENU_ARGS="$MENU_ARGS" "$MENU" trigger.screenrecord
expected_menu=$'summon\ndesktop.menu\n{"menu":"trigger.screenrecord"}'
assert_equal "$(<"$MENU_ARGS")" "$expected_menu"

rm -f "$MENU_ARGS"
set +e
PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_MENU_ARGS="$MENU_ARGS" "$MENU" 'trigger.screenrecord;touch /tmp/menu-test' 2>/dev/null
status=$?
set -e
[[ $status -eq 2 ]] || {
  printf 'menu accepted an unsafe route with status %d\n' "$status" >&2
  exit 1
}
[[ ! -e $MENU_ARGS ]] || {
  printf 'menu executed an unsafe route\n' >&2
  exit 1
}

cat >"$BIN/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$BIN/pgrep" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$BIN/pkill" <<'EOF'
#!/bin/bash
[[ ${1:-} == "-9" ]] && exit 1
exit 0
EOF

chmod +x "$BIN/sleep" "$BIN/pgrep" "$BIN/pkill"

stop_status=0
PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_NOTIFY_ARGS="$NOTIFY_ARGS" SCREENRECORD_DIR="$VIDEOS" \
  SCREENRECORD_STATE_FILE="$STATE_FILE" \
  "$SCREENRECORD" --stop-recording || stop_status=$?
[[ ! -e $STATE_FILE ]] || {
  printf 'screen recording state survived a raced hard kill\n' >&2
  exit 1
}
assert_equal "$stop_status" "0"

PGREP_COUNT="$TEST_ROOT/pgrep-count"
PREVIEW_VIDEO="$VIDEOS/preview-source.mp4"
: >"$PREVIEW_VIDEO"
printf '%s\n' "$PREVIEW_VIDEO" >"$STATE_FILE"
rm -f "$PGREP_COUNT"

cat >"$BIN/pgrep" <<'EOF'
#!/bin/bash

count=0
[[ -f $TEST_PGREP_COUNT ]] && count=$(<"$TEST_PGREP_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$TEST_PGREP_COUNT"
((count == 1))
EOF

# shellcheck disable=SC2016
cat >"$BIN/ffmpeg" <<'EOF'
#!/bin/bash

output=""
for arg in "$@"; do
  case "$arg" in
    *.mp4|*.png) output="$arg" ;;
  esac
done
: >"$output"
EOF

chmod +x "$BIN/pgrep" "$BIN/ffmpeg"
rm -f "$NOTIFY_ARGS"

stop_status=0
PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_NOTIFY_ARGS="$NOTIFY_ARGS" TEST_PGREP_COUNT="$PGREP_COUNT" \
  SCREENRECORD_DIR="$VIDEOS" SCREENRECORD_STATE_FILE="$STATE_FILE" \
  "$SCREENRECORD" --stop-recording || stop_status=$?
[[ ! -e $STATE_FILE ]] || {
  printf 'screen recording state survived successful preview generation\n' >&2
  exit 1
}
assert_equal "$stop_status" "0"
expected_notification="Screen recording saved
Open with Super + Alt + , (or click this)
-t
10000
-i
${PREVIEW_VIDEO%.mp4}-preview.png
-A
default=open"
wait_for_notification
assert_equal "$(<"$NOTIFY_ARGS")" "$expected_notification"

printf '%s\n' "$PREVIEW_VIDEO" >"$STATE_FILE"
rm -f "$PGREP_COUNT" "$NOTIFY_ARGS"

cat >"$BIN/ffmpeg" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$BIN/pkill" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$BIN/pgrep" "$BIN/ffmpeg" "$BIN/pkill"

stop_status=0
PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_NOTIFY_ARGS="$NOTIFY_ARGS" TEST_PGREP_COUNT="$PGREP_COUNT" \
  SCREENRECORD_DIR="$VIDEOS" \
  SCREENRECORD_STATE_FILE="$STATE_FILE" "$SCREENRECORD" --stop-recording || stop_status=$?
[[ ! -e $STATE_FILE ]] || {
  printf 'screen recording state survived preview generation failure\n' >&2
  exit 1
}
assert_equal "$stop_status" "0"
expected_notification="Screen recording saved
Open with Super + Alt + , (or click this)
-t
10000
-i
$PREVIEW_VIDEO
-A
default=open"
wait_for_notification
assert_equal "$(<"$NOTIFY_ARGS")" "$expected_notification"

printf '%s\n' 'screenrecord and menu routing tests passed'
