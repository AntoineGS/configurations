#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
helper=$repo_root/Linux/os/helpers/herdr-waypipe-env
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

state=$tmp/state/herdr/waypipe.env
state_dir=$(dirname -- "$state")
runtime=$tmp/runtime
mkdir -p "$state_dir" "$runtime"
chmod 777 "$state_dir"

make_socket() {
  python - "$1" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PY
}

assert_equal() {
  if [ "$1" != "$2" ]; then
    printf 'expected:\n%s\nactual:\n%s\n' "$2" "$1" >&2
    exit 1
  fi
}

assert_publish_rejected() {
  if "$@" >"$tmp/output" 2>"$tmp/error"; then
    printf 'publish unexpectedly succeeded\n' >&2
    exit 1
  fi
  assert_prior_snapshot_unchanged
}

assert_prior_snapshot_unchanged() {
  HERDR_WAYPIPE_ENV_FILE="$state" "$helper" read >"$tmp/read-after-rejection"
  if ! cmp "$tmp/expected-output" "$state" >/dev/null 2>&1 ||
    ! cmp "$tmp/expected-output" "$tmp/read-after-rejection" >/dev/null 2>&1; then
    printf 'rejected publish changed the prior readable snapshot\n' >&2
    exit 1
  fi
}

assert_read_rejected_silently() {
  if HERDR_WAYPIPE_ENV_FILE="$1" "$helper" read >"$tmp/output" 2>"$tmp/error"; then
    printf 'read unexpectedly succeeded for %s\n' "$1" >&2
    exit 1
  fi
  if [ -s "$tmp/output" ] || [ -s "$tmp/error" ]; then
    printf 'rejected read produced output for %s\n' "$1" >&2
    exit 1
  fi
}

assert_unsafe_publish_rejected() {
  unsafe_state=$1
  working_dir=$2
  protected_dir=$3
  mode_before=$(stat -c '%a' "$protected_dir")
  if (cd "$working_dir" && env HERDR_WAYPIPE_ENV_FILE="$unsafe_state" \
    WAYLAND_DISPLAY="$absolute_display" XDG_RUNTIME_DIR="$runtime" DISPLAY=:0 \
    "$helper" publish) >"$tmp/output" 2>"$tmp/error"; then
    printf 'unsafe state path unexpectedly published: %s\n' "$unsafe_state" >&2
    exit 1
  fi
  assert_equal "$(stat -c '%a' "$protected_dir")" "$mode_before"
  assert_prior_snapshot_unchanged
}

relative_display=wayland-relative
make_socket "$runtime/$relative_display"

(umask 000
  env HERDR_WAYPIPE_ENV_FILE="$state" \
    WAYLAND_DISPLAY="$relative_display" \
    XDG_RUNTIME_DIR="$runtime" \
    DISPLAY='localhost:12.0' \
    "$helper" publish)

expected="WAYLAND_DISPLAY=$relative_display
XDG_RUNTIME_DIR=$runtime
DISPLAY=localhost:12.0"
actual=$(HERDR_WAYPIPE_ENV_FILE="$state" "$helper" read)
assert_equal "$actual" "$expected"
assert_equal "$(stat -c '%a' "$state")" 600

absolute_display=$tmp/wayland-absolute
make_socket "$absolute_display"
env -u DISPLAY HERDR_WAYPIPE_ENV_FILE="$state" \
  WAYLAND_DISPLAY="$absolute_display" \
  XDG_RUNTIME_DIR="$tmp/runtime replacement" \
  "$helper" publish

expected="WAYLAND_DISPLAY=$absolute_display
XDG_RUNTIME_DIR=$tmp/runtime replacement
DISPLAY="
actual=$(HERDR_WAYPIPE_ENV_FILE="$state" "$helper" read)
assert_equal "$actual" "$expected"
assert_equal "$(wc -l <"$state" | tr -d ' ')" 3
HERDR_WAYPIPE_ENV_FILE="$state" "$helper" read >"$tmp/read-output"
printf '%s\n' "$expected" >"$tmp/expected-output"
if ! cmp "$tmp/expected-output" "$tmp/read-output" >/dev/null 2>&1; then
  printf 'normalized read output did not match byte-for-byte\n' >&2
  exit 1
