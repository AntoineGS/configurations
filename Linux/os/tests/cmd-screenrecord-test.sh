#!/bin/bash

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
SCREENRECORD="$REPO_ROOT/Linux/os/helpers/cmd-screenrecord"
MENU="$REPO_ROOT/Linux/os/helpers/menu"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

BIN="$TEST_ROOT/bin"
HOME_DIR="$TEST_ROOT/home"
VIDEOS="$TEST_ROOT/videos"
GSR_ARGS="$TEST_ROOT/gpu-screen-recorder-args"
MENU_ARGS="$TEST_ROOT/menu-args"
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
exit 0
EOF

cat >"$BIN/date" <<'EOF'
#!/bin/bash
printf '2026-07-25_00-00-00\n'
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

printf '%s\n' "$@" >"$TEST_GSR_ARGS"

output=""
previous=""
for arg in "$@"; do
  [[ $previous == "-o" ]] && output="$arg"
  previous="$arg"
done

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

run_screenrecord() {
  rm -f "$GSR_ARGS"
  PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_GSR_ARGS="$GSR_ARGS" SCREENRECORD_STATE_FILE="$STATE_FILE" \
    "$SCREENRECORD" "$@"
}

run_screenrecord --region --resolution=0x0
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
$VIDEOS/screenrecording-2026-07-25_00-00-00.mp4"
assert_equal "$(<"$GSR_ARGS")" "$expected"
[[ -f $STATE_FILE ]] || {
  printf 'screen recording state was not written to the isolated test path\n' >&2
  exit 1
}

run_screenrecord --resolution=0x0
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
$VIDEOS/screenrecording-2026-07-25_00-00-00.mp4"
assert_equal "$(<"$GSR_ARGS")" "$expected"

rm -f "$GSR_ARGS"
PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_GSR_ARGS="$GSR_ARGS" TEST_SLURP_CANCEL=true \
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

cat >"$BIN/vicinae" <<'EOF'
#!/bin/bash

case "$*" in
*"Capture area"*) printf '%s\n' "${TEST_CAPTURE_CHOICE:-Region}" ;;
*Screenrecord*) printf '%s\n' "${TEST_AUDIO_CHOICE:-With no audio}" ;;
*) exit 1 ;;
esac
EOF

cat >"$BIN/cmd-screenrecord" <<'EOF'
#!/bin/bash

[[ ${1:-} == "--stop-recording" ]] && exit 1
: >"$TEST_MENU_ARGS"
(($# == 0)) || printf '%s\n' "$@" >>"$TEST_MENU_ARGS"
EOF

chmod +x "$BIN/vicinae" "$BIN/cmd-screenrecord"

PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_MENU_ARGS="$MENU_ARGS" TEST_CAPTURE_CHOICE=Region "$MENU" screenrecord
assert_equal "$(<"$MENU_ARGS")" "--region"

PATH="$BIN:$PATH" HOME="$HOME_DIR" TEST_MENU_ARGS="$MENU_ARGS" TEST_CAPTURE_CHOICE="Screen / window" "$MENU" screenrecord
assert_equal "$(<"$MENU_ARGS")" ""

printf '%s\n' 'screenrecord routing tests passed'
