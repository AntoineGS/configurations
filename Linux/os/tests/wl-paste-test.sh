#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
wrapper=$repo_root/Linux/os/helpers/wl-paste
env_helper=$repo_root/Linux/os/helpers/herdr-waypipe-env
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin" "$tmp/remote"

cat >"$tmp/bin/herdr-waypipe-env" <<'EOF'
#!/bin/sh
case ${TEST_HERDR_READ_RESULT-} in
  failure) exit 1 ;;
  extra-empty)
    printf '%s\n' \
      'WAYLAND_DISPLAY=wayland-remote' \
      'XDG_RUNTIME_DIR=/run/user/remote' \
      'DISPLAY=:1' \
      ''
    ;;
  malformed)
    printf '%s\n' \
      'WAYLAND_DISPLAY=wayland-remote' \
      'XDG_RUNTIME_DIR=/run/user/remote' \
      'INVALID_DISPLAY=:1'
    ;;
  *) exec "$TEST_HERDR_WAYPIPE_ENV_REAL" "$@" ;;
esac
EOF

cat >"$tmp/bin/real-wl-paste" <<'EOF'
#!/bin/sh
printf 'display=%s\n' "${WAYLAND_DISPLAY-}"
printf 'runtime=%s\n' "${XDG_RUNTIME_DIR-}"
if [ "${DISPLAY+x}" = x ]; then
  printf 'xdisplay=%s\n' "$DISPLAY"
else
  printf '%s\n' 'xdisplay=<unset>'
fi
for arg do
  printf 'arg=%s\n' "$arg"
done
exit "${TEST_WL_PASTE_EXIT:-0}"
EOF

chmod +x "$tmp/bin/herdr-waypipe-env" "$tmp/bin/real-wl-paste"

assert_equal() {
  if [ "$1" != "$2" ]; then
    printf 'expected:\n%s\nactual:\n%s\n' "$2" "$1" >&2
    exit 1
  fi
}

snapshot=$tmp/waypipe.env
cat >"$snapshot" <<EOF
WAYLAND_DISPLAY=wayland-remote
XDG_RUNTIME_DIR=$tmp/remote
DISPLAY=:1
EOF

python - "$tmp/remote/wayland-remote" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PY

expected='display=wayland-local
runtime=/run/user/local
xdisplay=:0
arg=--type
arg=image/png'

actual=$(env -u HERDR_ENV \
  PATH="$tmp/bin:$PATH" \
  TEST_HERDR_WAYPIPE_ENV_REAL="$env_helper" \
  HERDR_WAYPIPE_ENV_FILE="$snapshot" \
  WAYLAND_DISPLAY=wayland-local \
  XDG_RUNTIME_DIR=/run/user/local \
  DISPLAY=:0 \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type image/png)
assert_equal "$actual" "$expected"

expected="display=wayland-remote
runtime=$tmp/remote
xdisplay=:1
arg=--list-types"

actual=$(PATH="$tmp/bin:$PATH" \
  TEST_HERDR_WAYPIPE_ENV_REAL="$env_helper" \
  HERDR_WAYPIPE_ENV_FILE="$snapshot" HERDR_ENV=1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local DISPLAY=:0 \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --list-types)
assert_equal "$actual" "$expected"

expected='display=wayland-local
runtime=/run/user/local
xdisplay=:0
arg=--type
arg=text/plain'

actual=$(PATH="$tmp/bin:$PATH" \
  TEST_HERDR_WAYPIPE_ENV_REAL="$env_helper" \
  TEST_HERDR_READ_RESULT=failure HERDR_ENV=1 \
  HERDR_LOCAL_WAYLAND_ENV_CAPTURED=1 \
  HERDR_LOCAL_WAYLAND_DISPLAY=wayland-local \
  HERDR_LOCAL_XDG_RUNTIME_DIR=/run/user/local \
  HERDR_LOCAL_DISPLAY=:0 HERDR_LOCAL_DISPLAY_SET=1 \
  WAYLAND_DISPLAY=wayland-stale XDG_RUNTIME_DIR=/run/user/stale DISPLAY=:9 \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type text/plain)
assert_equal "$actual" "$expected"

cat >"$snapshot" <<EOF
WAYLAND_DISPLAY=wayland-remote
XDG_RUNTIME_DIR=$tmp/remote
DISPLAY=
EOF

expected="display=wayland-remote
runtime=$tmp/remote
xdisplay=<unset>
arg=--no-newline"

actual=$(PATH="$tmp/bin:$PATH" \
  TEST_HERDR_WAYPIPE_ENV_REAL="$env_helper" \
  HERDR_WAYPIPE_ENV_FILE="$snapshot" HERDR_ENV=1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local DISPLAY=:0 \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --no-newline)
assert_equal "$actual" "$expected"

rm "$tmp/remote/wayland-remote"

expected='display=wayland-local
runtime=/run/user/local
xdisplay=:0
arg=--type
arg=text/plain'

actual=$(PATH="$tmp/bin:$PATH" \
  TEST_HERDR_WAYPIPE_ENV_REAL="$env_helper" \
  HERDR_WAYPIPE_ENV_FILE="$snapshot" HERDR_ENV=1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local DISPLAY=:0 \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type text/plain)
assert_equal "$actual" "$expected"

actual=$(PATH="$tmp/bin:$PATH" \
  TEST_HERDR_WAYPIPE_ENV_REAL="$env_helper" \
  TEST_HERDR_READ_RESULT=malformed HERDR_ENV=1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local DISPLAY=:0 \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type text/plain)
assert_equal "$actual" "$expected"

actual=$(PATH="$tmp/bin:$PATH" \
  TEST_HERDR_WAYPIPE_ENV_REAL="$env_helper" \
  TEST_HERDR_READ_RESULT=extra-empty HERDR_ENV=1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local DISPLAY=:0 \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type text/plain)
assert_equal "$actual" "$expected"

actual=$(PATH="$tmp/bin:$PATH" \
  TEST_HERDR_WAYPIPE_ENV_REAL="$env_helper" \
  TEST_HERDR_READ_RESULT=failure HERDR_ENV=1 \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local DISPLAY=:0 \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" \
  "$wrapper" --type text/plain)
assert_equal "$actual" "$expected"

expected='display=wayland-local
runtime=/run/user/local
xdisplay=:0
arg=
arg=two words'

if actual=$(env -u HERDR_ENV \
  PATH="$tmp/bin:$PATH" \
  TEST_HERDR_WAYPIPE_ENV_REAL="$env_helper" \
  WAYLAND_DISPLAY=wayland-local XDG_RUNTIME_DIR=/run/user/local DISPLAY=:0 \
  WL_PASTE_REAL="$tmp/bin/real-wl-paste" TEST_WL_PASTE_EXIT=23 \
  "$wrapper" "" "two words"); then
  status=0
else
  status=$?
fi
assert_equal "$actual" "$expected"
assert_equal "$status" 23

printf '%s\n' 'wl-paste routing tests passed'