fi

HERDR_WAYPIPE_ENV_FILE="$state" "$helper" clear
if [ -e "$state" ]; then
  printf 'clear did not remove the Waypipe snapshot\n' >&2
  exit 1
fi
assert_read_rejected_silently "$state"
env -u DISPLAY HERDR_WAYPIPE_ENV_FILE="$state" \
  WAYLAND_DISPLAY="$absolute_display" XDG_RUNTIME_DIR="$tmp/runtime replacement" \
  "$helper" publish
HERDR_WAYPIPE_ENV_FILE="$state" "$helper" read >"$tmp/expected-output"

relative_parent=$tmp/relative-parent
mkdir "$relative_parent"
chmod 755 "$relative_parent"
assert_unsafe_publish_rejected waypipe.env "$relative_parent" "$relative_parent"
assert_unsafe_publish_rejected ./waypipe.env "$relative_parent" "$relative_parent"

lexical_parent=$tmp/lexical-parent
mkdir -p "$lexical_parent/child"
chmod 755 "$lexical_parent"
assert_unsafe_publish_rejected "$lexical_parent/child/../waypipe.env" "$tmp" "$lexical_parent"

trailing_parent=$tmp/trailing/herdr
mkdir -p "$trailing_parent"
chmod 755 "$trailing_parent"
assert_unsafe_publish_rejected "$trailing_parent/" "$tmp" "$trailing_parent"

symlink_target=$tmp/symlink-target
symlink_parent=$tmp/symlink-parent
mkdir "$symlink_target"
chmod 755 "$symlink_target"
ln -s "$symlink_target" "$symlink_parent"
symlink_target_mode=$(stat -c '%a' "$symlink_target")
if HERDR_WAYPIPE_ENV_FILE="$symlink_parent/waypipe.env" \
  WAYLAND_DISPLAY="$absolute_display" XDG_RUNTIME_DIR="$runtime" DISPLAY=:0 \
  "$helper" publish >"$tmp/output" 2>"$tmp/error"; then
  symlink_status=0
else
  symlink_status=$?
fi
symlink_failure=0
if [ "$symlink_status" -eq 0 ]; then
  printf 'symlinked state parent unexpectedly published\n' >&2
  symlink_failure=1
fi
if [ "$(stat -c '%a' "$symlink_target")" != "$symlink_target_mode" ]; then
  printf 'symlinked state parent changed target mode\n' >&2
  symlink_failure=1
fi
if [ -e "$symlink_target/waypipe.env" ]; then
  printf 'symlinked state parent created target state\n' >&2
  symlink_failure=1
fi
[ "$symlink_failure" -eq 0 ] || exit 1
assert_prior_snapshot_unchanged

mkdir "$tmp/unsafe-bin"
cat >"$tmp/unsafe-bin/chmod" <<'EOF'
#!/bin/sh
: >"$TEST_CHMOD_CALLED"
exit 1
EOF
chmod +x "$tmp/unsafe-bin/chmod"
root_mode=$(stat -c '%a' /)
for unsafe_state in /waypipe.env //waypipe.env /tmp/../waypipe.env; do
  rm -f "$tmp/chmod-called"
  if PATH="$tmp/unsafe-bin:$PATH" TEST_CHMOD_CALLED="$tmp/chmod-called" \
    HERDR_WAYPIPE_ENV_FILE="$unsafe_state" WAYLAND_DISPLAY="$absolute_display" \
    XDG_RUNTIME_DIR="$runtime" DISPLAY=:0 "$helper" publish \
    >"$tmp/output" 2>"$tmp/error"; then
    printf 'unsafe root state path unexpectedly published: %s\n' "$unsafe_state" >&2
    exit 1
  fi
  if [ -e "$tmp/chmod-called" ]; then
    printf 'unsafe root state path attempted chmod: %s\n' "$unsafe_state" >&2
    exit 1
  fi
  assert_equal "$(stat -c '%a' /)" "$root_mode"
  assert_prior_snapshot_unchanged
done

