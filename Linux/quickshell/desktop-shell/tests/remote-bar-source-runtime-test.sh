#!/usr/bin/env bash
set -euo pipefail

test_dir=$(realpath -- "$(dirname -- "${BASH_SOURCE[0]}")")
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/remote-bar-source.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
mkdir -p -- "$tmp_dir/bin" "$tmp_dir/home" "$tmp_dir/config" "$tmp_dir/state" "$tmp_dir/cache" "$tmp_dir/runtime"
mkdir -p -- "$tmp_dir/services"
cp -- "$test_dir/fixtures/remote-bar-source/shell.qml" "$tmp_dir/shell.qml"
cp -- "$test_dir/../services/RemoteBarSource.qml" "$test_dir/../services/RemoteBarModel.js" "$tmp_dir/services/"
chmod 0700 -- "$tmp_dir/runtime"
cp -- "$test_dir/fixtures/remote-bar-source/desktop-remote-bar" "$tmp_dir/bin/desktop-remote-bar"
chmod 0755 -- "$tmp_dir/bin/desktop-remote-bar"

status=0
timeout --kill-after=2s 20s env -u WAYLAND_DISPLAY -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
  HOME="$tmp_dir/home" XDG_CONFIG_HOME="$tmp_dir/config" \
  XDG_STATE_HOME="$tmp_dir/state" XDG_CACHE_HOME="$tmp_dir/cache" \
  XDG_DATA_HOME="$tmp_dir/data" XDG_RUNTIME_DIR="$tmp_dir/runtime" \
  QT_QPA_PLATFORM=offscreen PATH="$tmp_dir/bin:$PATH" \
  quickshell -p "$tmp_dir/shell.qml" >"$tmp_dir/log" 2>&1 || status=$?
log=$(<"$tmp_dir/log")
printf '%s\n' "$log"
[[ $status == 0 && $log == *"RemoteBarSource runtime fixture passed"* ]]
