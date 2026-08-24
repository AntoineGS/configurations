#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
manager="$repo_root/Linux/os/helpers/desktop-shell-plugin"
validator="$repo_root/Linux/os/helpers/desktop-shell-plugin-validate"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[[ -x "$validator" ]] || fail "validator is missing or not executable"
[[ -x "$manager" ]] || fail "manager is missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required"

plugins_dir="$test_root/plugins"
source_repo="$test_root/source"
ipc_stub="$test_root/ipc"
log_file="$test_root/ipc.log"
mkdir -p -- "$source_repo"

write_manifest() {
  jq -n '{schemaVersion:1,id:"acme.widget",name:"Acme Widget",version:"1.0.0",kinds:["bar-widget"],entryPoints:{barWidget:"Widget.qml"}}' >"$source_repo/manifest.json"
  printf 'import QtQuick\n' >"$source_repo/Widget.qml"
}

write_manifest
git -C "$source_repo" init -q
git -C "$source_repo" -c user.name=test -c user.email=test@example.invalid add .
git -C "$source_repo" -c user.name=test -c user.email=test@example.invalid commit -qm initial

cat >"$ipc_stub" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\t%s\t%s\n' "${2-}" "${3-}" "${4-}" >>"$IPC_LOG"
case "${2-}" in
  rescanPlugins) printf '%s\n' "${IPC_RESCAN_RESULT:-ok}" ;;
  listPlugins)
    if [[ -f $IPC_LIST ]]; then cat -- "$IPC_LIST"; else printf '[]\n'; fi
    ;;
  enablePlugin|setPluginEnabled) printf 'ok\n' ;;
  *) printf 'unsupported\n'; exit 1 ;;
esac
EOF
chmod +x -- "$ipc_stub"
export IPC_LOG="$log_file" IPC_LIST="$test_root/list.json"
manager_env=(DESKTOP_SHELL_PLUGINS_DIR="$plugins_dir" DESKTOP_SHELL_PLUGIN_VALIDATE="$validator" DESKTOP_SHELL_PLUGIN_IPC="$ipc_stub")

if env "${manager_env[@]}" "$manager" add "$source_repo" </dev/null >/dev/null 2>"$test_root/noninteractive.err"; then
  fail "non-interactive add unexpectedly succeeded"
fi
grep -Fq -- '--yes' "$test_root/noninteractive.err" || fail "non-interactive refusal omitted --yes guidance"

env "${manager_env[@]}" "$manager" add "$source_repo" --yes >/dev/null || fail "add failed"
[[ -f "$plugins_dir/acme.widget/manifest.json" ]] || fail "plugin was not installed under manifest id"
grep -Fq $'rescanPlugins\t\t' "$log_file" || fail "add did not request rescan"

jq -n '[{id:"acme.widget",name:"Acme Widget",kinds:["bar-widget"],enabled:false,clonedFrom:"local"}]' >"$IPC_LIST"
json_output=$(env "${manager_env[@]}" "$manager" list --json)
[[ $(jq -r '.[0].id' <<<"$json_output") == acme.widget ]] || fail "list --json changed plugin data"
plain_output=$(env "${manager_env[@]}" "$manager" list)
[[ $plain_output == $'acme.widget\tdisabled\tlocal\tbar-widget\tAcme Widget' ]] || fail "plain list format is incorrect"

env "${manager_env[@]}" "$manager" enable acme.widget 'section=right,index=2' || fail "enable failed"
grep -Fq $'enablePlugin\tacme.widget\t{"section":"right","index":2}' "$log_file" || fail "placement JSON is incorrect"
env "${manager_env[@]}" "$manager" disable acme.widget || fail "disable failed"
grep -Fq $'setPluginEnabled\tacme.widget\tfalse' "$log_file" || fail "disable call is incorrect"

if env "${manager_env[@]}" "$manager" enable acme.widget 'before=one,after=two' >/dev/null 2>&1; then
  fail "conflicting placement was accepted"
fi
if env "${manager_env[@]}" "$manager" add "$source_repo" --yes --expected-id other.widget >/dev/null 2>"$test_root/id.err"; then
  fail "expected-id mismatch was accepted"
fi
stages=("$plugins_dir"/.add.*)
[[ ! -e "$plugins_dir/other.widget" && ${#stages[@]} == 0 ]] || fail "failed expected-id add left files behind"

second_repo="$test_root/second"
cp -a -- "$source_repo" "$second_repo"
jq '.id="beta.widget"' "$second_repo/manifest.json" >"$second_repo/manifest.tmp"
mv -- "$second_repo/manifest.tmp" "$second_repo/manifest.json"
git -C "$second_repo" -c user.name=test -c user.email=test@example.invalid add .
git -C "$second_repo" -c user.name=test -c user.email=test@example.invalid commit -qm beta
IPC_RESCAN_RESULT=failed env "${manager_env[@]}" "$manager" add "$second_repo" --yes >/dev/null 2>&1 && fail "failed rescan was accepted"
[[ ! -e "$plugins_dir/beta.widget" ]] || fail "failed rescan left installed target"
stages=("$plugins_dir"/.add.*)
[[ ${#stages[@]} == 0 ]] || fail "failed rescan left staging directory"

reserved_repo="$test_root/reserved"
cp -a -- "$source_repo" "$reserved_repo"
jq '.id="desktop.clock"' "$reserved_repo/manifest.json" >"$reserved_repo/manifest.tmp"
mv -- "$reserved_repo/manifest.tmp" "$reserved_repo/manifest.json"
if env "${manager_env[@]}" "$manager" add "$reserved_repo" --yes >/dev/null 2>&1; then
  fail "reserved id was accepted"
fi
stages=("$plugins_dir"/.add.*)
[[ ${#stages[@]} == 0 ]] || fail "validator failure left staging directory"

printf 'PASS: desktop-shell plugin manager\n'
