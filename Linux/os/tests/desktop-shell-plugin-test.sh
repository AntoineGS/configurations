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

make_identity_plugin() {
  local remote=$1 seed=$2 installed=$3 id=$4
  cp -a -- "$source_repo" "$seed"
  jq --arg id "$id" '.id=$id' "$seed/manifest.json" >"$seed/manifest.tmp"
  mv -- "$seed/manifest.tmp" "$seed/manifest.json"
  git -C "$seed" add manifest.json
  git -C "$seed" -c user.name=test -c user.email=test@example.invalid commit -qm "$id"
  git -C "$seed" checkout -q -b main
  git clone -q --bare -- "$seed" "$remote"
  git -C "$seed" remote add origin "$remote"
  git -C "$seed" push -q "$remote" main
  git -C "$remote" symbolic-ref HEAD refs/heads/main
  git clone -q -- "$remote" "$installed"
}

update_identity_remote() {
  local seed=$1 id=$2
  jq --arg id "$id" '.id=$id' "$seed/manifest.json" >"$seed/manifest.tmp"
  mv -- "$seed/manifest.tmp" "$seed/manifest.json"
  git -C "$seed" add manifest.json
  git -C "$seed" -c user.name=test -c user.email=test@example.invalid commit -qm "$id"
  git -C "$seed" push -q origin main
}

commit_identity_remote_change() {
  local seed=$1 marker=$2
  printf '%s\n' "$marker" >>"$seed/Widget.qml"
  git -C "$seed" add Widget.qml
  git -C "$seed" -c user.name=test -c user.email=test@example.invalid commit -qm "$marker"
  git -C "$seed" push -q origin main
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
  rescanPlugins)
    if [[ -n ${IPC_RESCAN_MARKER:-} ]]; then
      : >"$IPC_RESCAN_MARKER"
    fi
    if [[ ${IPC_REPLACE_TARGET:-0} == 1 ]]; then
      mv -- "$IPC_TARGET" "$IPC_REPLACEMENT_BACKUP"
      mkdir -- "$IPC_TARGET"
      printf 'replacement\n' >"$IPC_TARGET/marker"
    fi
    if [[ ${IPC_SIGNAL_AFTER_RESCAN:-0} == 1 ]]; then
      kill -TERM "$PPID"
      sleep 0.2
    fi
    if [[ ${IPC_RESCAN_REPLACE_TARGET:-0} == 1 ]]; then
      mv -- "$IPC_TARGET" "$IPC_REPLACEMENT_BACKUP"
      mkdir -- "$IPC_TARGET"
      printf 'replacement-during-ipc\n' >"$IPC_TARGET/marker"
    fi
    if [[ ${IPC_RESCAN_REPOPULATE:-0} == 1 ]]; then
      mkdir -- "$IPC_TARGET"
      printf 'repopulated-during-ipc\n' >"$IPC_TARGET/marker"
    fi
    printf '%s\n' "${IPC_RESCAN_RESULT:-ok}"
    ;;
  beginPluginRescan)
    printf '%s\t\t\n' rescanPlugins >>"$IPC_LOG"
    if [[ -n ${IPC_RESCAN_MARKER:-} ]]; then
      : >"$IPC_RESCAN_MARKER"
    fi
    if [[ ${IPC_REPLACE_TARGET:-0} == 1 ]]; then
      mv -- "$IPC_TARGET" "$IPC_REPLACEMENT_BACKUP"
      mkdir -- "$IPC_TARGET"
      printf 'replacement\n' >"$IPC_TARGET/marker"
    fi
    if [[ ${IPC_SIGNAL_AFTER_RESCAN:-0} == 1 ]]; then
      kill -TERM "$PPID"
      sleep 0.2
    fi
    if [[ ${IPC_RESCAN_REPLACE_TARGET:-0} == 1 ]]; then
      mv -- "$IPC_TARGET" "$IPC_REPLACEMENT_BACKUP"
      mkdir -- "$IPC_TARGET"
      printf 'replacement-during-ipc\n' >"$IPC_TARGET/marker"
    fi
    if [[ ${IPC_RESCAN_REPOPULATE:-0} == 1 ]]; then
      mkdir -- "$IPC_TARGET"
      printf 'repopulated-during-ipc\n' >"$IPC_TARGET/marker"
    fi
    printf '1:1\n'
    ;;
  pluginRescanStatus)
    [[ $# -eq 3 ]] || exit 2
    if [[ -n ${IPC_STATUS_PENDING_MARKER:-} && ! -e ${IPC_BEGIN_RELEASE:-} ]]; then
      : >"$IPC_STATUS_PENDING_MARKER"
      printf 'pending\n'
    elif [[ ${IPC_RESCAN_RESULT:-ok} == ok ]]; then printf 'ok\n'; else printf 'error: %s\n' "${IPC_RESCAN_RESULT}"; fi
    ;;
  listPlugins)
    count_file="$IPC_LOG.list-count"
    count=0
    [[ -f $count_file ]] && count=$(<"$count_file")
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    if [[ ${IPC_LIST_MODE:-normal} == invalid ]]; then
      printf '%s\n' 'not-json'
    elif [[ ${IPC_LIST_MODE:-normal} == object ]]; then
      printf '%s\n' '{"id":"not-an-array"}'
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
  setPluginEnabled)
    if [[ ${IPC_REPLACE_ON_DISABLE:-0} == 1 ]]; then
      mv -- "$IPC_TARGET" "$IPC_REPLACEMENT_BACKUP"
      mkdir -- "$IPC_TARGET"
      printf 'replacement\n' >"$IPC_TARGET/marker"
    fi
    if [[ ${IPC_REPLACE_ROOT_ON_DISABLE:-0} == 1 ]]; then
      mv -- "$IPC_ROOT" "$IPC_ROOT_BACKUP"
      ln -s -- "$IPC_REPLACEMENT_ROOT" "$IPC_ROOT"
    fi
    printf '%s\n' "${IPC_DISABLE_RESULT:-ok}"
    ;;
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

failed_rescan_repo="$test_root/failed-rescan"
make_repo "$failed_rescan_repo" failed-rescan.widget
rescan_warning=$(IPC_RESCAN_RESULT=not-ok env "${manager_env[@]}" "$manager" add "$failed_rescan_repo" --yes 2>&1)
[[ -d "$plugins_dir/failed-rescan.widget" ]] || fail "rescan IPC failure rolled back publication"
[[ $rescan_warning == *"warning"* && $rescan_warning == *"reload"* ]] \
  || fail "rescan IPC failure omitted actionable warning"

jq -n '[
  {id:"desktop.bar",name:"Desktop Bar",kinds:["bar"],enabled:true,firstParty:true},
  {id:"Acme_Widget",name:"Acme Widget",kinds:["bar-widget"],enabled:false,clonedFrom:"local"},
  {id:"weather",name:"Weather",kinds:["panel"],enabled:false,clonedFrom:"local"}
]' >"$IPC_LIST"
for accepted_id in weather Acme_Widget acme-widget; do
  make_repo "$test_root/$accepted_id" "$accepted_id"
  env "${manager_env[@]}" "$manager" validate "$test_root/$accepted_id" >/dev/null \
    || fail "approved plugin ID was rejected: $accepted_id"
done
for rejected_id in desktop.clock omarchy.fake acme..widget; do
  make_repo "$test_root/rejected-$rejected_id" "$rejected_id"
  if env "${manager_env[@]}" "$manager" validate "$test_root/rejected-$rejected_id" >/dev/null 2>&1; then
    fail "rejected plugin ID was accepted: $rejected_id"
  fi
done
json_output=$(env "${manager_env[@]}" "$manager" list --json)
[[ $(jq -e 'map(.id) == ["desktop.bar", "Acme_Widget", "weather"]' <<<"$json_output") == true ]] \
  || fail "list --json rejected or changed valid plugin IDs"
plain_output=$(env "${manager_env[@]}" "$manager" list)
[[ $plain_output == *$'desktop.bar\tenabled'* && $plain_output == *$'Acme_Widget\tdisabled'* \
  && $plain_output == *$'weather\tdisabled'* ]] || fail "plain list format is incorrect"

env "${manager_env[@]}" "$manager" enable acme.widget --section right --index 2 || fail "enable failed"
grep -Fq $'enablePlugin\tacme.widget\t{"section":"right","index":2}' "$log_file" || fail "placement JSON is incorrect"
env "${manager_env[@]}" "$manager" enable acme.widget --index 3 || fail "independent index enable failed"
grep -Fq $'enablePlugin\tacme.widget\t{"index":3}' "$log_file" || fail "independent index JSON is incorrect"
env "${manager_env[@]}" "$manager" enable acme.widget --section left || fail "independent option section enable failed"
grep -Fq $'enablePlugin\tacme.widget\t{"section":"left"}' "$log_file" || fail "independent option section JSON is incorrect"
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
if env "${manager_env[@]}" "$manager" enable acme.widget --section right left >/dev/null 2>&1; then
  fail "option-then-positional section duplication was accepted"
fi
if env "${manager_env[@]}" "$manager" enable acme.widget left --section right >/dev/null 2>&1; then
  fail "positional-then-option section duplication was accepted"
fi
if env "${manager_env[@]}" "$manager" add "$source_repo" --yes --expected-id other.widget >/dev/null 2>"$test_root/id.err"; then
  fail "expected-id mismatch was accepted"
