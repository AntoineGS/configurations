#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source_helper="$repo_root/Linux/os/helpers/setup-desktop-shell-marketplace"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -x "$source_helper" ]] || fail "setup helper is missing or not executable"

plugins_dir="$test_root/plugins"
helper_dir="$test_root/helpers"
bin_dir="$test_root/bin"
log_file="$test_root/calls.log"
mkdir -p -- "$plugins_dir" "$helper_dir" "$bin_dir"

cat >"$helper_dir/desktop-shell-plugin" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'manager %s\n' "$*" >>"$CALL_LOG"
case ${1-} in
  list) [[ ${2-} == --json ]] && cat -- "$PLUGIN_LIST_FILE" ;;
  add) mkdir -p -- "$DESKTOP_SHELL_PLUGINS_DIR/io.yasino55.omarchy-plugin-marketplace"; printf '%s\n' '{"id":"io.yasino55.omarchy-plugin-marketplace"}' >"$DESKTOP_SHELL_PLUGINS_DIR/io.yasino55.omarchy-plugin-marketplace/manifest.json"; git -C "$DESKTOP_SHELL_PLUGINS_DIR/io.yasino55.omarchy-plugin-marketplace" init -q; git -C "$DESKTOP_SHELL_PLUGINS_DIR/io.yasino55.omarchy-plugin-marketplace" remote add origin 'https://github.com/Yasino55/omarchy-plugin-marketplace.git' ;;
  enable)
    [[ ${3-} == --headless ]] || exit 2
    tmp_config=$(mktemp)
    jq --arg id io.yasino55.omarchy-plugin-marketplace \
      '.bar.layout.left = [.bar.layout.left[]? | select(.id != $id)]
       | .bar.layout.center = [.bar.layout.center[]? | select(.id != $id)]
       | .bar.layout.right = [.bar.layout.right[]? | select(.id != $id)]' \
      "$SHELL_CONFIG_FILE" >"$tmp_config"
    mv -- "$tmp_config" "$SHELL_CONFIG_FILE"
    tmp_list=$(mktemp)
    jq --arg id io.yasino55.omarchy-plugin-marketplace \
      'map(if .id == $id then .enabled = true else . end)' \
      "$PLUGIN_LIST_FILE" >"$tmp_list"
    mv -- "$tmp_list" "$PLUGIN_LIST_FILE"
    printf 'enabled\n' >>"$CALL_LOG"
    ;;
  *) exit 2 ;;
esac
EOF
cat >"$helper_dir/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'ipc %s\n' "$*" >>"$CALL_LOG"
case ${1-} in
  shell) case ${2-} in
    listShellConfig) cat -- "$SHELL_CONFIG_FILE" ;;
    rescanPlugins) printf 'ok\n' ;;
    *) exit 2 ;;
  esac ;;
  *) exit 2 ;;
esac
EOF
cat >"$bin_dir/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
if [[ ${1-} == --user && ${2-} == is-active ]]; then
  [[ ${SYSTEMCTL_ACTIVE:-0} == 1 ]] && exit 0
  exit 1
fi
exit 0
EOF
cp -- "$source_helper" "$helper_dir/setup-desktop-shell-marketplace"
chmod +x -- "$helper_dir/desktop-shell-plugin" "$helper_dir/omarchy-shell" "$helper_dir/setup-desktop-shell-marketplace" "$bin_dir/systemctl"

export CALL_LOG="$log_file" DESKTOP_SHELL_PLUGINS_DIR="$plugins_dir" PLUGIN_LIST_FILE="$test_root/plugin-list.json" SHELL_CONFIG_FILE="$test_root/shell-config.json"
printf '%s\n' '[{"id":"io.yasino55.omarchy-plugin-marketplace","enabled":true,"firstParty":false}]' >"$PLUGIN_LIST_FILE"
printf '%s\n' '{"bar":{"layout":{"left":[],"center":[],"right":[]}}}' >"$SHELL_CONFIG_FILE"

if "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then
  fail "missing checkout unexpectedly passed check"
fi
[[ ! -e "$plugins_dir/io.yasino55.omarchy-plugin-marketplace" ]] || fail "check mutated missing checkout"
pass "missing checkout fails read-only check"

mkdir -p -- "$plugins_dir/io.yasino55.omarchy-plugin-marketplace"
printf '%s\n' '{"id":"io.yasino55.omarchy-plugin-marketplace"}' >"$plugins_dir/io.yasino55.omarchy-plugin-marketplace/manifest.json"
git -C "$plugins_dir/io.yasino55.omarchy-plugin-marketplace" init -q
git -C "$plugins_dir/io.yasino55.omarchy-plugin-marketplace" remote add origin 'git@github.com:Yasino55/omarchy-plugin-marketplace.git'
"$helper_dir/setup-desktop-shell-marketplace" --check || fail "correct checkout failed check"
pass "correct checkout passes normalized check"

rm -rf -- "$plugins_dir/io.yasino55.omarchy-plugin-marketplace"
: >"$log_file"
if ! PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --apply >"$test_root/apply.out" 2>"$test_root/apply.err"; then
  cat "$test_root/apply.err" >&2 || true
  cat "$log_file" >&2 || true
  fail "apply failed"
fi
grep -Fq 'manager add https://github.com/Yasino55/omarchy-plugin-marketplace.git --yes --expected-id io.yasino55.omarchy-plugin-marketplace' "$log_file" || fail "apply did not install with expected arguments"
grep -Fq 'manager enable io.yasino55.omarchy-plugin-marketplace --headless' "$log_file" || fail "apply did not request headless enablement"
grep -Fq 'ipc shell rescanPlugins' "$log_file" || fail "apply did not request plugin rescan"
grep -Fq 'systemctl --user start desktop-shell.service' "$log_file" || fail "apply did not start service"
jq -e --arg id io.yasino55.omarchy-plugin-marketplace \
  '[.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?] | all(.id != $id)' \
  "$SHELL_CONFIG_FILE" >/dev/null || fail "apply retained marketplace bar placement"
