#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
helpers="$repo_root/Linux/os/helpers"
waybar_config="$repo_root/Linux/waybar/config.jsonc.tmpl"
test_root=$(mktemp -d)
bin="$test_root/bin"
log="$test_root/calls.log"

trap 'rm -rf "$test_root"' EXIT
mkdir -p "$bin"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

stub() {
  local name=$1
  cat >"$bin/$name" <<'EOF'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$UPDATE_TEST_LOG"
EOF
  chmod +x "$bin/$name"
}

assert_calls() {
  local expected=$1
  local actual
  actual=$(<"$log")
  [[ $actual == "$expected" ]] || fail "expected calls:\n$expected\nactual calls:\n$actual"
}

for command in snapshot update-time update-git update-perform; do
  stub "$command"
done

: >"$log"
PATH="$bin:$PATH" UPDATE_TEST_LOG="$log" "$helpers/update" -y
assert_calls $'snapshot create\nupdate-time \nupdate-perform '

for command in hyprctl update-keyring update-available-reset update-system-pkgs update-aur-pkgs \
  update-orphan-pkgs hook update-analyze-logs update-restart; do
  stub "$command"
done

: >"$log"
PATH="$bin:$PATH" UPDATE_TEST_LOG="$log" "$helpers/update-perform"
assert_calls $'hyprctl eval hl.dispatch(hl.dsp.window.tag({tag="+noidle"}))\nupdate-keyring \nupdate-system-pkgs \nupdate-aur-pkgs \nupdate-orphan-pkgs \nhook post-update\nupdate-analyze-logs \nupdate-restart \nhyprctl eval hl.dispatch(hl.dsp.window.tag({tag="-noidle"}))'

cat >"$bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$UPDATE_TEST_LOG"
EOF
chmod +x "$bin/sudo"

: >"$log"
PATH="$bin:$PATH" UPDATE_TEST_LOG="$log" "$helpers/update-keyring"
assert_calls 'sudo pacman -Sy --noconfirm archlinux-keyring'

if grep -Eq 'OMARCHY_PATH|40DFB630FF42BCFFB047046CF0134EE680CAC571|pkg-(missing|add) keyring' \
  "$helpers/update" "$helpers/update-perform" "$helpers/update-keyring"; then
  fail "update flow still contains Omarchy repository or signing-key dependencies"
fi

if grep -q 'custom/update' "$waybar_config"; then
  fail "Waybar still references the removed Omarchy update checker"
fi

printf 'PASS: Arch/AUR update flow\n'
