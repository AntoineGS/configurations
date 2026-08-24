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

make_repo() {
  local directory=$1 id=$2
  cp -a -- "$source_repo" "$directory"
  jq --arg id "$id" '.id=$id' "$directory/manifest.json" >"$directory/manifest.tmp"
  mv -- "$directory/manifest.tmp" "$directory/manifest.json"
  git -C "$directory" -c user.name=test -c user.email=test@example.invalid add .
  git -C "$directory" -c user.name=test -c user.email=test@example.invalid commit -qm "$id"
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
    count_file="$IPC_LOG.list-count"
    count=0
    [[ -f $count_file ]] && count=$(<"$count_file")
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    if [[ ${IPC_LIST_MODE:-normal} == invalid ]]; then
      printf '%s\n' 'not-json'
    elif [[ ${IPC_LIST_MODE:-normal} == unsafe ]]; then
      printf '%s\n' '[{"id":"../unsafe"}]'
    elif [[ ${IPC_NEVER_DISCOVER:-0} == 1 || ( ${IPC_DELAY_LIST:-0} -ge "$count" ) ]]; then
      printf '[]\n'
    elif [[ -f $IPC_LIST ]]; then
      cat -- "$IPC_LIST"
    else
      printf '[]\n'
    fi
    ;;
  enablePlugin) printf '%s\n' "${IPC_ENABLE_RESULT:-ok}" ;;
  setPluginEnabled) printf '%s\n' "${IPC_DISABLE_RESULT:-ok}" ;;
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

env "${manager_env[@]}" "$manager" enable acme.widget --section right --index 2 || fail "enable failed"
grep -Fq $'enablePlugin\tacme.widget\t{"section":"right","index":2}' "$log_file" || fail "placement JSON is incorrect"
env "${manager_env[@]}" "$manager" enable acme.widget right || fail "positional section enable failed"
grep -Fq $'enablePlugin\tacme.widget\t{"section":"right"}' "$log_file" || fail "positional section JSON is incorrect"
env "${manager_env[@]}" "$manager" enable acme.widget --before acme.other || fail "before enable failed"
grep -Fq $'enablePlugin\tacme.widget\t{"before":"acme.other"}' "$log_file" || fail "before JSON is incorrect"
env "${manager_env[@]}" "$manager" enable acme.widget --after acme.other || fail "after enable failed"
grep -Fq $'enablePlugin\tacme.widget\t{"after":"acme.other"}' "$log_file" || fail "after JSON is incorrect"
env "${manager_env[@]}" "$manager" disable acme.widget || fail "disable failed"
grep -Fq $'setPluginEnabled\tacme.widget\tfalse' "$log_file" || fail "disable call is incorrect"

if env "${manager_env[@]}" "$manager" enable acme.widget --before acme.one --after acme.two >/dev/null 2>&1; then
  fail "conflicting placement was accepted"
fi
if env "${manager_env[@]}" "$manager" enable acme.widget --unknown value >/dev/null 2>&1; then
  fail "unknown placement option was accepted"
fi
if env "${manager_env[@]}" "$manager" enable acme.widget --section left --section right >/dev/null 2>&1; then
  fail "duplicate section option was accepted"
fi
if env "${manager_env[@]}" "$manager" add "$source_repo" --yes --expected-id other.widget >/dev/null 2>"$test_root/id.err"; then
  fail "expected-id mismatch was accepted"