pass "apply installs, waits, and enables headless"

if PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then :; else fail "applied checkout failed second check"; fi
pass "repeated check is idempotent"

: >"$log_file"
PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --apply || fail "repeated apply failed"
! grep -Fq 'manager add ' "$log_file" || fail "repeated apply recloned checkout"
pass "repeated apply does not update or reclone"

: >"$log_file"
SYSTEMCTL_ACTIVE=0 PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --apply || fail "stopped-service recovery apply failed"
grep -Fq 'systemctl --user start desktop-shell.service' "$log_file" || fail "stopped service was not started before state recheck"
pass "existing checkout starts stopped service before rechecking"

: >"$log_file"
SYSTEMCTL_ACTIVE=1 PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --apply || fail "active-service apply failed"
! grep -Fq 'systemctl --user start desktop-shell.service' "$log_file" || fail "active service was redundantly started"
pass "active service is not redundantly started"

rm -rf -- "$plugins_dir/io.yasino55.omarchy-plugin-marketplace"
ln -s -- "$test_root/missing-checkout" "$plugins_dir/io.yasino55.omarchy-plugin-marketplace"
: >"$log_file"
if PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --apply >/dev/null 2>&1; then fail "dangling checkout symlink was accepted"; fi
! grep -Fq 'manager add ' "$log_file" || fail "dangling symlink triggered installation"
pass "dangling checkout symlink is rejected without installation"
rm -f -- "$plugins_dir/io.yasino55.omarchy-plugin-marketplace"
mkdir -p -- "$plugins_dir/io.yasino55.omarchy-plugin-marketplace"
printf '%s\n' '{"id":"io.yasino55.omarchy-plugin-marketplace"}' >"$plugins_dir/io.yasino55.omarchy-plugin-marketplace/manifest.json"
git -C "$plugins_dir/io.yasino55.omarchy-plugin-marketplace" init -q
git -C "$plugins_dir/io.yasino55.omarchy-plugin-marketplace" remote add origin 'https://github.com/Yasino55/omarchy-plugin-marketplace.git'

if "$helper_dir/omarchy-shell" shell plugin-rescan >/dev/null 2>&1; then fail "unsupported IPC method was accepted"; fi
pass "IPC stub rejects unsupported method names"

git -C "$plugins_dir/io.yasino55.omarchy-plugin-marketplace" remote set-url origin 'https://github.com/other-owner/other-repository.git'
if "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then fail "wrong origin passed check"; fi
if PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --apply >/dev/null 2>&1; then fail "wrong origin was replaced"; fi
[[ $(git -C "$plugins_dir/io.yasino55.omarchy-plugin-marketplace" remote get-url origin) == 'https://github.com/other-owner/other-repository.git' ]] || fail "wrong-origin checkout was mutated"
pass "wrong-origin checkout is rejected without replacement"

git -C "$plugins_dir/io.yasino55.omarchy-plugin-marketplace" remote set-url origin 'https://github.com/Yasino55/omarchy-plugin-marketplace.git'
jq '.id = "wrong.id"' "$plugins_dir/io.yasino55.omarchy-plugin-marketplace/manifest.json" >"$test_root/manifest.json"
mv -- "$test_root/manifest.json" "$plugins_dir/io.yasino55.omarchy-plugin-marketplace/manifest.json"
if "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then fail "wrong manifest id passed check"; fi
pass "wrong manifest id is rejected"
jq -n '{id:"io.yasino55.omarchy-plugin-marketplace"}' >"$plugins_dir/io.yasino55.omarchy-plugin-marketplace/manifest.json"

printf '%s\n' '[]' >"$PLUGIN_LIST_FILE"
if "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then fail "undiscovered plugin passed check"; fi
printf '%s\n' '[{"id":"io.yasino55.omarchy-plugin-marketplace","enabled":false,"firstParty":false}]' >"$PLUGIN_LIST_FILE"
if "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then fail "disabled plugin passed check"; fi
printf '%s\n' '[{"id":"io.yasino55.omarchy-plugin-marketplace","enabled":true,"firstParty":false}]' >"$PLUGIN_LIST_FILE"
printf '%s\n' '{"bar":{"layout":{"left":[],"center":[],"right":[{"id":"io.yasino55.omarchy-plugin-marketplace"}]}}}' >"$SHELL_CONFIG_FILE"
if "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then fail "wrong placement passed check"; fi
pass "discovery, enabled state, and barless placement are checked"

: >"$log_file"
PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --apply \
  || fail "bar-to-headless migration failed"
grep -Fq 'manager enable io.yasino55.omarchy-plugin-marketplace --headless' "$log_file" \
  || fail "apply did not request headless enablement for placed plugin"
jq -e --arg id io.yasino55.omarchy-plugin-marketplace \
  '[.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?] | all(.id != $id)' \
  "$SHELL_CONFIG_FILE" >/dev/null || fail "apply retained marketplace bar placement"
pass "bar placement migrates to headless state"

: >"$log_file"
PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --apply \
  || fail "headless apply was not idempotent"
! grep -Fq 'manager enable ' "$log_file" || fail "headless apply re-enabled marketplace"
pass "headless apply is idempotent"

printf 'All marketplace bootstrap tests passed.\n'
