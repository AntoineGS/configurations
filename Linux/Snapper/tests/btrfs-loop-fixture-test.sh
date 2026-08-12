#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="${SCRIPT_DIR}/../snapper-initialize"
TEST_ROOT="$(mktemp -d)"
IMAGE="$TEST_ROOT/fixture.img"
SECOND_IMAGE="$TEST_ROOT/second.img"
MOUNT_ROOT="$TEST_ROOT/mnt"
SECOND_TOP="$TEST_ROOT/second-top"
CONFIG_DIR="$TEST_ROOT/etc/snapper/configs"
REGISTRATION_FILE="$TEST_ROOT/etc/conf.d/snapper"
TEMPLATE="$TEST_ROOT/default-template"
STATE_DIR="$TEST_ROOT/snapper-state"
STUB_BIN="$TEST_ROOT/bin"
LOOP_DEVICE=""
SECOND_LOOP_DEVICE=""

cleanup() {
  umount "$MOUNT_ROOT/root/.snapshots" 2>/dev/null || true
  umount "$MOUNT_ROOT/root" 2>/dev/null || true
  umount "$MOUNT_ROOT/home" 2>/dev/null || true
  umount "$MOUNT_ROOT" 2>/dev/null || true
  umount "$SECOND_TOP" 2>/dev/null || true
  if [[ -n "$SECOND_LOOP_DEVICE" ]]; then
    losetup -d "$SECOND_LOOP_DEVICE" 2>/dev/null || true
  fi
  if [[ -n "$LOOP_DEVICE" ]]; then
    losetup -d "$LOOP_DEVICE" 2>/dev/null || true
  fi
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

skip() {
  printf 'SKIP: %s\n' "$1"
  exit 0
}

for command_name in btrfs losetup mkfs.btrfs mount truncate umount; do
  command -v "$command_name" >/dev/null 2>&1 || skip "missing command: $command_name"
done

[[ "$EUID" -eq 0 ]] || skip 'root privileges are required to mount the disposable fixture'
[[ -w /dev/loop-control ]] || skip '/dev/loop-control is not writable'

write_executable() {
  local -r path="$1"
  shift

  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' "$@" >"$path"
  chmod +x -- "$path"
}

create_snapper_stub() {
  mkdir -p -- "$STUB_BIN"

  # shellcheck disable=SC2016
  write_executable "$STUB_BIN/snapper" \
    'config=""' \
    'command_name=""' \
    'print_number=false' \
    'while [[ $# -gt 0 ]]; do' \
    '  case "$1" in' \
    '    --no-dbus|--csvout|--no-headers) shift ;;' \
    '    --config|-c) config="$2"; shift 2 ;;' \
    '    --columns) shift 2 ;;' \
    '    --description) shift 2 ;;' \
    '    --cleanup-algorithm) shift 2 ;;' \
    '    --print-number) print_number=true; shift ;;' \
    '    list|create) command_name="$1"; shift ;;' \
    '    *) shift ;;' \
    '  esac' \
    'done' \
    'state_file="$SNAPPER_TEST_STATE_DIR/$config"' \
    'mount_path="$([[ "$config" == root ]] && printf "%s" "$SNAPPER_TEST_ROOT_MOUNT" || printf "%s" "$SNAPPER_TEST_HOME_MOUNT")"' \
    'if [[ "$command_name" == list ]]; then' \
    '  if [[ -e "$state_file" ]]; then printf "1,initial recovery snapshot\\n"; fi' \
    '  exit 0' \
    'fi' \
    '[[ "$command_name" == create ]] || exit 2' \
    'snapshot_path="$mount_path/.snapshots/1/snapshot"' \
    '/usr/bin/mkdir -p -- "${snapshot_path%/*}"' \
    '/usr/bin/btrfs subvolume snapshot -r "$mount_path" "$snapshot_path" >/dev/null' \
    'printf 1 >"$state_file"' \
    '[[ "$print_number" == true ]] && printf "1\\n"'
}

create_first_filesystem() {
  local -r image="$1"
  local -r top="$2"

  truncate -s 256M "$image" || return 1
  mkfs.btrfs -q "$image" || return 1
  LOOP_DEVICE="$(losetup --find --show "$image")" || return 1
  mount -t btrfs -o subvolid=5 "$LOOP_DEVICE" "$top" || return 1
  btrfs subvolume create "$top/@" >/dev/null || return 1
  btrfs subvolume create "$top/@/.snapshots" >/dev/null || return 1
}

create_second_filesystem() {
  local -r image="$1"
  local -r top="$2"

  truncate -s 256M "$image" || return 1
  mkfs.btrfs -q "$image" || return 1
  SECOND_LOOP_DEVICE="$(losetup --find --show "$image")" || return 1
  mount -t btrfs -o subvolid=5 "$SECOND_LOOP_DEVICE" "$top" || return 1
  btrfs subvolume create "$top/@home" >/dev/null || return 1
  btrfs subvolume create "$top/@home/.snapshots" >/dev/null || return 1
}

mkdir -p -- "$MOUNT_ROOT" "$SECOND_TOP" "$CONFIG_DIR" "${REGISTRATION_FILE%/*}" "$STATE_DIR" "${TEMPLATE%/*}"

if ! create_first_filesystem "$IMAGE" "$MOUNT_ROOT"; then
  skip 'loop-backed Btrfs mount is unavailable'
fi
btrfs subvolume create "$MOUNT_ROOT/@home" >/dev/null
btrfs subvolume create "$MOUNT_ROOT/@.snapshots" >/dev/null
mkdir -p -- "$MOUNT_ROOT/root" "$MOUNT_ROOT/home"
mount -t btrfs -o subvol=@ "$LOOP_DEVICE" "$MOUNT_ROOT/root"
mount -t btrfs -o subvol=@home "$LOOP_DEVICE" "$MOUNT_ROOT/home"

printf 'SUBVOLUME="/"\nFSTYPE="btrfs"\nTIMELINE_CREATE="yes"\nTIMELINE_CLEANUP="yes"\nTIMELINE_LIMIT_HOURLY="6"\nTIMELINE_LIMIT_DAILY="7"\nTIMELINE_LIMIT_WEEKLY="4"\nTIMELINE_LIMIT_MONTHLY="6"\nTIMELINE_LIMIT_QUARTERLY="4"\nTIMELINE_LIMIT_YEARLY="2"\n' >"$CONFIG_DIR/root"
sed 's#SUBVOLUME="/"#SUBVOLUME="/home"#' "$CONFIG_DIR/root" >"$CONFIG_DIR/home"
printf 'SNAPPER_CONFIGS="root home"\n' >"$REGISTRATION_FILE"
printf 'SUBVOLUME="/"\nFSTYPE="btrfs"\n' >"$TEMPLATE"
chmod 0644 -- "$CONFIG_DIR/root" "$CONFIG_DIR/home" "$REGISTRATION_FILE"
chown root:root -- "$CONFIG_DIR/root" "$CONFIG_DIR/home" "$REGISTRATION_FILE"
create_snapper_stub

run_initializer() {
  env \
    PATH="$STUB_BIN:$PATH" \
    SNAPPER_TEST_STATE_DIR="$STATE_DIR" \
    SNAPPER_TEST_ROOT_MOUNT="$MOUNT_ROOT/root" \
    SNAPPER_TEST_HOME_MOUNT="$MOUNT_ROOT/home" \
    SNAPPER_INITIALIZER_ROOT_MOUNT="$MOUNT_ROOT/root" \
    SNAPPER_INITIALIZER_HOME_MOUNT="$MOUNT_ROOT/home" \
    SNAPPER_INITIALIZER_CONFIG_DIR="$CONFIG_DIR" \
    SNAPPER_INITIALIZER_REGISTRATION_FILE="$REGISTRATION_FILE" \
    SNAPPER_INITIALIZER_TEMPLATE="$TEMPLATE" \
    "$SCRIPT" "$@"
}

run_initializer --apply >/dev/null
run_initializer --check >/dev/null

mount -t btrfs -o subvol=@.snapshots "$LOOP_DEVICE" "$MOUNT_ROOT/root/.snapshots"
if run_initializer --check >/dev/null 2>&1; then
  printf 'FAIL: sibling snapshot mount was accepted\n' >&2
  exit 1
fi
umount "$MOUNT_ROOT/root/.snapshots"

if ! create_second_filesystem "$SECOND_IMAGE" "$SECOND_TOP"; then
  skip 'second disposable Btrfs mount is unavailable'
fi
umount "$MOUNT_ROOT/home"
mount -t btrfs -o subvol=@home "$SECOND_LOOP_DEVICE" "$MOUNT_ROOT/home"
if run_initializer --check >/dev/null 2>&1; then
  printf 'FAIL: mismatched Btrfs UUIDs were accepted\n' >&2
  exit 1
fi

printf 'PASS: disposable Btrfs topology and UUID validation\n'