fi
stages=("$plugins_dir"/.add.*)
[[ ! -e "$plugins_dir/other.widget" && ${#stages[@]} == 0 ]] || fail "failed expected-id add left files behind"

second_repo="$test_root/second"
make_repo "$second_repo" beta.widget
IPC_RESCAN_RESULT=failed env "${manager_env[@]}" "$manager" add "$second_repo" --yes >/dev/null 2>&1 && fail "failed rescan was accepted"
[[ ! -e "$plugins_dir/beta.widget" ]] || fail "failed rescan left installed target"
stages=("$plugins_dir"/.add.*)
[[ ${#stages[@]} == 0 ]] || fail "failed rescan left staging directory"

reserved_repo="$test_root/reserved"
make_repo "$reserved_repo" desktop.clock
if env "${manager_env[@]}" "$manager" add "$reserved_repo" --yes >/dev/null 2>&1; then
  fail "reserved id was accepted"
fi
stages=("$plugins_dir"/.add.*)
[[ ${#stages[@]} == 0 ]] || fail "validator failure left staging directory"

symlink_repo="$test_root/symlink"
make_repo "$symlink_repo" symlink.widget
ln -s -- /tmp "$symlink_repo/unsafe-link"
git -C "$symlink_repo" add unsafe-link
git -C "$symlink_repo" -c user.name=test -c user.email=test@example.invalid commit -qm symlink
if env "${manager_env[@]}" "$manager" add "$symlink_repo" --yes >/dev/null 2>&1; then
  fail "symlinked plugin was accepted"
fi
stages=("$plugins_dir"/.add.*)
[[ ${#stages[@]} == 0 ]] || fail "symlink validation left staging directory"

alias_manager="$test_root/manager-link"
ln -s -- "$manager" "$alias_manager"
"$alias_manager" validate "$source_repo" || fail "symlinked manager path did not resolve helpers"

alias_repo="$test_root/alias"
make_repo "$alias_repo" alias.widget
env "${manager_env[@]}" "$manager" install "$alias_repo" --yes >/dev/null || fail "install alias failed"
[[ -d "$plugins_dir/alias.widget" ]] || fail "install alias did not install target"

fake_bin="$test_root/bin"
mkdir -p -- "$fake_bin"
cat >"$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"$GIT_CAPTURE"
printf '%s\n' "GIT_TERMINAL_PROMPT=$GIT_TERMINAL_PROMPT" >>"$GIT_CAPTURE"
printf '%s\n' "GIT_ASKPASS=$GIT_ASKPASS" >>"$GIT_CAPTURE"
printf '%s\n' "GIT_SSH_COMMAND=$GIT_SSH_COMMAND" >>"$GIT_CAPTURE"
exec /usr/bin/git "$@"
EOF
chmod +x -- "$fake_bin/git"
prompt_repo="$test_root/prompt"
make_repo "$prompt_repo" prompt.widget
GIT_CAPTURE="$test_root/git.capture" PATH="$fake_bin:$PATH" env "${manager_env[@]}" "$manager" add "$prompt_repo" --yes >/dev/null || fail "captured clone failed"
grep -Fq -- '--no-recurse-submodules' "$test_root/git.capture" || fail "submodule recursion was not disabled"
grep -Fq -- 'GIT_TERMINAL_PROMPT=0' "$test_root/git.capture" || fail "Git terminal prompts were not disabled"
grep -Fq -- 'GIT_ASKPASS=/bin/false' "$test_root/git.capture" || fail "Git askpass was not disabled"

if command -v script >/dev/null 2>&1; then
  prompt_output=$(printf 'n\n' | script -qefc "env ${manager_env[*]} '$manager' add 'https://user:SECRET@example.invalid/repo?token=QUERY#fragment'" /dev/null 2>&1 || true)
  [[ $prompt_output == *'https://example.invalid/repo'* ]] || fail "interactive confirmation omitted sanitized URL"
  [[ $prompt_output != *SECRET* && $prompt_output != *QUERY* && $prompt_output != *fragment* ]] || fail "interactive confirmation leaked URL credentials"
fi
if env "${manager_env[@]}" "$manager" add "$test_root/missing-repository" --yes >/dev/null 2>&1; then
  fail "failed clone was accepted"
fi
stages=("$plugins_dir"/.add.*)
[[ ${#stages[@]} == 0 ]] || fail "failed clone left staging directory"

jq -n '[{"id":"acme.widget"}]' >"$IPC_LIST"
IPC_LIST_MODE=invalid env "${manager_env[@]}" "$manager" list --json >/dev/null 2>&1 && fail "invalid list response was accepted"
IPC_LIST_MODE=unsafe env "${manager_env[@]}" "$manager" list --json >/dev/null 2>&1 && fail "unsafe list id was accepted"
IPC_ENABLE_RESULT=not-ok env "${manager_env[@]}" "$manager" enable acme.widget >/dev/null 2>&1 && fail "non-ok enable response was accepted"
IPC_DISABLE_RESULT=not-ok env "${manager_env[@]}" "$manager" disable acme.widget >/dev/null 2>&1 && fail "non-ok disable response was accepted"

delayed_repo="$test_root/delayed"
make_repo "$delayed_repo" delayed.widget
jq -n '[{id:"delayed.widget",name:"Delayed",kinds:["bar-widget"],enabled:false}]' >"$IPC_LIST"
rm -f -- "$IPC_LOG.list-count"
IPC_DELAY_LIST=2 env "${manager_env[@]}" "$manager" add "$delayed_repo" --yes --enable >/dev/null || fail "delayed discovery activation failed"
list_count=$(<"$IPC_LOG.list-count")
[[ $list_count -ge 3 ]] || fail "activation did not wait for discovery"
enable_line=$(grep -n $'enablePlugin\tdelayed.widget' "$log_file" | cut -d: -f1)
last_list_line=$(grep -n $'listPlugins\t' "$log_file" | tail -n 1 | cut -d: -f1)
[[ $enable_line -gt $last_list_line ]] || fail "activation preceded discovery"

timeout_repo="$test_root/timeout"
make_repo "$timeout_repo" timeout.widget
rm -f -- "$IPC_LOG.list-count"
if IPC_NEVER_DISCOVER=1 env "${manager_env[@]}" "$manager" add "$timeout_repo" --yes --enable >/dev/null 2>&1; then
  fail "discovery timeout was accepted"
fi
[[ ! -e "$plugins_dir/timeout.widget" ]] || fail "discovery timeout left target"

activation_repo="$test_root/activation"
make_repo "$activation_repo" activation.widget
jq -n '[{id:"activation.widget",name:"Activation",kinds:["bar-widget"],enabled:false}]' >"$IPC_LIST"
if IPC_ENABLE_RESULT=failed env "${manager_env[@]}" "$manager" add "$activation_repo" --yes --enable >/dev/null 2>&1; then
  fail "activation failure was accepted"
fi
[[ ! -e "$plugins_dir/activation.widget" ]] || fail "activation failure left target"

credential_error=$(env "${manager_env[@]}" "$manager" add 'https://user:SECRET@example.invalid/repo?token=QUERY#fragment' --yes 2>&1 || true)
[[ $credential_error != *SECRET* && $credential_error != *QUERY* && $credential_error != *fragment* ]] || fail "clone diagnostics leaked URL credentials"
control_url=$'https://example.invalid/repo\nforged'
if env "${manager_env[@]}" "$manager" add "$control_url" --yes >/dev/null 2>"$test_root/control.err"; then
  fail "control-character URL was accepted"
fi
grep -Fq 'control characters' "$test_root/control.err" || fail "control-character URL was not rejected clearly"

duplicate_root="$plugins_dir/renamed-plugin"
cp -a -- "$plugins_dir/acme.widget" "$duplicate_root"
rm -rf -- "$plugins_dir/acme.widget"
if env "${manager_env[@]}" "$manager" add "$source_repo" --yes >/dev/null 2>&1; then
  fail "duplicate manifest ID under renamed directory was accepted"
fi
rm -rf -- "$duplicate_root"

printf 'PASS: desktop-shell plugin manager\n'
