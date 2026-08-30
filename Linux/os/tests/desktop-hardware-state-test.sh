#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helper="$repo_root/Linux/os/helpers/desktop-hardware-state"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/sys"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "[{\"name\":\"eDP-1\",\"description\":\"fixture\",\"width\":1920,\"height\":1080,\"scale\":1,\"focused\":true,\"disabled\":false,\"mirrorOf\":\"none\"}]"' \
  >"$test_root/bin/hyprctl"
chmod 0755 "$test_root/bin/hyprctl"

state_dir="$test_root/state"
first=$(PATH="$test_root/bin:$PATH" DESKTOP_HARDWARE_SYSFS_ROOT="$test_root/sys" \
  DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$helper" monitor)
cache="$state_dir/monitor.json"
first_inode=$(stat -c '%i' "$cache")
first_updated=$(jq -r '.updatedAt' "$cache")
sleep 1
second=$(PATH="$test_root/bin:$PATH" DESKTOP_HARDWARE_SYSFS_ROOT="$test_root/sys" \
  DESKTOP_HARDWARE_STATE_DIR="$state_dir" "$helper" monitor)
second_inode=$(stat -c '%i' "$cache")
second_updated=$(jq -r '.updatedAt' <<<"$second")

[[ "$first_inode" == "$second_inode" ]] || exit 1
[[ "$second_updated" -gt "$first_updated" ]] || exit 1
jq -e --argjson first "$first" '.data == $first.data and .available == $first.available and .stale == $first.stale' \
  <<<"$second" >/dev/null
printf '%s\n' 'desktop hardware cache regression passed'
