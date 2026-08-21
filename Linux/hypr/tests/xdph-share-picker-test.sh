#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PICKER="$SCRIPT_DIR/../xdph-share-picker"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
TEST_BIN="$TEST_ROOT/bin"
mkdir -p -- "$TEST_BIN"

cat >"$TEST_BIN/hostname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$TEST_HOSTNAME"
EOF

cat >"$TEST_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${1:-} == monitors && ${2:-} == -j && $# == 2 ]] || exit 125
printf '%s\n' "$TEST_MONITORS"
EOF

cat >"$TEST_BIN/hyprland-preview-share-picker" <<'EOF'
#!/usr/bin/env bash
printf 'preview'
printf ' <%s>' "$@"
printf '\n'
EOF

chmod 0700 "$TEST_BIN/hostname" "$TEST_BIN/hyprctl" "$TEST_BIN/hyprland-preview-share-picker"
export PATH="$TEST_BIN:/usr/bin:/bin"

[[ -x $PICKER ]] || fail "$PICKER must exist and be executable"

active_dp2='[{"id":0,"name":"DP-2","description":"Remote display","make":"Generic","model":"Display","serial":"1","width":1920,"height":1080,"refreshRate":60.0,"x":0,"y":0,"activeWorkspace":{"id":1,"name":"1"},"specialWorkspace":{"id":0,"name":""},"reserved":[0,0,0,0],"scale":1.0,"transform":0,"focused":true,"dpmsStatus":true,"vrr":false,"solitary":"0","activelyTearing":false,"directScanoutTo":"0","disabled":false,"currentFormat":"XRGB8888","mirrorOf":"none","availableModes":["1920x1080@60.00Hz"],"colorManagementPreset":"srgb","sdrBrightness":1.0,"sdrSaturation":1.0,"sdrMinLuminance":0.2,"sdrMaxLuminance":80}]'
disabled_dp2='[{"id":0,"name":"DP-2","description":"Remote display","make":"Generic","model":"Display","serial":"1","width":1920,"height":1080,"refreshRate":60.0,"x":0,"y":0,"activeWorkspace":{"id":1,"name":"1"},"specialWorkspace":{"id":0,"name":""},"reserved":[0,0,0,0],"scale":1.0,"transform":0,"focused":false,"dpmsStatus":false,"vrr":false,"solitary":"0","activelyTearing":false,"directScanoutTo":"0","disabled":true,"currentFormat":"XRGB8888","mirrorOf":"none","availableModes":["1920x1080@60.00Hz"],"colorManagementPreset":"srgb","sdrBrightness":1.0,"sdrSaturation":1.0,"sdrMinLuminance":0.2,"sdrMaxLuminance":80}]'

output=$(TEST_HOSTNAME=antoinews-linux TEST_MONITORS=$active_dp2 "$PICKER") ||
  fail 'antoinews-linux picker rejected active DP-2'
[[ $output == '[SELECTION]r/screen:DP-2' ]] ||
  fail "antoinews-linux picker returned unexpected selection: $output"

if TEST_HOSTNAME=antoinews-linux TEST_MONITORS=$disabled_dp2 "$PICKER" >"$TEST_ROOT/disabled.out"; then
  fail 'antoinews-linux picker accepted disabled DP-2'
fi
[[ ! -s $TEST_ROOT/disabled.out ]] || fail 'disabled DP-2 produced a selection'

for host in DESKTOP-E07VTRN omarchbook unknown-host; do
  output=$(TEST_HOSTNAME=$host TEST_MONITORS='[]' "$PICKER" screen window) ||
    fail "$host picker did not delegate to the preview picker"
  [[ $output == 'preview <screen> <window>' ]] ||
    fail "$host picker did not preserve preview picker arguments: $output"
done

printf 'PASS: XDPH share picker tests\n'
