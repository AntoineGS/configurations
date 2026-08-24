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
  list) [[ ${2-} == --json ]] && printf '%s\n' "${PLUGIN_LIST:-[]}" ;;
  add) mkdir -p -- "$DESKTOP_SHELL_PLUGINS_DIR/io.yasino55.omarchy-plugin-marketplace"; printf '%s\n' '{"id":"io.yasino55.omarchy-plugin-marketplace"}' >"$DESKTOP_SHELL_PLUGINS_DIR/io.yasino55.omarchy-plugin-marketplace/manifest.json"; git -C "$DESKTOP_SHELL_PLUGINS_DIR/io.yasino55.omarchy-plugin-marketplace" init -q; git -C "$DESKTOP_SHELL_PLUGINS_DIR/io.yasino55.omarchy-plugin-marketplace" remote add origin 'https://github.com/Yasino55/omarchy-plugin-marketplace.git' ;;
  enable) printf 'enabled\n' >>"$CALL_LOG" ;;
  *) exit 2 ;;
esac
EOF
cat >"$helper_dir/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'ipc %s\n' "$*" >>"$CALL_LOG"
case ${1-} in
  shell) case ${2-} in
    listShellConfig) printf '%s\n' "$SHELL_CONFIG" ;;
    *) printf 'ok\n' ;;
  esac ;;
  *) exit 2 ;;
esac
EOF
cat >"$bin_dir/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
[[ ${1-} == --user && ${2-} == is-active ]] && exit 1
exit 0
EOF
cp -- "$source_helper" "$helper_dir/setup-desktop-shell-marketplace"
chmod +x -- "$helper_dir/desktop-shell-plugin" "$helper_dir/omarchy-shell" "$helper_dir/setup-desktop-shell-marketplace" "$bin_dir/systemctl"

export CALL_LOG="$log_file" DESKTOP_SHELL_PLUGINS_DIR="$plugins_dir" PLUGIN_LIST='[{"id":"io.yasino55.omarchy-plugin-marketplace","enabled":true,"firstParty":false}]' SHELL_CONFIG='{"bar":{"layout":{"right":[{"id":"io.yasino55.omarchy-plugin-marketplace"}]}}}'

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
grep -Fq 'manager enable io.yasino55.omarchy-plugin-marketplace --section right' "$log_file" || fail "apply did not explicitly enable right section"
grep -Fq 'ipc shell plugin-rescan' "$log_file" || fail "apply did not request plugin rescan"
grep -Fq 'systemctl --user start desktop-shell.service' "$log_file" || fail "apply did not start service"
pass "apply installs, waits, and enables right section"

if PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then :; else fail "applied checkout failed second check"; fi
pass "repeated check is idempotent"

: >"$log_file"
PATH="$bin_dir:$PATH" "$helper_dir/setup-desktop-shell-marketplace" --apply || fail "repeated apply failed"
! grep -Fq 'manager add ' "$log_file" || fail "repeated apply recloned checkout"
pass "repeated apply does not update or reclone"

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

PLUGIN_LIST='[]'
if "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then fail "undiscovered plugin passed check"; fi
PLUGIN_LIST='[{"id":"io.yasino55.omarchy-plugin-marketplace","enabled":false,"firstParty":false}]'
if "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then fail "disabled plugin passed check"; fi
PLUGIN_LIST='[{"id":"io.yasino55.omarchy-plugin-marketplace","enabled":true,"firstParty":false}]'
SHELL_CONFIG='{"bar":{"layout":{"right":[]}}}'
if "$helper_dir/setup-desktop-shell-marketplace" --check >/dev/null 2>&1; then fail "wrong placement passed check"; fi
pass "discovery, enabled state, and right placement are checked"

printf 'All marketplace bootstrap tests passed.\n'