assert_publish_rejected env HERDR_WAYPIPE_ENV_FILE="$state" \
  WAYLAND_DISPLAY=missing XDG_RUNTIME_DIR="$runtime" DISPLAY=:0 \
  "$helper" publish

non_socket=$runtime/not-a-socket
: >"$non_socket"
assert_publish_rejected env HERDR_WAYPIPE_ENV_FILE="$state" \
  WAYLAND_DISPLAY=not-a-socket XDG_RUNTIME_DIR="$runtime" DISPLAY=:0 \
  "$helper" publish

assert_publish_rejected env HERDR_WAYPIPE_ENV_FILE="$state" \
  WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$runtime" DISPLAY=:0 \
  "$helper" publish
assert_publish_rejected env HERDR_WAYPIPE_ENV_FILE="$state" \
  WAYLAND_DISPLAY="$absolute_display" XDG_RUNTIME_DIR= DISPLAY=:0 \
  "$helper" publish

assert_read_rejected_silently "$tmp/missing.env"
rm "$absolute_display"
assert_read_rejected_silently "$state"

make_socket "$absolute_display"
newline=$(printf '\nx')
tab=$(printf '\tx')
carriage_return=$(printf '\rx')
for invalid in "$newline" "$tab" "$carriage_return"; do
  invalid_socket=$tmp/wayland-invalid$invalid
  make_socket "$invalid_socket"
  assert_publish_rejected env HERDR_WAYPIPE_ENV_FILE="$state" \
    WAYLAND_DISPLAY="$invalid_socket" XDG_RUNTIME_DIR="$runtime" DISPLAY=:0 \
    "$helper" publish
  assert_publish_rejected env HERDR_WAYPIPE_ENV_FILE="$state" \
    WAYLAND_DISPLAY="$absolute_display" XDG_RUNTIME_DIR="$invalid" DISPLAY=:0 \
    "$helper" publish
  assert_publish_rejected env HERDR_WAYPIPE_ENV_FILE="$state" \
    WAYLAND_DISPLAY="$absolute_display" XDG_RUNTIME_DIR="$runtime" DISPLAY="$invalid" \
    "$helper" publish
done

malformed=$tmp/malformed.env
printf 'WAYLAND_DISPLAY=not-a-socket\nXDG_RUNTIME_DIR=%s\nDISPLAY=:0\n' \
  "$runtime" >"$malformed"
assert_read_rejected_silently "$malformed"

for invalid in "$tab" "$carriage_return"; do
  printf 'WAYLAND_DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nDISPLAY=invalid%svalue\n' \
    "$absolute_display" "$runtime" "$invalid" >"$malformed"
  assert_read_rejected_silently "$malformed"
done

printf 'XDG_RUNTIME_DIR=%s\nWAYLAND_DISPLAY=%s\nDISPLAY=:0\n' \
  "$runtime" "$relative_display" >"$malformed"
assert_read_rejected_silently "$malformed"

printf 'WAYLAND_DISPLAY=%s\nXDG_RUNTIME_DIR=%s\n' \
  "$relative_display" "$runtime" >"$malformed"
assert_read_rejected_silently "$malformed"

printf 'WAYLAND_DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nDISPLAY=:0\nEXTRA=value\n' \
  "$relative_display" "$runtime" >"$malformed"
assert_read_rejected_silently "$malformed"

printf 'WAYLAND_DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nINVALID=:0\n' \
  "$relative_display" "$runtime" >"$malformed"
assert_read_rejected_silently "$malformed"

printf 'WAYLAND_DISPLAY=%s\nXDG_RUNTIME_DIR=\nDISPLAY=:0\n' \
  "$absolute_display" >"$malformed"
assert_read_rejected_silently "$malformed"

assert_equal "$(stat -c '%a' "$state_dir")" 700

if "$helper" unsupported >"$tmp/output" 2>"$tmp/error"; then
  printf 'unknown command unexpectedly succeeded\n' >&2
  exit 1
else
  status=$?
fi
assert_equal "$status" 2
assert_equal "$(cat "$tmp/error")" 'usage: herdr-waypipe-env {publish|read|clear}'

printf '%s\n' 'herdr waypipe environment tests passed'
