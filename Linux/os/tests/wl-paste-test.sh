#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
wrapper=$repo_root/Linux/os/helpers/wl-paste
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin" "$tmp/local" "$tmp/remote"

cat >"$tmp/bin/tmux" <<'EOF'
#!/bin/sh
case $1 in
  display-message)
    printf '%s\n' test-session
    ;;
  show-environment)
    case ${TEST_TMUX_SHOW_ENVIRONMENT_RESULT-} in
      failure) exit 1 ;;
      malformed) printf 'invalid-%s\n' "$4" ;;
      unset) printf '%s%s\n' '-' "$4" ;;
      *)
        case "$#:$2:$3:$4" in
          4:-t:test-session:WAYLAND_DISPLAY) printf 'WAYLAND_DISPLAY=%s\n' "$TEST_TMUX_WAYLAND_DISPLAY" ;;
          4:-t:test-session:XDG_RUNTIME_DIR) printf 'XDG_RUNTIME_DIR=%s\n' "$TEST_TMUX_XDG_RUNTIME_DIR" ;;
          *) exit 1 ;;
        esac
        ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$tmp/bin/real-wl-paste" <<'EOF'
#!/bin/sh
printf 'display=%s\n' "${WAYLAND_DISPLAY-}"
printf 'runtime=%s\n' "${XDG_RUNTIME_DIR-}"
for arg do
  printf 'arg=%s\n' "$arg"
done
exit "${TEST_WL_PASTE_EXIT:-0}"
EOF

chmod +x "$tmp/bin/tmux" "$tmp/bin/real-wl-paste"

assert_equal() {
  if [ "$1" != "$2" ]; then
    printf 'expected:\n%s\nactual:\n%s\n' "$2" "$1" >&2
    exit 1
  fi
}

expected='display=wayland-local
runtime=/run/user/local
arg=--type
arg=image/png'

actual=$(env -u TMUX -u TMUX_PANE \
  WAYLAND_DISPLAY=wayland-local \
  XDG_RUNTIME_DIR=/run/user/local \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type image/png)
assert_equal "$actual" "$expected"

python - "$tmp/remote/wayland-remote" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PY

expected="display=wayland-remote
runtime=$tmp/remote
arg=--list-types"

actual=$(PATH="$tmp/bin:$PATH" \
  TMUX=/tmp/tmux TEST_TMUX_WAYLAND_DISPLAY=wayland-remote \
  TEST_TMUX_XDG_RUNTIME_DIR="$tmp/remote" TMUX_PANE=%1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --list-types)
assert_equal "$actual" "$expected"

rm "$tmp/remote/wayland-remote"

expected='display=wayland-local
runtime=/run/user/local
arg=--no-newline'

actual=$(PATH="$tmp/bin:$PATH" \
  TMUX=/tmp/tmux TEST_TMUX_WAYLAND_DISPLAY=wayland-remote \
  TEST_TMUX_XDG_RUNTIME_DIR="$tmp/remote" TMUX_PANE=%1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --no-newline)
assert_equal "$actual" "$expected"

expected='display=wayland-local
runtime=/run/user/local
arg=--type
arg=text/plain'

actual=$(PATH="$tmp/bin:$PATH" \
  TMUX=/tmp/tmux TEST_TMUX_SHOW_ENVIRONMENT_RESULT=malformed TMUX_PANE=%1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type text/plain)
assert_equal "$actual" "$expected"

actual=$(PATH="$tmp/bin:$PATH" \
  TMUX=/tmp/tmux TEST_TMUX_SHOW_ENVIRONMENT_RESULT=unset TMUX_PANE=%1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type text/plain)
assert_equal "$actual" "$expected"

actual=$(PATH="$tmp/bin:$PATH" \
  TMUX=/tmp/tmux TEST_TMUX_SHOW_ENVIRONMENT_RESULT=failure TMUX_PANE=%1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type text/plain)
assert_equal "$actual" "$expected"

expected='display=wayland-local
runtime=/run/user/local
arg=
arg=two words'

if actual=$(env -u TMUX -u TMUX_PANE \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" TEST_WL_PASTE_EXIT=23 \
  "$wrapper" "" "two words"); then
  status=0
else
  status=$?
fi
assert_equal "$actual" "$expected"
assert_equal "$status" 23

printf '%s\n' 'wl-paste routing tests passed'
