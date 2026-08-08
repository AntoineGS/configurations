#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
wrapper=$repo_root/Linux/os/helpers/wl-copy
env_helper=$repo_root/Linux/os/helpers/herdr-waypipe-env
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin" "$tmp/remote"

cat >"$tmp/bin/real-wl-copy" <<'EOF'
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
EOF
chmod +x "$tmp/bin/real-wl-copy"

python - "$tmp/remote/wayland-remote" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PY

snapshot=$tmp/waypipe.env
cat >"$snapshot" <<EOF
WAYLAND_DISPLAY=wayland-remote
XDG_RUNTIME_DIR=$tmp/remote
DISPLAY=:1
EOF

actual=$(PATH="$repo_root/Linux/os/helpers:$PATH" \
  HERDR_WAYPIPE_ENV_FILE="$snapshot" HERDR_ENV=1 \
  HERDR_LOCAL_WAYLAND_ENV_CAPTURED=1 \
  HERDR_LOCAL_WAYLAND_DISPLAY=wayland-local \
  HERDR_LOCAL_XDG_RUNTIME_DIR=/run/user/local \
  HERDR_LOCAL_DISPLAY=:0 HERDR_LOCAL_DISPLAY_SET=1 \
  WAYLAND_DISPLAY=wayland-stale XDG_RUNTIME_DIR=/run/user/stale DISPLAY=:9 \
  WL_COPY_REAL="$tmp/bin/real-wl-copy" \
  "$wrapper" --type text/plain)
expected="display=wayland-remote
runtime=$tmp/remote
xdisplay=:1
arg=--type
arg=text/plain"
if [ "$actual" != "$expected" ]; then
  printf 'remote clipboard routing failed\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

HERDR_WAYPIPE_ENV_FILE="$snapshot" "$env_helper" clear
actual=$(PATH="$repo_root/Linux/os/helpers:$PATH" \
  HERDR_WAYPIPE_ENV_FILE="$snapshot" HERDR_ENV=1 \
  HERDR_LOCAL_WAYLAND_ENV_CAPTURED=1 \
  HERDR_LOCAL_WAYLAND_DISPLAY=wayland-local \
  HERDR_LOCAL_XDG_RUNTIME_DIR=/run/user/local \
  HERDR_LOCAL_DISPLAY=:0 HERDR_LOCAL_DISPLAY_SET=1 \
  WAYLAND_DISPLAY=wayland-stale XDG_RUNTIME_DIR=/run/user/stale DISPLAY=:9 \
  WL_COPY_REAL="$tmp/bin/real-wl-copy" \
  "$wrapper" --trim-newline)
expected='display=wayland-local
runtime=/run/user/local
xdisplay=:0
arg=--trim-newline'
if [ "$actual" != "$expected" ]; then
  printf 'local clipboard restoration failed\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

printf '%s\n' 'wl-copy routing tests passed'