fi
stages=("$plugins_dir"/.plugin-artifacts/*/add.*)
[[ ! -e "$plugins_dir/other.widget" && ${#stages[@]} == 0 ]] || {
  printf 'expected-id error:\n%s\nstages:\n%s\n' "$(<"$test_root/id.err")" "${stages[*]}" >&2
  fail "failed expected-id add left files behind"
}

reserved_repo="$test_root/reserved"
make_repo "$reserved_repo" desktop.clock
if env "${manager_env[@]}" "$manager" add "$reserved_repo" --yes >/dev/null 2>&1; then
  fail "reserved id was accepted"
fi
stages=("$plugins_dir"/.plugin-artifacts/*/add.*)
[[ ${#stages[@]} == 0 ]] || fail "validator failure left staging directory"

symlink_repo="$test_root/symlink"
make_repo "$symlink_repo" symlink.widget
ln -s -- /tmp "$symlink_repo/unsafe-link"
git -C "$symlink_repo" add unsafe-link
git -C "$symlink_repo" -c user.name=test -c user.email=test@example.invalid commit -qm symlink
if env "${manager_env[@]}" "$manager" add "$symlink_repo" --yes >/dev/null 2>&1; then
  fail "symlinked plugin was accepted"
fi
stages=("$plugins_dir"/.plugin-artifacts/*/add.*)
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
else
  fail "script is required for deterministic interactive sanitizer coverage"
fi
if command -v script >/dev/null 2>&1; then
  scp_prompt=$(printf 'n\n' | script -qefc "env ${manager_env[*]} '$manager' add 'TOKEN@host.example:repo/path?token=QUERY#fragment'" /dev/null 2>&1 || true)
  [[ $scp_prompt == *'host.example:repo/path'* ]] || fail "SCP-like confirmation omitted sanitized URL"
  [[ $scp_prompt != *TOKEN* && $scp_prompt != *QUERY* && $scp_prompt != *fragment* ]] || fail "SCP-like confirmation leaked credentials"
fi
sanitized_scp=$("$manager" sanitize-url 'TOKEN@host.example:repo/path?token=QUERY#fragment')
[[ $sanitized_scp == 'host.example:repo/path' ]] || fail "deterministic SCP sanitizer path failed"
if env "${manager_env[@]}" "$manager" add "$test_root/missing-repository" --yes >/dev/null 2>&1; then
  fail "failed clone was accepted"
fi
stages=("$plugins_dir"/.plugin-artifacts/*/add.*)
[[ ${#stages[@]} == 0 ]] || fail "failed clone left staging directory"

jq -n '[{"id":"acme.widget"}]' >"$IPC_LIST"
IPC_LIST_MODE=invalid env "${manager_env[@]}" "$manager" list --json >/dev/null 2>&1 && fail "invalid list response was accepted"
IPC_LIST_MODE=object env "${manager_env[@]}" "$manager" list --json >/dev/null 2>&1 && fail "non-array list response was accepted"
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

failed_enable_repo="$test_root/failed-enable"
make_repo "$failed_enable_repo" failed-enable.widget
enable_warning=$(IPC_ENABLE_RESULT=not-ok env "${manager_env[@]}" "$manager" add "$failed_enable_repo" --yes --enable 2>&1 || true)
[[ -d "$plugins_dir/failed-enable.widget" ]] || fail "enable failure rolled back publication"
[[ $enable_warning == *"not enabled"* || $enable_warning == *"installed"* ]] \
  || fail "enable failure omitted installed-but-not-enabled warning"

signal_repo="$test_root/signal"
make_repo "$signal_repo" signal.widget
signal_status=0
IPC_SIGNAL_AFTER_RESCAN=1 env "${manager_env[@]}" "$manager" add "$signal_repo" --yes >/dev/null 2>&1 || signal_status=$?
[[ $signal_status == 143 ]] || fail "TERM after move returned status $signal_status"
[[ -d "$plugins_dir/signal.widget" ]] || fail "TERM after move deleted committed source"

signal_hook="$test_root/install-signal-hook"
cat >"$signal_hook" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$1" in
  before-discovery|before-enable)
    kill -TERM "$PPID"
    sleep 0.2
    ;;
esac
EOF
chmod +x -- "$signal_hook"
discovery_signal_repo="$test_root/discovery-signal"
make_repo "$discovery_signal_repo" discovery-signal.widget
discovery_signal_status=0
env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$signal_hook" \
  "$manager" add "$discovery_signal_repo" --yes --enable >/dev/null 2>&1 || discovery_signal_status=$?
[[ $discovery_signal_status == 143 ]] || fail "TERM during discovery returned status $discovery_signal_status"
[[ -d "$plugins_dir/discovery-signal.widget" ]] || fail "TERM during discovery deleted committed source"

enable_signal_repo="$test_root/enable-signal"
make_repo "$enable_signal_repo" enable-signal.widget
enable_signal_status=0
env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$signal_hook" \
  "$manager" add "$enable_signal_repo" --yes --enable >/dev/null 2>&1 || enable_signal_status=$?
[[ $enable_signal_status == 143 ]] || fail "TERM during enable returned status $enable_signal_status"
[[ -d "$plugins_dir/enable-signal.widget" ]] || fail "TERM during enable deleted committed source"

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

# Task 7 lifecycle fixtures use only local bare Git remotes.
remote_root="$test_root/remote"
remote_seed="$test_root/remote-seed"
mkdir -p -- "$remote_root"
cp -a -- "$source_repo" "$remote_seed"
jq --arg id lifecycle.widget '.id=$id' "$remote_seed/manifest.json" >"$remote_seed/manifest.tmp"
mv -- "$remote_seed/manifest.tmp" "$remote_seed/manifest.json"
git -C "$remote_seed" add manifest.json
git -C "$remote_seed" -c user.name=test -c user.email=test@example.invalid commit -qm lifecycle
git clone -q --bare -- "$remote_seed" "$remote_root/lifecycle.git"
git clone -q -- "$remote_root/lifecycle.git" "$plugins_dir/lifecycle.widget"
git -C "$plugins_dir/lifecycle.widget" remote set-head origin -a >/dev/null 2>&1 || true

rescan_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
env "${manager_env[@]}" "$manager" update lifecycle.widget --yes >/dev/null || fail "up-to-date update failed"
rescan_after=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
[[ $rescan_after == "$rescan_before" ]] || fail "up-to-date update requested rescan"

manual_artifacts=(
  "$plugins_dir/.plugin-artifacts/lifecycle.widget/rollback.manual"
  "$plugins_dir/.plugin-artifacts/lifecycle.widget/update.manual"
  "$plugins_dir/.plugin-artifacts/lifecycle.widget/rejected.manual"
  "$plugins_dir/.plugin-artifacts/lifecycle.widget/removed.manual"
)
for manual_artifact in "${manual_artifacts[@]}"; do
  mkdir -p -- "${manual_artifact%/*}"
  mkdir -- "$manual_artifact"
  if env "${manager_env[@]}" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
    fail "hidden artifact was accepted: $manual_artifact"
  fi
  [[ -d "$manual_artifact" ]] || fail "hidden artifact was changed: $manual_artifact"
  rmdir -- "$manual_artifact"
done
manual_guidance_rollback="$plugins_dir/.plugin-artifacts/lifecycle.widget/rollback.guidance"
mkdir -p -- "${manual_guidance_rollback%/*}"
mv -T -- "$plugins_dir/lifecycle.widget" "$manual_guidance_rollback"
manual_guidance_output=$(env "${manager_env[@]}" "$manager" update lifecycle.widget --yes 2>&1 || true)
printf -v manual_guidance_mv 'mv -T -- %q %q' "$manual_guidance_rollback" "$plugins_dir/lifecycle.widget"
[[ $manual_guidance_output == *"$manual_guidance_mv"* && $manual_guidance_output != */proc/self/fd/* ]] || {
  printf 'manual guidance:\n%s\nexpected:\n%s\n' "$manual_guidance_output" "$manual_guidance_mv" >&2
  fail "single rollback manual guidance was not canonical and exact"
}
mv -T -- "$manual_guidance_rollback" "$plugins_dir/lifecycle.widget"
mkdir -- "$plugins_dir/.plugin-artifacts/lifecycle.widget/rollback.guidance-a" "$plugins_dir/.plugin-artifacts/lifecycle.widget/rollback.guidance-b"
manual_multiple_output=$(env "${manager_env[@]}" "$manager" update lifecycle.widget --yes 2>&1 || true)
[[ $manual_multiple_output != *'mv -T --'* ]] || fail "multiple rollback guidance suggested ambiguous restoration"
rm -rf -- "$plugins_dir/.plugin-artifacts/lifecycle.widget/rollback.guidance-a" "$plugins_dir/.plugin-artifacts/lifecycle.widget/rollback.guidance-b"
ln -s -- "$plugins_dir/lifecycle.widget" "$plugins_dir/.plugin-artifacts/lifecycle.widget/update.invalid-type"
if env "${manager_env[@]}" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "invalid recovery artifact type was accepted"
fi
[[ -L "$plugins_dir/.plugin-artifacts/lifecycle.widget/update.invalid-type" ]] || fail "invalid recovery artifact was deleted"
rm -f -- "$plugins_dir/.plugin-artifacts/lifecycle.widget/update.invalid-type"

malformed_owner_file="$plugins_dir/.plugin-artifacts/malformed-owner-file"
: >"$malformed_owner_file"
if env "${manager_env[@]}" "$manager" add "$source_repo" --yes >/dev/null 2>&1; then
  fail "add ignored malformed depth-one owner file"
fi
rm -f -- "$malformed_owner_file"

malformed_owner_link="$plugins_dir/.plugin-artifacts/malformed-owner-link"
ln -s -- /tmp "$malformed_owner_link"
if env "${manager_env[@]}" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "update ignored malformed depth-one owner symlink"
fi
rm -f -- "$malformed_owner_link"

malformed_owner_name="$plugins_dir/.plugin-artifacts/malformed..owner/update.marker"
mkdir -p -- "${malformed_owner_name%/*}"
mkdir -- "$malformed_owner_name"
if env "${manager_env[@]}" "$manager" remove lifecycle.widget --yes >/dev/null 2>&1; then
  fail "remove ignored malformed artifact owner name"
fi
rm -rf -- "${malformed_owner_name%/*}"

git -C "$remote_seed" checkout -q -b main
printf 'updated\n' >"$remote_seed/Widget.qml"
git -C "$remote_seed" add Widget.qml
git -C "$remote_seed" -c user.name=test -c user.email=test@example.invalid commit -qm update
git -C "$remote_seed" push -q "$remote_root/lifecycle.git" main
git -C "$remote_root/lifecycle.git" symbolic-ref HEAD refs/heads/main
prior_commit=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
atomic_manifest_hash=$(sha256sum "$plugins_dir/lifecycle.widget/manifest.json")
atomic_qml_hash=$(sha256sum "$plugins_dir/lifecycle.widget/Widget.qml")
atomic_inode=$(stat -c '%d:%i' "$plugins_dir/lifecycle.widget")
atomic_hook="$test_root/atomic-hook"
cat >"$atomic_hook" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $1 == update-after-fetch ]]; then
  [[ $(sha256sum "$ATOMIC_PUBLIC/manifest.json") == "$ATOMIC_MANIFEST_HASH" ]] || exit 1
  [[ $(sha256sum "$ATOMIC_PUBLIC/Widget.qml") == "$ATOMIC_QML_HASH" ]] || exit 1
fi
EOF
chmod +x -- "$atomic_hook"
atomic_validator="$test_root/atomic-validator"
cat >"$atomic_validator" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
candidate=$1
candidate_real=$(realpath -- "$candidate")
if [[ $candidate_real == "$ATOMIC_PUBLIC" ]]; then
  exec "$ATOMIC_REAL_VALIDATOR" "$candidate_real"
fi
[[ $candidate_real == "$ATOMIC_PLUGINS"/.plugin-artifacts/lifecycle.widget/update.* ]] || { printf 'bad candidate path: %s\n' "$candidate_real" >&2; exit 1; }
[[ $(sha256sum "$ATOMIC_PUBLIC/manifest.json") == "$ATOMIC_MANIFEST_HASH" ]] || { printf 'manifest changed\n' >&2; exit 1; }
[[ $(sha256sum "$ATOMIC_PUBLIC/Widget.qml") == "$ATOMIC_QML_HASH" ]] || { printf 'qml changed\n' >&2; exit 1; }
stages=("$ATOMIC_PLUGINS"/.plugin-artifacts/lifecycle.widget/update.*)
[[ ${#stages[@]} == 1 && -d ${stages[0]} ]] || { printf 'stage count: %s\n' "${#stages[@]}" >&2; exit 1; }
exec "$ATOMIC_REAL_VALIDATOR" "$candidate_real"
EOF
chmod +x -- "$atomic_validator"
env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$atomic_hook" \
  DESKTOP_SHELL_PLUGIN_VALIDATE="$atomic_validator" ATOMIC_PUBLIC="$plugins_dir/lifecycle.widget" \
  ATOMIC_PLUGINS="$plugins_dir" ATOMIC_MANIFEST_HASH="$atomic_manifest_hash" ATOMIC_QML_HASH="$atomic_qml_hash" \
  ATOMIC_REAL_VALIDATOR="$validator" "$manager" update lifecycle.widget --yes >"$test_root/atomic.out" 2>"$test_root/atomic.err" || {
    printf 'atomic update output:\n%s\n' "$(<"$test_root/atomic.err")" >&2
    fail "atomic update failed"
  }
if grep -Fq 'retaining rejected artifact' "$test_root/atomic.err"; then
  fail "successful update warned about a missing rejected artifact"
fi
updated_commit=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
[[ $updated_commit != "$prior_commit" ]] || fail "fast-forward update did not advance"
[[ $(git -C "$plugins_dir/lifecycle.widget" remote get-url origin) == "$remote_root/lifecycle.git" ]] ||
  fail "published checkout lost origin"
[[ $(git -C "$plugins_dir/lifecycle.widget" status --porcelain) == "" ]] || fail "published checkout is dirty"
[[ $(stat -c '%d:%i' "$plugins_dir/lifecycle.widget") != "$atomic_inode" ]] || fail "publication did not swap directory identity"
[[ $(sha256sum "$plugins_dir/lifecycle.widget/manifest.json") == "$atomic_manifest_hash" ]] || fail "manifest changed unexpectedly"
grep -Fq $'rescanPlugins\t\t' "$log_file" || fail "successful update did not request rescan"
printf 'artifact-gap-update\n' >>"$remote_seed/Widget.qml"
git -C "$remote_seed" add Widget.qml
git -C "$remote_seed" -c user.name=test -c user.email=test@example.invalid commit -qm artifact-gap-update
git -C "$remote_seed" push -q "$remote_root/lifecycle.git" main
gap_artifact="$plugins_dir/.plugin-artifacts/lifecycle.widget/update.gap"
gap_hook="$test_root/gap-hook"
cat >"$gap_hook" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $1 == update-after-fetch ]]; then
  mkdir -p -- "${GAP_ARTIFACT%/*}"
  mkdir -- "$GAP_ARTIFACT"
fi
EOF
chmod +x -- "$gap_hook"
gap_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$gap_hook" GAP_ARTIFACT="$gap_artifact" \
  "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "artifact created before candidate build was accepted"
fi
[[ $(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD) == "$gap_prior" ]] || \
  fail "pre-build artifact changed explicit update target"
[[ -d "$gap_artifact" ]] || fail "pre-build artifact evidence was deleted"
rm -rf -- "$gap_artifact"
printf 'post-verify-update\n' >>"$remote_seed/Widget.qml"
git -C "$remote_seed" add Widget.qml
git -C "$remote_seed" -c user.name=test -c user.email=test@example.invalid commit -qm post-verify-update
git -C "$remote_seed" push -q "$remote_root/lifecycle.git" main
post_verify_validator="$test_root/post-verify-validator"
cat >"$post_verify_validator" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $(realpath -- "$1") == "$POST_VERIFY_PUBLIC" ]]; then
  exit 1
fi
exec "$POST_VERIFY_REAL_VALIDATOR" "$1"
EOF
chmod +x -- "$post_verify_validator"
post_verify_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_VALIDATE="$post_verify_validator" \
  POST_VERIFY_PUBLIC="$plugins_dir/lifecycle.widget" POST_VERIFY_REAL_VALIDATOR="$validator" \
  "$manager" update lifecycle.widget --yes >"$test_root/post_verify.out" 2>"$test_root/post_verify.err"; then
  fail "post-publication verification failure was accepted"
fi
[[ $(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD) == "$post_verify_prior" ]] ||
  fail "post-publication verification did not restore old checkout"
post_verify_artifacts=("$plugins_dir/.plugin-artifacts/lifecycle.widget"/{update,rollback,rejected}.*)
if [[ ${#post_verify_artifacts[@]} != 0 ]]; then
  [[ ${#post_verify_artifacts[@]} == 1 && ${post_verify_artifacts[0]} == "$plugins_dir/.plugin-artifacts/lifecycle.widget/rejected."* ]] || {
    printf 'post-verify stdout:\n%s\npost-verify stderr:\n%s\n' "$(<"$test_root/post_verify.out")" "$(<"$test_root/post_verify.err")" >&2
    fail "post-publication failure left unexpected artifacts: ${post_verify_artifacts[*]}"
  }
  rm -rf -- "${post_verify_artifacts[0]}"
fi

printf 'second-rename-update\n' >>"$remote_seed/Widget.qml"
git -C "$remote_seed" add Widget.qml
git -C "$remote_seed" -c user.name=test -c user.email=test@example.invalid commit -qm second-rename-update
git -C "$remote_seed" push -q "$remote_root/lifecycle.git" main
rename_bin="$test_root/rename-bin"
mkdir -p -- "$rename_bin"
cat >"$rename_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
  if [[ ${FAIL_SECOND_RENAME:-0} == 1 && $* == *'.plugin-artifacts/lifecycle.widget/update.'* && $* == *'lifecycle.widget'* ]]; then
  exit 1
fi
exec /bin/mv "$@"
EOF
chmod +x -- "$rename_bin/mv"
second_rename_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
if env "${manager_env[@]}" PATH="$rename_bin:$PATH" FAIL_SECOND_RENAME=1 "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "second publication rename failure was accepted"
fi
[[ $(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD) == "$second_rename_prior" ]] ||
  fail "second publication rename failure lost old checkout"
rm -rf -- "$plugins_dir/.plugin-artifacts/lifecycle.widget/rollback."*

public_id_drift_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
jq '.id = "drifted.widget"' "$plugins_dir/lifecycle.widget/manifest.json" >"$plugins_dir/lifecycle.widget/manifest.tmp"
mv -- "$plugins_dir/lifecycle.widget/manifest.tmp" "$plugins_dir/lifecycle.widget/manifest.json"
git -C "$plugins_dir/lifecycle.widget" add manifest.json
git -C "$plugins_dir/lifecycle.widget" -c user.name=test -c user.email=test@example.invalid commit -qm public-id-drift
public_id_drift_hook="$test_root/public-id-drift-hook"
cat >"$public_id_drift_hook" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $1 != update-after-fetch ]] || : >"$PUBLIC_ID_DRIFT_FETCHED"
EOF
chmod +x -- "$public_id_drift_hook"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$public_id_drift_hook" \
  PUBLIC_ID_DRIFT_FETCHED="$test_root/public-id-drift-fetched" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "public manifest ID drift was accepted"
fi
[[ ! -e "$test_root/public-id-drift-fetched" ]] || fail "public ID drift fetched before rejection"
git -C "$plugins_dir/lifecycle.widget" reset --hard -q "$public_id_drift_prior"
git -C "$plugins_dir/lifecycle.widget" checkout -q --detach "$public_id_drift_prior"
hidden_dir="$plugins_dir/.hidden.widget"
mkdir -p -- "$hidden_dir"
env "${manager_env[@]}" "$manager" update --yes >/dev/null || fail "bulk update failed"
if env "${manager_env[@]}" "$manager" update missing.widget --yes >/dev/null 2>&1; then
  fail "unknown update ID was accepted"
fi

non_git_update="$plugins_dir/non-git-update.widget"
mkdir -p -- "$non_git_update"
if env "${manager_env[@]}" "$manager" update non-git-update.widget --yes >/dev/null 2>&1; then
  fail "non-Git update was accepted"
fi

no_origin="$plugins_dir/no-origin.widget"
git clone -q -- "$remote_root/lifecycle.git" "$no_origin"
git -C "$no_origin" remote remove origin
if env "${manager_env[@]}" "$manager" update no-origin.widget --yes >/dev/null 2>&1; then
  fail "missing-origin update was accepted"
fi
rm -rf -- "$no_origin"

invalid_remote="$test_root/invalid.git"
invalid_head="$plugins_dir/invalid-head.widget"
git init -q --bare "$invalid_remote"
git init -q "$invalid_head"
git -C "$invalid_head" config user.name test
git -C "$invalid_head" config user.email test@example.invalid
git -C "$invalid_head" remote add origin "$invalid_remote"
printf 'invalid-head\n' >"$invalid_head/data"
git -C "$invalid_head" add .
git -C "$invalid_head" commit -qm invalid-head
if env "${manager_env[@]}" "$manager" update invalid-head.widget --yes >/dev/null 2>&1; then
  fail "invalid remote HEAD update was accepted"
fi

validation_repo="$test_root/validation"
cp -a -- "$remote_seed" "$validation_repo"
printf 'invalid\n' >"$validation_repo/Widget.qml"
git -C "$validation_repo" add Widget.qml
git -C "$validation_repo" -c user.name=test -c user.email=test@example.invalid commit -qm invalid-update
git -C "$validation_repo" push -q "$remote_root/lifecycle.git" main
validation_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
validation_rescan_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_VALIDATE=/bin/false "$manager" update lifecycle.widget --yes >"$test_root/validation.out" 2>"$test_root/validation.err"; then
  fail "validation-failing update was accepted"
fi
[[ $(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD) == "$validation_prior" ]] || fail "validation rollback changed commit"
validation_stages=("$plugins_dir/.plugin-artifacts/lifecycle.widget/update."*)
[[ ${#validation_stages[@]} == 0 ]] || { printf 'validation output:\n%s\n' "$(<"$test_root/validation.err")" >&2; fail "validation failure left update stage: ${validation_stages[*]}"; }
find_fail_bin="$test_root/find-fail-bin"
mkdir -p -- "$find_fail_bin"
cat >"$find_fail_bin/find" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $* == *' -xdev '* ]]; then
  exit 1
fi
exec /usr/bin/find "$@"
EOF
chmod +x -- "$find_fail_bin/find"
if env "${manager_env[@]}" PATH="$find_fail_bin:$PATH" DESKTOP_SHELL_PLUGIN_VALIDATE=/bin/false \
  "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "find deletion failure was accepted"
fi
find_fail_stages=("$plugins_dir/.plugin-artifacts/lifecycle.widget/update."*)
[[ ${#find_fail_stages[@]} == 1 ]] || fail "find deletion failure did not retain stage"
rm -rf -- "${find_fail_stages[@]}"
validation_rescan_after=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
[[ $validation_rescan_after == "$validation_rescan_before" ]] || fail "validation rollback requested rescan"

signal_validator="$test_root/signal-validator"
cat >"$signal_validator" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
kill -TERM "\$PPID"
sleep 0.2
exec "$validator" "\$1"
EOF
chmod +x -- "$signal_validator"
signal_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
signal_status=0
env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_VALIDATE="$signal_validator" "$manager" update lifecycle.widget --yes >"$test_root/signal.out" 2>"$test_root/signal.err" || signal_status=$?
[[ $signal_status == 143 ]] || { printf 'signal output:\n%s\n' "$(<"$test_root/signal.err")" >&2; fail "signal after merge returned status $signal_status"; }
[[ $(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD) == "$signal_prior" ]] || fail "signal after merge did not roll back"

race_hook="$test_root/race-hook"
cat >"$race_hook" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ -z ${RACE_HOOK_LOG:-} ]] || printf '%s\n' "$1" >>"$RACE_HOOK_LOG"
case "$1" in
  root-open)
    [[ -n ${RACE_ROOT:-} ]] || exit 0
    mv -- "$RACE_ROOT" "$RACE_ROOT_BACKUP"
    ln -s -- "$RACE_REPLACEMENT" "$RACE_ROOT"
    ;;
  update-after-status|update-after-fetch)
    if [[ ${RACE_METADATA_SWAP:-0} == 1 ]]; then
      mv -- "$RACE_GIT_DIR" "$RACE_GIT_BACKUP"
      cp -a -- "$RACE_GIT_REPLACEMENT" "$RACE_GIT_DIR"
    else
      mv -- "$RACE_TARGET" "$RACE_TARGET_BACKUP"
      git clone -q -- "$RACE_REMOTE" "$RACE_TARGET"
    fi
    ;;
  remove-before-quarantine)
    [[ ${RACE_REMOVE_BEFORE:-0} == 1 ]] || exit 0
    mv -- "$RACE_TARGET" "$RACE_TARGET_BACKUP"
    mkdir -- "$RACE_TARGET"
    printf 'replacement\n' >"$RACE_TARGET/marker"
    ;;
  remove-after-revalidate)
    [[ ${RACE_REMOVE_AFTER:-0} == 1 ]] || exit 0
    mv -- "$RACE_TARGET" "$RACE_TARGET_BACKUP"
    mkdir -- "$RACE_TARGET"
    printf 'replacement\n' >"$RACE_TARGET/marker"
    ;;
  quarantine-after-identity)
    [[ ${RACE_IDENTITY_AFTER:-0} == 1 ]] || exit 0
    mv -- "$2" "$RACE_TARGET_BACKUP"
    git clone -q -- "$RACE_REMOTE" "$2"
    ;;
  quarantine-after-delete)
    [[ ${RACE_DELETE_AFTER:-0} == 1 ]] || exit 0
    mv -- "$2" "$RACE_TARGET_BACKUP"
    mkdir -- "$2"
    ;;
  before-publication|after-first-publication-rename)
    exit 0
    ;;
  before-rescan)
    case ${RACE_RESCAN_MODE:-} in
      update)
        mv -- "$RACE_TARGET" "$RACE_TARGET_BACKUP"
        mkdir -- "$RACE_TARGET"
        printf 'replacement\n' >"$RACE_TARGET/marker"
        ;;
      remove)
        mkdir -- "$RACE_TARGET"
        printf 'repopulated\n' >"$RACE_TARGET/marker"
        ;;
    esac
    ;;
  *)
    printf 'unknown race hook: %s\n' "$1" >&2
    exit 2
    ;;
esac
EOF
chmod +x -- "$race_hook"

race_root="$test_root/race-root"
race_root_backup="$test_root/race-root-backup"
race_replacement="$test_root/race-replacement"
mkdir -p -- "$race_root" "$race_replacement"
race_status=0
env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$race_root" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$race_hook" \
  RACE_ROOT="$race_root" RACE_ROOT_BACKUP="$race_root_backup" RACE_REPLACEMENT="$race_replacement" \
  "$manager" update --yes >/dev/null 2>&1 || race_status=$?
[[ $race_status != 0 && -L $race_root ]] || fail "root-open replacement was accepted"
rm -f -- "$race_root"
mv -- "$race_root_backup" "$race_root"

status_race_backup="$test_root/status-race-backup"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$race_hook" \
  RACE_TARGET="$plugins_dir/lifecycle.widget" RACE_TARGET_BACKUP="$status_race_backup" RACE_REMOTE="$remote_root/lifecycle.git" \
  DESKTOP_SHELL_PLUGIN_VALIDATE="$validator" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "status-to-fetch replacement was accepted"
fi
[[ -d "$status_race_backup" && -d "$plugins_dir/lifecycle.widget" ]] || fail "status race fixture was lost"
rm -rf -- "$status_race_backup"

metadata_replacement="$test_root/metadata-replacement"
git clone -q -- "$remote_root/lifecycle.git" "$metadata_replacement"
metadata_backup="$test_root/metadata-backup"
metadata_error="$test_root/metadata-race.err"
metadata_hook_log="$test_root/metadata-race.log"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$race_hook" RACE_METADATA_SWAP=1 \
  RACE_GIT_DIR="$plugins_dir/lifecycle.widget/.git" RACE_GIT_BACKUP="$metadata_backup" \
  RACE_GIT_REPLACEMENT="$metadata_replacement/.git" RACE_HOOK_LOG="$metadata_hook_log" "$manager" update lifecycle.widget --yes >"$metadata_error" 2>&1; then
  printf 'metadata race command output:\n%s\nhooks:\n%s\n' "$(<"$metadata_error")" "$(<"$metadata_hook_log")" >&2
  fail "Git metadata replacement was accepted"
fi
[[ -d "$metadata_backup" && -d "$plugins_dir/lifecycle.widget/.git" ]] || fail "Git metadata race fixture was lost"
rm -rf -- "$plugins_dir/lifecycle.widget/.git"
mv -- "$metadata_backup" "$plugins_dir/lifecycle.widget/.git"
rm -rf -- "$metadata_replacement"

rollback_metadata_validator="$test_root/rollback-metadata-validator"
printf 'rollback-metadata\n' >>"$validation_repo/Widget.qml"
git -C "$validation_repo" add Widget.qml
git -C "$validation_repo" -c user.name=test -c user.email=test@example.invalid commit -qm rollback-metadata
git -C "$validation_repo" push -q "$remote_root/lifecycle.git" main
cat >"$rollback_metadata_validator" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
mv -- "$RACE_TARGET/.git" "$RACE_GIT_BACKUP"
cp -a -- "$RACE_GIT_REPLACEMENT" "$RACE_TARGET/.git"
exit 1
EOF
chmod +x -- "$rollback_metadata_validator"
rollback_metadata_backup="$test_root/rollback-metadata-backup"
rollback_metadata_replacement="$test_root/rollback-metadata-replacement"
git clone -q -- "$remote_root/lifecycle.git" "$rollback_metadata_replacement"
git -C "$plugins_dir/lifecycle.widget" show HEAD:Widget.qml >"$test_root/rollback-metadata-prior-widget"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_VALIDATE="$rollback_metadata_validator" \
  RACE_TARGET="$plugins_dir/lifecycle.widget" RACE_GIT_BACKUP="$rollback_metadata_backup" \
  RACE_GIT_REPLACEMENT="$rollback_metadata_replacement/.git" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "metadata replacement validation unexpectedly succeeded"
fi
[[ -d "$rollback_metadata_backup" && -d "$plugins_dir/lifecycle.widget" ]] ||
  fail "candidate validation metadata race fixture was lost"
rm -rf -- "$plugins_dir/lifecycle.widget/.git"
mv -- "$rollback_metadata_backup" "$plugins_dir/lifecycle.widget/.git"
rm -rf -- "$rollback_metadata_replacement"
printf 'validator-update\n' >>"$validation_repo/Widget.qml"
git -C "$validation_repo" add Widget.qml
git -C "$validation_repo" -c user.name=test -c user.email=test@example.invalid commit -qm validator-update
git -C "$validation_repo" push -q "$remote_root/lifecycle.git" main

validator_swap="$test_root/validator-swap"
validator_swap_backup="$test_root/validator-swap-backup"
validator_swap_error="$test_root/validator-swap.err"
cat >"$validator_swap" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
mv -- "$RACE_TARGET" "$RACE_TARGET_BACKUP"
git clone -q -- "$RACE_REMOTE" "$RACE_TARGET"
exec "$RACE_VALIDATOR" "$1"
EOF
chmod +x -- "$validator_swap"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_VALIDATE="$validator_swap" \
  RACE_TARGET="$plugins_dir/lifecycle.widget" RACE_TARGET_BACKUP="$validator_swap_backup" \
  RACE_REMOTE="$remote_root/lifecycle.git" RACE_VALIDATOR="$validator" \
  "$manager" update lifecycle.widget --yes >"$validator_swap_error" 2>&1; then
  fail "public target replacement during candidate validation was accepted"
else
  printf 'validator race command output:\n%s\n' "$(<"$validator_swap_error")" >&2
fi
[[ -d "$validator_swap_backup" && -d "$plugins_dir/lifecycle.widget" ]] || fail "validator target race fixture was lost"
rm -rf -- "$validator_swap_backup"

fetch_race_backup="$test_root/fetch-race-backup"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$race_hook" \
  RACE_TARGET="$plugins_dir/lifecycle.widget" RACE_TARGET_BACKUP="$fetch_race_backup" RACE_REMOTE="$remote_root/lifecycle.git" \
  "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "fetch-to-merge replacement was accepted"
fi
[[ -d "$fetch_race_backup" && -d "$plugins_dir/lifecycle.widget" ]] || fail "fetch race fixture was lost"
rm -rf -- "$fetch_race_backup"

: <<'OUT_OF_SCOPE_RACES'
remove_race_target="$plugins_dir/remove-race.widget"
mkdir -p -- "$remove_race_target"
printf '{}\n' >"$remove_race_target/manifest.json"
remove_race_backup="$test_root/remove-race-backup"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$race_hook" \
  RACE_REMOVE_BEFORE=1 RACE_TARGET="$remove_race_target" RACE_TARGET_BACKUP="$remove_race_backup" \
  "$manager" remove remove-race.widget --yes >/dev/null 2>&1; then
  fail "revalidation-to-rename replacement was accepted"
fi
[[ -f "$remove_race_backup/manifest.json" && -f "$remove_race_target/marker" ]] || fail "remove rename race fixture was lost"

anchor_race_target="$plugins_dir/anchor-race.widget"
mkdir -p -- "$anchor_race_target"
printf '{}\n' >"$anchor_race_target/manifest.json"
anchor_race_backup="$test_root/anchor-race-backup"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$race_hook" RACE_REMOVE_AFTER=1 \
  RACE_TARGET="$anchor_race_target" RACE_TARGET_BACKUP="$anchor_race_backup" \
  "$manager" remove anchor-race.widget --yes >/dev/null 2>&1; then
  fail "final check-to-quarantine replacement was accepted"
fi
[[ -f "$anchor_race_backup/manifest.json" && -f "$anchor_race_target/marker" ]] || fail "quarantine restoration fixture was lost"

quarantine_race_target="$plugins_dir/quarantine-race.widget"
git clone -q -- "$remote_root/lifecycle.git" "$quarantine_race_target"
quarantine_race_backup="$test_root/quarantine-race-backup"
quarantine_race_error="$test_root/quarantine-race.err"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$race_hook" RACE_IDENTITY_AFTER=1 \
  RACE_TARGET="$test_root/.removed.quarantine-race.widget" RACE_TARGET_BACKUP="$quarantine_race_backup" RACE_REMOTE="$remote_root/lifecycle.git" \
  "$manager" remove quarantine-race.widget --yes >"$quarantine_race_error" 2>&1; then
  fail "post-quarantine identity replacement was accepted"
fi
quarantine_replacement="$plugins_dir/.removed.quarantine-race.widget.*"
quarantine_matches=0
for quarantine_path in $quarantine_replacement; do
  [[ -d $quarantine_path ]] || continue
  quarantine_matches=$((quarantine_matches + 1))
done
if [[ $quarantine_matches != 1 || ! -d $quarantine_race_backup ]]; then
  printf 'quarantine race command output:\n%s\n' "$(<"$quarantine_race_error")" >&2
  fail "quarantine identity race deleted or lost object"
fi

post_delete_target="$plugins_dir/post-delete-race.widget"
git clone -q -- "$remote_root/lifecycle.git" "$post_delete_target"
post_delete_backup="$test_root/post-delete-backup"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$race_hook" RACE_DELETE_AFTER=1 \
  RACE_TARGET_BACKUP="$post_delete_backup" "$manager" remove post-delete-race.widget --yes >/dev/null 2>&1; then
  fail "post-delete quarantine replacement was accepted"
fi
post_delete_path="$plugins_dir/.removed.post-delete-race.widget.*"
post_delete_matches=0
for quarantine_path in $post_delete_path; do
  [[ -d $quarantine_path ]] || continue
  post_delete_matches=$((post_delete_matches + 1))
done
[[ $post_delete_matches == 1 && -d "$post_delete_backup" ]] || fail "post-delete quarantine replacement was removed"
OUT_OF_SCOPE_RACES

bulk_plugins="$test_root/bulk-plugins"
mkdir -p -- "$bulk_plugins"
bulk_good="$bulk_plugins/bulk-good.widget"
bulk_bad="$bulk_plugins/bulk-bad.widget"
bulk_good_remote="$test_root/bulk-good.git"
bulk_good_seed="$test_root/bulk-good-seed"
bulk_bad_remote="$test_root/bulk-bad.git"
bulk_bad_seed="$test_root/bulk-bad-seed"
make_identity_plugin "$bulk_good_remote" "$bulk_good_seed" "$bulk_good" bulk-good.widget
make_identity_plugin "$bulk_bad_remote" "$bulk_bad_seed" "$bulk_bad" bulk-bad.widget
commit_identity_remote_change "$bulk_good_seed" bulk-update-good
printf 'bulk-diverged\n' >>"$bulk_bad/Widget.qml"
git -C "$bulk_bad" add Widget.qml
git -C "$bulk_bad" -c user.name=test -c user.email=test@example.invalid commit -qm bulk-diverged
commit_identity_remote_change "$bulk_bad_seed" bulk-update-bad
git -C "$bulk_bad" reset --hard -q HEAD~1
printf 'bulk-update\n' >>"$validation_repo/Widget.qml"
git -C "$validation_repo" add Widget.qml
git -C "$validation_repo" -c user.name=test -c user.email=test@example.invalid commit -qm bulk-update
git -C "$validation_repo" push -q "$remote_root/lifecycle.git" main
bulk_good_prior=$(git -C "$bulk_good" rev-parse HEAD)
bulk_bad_prior=$(git -C "$bulk_bad" rev-parse HEAD)
bulk_gap_artifact="$bulk_plugins/.plugin-artifacts/bulk-good.widget/update.gap"
bulk_gap_hook="$test_root/bulk-gap-hook"
cat >"$bulk_gap_hook" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $1 == update-after-fetch && ${2-} == *bulk-good.widget* ]]; then
  mkdir -p -- "${BULK_GAP_ARTIFACT%/*}"
  mkdir -- "$BULK_GAP_ARTIFACT"
fi
EOF
chmod +x -- "$bulk_gap_hook"
bulk_gap_status=0
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$bulk_plugins" \
  DESKTOP_SHELL_PLUGIN_TEST_HOOK="$bulk_gap_hook" BULK_GAP_ARTIFACT="$bulk_gap_artifact" \
  "$manager" update --yes >/dev/null 2>&1; then
  bulk_gap_status=0
else
  bulk_gap_status=$?
fi
[[ $bulk_gap_status != 0 ]] || fail "bulk pre-build artifact was accepted"
[[ $(git -C "$bulk_good" rev-parse HEAD) == "$bulk_good_prior" ]] || fail "bulk gap changed blocked plugin"
[[ $(git -C "$bulk_bad" rev-parse HEAD) != "$bulk_bad_prior" ]] || fail "bulk gap did not continue independent plugin"
[[ -d "$bulk_gap_artifact" ]] || fail "bulk gap artifact evidence was deleted"
rm -rf -- "$bulk_gap_artifact"
bulk_bad_prior=$(git -C "$bulk_bad" rev-parse HEAD)
bulk_orphan_artifact="$bulk_plugins/.plugin-artifacts/unassigned/rollback.ABC123"
mkdir -p -- "${bulk_orphan_artifact%/*}"
mkdir -- "$bulk_orphan_artifact"
visible_non_git="$bulk_plugins/visible.widget"
mkdir -p -- "$visible_non_git"
printf 'visible\n' >"$visible_non_git/marker"
bulk_rescan_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
bulk_status=0
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$bulk_plugins" "$manager" update --yes >/dev/null 2>&1; then
  bulk_status=0
else
  bulk_status=$?
fi
[[ $bulk_status != 0 ]] || fail "partial bulk update unexpectedly succeeded"
[[ $(git -C "$bulk_good" rev-parse HEAD) == "$bulk_good_prior" ]] || fail "global artifact block changed good plugin"
[[ $(git -C "$bulk_bad" rev-parse HEAD) == "$bulk_bad_prior" ]] || fail "partial bulk update changed failed plugin"
[[ -d "$bulk_orphan_artifact" ]] || fail "bulk artifact-only evidence was deleted"
bulk_rescan_after=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
[[ $bulk_rescan_after == "$bulk_rescan_before" ]] || fail "global artifact block requested a rescan"
[[ -f "$visible_non_git/marker" ]] || fail "visible non-Git directory was touched by bulk update"

sentinel_plugins="$test_root/sentinel-plugins"
mkdir -p -- "$sentinel_plugins"
sentinel_target_remote="$test_root/sentinel-target.git"
sentinel_target_seed="$test_root/sentinel-target-seed"
sentinel_target="$sentinel_plugins/sentinel-target.widget"
sentinel_peer_remote="$test_root/sentinel-peer.git"
sentinel_peer_seed="$test_root/sentinel-peer-seed"
sentinel_peer="$sentinel_plugins/sentinel-peer.widget"
make_identity_plugin "$sentinel_target_remote" "$sentinel_target_seed" "$sentinel_target" sentinel-target.widget
make_identity_plugin "$sentinel_peer_remote" "$sentinel_peer_seed" "$sentinel_peer" sentinel-peer.widget
commit_identity_remote_change "$sentinel_target_seed" sentinel-target-update
commit_identity_remote_change "$sentinel_peer_seed" sentinel-peer-update
sentinel_target_prior=$(git -C "$sentinel_target" rev-parse HEAD)
sentinel_peer_prior=$(git -C "$sentinel_peer" rev-parse HEAD)
sentinel_artifact="$sentinel_plugins/.plugin-artifacts/_unassigned/rollback.sentinel"
mkdir -p -- "${sentinel_artifact%/*}"
mkdir -- "$sentinel_artifact"
sentinel_rescan_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
sentinel_status=0
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$sentinel_plugins" "$manager" update --yes >/dev/null 2>&1; then
  sentinel_status=0
else
  sentinel_status=$?
fi
[[ $sentinel_status != 0 ]] || fail "reserved _unassigned bulk artifact was accepted"
[[ $(git -C "$sentinel_target" rev-parse HEAD) == "$sentinel_target_prior" ]] || fail "_unassigned artifact changed target"
[[ $(git -C "$sentinel_peer" rev-parse HEAD) == "$sentinel_peer_prior" ]] || fail "_unassigned artifact changed peer"
[[ $(grep -c $'rescanPlugins\t\t' "$log_file" || true) == "$sentinel_rescan_before" ]] || fail "_unassigned artifact requested rescan"
[[ -d "$sentinel_artifact" ]] || fail "_unassigned artifact evidence was deleted"

malformed_plugins="$test_root/malformed-plugins"
mkdir -p -- "$malformed_plugins"
malformed_target_remote="$test_root/malformed-target.git"
malformed_target_seed="$test_root/malformed-target-seed"
malformed_target="$malformed_plugins/malformed-target.widget"
malformed_peer_remote="$test_root/malformed-peer.git"
malformed_peer_seed="$test_root/malformed-peer-seed"
malformed_peer="$malformed_plugins/malformed-peer.widget"
make_identity_plugin "$malformed_target_remote" "$malformed_target_seed" "$malformed_target" malformed-target.widget
make_identity_plugin "$malformed_peer_remote" "$malformed_peer_seed" "$malformed_peer" malformed-peer.widget
commit_identity_remote_change "$malformed_target_seed" malformed-target-update
commit_identity_remote_change "$malformed_peer_seed" malformed-peer-update
malformed_target_prior=$(git -C "$malformed_target" rev-parse HEAD)
malformed_peer_prior=$(git -C "$malformed_peer" rev-parse HEAD)
malformed_artifact="$malformed_plugins/.plugin-artifacts/malformed-target.widget/nested/record"
mkdir -p -- "${malformed_artifact%/*}"
: >"$malformed_artifact"
malformed_rescan_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
malformed_status=0
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$malformed_plugins" "$manager" update --yes >/dev/null 2>&1; then
  malformed_status=0
else
  malformed_status=$?
fi
[[ $malformed_status != 0 ]] || fail "malformed depth-two artifact was accepted"
[[ $(git -C "$malformed_target" rev-parse HEAD) == "$malformed_target_prior" ]] || fail "malformed artifact changed target"
[[ $(git -C "$malformed_peer" rev-parse HEAD) == "$malformed_peer_prior" ]] || fail "malformed artifact changed peer"
[[ $(grep -c $'rescanPlugins\t\t' "$log_file" || true) == "$malformed_rescan_before" ]] || fail "malformed artifact requested rescan"
[[ -f "$malformed_artifact" ]] || fail "malformed artifact evidence was deleted"

sort_plugins="$test_root/sort-plugins"
mkdir -p -- "$sort_plugins"
sort_target_remote="$test_root/sort-target.git"
sort_target_seed="$test_root/sort-target-seed"
sort_target="$sort_plugins/sort-target.widget"
sort_peer_remote="$test_root/sort-peer.git"
sort_peer_seed="$test_root/sort-peer-seed"
sort_peer="$sort_plugins/sort-peer.widget"
make_identity_plugin "$sort_target_remote" "$sort_target_seed" "$sort_target" sort-target.widget
make_identity_plugin "$sort_peer_remote" "$sort_peer_seed" "$sort_peer" sort-peer.widget
commit_identity_remote_change "$sort_target_seed" sort-target-update
commit_identity_remote_change "$sort_peer_seed" sort-peer-update
sort_target_prior=$(git -C "$sort_target" rev-parse HEAD)
sort_peer_prior=$(git -C "$sort_peer" rev-parse HEAD)
sort_artifact="$sort_plugins/.plugin-artifacts/sort-target.widget/update.sort"
mkdir -p -- "${sort_artifact%/*}"
mkdir -- "$sort_artifact"
sort_fail_bin="$test_root/sort-fail-bin"
mkdir -p -- "$sort_fail_bin"
cat >"$sort_fail_bin/sort" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1-} != -z ]]; then
  printf '%s\n' partial-sort-result
  exit 1
fi
exec /usr/bin/sort "$@"
EOF
chmod +x -- "$sort_fail_bin/sort"
sort_status=0
sort_rescan_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$sort_plugins" PATH="$sort_fail_bin:$PATH" \
  "$manager" update --yes >/dev/null 2>&1; then
  sort_status=0
else
  sort_status=$?
fi
[[ $sort_status != 0 ]] || fail "per-ID diagnostic sorting failure was accepted"
[[ $(git -C "$sort_target" rev-parse HEAD) == "$sort_target_prior" ]] || fail "sorting failure changed target"
[[ $(git -C "$sort_peer" rev-parse HEAD) == "$sort_peer_prior" ]] || fail "sorting failure allowed a peer update"
[[ $(grep -c $'rescanPlugins\t\t' "$log_file" || true) == "$sort_rescan_before" ]] || fail "sorting failure requested rescan"
[[ -d "$sort_artifact" ]] || fail "sorting failure deleted artifact evidence"
rm -rf -- "$sort_artifact"

identity_plugins="$test_root/identity-plugins"
mkdir -p -- "$identity_plugins"
identity_a_remote="$test_root/identity-a.git"
identity_a_seed="$test_root/identity-a-seed"
identity_a="$identity_plugins/acme.a"
identity_b_remote="$test_root/identity-b.git"
identity_b_seed="$test_root/identity-b-seed"
identity_b="$identity_plugins/acme.b"
make_identity_plugin "$identity_a_remote" "$identity_a_seed" "$identity_a" acme.a
make_identity_plugin "$identity_b_remote" "$identity_b_seed" "$identity_b" acme.b
identity_a_prior=$(git -C "$identity_a" rev-parse HEAD)
identity_b_prior=$(git -C "$identity_b" rev-parse HEAD)
update_identity_remote "$identity_a_seed" acme.renamed
identity_rescan_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
identity_status=0
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$identity_plugins" "$manager" update --yes >/dev/null 2>&1; then
  identity_status=0
else
  identity_status=$?
fi
[[ $identity_status != 0 ]] || fail "bulk manifest identity change was accepted"
[[ $(git -C "$identity_a" rev-parse HEAD) == "$identity_a_prior" ]] || fail "identity-changing update changed A"
[[ $(git -C "$identity_b" rev-parse HEAD) == "$identity_b_prior" ]] || fail "identity-changing update touched B"
identity_rescan_after=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
[[ $identity_rescan_after == "$identity_rescan_before" ]] || fail "identity-changing bulk update requested rescan"
jq -n '[{id:"acme.a"},{id:"acme.b"}]' >"$IPC_LIST"
identity_list=$(env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$identity_plugins" "$manager" list)
[[ $identity_list == *$'acme.a\t'* ]] || fail "identity-changing update lost A's original ID"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$identity_plugins" "$manager" update acme.a --yes >/dev/null 2>&1; then
  fail "explicit update accepted changed manifest ID"
fi
env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$identity_plugins" "$manager" remove acme.a --yes >/dev/null ||
  fail "remove did not resolve A by its original ID"
[[ ! -e "$identity_a" ]] || fail "remove did not remove A by its original ID"

duplicate_plugins="$test_root/duplicate-plugins"
mkdir -p -- "$duplicate_plugins"
duplicate_a_remote="$test_root/duplicate-a.git"
duplicate_a_seed="$test_root/duplicate-a-seed"
duplicate_a="$duplicate_plugins/acme.a"
duplicate_b_remote="$test_root/duplicate-b.git"
duplicate_b_seed="$test_root/duplicate-b-seed"
duplicate_b="$duplicate_plugins/acme.b"
make_identity_plugin "$duplicate_a_remote" "$duplicate_a_seed" "$duplicate_a" acme.a
make_identity_plugin "$duplicate_b_remote" "$duplicate_b_seed" "$duplicate_b" acme.b
duplicate_a_prior=$(git -C "$duplicate_a" rev-parse HEAD)
duplicate_b_prior=$(git -C "$duplicate_b" rev-parse HEAD)
update_identity_remote "$duplicate_a_seed" acme.b
duplicate_rescan_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
duplicate_status=0
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$duplicate_plugins" "$manager" update --yes >/dev/null 2>&1; then
  duplicate_status=0
else
  duplicate_status=$?
fi
[[ $duplicate_status != 0 ]] || fail "bulk duplicate manifest ID was accepted"
[[ $(git -C "$duplicate_a" rev-parse HEAD) == "$duplicate_a_prior" ]] || fail "duplicate update changed A"
[[ $(git -C "$duplicate_b" rev-parse HEAD) == "$duplicate_b_prior" ]] || fail "duplicate update touched B"
duplicate_rescan_after=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
[[ $duplicate_rescan_after == "$duplicate_rescan_before" ]] || fail "duplicate bulk update requested rescan"
jq -n '[{id:"acme.a"},{id:"acme.b"}]' >"$IPC_LIST"
duplicate_list=$(env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$duplicate_plugins" "$manager" list)
[[ $duplicate_list == *$'acme.a\t'* ]] || fail "duplicate update lost A's original ID"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$duplicate_plugins" "$manager" update acme.a --yes >/dev/null 2>&1; then
  fail "explicit duplicate update was accepted"
fi
env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$duplicate_plugins" "$manager" remove acme.a --yes >/dev/null ||
  fail "remove did not resolve duplicate A by its original ID"
[[ ! -e "$duplicate_a" ]] || fail "remove did not remove duplicate A by its original ID"

rescan_swap_backup="$test_root/rescan-swap-backup"
rescan_swap_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
rescan_hook="$test_root/rescan-hook"
cat >"$rescan_hook" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$1" >>"$RACE_RESCAN_LOG"
if [[ $1 == before-rescan ]]; then
  mv -- "$RACE_TARGET" "$RACE_TARGET_BACKUP"
  mkdir -- "$RACE_TARGET"
  printf 'replacement\n' >"$RACE_TARGET/marker"
fi
exit 0
EOF
chmod +x -- "$rescan_hook"
if ! env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$rescan_hook" \
  RACE_TARGET="$plugins_dir/lifecycle.widget" RACE_TARGET_BACKUP="$rescan_swap_backup" RACE_RESCAN_LOG="$test_root/rescan-hook.log" \
  "$manager" update lifecycle.widget --yes >"$test_root/rescan-manager.out" 2>&1; then
  fail "update failed after publication: $(<"$test_root/rescan-hook.log")"
fi
[[ -f "$plugins_dir/lifecycle.widget/marker" ]] || fail "rescan replacement was removed"
[[ $(git -C "$rescan_swap_backup" rev-parse HEAD) != "$rescan_swap_prior" ]] || fail "published checkout was rolled back"
rm -rf -- "$plugins_dir/lifecycle.widget"
mv -- "$rescan_swap_backup" "$plugins_dir/lifecycle.widget"

printf 'ipc-rescan-update\n' >>"$validation_repo/Widget.qml"
git -C "$validation_repo" add Widget.qml
git -C "$validation_repo" -c user.name=test -c user.email=test@example.invalid commit -qm ipc-rescan-update
git -C "$validation_repo" push -q "$remote_root/lifecycle.git" main
ipc_rescan_backup="$test_root/ipc-rescan-backup"
ipc_rescan_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
if ! env "${manager_env[@]}" IPC_RESCAN_REPLACE_TARGET=1 IPC_TARGET="$plugins_dir/lifecycle.widget" \
  IPC_REPLACEMENT_BACKUP="$ipc_rescan_backup" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "update failed after IPC rescan replacement"
fi
[[ -f "$plugins_dir/lifecycle.widget/marker" && -d "$ipc_rescan_backup" ]] ||
  fail "rescan IPC replacement fixture was lost"
[[ $(git -C "$ipc_rescan_backup" rev-parse HEAD) != "$ipc_rescan_prior" ]] ||
  fail "IPC rescan replacement rolled back published update"
rm -rf -- "$plugins_dir/lifecycle.widget"
mv -- "$ipc_rescan_backup" "$plugins_dir/lifecycle.widget"

printf 'dirty\n' >>"$plugins_dir/lifecycle.widget/Widget.qml"
if env "${manager_env[@]}" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "local modifications were accepted"
fi
git -C "$plugins_dir/lifecycle.widget" reset --hard -q "$validation_prior"
git -C "$plugins_dir/lifecycle.widget" checkout -q --detach "$validation_prior"
printf 'diverged\n' >"$plugins_dir/lifecycle.widget/Widget.qml"
git -C "$plugins_dir/lifecycle.widget" add Widget.qml
git -C "$plugins_dir/lifecycle.widget" -c user.name=test -c user.email=test@example.invalid commit -qm divergent
if env "${manager_env[@]}" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "divergent update was accepted"
fi

if env "${manager_env[@]}" "$manager" update lifecycle.widget </dev/null >/dev/null 2>&1; then
  fail "non-interactive update without --yes succeeded"
fi
if env "${manager_env[@]}" "$manager" remove lifecycle.widget </dev/null >/dev/null 2>&1; then
  fail "non-interactive remove without --yes succeeded"
fi

enclosing_root="$test_root/enclosing"
mkdir -p -- "$enclosing_root/$plugins_dir"
git -C "$enclosing_root" init -q
git -C "$enclosing_root" config user.name test
git -C "$enclosing_root" config user.email test@example.invalid
mkdir -p -- "$enclosing_root/$plugins_dir/enclosed.widget"
printf '{}\n' >"$enclosing_root/$plugins_dir/enclosed.widget/manifest.json"
git -C "$enclosing_root" add .
git -C "$enclosing_root" commit -qm enclosing
if DESKTOP_SHELL_PLUGINS_DIR="$enclosing_root/$plugins_dir" env "${manager_env[@]}" "$manager" update enclosed.widget --yes >/dev/null 2>&1; then
  fail "enclosing Git worktree was treated as a plugin checkout"
fi

replace_dir="$plugins_dir/replace.widget"
mkdir -p -- "$replace_dir"
printf '{}\n' >"$replace_dir/manifest.json"
replace_backup="$test_root/replace-backup"
if IPC_REPLACE_ON_DISABLE=1 IPC_TARGET="$replace_dir" IPC_REPLACEMENT_BACKUP="$replace_backup" \
  env "${manager_env[@]}" "$manager" remove replace.widget --yes >/dev/null 2>&1; then
  fail "target replacement during disable was accepted"
fi
[[ -f "$replace_dir/marker" && -f "$replace_backup/manifest.json" ]] || fail "target replacement safety state was lost"

root_replace_dir="$plugins_dir/root-replace.widget"
mkdir -p -- "$root_replace_dir"
printf '{}\n' >"$root_replace_dir/manifest.json"
replacement_root="$test_root/replacement-root"
mkdir -- "$replacement_root"
root_backup="$test_root/root-backup"
if IPC_REPLACE_ROOT_ON_DISABLE=1 IPC_ROOT="$plugins_dir" IPC_ROOT_BACKUP="$root_backup" IPC_REPLACEMENT_ROOT="$replacement_root" \
  env "${manager_env[@]}" "$manager" remove root-replace.widget --yes >/dev/null 2>&1; then
  fail "root replacement during disable was accepted"
fi
[[ -f "$root_backup/root-replace.widget/manifest.json" ]] || fail "root replacement moved original source"
[[ -L $plugins_dir && -d $plugins_dir ]] || fail "replacement root was not preserved"
rm -f -- "$plugins_dir"
mv -- "$root_backup" "$plugins_dir"

remove_dir="$plugins_dir/remove.widget"
git clone -q -- "$remote_root/lifecycle.git" "$remove_dir"
env "${manager_env[@]}" "$manager" remove remove.widget --yes >/dev/null || fail "Git removal failed"
[[ ! -e $remove_dir ]] || fail "Git removal left source directory"
grep -Fq $'setPluginEnabled\tremove.widget\tfalse' "$log_file" || fail "Git removal did not disable first"

lock_probe_dir="$plugins_dir/lock-probe.widget"
git clone -q -- "$remote_root/lifecycle.git" "$lock_probe_dir"
lock_probe_hook="$test_root/lock-probe-hook"
cat >"$lock_probe_hook" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $1 == quarantine-after-delete ]]; then
  (
    "$LOCK_PROBE_MANAGER" disable lock-probe.widget >"$LOCK_PROBE_OUTPUT" 2>&1
    : >"$LOCK_PROBE_MARKER"
  ) &
  probe_pid=$!
  for ((attempt = 0; attempt < 20; attempt++)); do
    [[ -e $LOCK_PROBE_MARKER ]] && break
    sleep 0.05
  done
  if [[ ! -e $LOCK_PROBE_MARKER ]]; then
    kill -TERM "$probe_pid" 2>/dev/null || true
    sleep 0.1
    kill -KILL "$probe_pid" 2>/dev/null || true
    wait "$probe_pid" 2>/dev/null || true
    printf 'cooperating manager did not acquire lock before timeout\n' >&2
    exit 1
  fi
  wait "$probe_pid"
fi
EOF
chmod +x -- "$lock_probe_hook"
lock_probe_marker="$test_root/lock-probe-marker"
env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$lock_probe_hook" \
  LOCK_PROBE_MANAGER="$manager" LOCK_PROBE_MARKER="$lock_probe_marker" LOCK_PROBE_OUTPUT="$test_root/lock-probe.out" \
  "$manager" remove lock-probe.widget --yes >/dev/null || fail "remove held manager lock during hidden cleanup"
[[ -e "$lock_probe_marker" ]] || { printf 'lock probe output:\n%s\n' "$(<"$test_root/lock-probe.out")" >&2; fail "cooperating manager did not proceed during hidden cleanup"; }

ipc_repopulate_dir="$plugins_dir/ipc-repopulate.widget"
mkdir -p -- "$ipc_repopulate_dir"
printf '{}\n' >"$ipc_repopulate_dir/manifest.json"
if env "${manager_env[@]}" IPC_RESCAN_REPOPULATE=1 IPC_TARGET="$ipc_repopulate_dir" \
  "$manager" remove ipc-repopulate.widget --yes >/dev/null 2>&1; then
  fail "removed ID repopulation during rescan IPC was accepted"
fi
[[ -f "$ipc_repopulate_dir/marker" ]] || fail "rescan IPC repopulation was not detected"

repopulate_dir="$plugins_dir/repopulate.widget"
mkdir -p -- "$repopulate_dir"
printf '{}\n' >"$repopulate_dir/manifest.json"
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$race_hook" RACE_RESCAN_MODE=remove \
  RACE_TARGET="$repopulate_dir" "$manager" remove repopulate.widget --yes >/dev/null 2>&1; then
  fail "removed ID repopulation before rescan was accepted"
fi
[[ -f "$repopulate_dir/marker" ]] || fail "repopulated removed ID was not preserved"

non_git_dir="$plugins_dir/non-git.widget"
mkdir -p -- "$non_git_dir"
printf '{}\n' >"$non_git_dir/manifest.json"
printf 'keep\n' >"$non_git_dir/data"
mount_fail_bin="$test_root/findmnt-nested-bin"
mkdir -p -- "$mount_fail_bin"
cat >"$mount_fail_bin/findmnt" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
target=${@: -1}
printf '%s/nested-mount\n' "$target"
EOF
chmod +x -- "$mount_fail_bin/findmnt"
mount_remove_dir="$plugins_dir/mount-remove.widget"
git clone -q -- "$remote_root/lifecycle.git" "$mount_remove_dir"
if env "${manager_env[@]}" PATH="$mount_fail_bin:$PATH" "$manager" remove mount-remove.widget --yes >"$test_root/mount_remove.out" 2>"$test_root/mount_remove.err"; then
  printf '%s\n%s\n' "$(<"$test_root/mount_remove.out")" "$(<"$test_root/mount_remove.err")" >&2
  fail "nested mount cleanup was accepted"
fi
mount_fail_backups=("$plugins_dir/.plugin-artifacts/mount-remove.widget/removed."*)
[[ ${#mount_fail_backups[@]} == 1 && -f "${mount_fail_backups[0]}/manifest.json" ]] || fail "nested mount refusal did not retain backup"
mv -T -- "${mount_fail_backups[0]}" "$mount_remove_dir"
env "${manager_env[@]}" "$manager" remove mount-remove.widget --yes >/dev/null || fail "nested mount recovery cleanup failed"

mount_equal_bin="$test_root/findmnt-equal-bin"
mkdir -p -- "$mount_equal_bin"
cat >"$mount_equal_bin/findmnt" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "${@: -1}"
EOF
chmod +x -- "$mount_equal_bin/findmnt"
equal_mount_dir="$plugins_dir/equal-mount.widget"
git clone -q -- "$remote_root/lifecycle.git" "$equal_mount_dir"
if env "${manager_env[@]}" PATH="$mount_equal_bin:$PATH" "$manager" remove equal-mount.widget --yes >/dev/null 2>&1; then
  fail "equal mount cleanup was accepted"
fi
equal_mount_backups=("$plugins_dir/.plugin-artifacts/equal-mount.widget/removed."*)
[[ ${#equal_mount_backups[@]} == 1 && -f "${equal_mount_backups[0]}/manifest.json" ]] || fail "equal mount refusal did not retain backup"
mv -T -- "${equal_mount_backups[0]}" "$equal_mount_dir"
env "${manager_env[@]}" "$manager" remove equal-mount.widget --yes >/dev/null || fail "equal mount recovery cleanup failed"

mount_root_bin="$test_root/findmnt-root-bin"
mkdir -p -- "$mount_root_bin"
cat >"$mount_root_bin/findmnt" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '/\n'
EOF
chmod +x -- "$mount_root_bin/findmnt"
root_mount_dir="$plugins_dir/root-mount.widget"
git clone -q -- "$remote_root/lifecycle.git" "$root_mount_dir"
env "${manager_env[@]}" PATH="$mount_root_bin:$PATH" "$manager" remove root-mount.widget --yes >/dev/null || fail "containing root mount was rejected"
[[ ! -e "$root_mount_dir" ]] || fail "root mount cleanup left source"
env "${manager_env[@]}" "$manager" remove non-git.widget --yes >/dev/null || fail "non-Git removal failed"
backup_count=0
for backup in "$plugins_dir/.plugin-artifacts/non-git.widget"/removed.*; do
  [[ -d $backup ]] || continue
  backup_count=$((backup_count + 1))
  [[ -f $backup/data ]] || fail "non-Git backup lost source data"
done
[[ $backup_count == 1 && ! -e $non_git_dir ]] || {
  printf 'non-git artifacts:\n'
  printf '%s\n' "$plugins_dir/.plugin-artifacts/non-git.widget"/* >&2
  fail "non-Git removal backup was unsafe"
}

disable_dir="$plugins_dir/disable-failure.widget"
mkdir -p -- "$disable_dir"
printf '{}\n' >"$disable_dir/manifest.json"
if IPC_DISABLE_RESULT=failed env "${manager_env[@]}" "$manager" remove disable-failure.widget --yes >/dev/null 2>&1; then
  fail "disable failure was accepted"
fi
[[ -d $disable_dir ]] || fail "disable failure touched source directory"

identity_remote="$remote_root/identity.widget.git"
identity_seed="$test_root/identity-seed"
cp -a -- "$validation_repo" "$identity_seed"
jq '.id = "identity.widget"' "$identity_seed/manifest.json" >"$identity_seed/manifest.tmp"
mv -- "$identity_seed/manifest.tmp" "$identity_seed/manifest.json"
git -C "$identity_seed" add manifest.json
git -C "$identity_seed" -c user.name=test -c user.email=test@example.invalid commit -qm identity
git clone -q --bare -- "$identity_seed" "$identity_remote"
git -C "$identity_remote" symbolic-ref HEAD refs/heads/main
identity_target="$plugins_dir/identity.widget"
git clone -q -- "$identity_remote" "$identity_target"

renamed_seed="$test_root/renamed-identity"
cp -a -- "$identity_seed" "$renamed_seed"
jq '.id = "renamed.widget"' "$renamed_seed/manifest.json" >"$renamed_seed/manifest.tmp"
mv -- "$renamed_seed/manifest.tmp" "$renamed_seed/manifest.json"
git -C "$renamed_seed" add manifest.json
git -C "$renamed_seed" -c user.name=test -c user.email=test@example.invalid commit -qm renamed
git -C "$renamed_seed" push -q --force "$identity_remote" main
identity_prior=$(git -C "$identity_target" rev-parse HEAD)
identity_rescans=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
if env "${manager_env[@]}" "$manager" update identity.widget --yes >/dev/null 2>&1; then
  fail "renamed manifest ID update was accepted"
fi
[[ $(git -C "$identity_target" rev-parse HEAD) == "$identity_prior" ]] || fail "renamed ID update was not rolled back"
[[ $(grep -c $'rescanPlugins\t\t' "$log_file" || true) == "$identity_rescans" ]] || fail "renamed ID update requested rescan"

duplicate_seed="$test_root/duplicate-identity"
cp -a -- "$identity_seed" "$duplicate_seed"
printf 'duplicate-check\n' >>"$duplicate_seed/Widget.qml"
git -C "$duplicate_seed" add Widget.qml
git -C "$duplicate_seed" -c user.name=test -c user.email=test@example.invalid commit -qm duplicate
git -C "$duplicate_seed" push -q --force "$identity_remote" main
cp -a -- "$identity_target" "$plugins_dir/identity-duplicate-root"
identity_prior=$(git -C "$identity_target" rev-parse HEAD)
identity_rescans=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
if env "${manager_env[@]}" "$manager" update identity.widget --yes >/dev/null 2>&1; then
  fail "duplicate manifest ID update was accepted"
fi
[[ $(git -C "$identity_target" rev-parse HEAD) == "$identity_prior" ]] || fail "duplicate ID update was not rolled back"
[[ $(grep -c $'rescanPlugins\t\t' "$log_file" || true) == "$identity_rescans" ]] || fail "duplicate ID update requested rescan"

printf 'PASS: desktop-shell plugin manager\n'
