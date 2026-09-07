#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helper="$repo_root/Linux/os/helpers/desktop-hardware-state"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/sys"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "[{\"name\":\"eDP-1\",\"description\":\"fixture\",\"width\":1920,\"height\":1080,\"scale\":1,\"focused\":true,\"disabled\":false,\"mirrorOf\":\"none\"},{\"name\":\"HDMI-1\",\"description\":\"external fixture\",\"width\":2560,\"height\":1440,\"scale\":1,\"focused\":false,\"disabled\":false,\"mirrorOf\":\"none\"}]"' \
  >"$test_root/bin/hyprctl"
chmod 0755 "$test_root/bin/hyprctl"

cat >"$test_root/bin/desktop-monitor-brightness" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

(( $# == 3 || $# == 4 )) || exit 64
[[ $1 == snapshot ]] || exit 64
printf '%s\n' "$@" >"${BRIGHTNESS_HELPER_ARGS:?}"
requested_connector=${4:-}
if [[ -n $requested_connector ]]; then
  printf '%s\n' '{"version":1,"topology":"fixture-topology","monitors":{"eDP-1":{"connector":"eDP-1","backend":"backlight","available":true,"stale":false,"error":"","current":40,"maximum":100,"percent":40,"identity":"fixture-identity","topology":"fixture-topology","edid":"","selector":{"kind":"backlight","value":"intel_backlight"}}}}'
else
  printf '%s\n' '{"version":1,"topology":"fixture-topology","monitors":{"eDP-1":{"connector":"eDP-1","backend":"backlight","available":true,"stale":false,"error":"","current":40,"maximum":100,"percent":40,"identity":"fixture-identity","topology":"fixture-topology","edid":"","selector":{"kind":"backlight","value":"intel_backlight"}},"HDMI-1":{"connector":"HDMI-1","backend":"ddc","available":true,"stale":false,"error":"","current":60,"maximum":100,"percent":60,"identity":"fixture-hdmi-identity","topology":"fixture-topology","edid":"","selector":{"kind":"bus","value":"7"}}}}'
fi
EOF
chmod 0755 "$test_root/bin/desktop-monitor-brightness"

state_dir="$test_root/state"
helper_args="$test_root/brightness-helper-args"
missing_helper_dir="$test_root/missing-helper"
fixture_root="$repo_root/Linux/os/tests/fixtures/monitor-brightness"
fixture_edid_a=$(tr -d '\r\n[:space:]' <"$fixture_root/display-a.edid.hex")
fixture_edid_b=$(tr -d '\r\n[:space:]' <"$fixture_root/display-b.edid.hex")
previous_topology=$(printf 'card0-DP-1\tDP-1\t%s\t3\tnone\ncard0-HDMI-1\tHDMI-1\t%s\t4\tnone' \
  "$fixture_edid_a" "$fixture_edid_b" | sha256sum | cut -d' ' -f1)
previous_snapshot=$(jq -cn --arg topology "$previous_topology" \
  '{version:1,topology:$topology,monitors:{}}')
declare -a helper_invocation=()

jq -e '(.version == 1) and (.topology | test("^[0-9a-f]{64}$")) and (.monitors | type == "object")' \
  <<<"$previous_snapshot" >/dev/null
first=$(PATH="$test_root/bin:$PATH" DESKTOP_HARDWARE_SYSFS_ROOT="$test_root/sys" \
  DESKTOP_HARDWARE_STATE_DIR="$state_dir" DESKTOP_HARDWARE_HELPER_DIR="$test_root/bin" \
  BRIGHTNESS_HELPER_ARGS="$helper_args" "$helper" monitor)
cache="$state_dir/monitor.json"
first_inode=$(stat -c '%i' "$cache")
first_updated=$(jq -r '.updatedAt' "$cache")
sleep 1
second=$(PATH="$test_root/bin:$PATH" DESKTOP_HARDWARE_SYSFS_ROOT="$test_root/sys" \
  DESKTOP_HARDWARE_STATE_DIR="$state_dir" DESKTOP_HARDWARE_HELPER_DIR="$test_root/bin" \
  BRIGHTNESS_HELPER_ARGS="$helper_args" "$helper" monitor "$previous_snapshot")
second_inode=$(stat -c '%i' "$cache")
second_updated=$(jq -r '.updatedAt' <<<"$second")

[[ "$first_inode" == "$second_inode" ]] || exit 1
[[ "$second_updated" -gt "$first_updated" ]] || exit 1
jq -e --argjson first "$first" '.data == $first.data and .available == $first.available and .stale == $first.stale' \
  <<<"$second" >/dev/null
mapfile -t helper_invocation <"$helper_args"
[[ ${#helper_invocation[@]} -eq 3 ]] || exit 1
[[ ${helper_invocation[0]} == snapshot ]] || exit 1
[[ ${helper_invocation[1]} == "$previous_snapshot" ]] || exit 1
[[ ${helper_invocation[2]} == *'eDP-1'* ]] || exit 1
jq -e '.data.brightnessSnapshot.version == 1 and .data.brightnessSnapshot.monitors["eDP-1"].current == 40' \
  <<<"$first" >/dev/null

targeted=$(PATH="$test_root/bin:$PATH" DESKTOP_HARDWARE_SYSFS_ROOT="$test_root/sys" \
  DESKTOP_HARDWARE_STATE_DIR="$state_dir" DESKTOP_HARDWARE_HELPER_DIR="$test_root/bin" \
  BRIGHTNESS_HELPER_ARGS="$helper_args" "$helper" monitor '{}' eDP-1)
mapfile -t helper_invocation <"$helper_args"
[[ ${#helper_invocation[@]} -eq 4 && ${helper_invocation[3]} == eDP-1 ]] || exit 1
jq -e '.data.brightnessSnapshot.monitors | has("eDP-1")' <<<"$targeted" >/dev/null

printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$test_root/bin/hyprctl"
chmod 0755 "$test_root/bin/hyprctl"
if stale_cache=$(PATH="$test_root/bin:$PATH" DESKTOP_HARDWARE_SYSFS_ROOT="$test_root/sys" \
  DESKTOP_HARDWARE_STATE_DIR="$state_dir" DESKTOP_HARDWARE_HELPER_DIR="$test_root/bin" \
  BRIGHTNESS_HELPER_ARGS="$helper_args" "$helper" monitor); then
  exit 1
else
  stale_status=$?
fi
[[ $stale_status -eq 1 ]] || exit 1
jq -e '
  .stale == true
  and (.data.monitors | length) == 2
  and (.data.brightnessSnapshot.monitors | length) == 2
  and .data.brightnessSnapshot.monitors["eDP-1"].current == 40
  and .data.brightnessSnapshot.monitors["HDMI-1"].current == 60
' <<<"$stale_cache" >/dev/null

printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "[{\"name\":\"eDP-1\",\"description\":\"fixture\",\"width\":1920,\"height\":1080,\"scale\":1,\"focused\":true,\"disabled\":false,\"mirrorOf\":\"none\"},{\"name\":\"HDMI-1\",\"description\":\"external fixture\",\"width\":2560,\"height\":1440,\"scale\":1,\"focused\":false,\"disabled\":false,\"mirrorOf\":\"none\"}]"' \
  >"$test_root/bin/hyprctl"
chmod 0755 "$test_root/bin/hyprctl"
mkdir -p -- "$missing_helper_dir"
fallback=$(PATH="$test_root/bin:$PATH" DESKTOP_HARDWARE_SYSFS_ROOT="$test_root/sys" \
  DESKTOP_HARDWARE_STATE_DIR="$state_dir" DESKTOP_HARDWARE_HELPER_DIR="$missing_helper_dir" \
  "$helper" monitor)
jq -e '
  .data.monitors[0].name == "eDP-1"
  and .data.brightness.available == false
  and .data.keyboardBrightness.available == false
  and .data.brightnessSnapshot.version == 1
  and .data.brightnessSnapshot.monitors["eDP-1"].available == false
  and .data.brightnessSnapshot.monitors["eDP-1"].current == null
' <<<"$fallback" >/dev/null
printf '%s\n' 'desktop hardware cache regression passed'
