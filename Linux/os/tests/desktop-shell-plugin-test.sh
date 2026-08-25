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

jq -n '[{id:"acme.widget",name:"Acme Widget",kinds:["bar-widget"],enabled:false,clonedFrom:"local"}]' >"$IPC_LIST"
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
[[ $(jq -r '.[0].id' <<<"$json_output") == acme.widget ]] || fail "list --json changed plugin data"
plain_output=$(env "${manager_env[@]}" "$manager" list)
[[ $plain_output == $'acme.widget\tdisabled\tlocal\tbar-widget\tAcme Widget' ]] || fail "plain list format is incorrect"

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
stages=("$plugins_dir"/.add.*)
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

replacement_repo="$test_root/replacement"
make_repo "$replacement_repo" replacement.widget
replacement_backup="$test_root/replacement-backup"
if IPC_RESCAN_RESULT=failed IPC_REPLACE_TARGET=1 IPC_TARGET="$plugins_dir/replacement.widget" \
  IPC_REPLACEMENT_BACKUP="$replacement_backup" env "${manager_env[@]}" "$manager" add "$replacement_repo" --yes >/dev/null 2>&1; then
  fail "replacement cleanup failure was accepted"
fi
[[ -f "$plugins_dir/replacement.widget/marker" ]] || fail "replacement was deleted during rollback"
[[ -f "$replacement_backup/manifest.json" ]] || fail "original target was not preserved for replacement test"
rm -rf -- "$plugins_dir/replacement.widget" "$replacement_backup"

signal_repo="$test_root/signal"
make_repo "$signal_repo" signal.widget
signal_status=0
IPC_SIGNAL_AFTER_RESCAN=1 env "${manager_env[@]}" "$manager" add "$signal_repo" --yes >/dev/null 2>&1 || signal_status=$?
[[ $signal_status == 143 ]] || fail "TERM after move returned status $signal_status"
[[ ! -e "$plugins_dir/signal.widget" ]] || fail "TERM after move left target"

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

git -C "$remote_seed" checkout -q -b main
printf 'updated\n' >"$remote_seed/Widget.qml"
git -C "$remote_seed" add Widget.qml
git -C "$remote_seed" -c user.name=test -c user.email=test@example.invalid commit -qm update
git -C "$remote_seed" push -q "$remote_root/lifecycle.git" main
git -C "$remote_root/lifecycle.git" symbolic-ref HEAD refs/heads/main
prior_commit=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
env "${manager_env[@]}" "$manager" update lifecycle.widget --yes >/dev/null || fail "fast-forward update failed"
updated_commit=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
[[ $updated_commit != "$prior_commit" ]] || fail "fast-forward update did not advance"
grep -Fq $'rescanPlugins\t\t' "$log_file" || fail "successful update did not request rescan"
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
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_VALIDATE=/bin/false "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "validation-failing update was accepted"
fi
[[ $(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD) == "$validation_prior" ]] || fail "validation rollback changed commit"
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
env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_VALIDATE="$signal_validator" "$manager" update lifecycle.widget --yes >/dev/null 2>&1 || signal_status=$?
[[ $signal_status == 143 ]] || fail "signal after merge returned status $signal_status"
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
cmp -s "$test_root/rollback-metadata-prior-widget" "$plugins_dir/lifecycle.widget/Widget.qml" ||
  fail "captured transaction was not rolled back after metadata replacement"
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
  printf 'validator race command output:\n%s\n' "$(<"$validator_swap_error")" >&2
  fail "public target replacement during validation was accepted"
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

bulk_plugins="$test_root/bulk-plugins"
mkdir -p -- "$bulk_plugins"
bulk_good="$bulk_plugins/bulk-good.widget"
bulk_bad="$bulk_plugins/bulk-bad.widget"
git clone -q -- "$remote_root/lifecycle.git" "$bulk_good"
git clone -q -- "$remote_root/lifecycle.git" "$bulk_bad"
printf 'bulk-diverged\n' >>"$bulk_bad/Widget.qml"
git -C "$bulk_bad" add Widget.qml
git -C "$bulk_bad" -c user.name=test -c user.email=test@example.invalid commit -qm bulk-diverged
printf 'bulk-update\n' >>"$validation_repo/Widget.qml"
git -C "$validation_repo" add Widget.qml
git -C "$validation_repo" -c user.name=test -c user.email=test@example.invalid commit -qm bulk-update
git -C "$validation_repo" push -q "$remote_root/lifecycle.git" main
bulk_good_prior=$(git -C "$bulk_good" rev-parse HEAD)
bulk_bad_prior=$(git -C "$bulk_bad" rev-parse HEAD)
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
[[ $(git -C "$bulk_good" rev-parse HEAD) != "$bulk_good_prior" ]] || fail "partial bulk update lost successful change"
[[ $(git -C "$bulk_bad" rev-parse HEAD) == "$bulk_bad_prior" ]] || fail "partial bulk update changed failed plugin"
bulk_rescan_after=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
[[ $((bulk_rescan_after - bulk_rescan_before)) == 1 ]] || fail "partial bulk update did not request exactly one rescan"
[[ -f "$visible_non_git/marker" ]] || fail "visible non-Git directory was touched by bulk update"

abort_plugins="$test_root/abort-plugins"
mkdir -p -- "$abort_plugins"
abort_first="$abort_plugins/abort-a.widget"
abort_second="$abort_plugins/abort-b.widget"
git clone -q -- "$remote_root/lifecycle.git" "$abort_first"
git clone -q -- "$remote_root/lifecycle.git" "$abort_second"
printf 'abort-rollback\n' >>"$validation_repo/Widget.qml"
git -C "$validation_repo" add Widget.qml
git -C "$validation_repo" -c user.name=test -c user.email=test@example.invalid commit -qm abort-rollback
git -C "$validation_repo" push -q "$remote_root/lifecycle.git" main
abort_validator="$test_root/abort-validator"
cat >"$abort_validator" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
count=0
[[ -f $ABORT_COUNT ]] && count=$(<"$ABORT_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$ABORT_COUNT"
exit 1
EOF
chmod +x -- "$abort_validator"
abort_bin="$test_root/abort-bin"
mkdir -p -- "$abort_bin"
abort_git="$abort_bin/git"
cat >"$abort_git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$ABORT_GIT_LOG"
if [[ " $* " == *' reset --hard '* ]]; then
  exit 1
fi
exec /usr/bin/git "$@"
EOF
chmod +x -- "$abort_git"
abort_hook="$test_root/abort-hook"
cat >"$abort_hook" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$1" >>"$ABORT_HOOK_LOG"
EOF
chmod +x -- "$abort_hook"
abort_status=0
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$abort_plugins" \
  DESKTOP_SHELL_PLUGIN_VALIDATE="$abort_validator" ABORT_COUNT="$test_root/abort-count" \
  ABORT_GIT_LOG="$test_root/abort-git.log" \
  DESKTOP_SHELL_PLUGIN_TEST_HOOK="$abort_hook" ABORT_HOOK_LOG="$test_root/abort-hook.log" \
  PATH="$abort_bin:$PATH" "$manager" update --yes >/dev/null 2>&1; then
  abort_status=0
else
  abort_status=$?
fi
[[ $abort_status != 0 ]] || fail "failed rollback bulk update unexpectedly succeeded"
[[ $(<"$test_root/abort-count") == 1 ]] || fail "bulk update continued after failed rollback: $(<"$test_root/abort-count")"
[[ $(grep -c 'update-after-status' "$test_root/abort-hook.log") == 1 ]] ||
  fail "bulk update started another plugin after failed rollback: $(<"$test_root/abort-hook.log")"

retained_abort_plugins="$test_root/retained-abort-plugins"
mkdir -p -- "$retained_abort_plugins"
retained_abort_a="$retained_abort_plugins/retained-a.widget"
retained_abort_b="$retained_abort_plugins/retained-b.widget"
git clone -q -- "$remote_root/lifecycle.git" "$retained_abort_a"
git clone -q -- "$remote_root/lifecycle.git" "$retained_abort_b"
printf 'retained-abort-update\n' >>"$validation_repo/Widget.qml"
git -C "$validation_repo" add Widget.qml
git -C "$validation_repo" -c user.name=test -c user.email=test@example.invalid commit -qm retained-abort-update
git -C "$validation_repo" push -q "$remote_root/lifecycle.git" main
retained_abort_validator="$test_root/retained-abort-validator"
cat >"$retained_abort_validator" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
count=0
[[ -f $RETAINED_ABORT_COUNT ]] && count=$(<"$RETAINED_ABORT_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$RETAINED_ABORT_COUNT"
if [[ $count == 1 ]]; then
  exec "$RETAINED_ABORT_REAL_VALIDATOR" "$1"
fi
exit 1
EOF
chmod +x -- "$retained_abort_validator"
retained_abort_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
retained_abort_status=0
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGINS_DIR="$retained_abort_plugins" \
  DESKTOP_SHELL_PLUGIN_VALIDATE="$retained_abort_validator" RETAINED_ABORT_COUNT="$test_root/retained-abort-count" \
  RETAINED_ABORT_REAL_VALIDATOR="$validator" ABORT_GIT_LOG="$test_root/retained-abort-git.log" \
  DESKTOP_SHELL_PLUGIN_TEST_HOOK="$abort_hook" ABORT_HOOK_LOG="$test_root/retained-abort-hook.log" \
  PATH="$abort_bin:$PATH" "$manager" update --yes >/dev/null 2>&1; then
  retained_abort_status=0
else
  retained_abort_status=$?
fi
[[ $retained_abort_status != 0 ]] || fail "retained success/current failure unexpectedly succeeded"
[[ $(<"$test_root/retained-abort-count") == 2 ]] || fail "bulk update began after current rollback failure"
[[ $(grep -c 'update-after-status' "$test_root/retained-abort-hook.log") == 2 ]] ||
  fail "retained rollback scenario started an unexpected plugin"
[[ $(grep -c ' reset --hard ' "$test_root/retained-abort-git.log") -ge 3 ]] ||
  fail "armed current transaction was not available for cleanup retry"
retained_abort_after=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
[[ $retained_abort_after == "$retained_abort_before" ]] || fail "rescan occurred before rollback was safe"

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
if env "${manager_env[@]}" DESKTOP_SHELL_PLUGIN_TEST_HOOK="$rescan_hook" \
  RACE_TARGET="$plugins_dir/lifecycle.widget" RACE_TARGET_BACKUP="$rescan_swap_backup" RACE_RESCAN_LOG="$test_root/rescan-hook.log" \
  "$manager" update lifecycle.widget --yes >"$test_root/rescan-manager.out" 2>&1; then
  fail "public target replacement before rescan was accepted: $(<"$test_root/rescan-hook.log")"
fi
[[ -f "$plugins_dir/lifecycle.widget/marker" ]] || fail "rescan replacement was removed"
[[ $(git -C "$rescan_swap_backup" rev-parse HEAD) == "$rescan_swap_prior" ]] ||
  fail "successful update was not rolled back after rescan replacement"
rm -rf -- "$plugins_dir/lifecycle.widget"
mv -- "$rescan_swap_backup" "$plugins_dir/lifecycle.widget"

ipc_rescan_backup="$test_root/ipc-rescan-backup"
ipc_rescan_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
if env "${manager_env[@]}" IPC_RESCAN_REPLACE_TARGET=1 IPC_TARGET="$plugins_dir/lifecycle.widget" \
  IPC_REPLACEMENT_BACKUP="$ipc_rescan_backup" "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  fail "public target replacement during rescan IPC was accepted"
fi
[[ -f "$plugins_dir/lifecycle.widget/marker" && -d "$ipc_rescan_backup" ]] ||
  fail "rescan IPC replacement fixture was lost"
[[ $(git -C "$ipc_rescan_backup" rev-parse HEAD) == "$ipc_rescan_prior" ]] ||
  fail "update was not rolled back after rescan IPC replacement"
rm -rf -- "$plugins_dir/lifecycle.widget"
mv -- "$ipc_rescan_backup" "$plugins_dir/lifecycle.widget"

rescan_rollback_bin="$test_root/rescan-rollback-bin"
mkdir -p -- "$rescan_rollback_bin"
rescan_rollback_git="$rescan_rollback_bin/git"
cat >"$rescan_rollback_git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ " $* " == *' reset --hard '* ]]; then
  count=0
  [[ -f $RESCAN_ROLLBACK_RESET_COUNT ]] && count=$(<"$RESCAN_ROLLBACK_RESET_COUNT")
  printf '%s\n' "$((count + 1))" >"$RESCAN_ROLLBACK_RESET_COUNT"
  if [[ ! -f $RESCAN_ROLLBACK_RESET_FAILED ]]; then
    : >"$RESCAN_ROLLBACK_RESET_FAILED"
    exit 1
  fi
fi
if [[ " $* " == *' rev-parse --absolute-git-dir '* && -f $RESCAN_ROLLBACK_REVALIDATE_FAILURE ]]; then
  rm -f -- "$RESCAN_ROLLBACK_REVALIDATE_FAILURE"
  exit 1
fi
exec /usr/bin/git "$@"
EOF
chmod +x -- "$rescan_rollback_git"
rescan_rollback_reset_failed="$test_root/rescan-rollback-reset-failed"
rescan_rollback_reset_count="$test_root/rescan-rollback-reset-count"
rescan_rollback_revalidate_failure="$test_root/rescan-rollback-revalidate-failure"
rescan_rollback_log_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
rescan_rollback_status=0
if env "${manager_env[@]}" PATH="$rescan_rollback_bin:$PATH" \
  IPC_RESCAN_MARKER="$rescan_rollback_revalidate_failure" \
  RESCAN_ROLLBACK_RESET_FAILED="$rescan_rollback_reset_failed" \
  RESCAN_ROLLBACK_RESET_COUNT="$rescan_rollback_reset_count" \
  RESCAN_ROLLBACK_REVALIDATE_FAILURE="$rescan_rollback_revalidate_failure" \
  "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  rescan_rollback_status=0
else
  rescan_rollback_status=$?
fi
[[ $rescan_rollback_status != 0 ]] || fail "failed retained rollback unexpectedly succeeded"
rescan_rollback_log_after=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
[[ $((rescan_rollback_log_after - rescan_rollback_log_before)) == 1 ]] ||
  fail "failed retained rollback requested a compensating rescan"
[[ -f "$rescan_rollback_reset_failed" ]] || fail "retained rollback failure was not exercised"
[[ $(<"$rescan_rollback_reset_count") -ge 2 ]] || fail "failed retained record was not retried during EXIT cleanup"
[[ ! -f "$rescan_rollback_revalidate_failure" ]] || fail "post-rescan identity mismatch was not exercised"

rescan_compensation_bin="$test_root/rescan-compensation-bin"
mkdir -p -- "$rescan_compensation_bin"
rescan_compensation_git="$rescan_compensation_bin/git"
cat >"$rescan_compensation_git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ " $* " == *' reset --hard '* ]]; then
  count=0
  [[ -f $RESCAN_COMPENSATION_RESET_COUNT ]] && count=$(<"$RESCAN_COMPENSATION_RESET_COUNT")
  printf '%s\n' "$((count + 1))" >"$RESCAN_COMPENSATION_RESET_COUNT"
fi
if [[ $* == *absolute-git-dir* && -f $RESCAN_COMPENSATION_REVALIDATE_FAILURE ]]; then
  count=0
  [[ -f $RESCAN_COMPENSATION_REVALIDATE_FAILURE_COUNT ]] && count=$(<"$RESCAN_COMPENSATION_REVALIDATE_FAILURE_COUNT")
  printf '%s\n' "$((count + 1))" >"$RESCAN_COMPENSATION_REVALIDATE_FAILURE_COUNT"
  rm -f -- "$RESCAN_COMPENSATION_REVALIDATE_FAILURE"
  exit 1
fi
exec /usr/bin/git "$@"
EOF
chmod +x -- "$rescan_compensation_git"
printf 'compensation-update\n' >>"$validation_repo/Widget.qml"
git -C "$validation_repo" add Widget.qml
git -C "$validation_repo" -c user.name=test -c user.email=test@example.invalid commit -qm compensation-update
git -C "$validation_repo" push -q "$remote_root/lifecycle.git" main
rescan_compensation_prior=$(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD)
rescan_compensation_reset_count="$test_root/rescan-compensation-reset-count"
rescan_compensation_revalidate_failure="$test_root/rescan-compensation-revalidate-failure"
rescan_compensation_revalidate_failure_count="$test_root/rescan-compensation-revalidate-failure-count"
rescan_compensation_before=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
rescan_compensation_status=0
if env "${manager_env[@]}" PATH="$rescan_compensation_bin:$PATH" \
  IPC_RESCAN_MARKER="$rescan_compensation_revalidate_failure" \
  RESCAN_COMPENSATION_RESET_COUNT="$rescan_compensation_reset_count" \
  RESCAN_COMPENSATION_REVALIDATE_FAILURE="$rescan_compensation_revalidate_failure" \
  RESCAN_COMPENSATION_REVALIDATE_FAILURE_COUNT="$rescan_compensation_revalidate_failure_count" \
  "$manager" update lifecycle.widget --yes >/dev/null 2>&1; then
  rescan_compensation_status=0
else
  rescan_compensation_status=$?
fi
[[ $rescan_compensation_status != 0 ]] || fail "compensating-rescan update unexpectedly succeeded"
rescan_compensation_after=$(grep -c $'rescanPlugins\t\t' "$log_file" || true)
[[ $((rescan_compensation_after - rescan_compensation_before)) == 2 ]] ||
  fail "successful retained rollback did not request exactly one compensating rescan"
[[ $(git -C "$plugins_dir/lifecycle.widget" rev-parse HEAD) == "$rescan_compensation_prior" ]] ||
  fail "compensating-rescan rollback did not restore the prior revision"
[[ $(<"$rescan_compensation_reset_count") -ge 2 ]] ||
  fail "retained cleanup did not safely retry the successful rollback"
[[ $(<"$rescan_compensation_revalidate_failure_count") == 1 ]] ||
  fail "initial post-rescan identity mismatch did not occur exactly once"
[[ -f "$rescan_compensation_revalidate_failure" ]] || fail "compensating rescan did not occur"

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
env "${manager_env[@]}" "$manager" remove non-git.widget --yes >/dev/null || fail "non-Git removal failed"
backup_count=0
for backup in "$plugins_dir"/.removed.non-git.widget.*; do
  [[ -d $backup ]] || continue
  backup_count=$((backup_count + 1))
  [[ -f $backup/data ]] || fail "non-Git backup lost source data"
done
[[ $backup_count == 1 && ! -e $non_git_dir ]] || fail "non-Git removal backup was unsafe"

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
