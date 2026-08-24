#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

if ! command -v quickshell >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: quickshell and jq are required\n'
  exit 0
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
helper_dir="$repo_root/Linux/os/helpers"
fixture="$shell_dir/tests/fixtures/plugins/widget"
tmp_dir=$(mktemp -d)
shell_pid=

stop_shell() {
  if [[ -n $shell_pid ]]; then
    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
    shell_pid=
  fi
}

cleanup() {
  stop_shell
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [[ -f ${shell_log:-} ]]; then
    sed -n '1,240p' "$shell_log" >&2
  fi
  exit 1
}

home="$tmp_dir/home"
plugins_dir="$tmp_dir/plugins"
state_file="$tmp_dir/state/desktop-shell/shell.json"
source_repo="$tmp_dir/marketplace-widget"
shell_config="$home/.config/quickshell/desktop-shell"
shell_log="$tmp_dir/quickshell.log"
mkdir -p -- "$home/.config/quickshell" "$plugins_dir" "$(dirname -- "$state_file")" "$source_repo"
ln -s -- "$shell_dir" "$shell_config"
mkdir -p -- "$home/.config/quickshell/desktop-shell/config"
jq -n '{version:1,bar:{id:"desktop.bar",layout:{left:[],center:[],right:[]}},plugins:[],disabledPlugins:[]}' \
  >"$home/.config/quickshell/desktop-shell/config/shell.json"
cp -- "$fixture/manifest.json" "$source_repo/manifest.json"
cp -- "$fixture/Widget.qml" "$source_repo/Widget.qml"

git -C "$source_repo" init -q
git -C "$source_repo" -c user.name=test -c user.email=test@example.invalid add .
git -C "$source_repo" -c user.name=test -c user.email=test@example.invalid commit -qm initial

defaults_template="$shell_dir/config/shell.json.tmpl"
defaults_checksum=$(sha256sum -- "$defaults_template")
git -C "$repo_root" diff --quiet -- "$defaults_template" || fail "repository defaults are already modified"

start_shell() {
  env \
    HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" \
    DESKTOP_SHELL_TEST_NO_SURFACES=1 \
    DESKTOP_SHELL_TEST_ALLOW_PLUGIN_STATE_MUTATION=1 \
    DESKTOP_SHELL_STATE_PATH="$state_file" \
    DESKTOP_SHELL_PLUGINS_DIR="$plugins_dir" \
    DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1 \
    quickshell -n -p "$shell_config" >"$shell_log" 2>&1 &
  shell_pid=$!

  for _ in {1..100}; do
    if quickshell ipc --pid "$shell_pid" call -- desktop-shell ping >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$shell_pid" 2>/dev/null; then
      fail "isolated shell exited during startup"
    fi
    sleep 0.1
  done
  fail "isolated shell did not become ready"
}

run_omarchy() {
  env \
    PATH="$helper_dir:$PATH" \
    HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" \
    DESKTOP_SHELL_STATE_PATH="$state_file" \
    DESKTOP_SHELL_PLUGINS_DIR="$plugins_dir" \
    DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1 \
    omarchy "$@"
}

wait_for_state() {
  local expression=$1
  for _ in {1..100}; do
    if [[ -f $state_file ]] && jq -e "$expression" "$state_file" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  fail "state did not satisfy: $expression"
}

wait_for_writes() {
  for _ in {1..100}; do
    if health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health 2>/dev/null) \
      && jq -e '.pluginStateWritePending == false and .pluginStateWriteError == ""' <<<"$health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  fail "plugin state write did not settle"
}

start_shell

run_omarchy plugin add "$source_repo" --yes >/dev/null || fail "local plugin add failed"
[[ -d "$plugins_dir/test.marketplace-widget/.git" ]] || fail "plugin checkout was not installed"

run_omarchy plugin enable test.marketplace-widget --section right >/dev/null || fail "plugin enable failed"
wait_for_state '.barWidgets | any(.[]; .id == "test.marketplace-widget" and .section == "right")'
wait_for_writes
plugin_list=$(run_omarchy plugin list --json) || fail "plugin list failed"
jq -e 'any(.[]; .id == "test.marketplace-widget" and .firstParty == false and .enabled == true and (.kinds | index("bar-widget")))' \
  <<<"$plugin_list" >/dev/null || fail "enabled third-party widget was not listed correctly"
jq -e '.bar.layout.right | any(.[]; .id == "test.marketplace-widget")' \
  <<<"$(quickshell ipc --pid "$shell_pid" call -- desktop-shell listShellConfig)" \
  >/dev/null || fail "enabled widget was not registered in shell configuration"

prior_commit=$(git -C "$plugins_dir/test.marketplace-widget" rev-parse HEAD)
printf '\n// valid lifecycle update\n' >>"$source_repo/Widget.qml"
git -C "$source_repo" add Widget.qml
git -C "$source_repo" -c user.name=test -c user.email=test@example.invalid commit -qm update
run_omarchy plugin update test.marketplace-widget --yes >/dev/null || fail "local plugin update failed"
updated_commit=$(git -C "$plugins_dir/test.marketplace-widget" rev-parse HEAD)
[[ $updated_commit != "$prior_commit" ]] || fail "plugin checkout did not advance after update"

run_omarchy plugin disable test.marketplace-widget >/dev/null || fail "plugin disable failed"
wait_for_state '(.barWidgets // []) | all(.[]; .id != "test.marketplace-widget")'
wait_for_writes
plugin_list=$(run_omarchy plugin list --json) || fail "plugin list after disable failed"
jq -e 'any(.[]; .id == "test.marketplace-widget" and .enabled == false)' <<<"$plugin_list" >/dev/null \
  || fail "disabled widget was not reported as disabled"

# Remove performs its own disable transaction; restore enabled state so that
# the manager's removal transaction has a live widget to disable.
run_omarchy plugin enable test.marketplace-widget --section right >/dev/null || fail "plugin re-enable failed"
wait_for_state '.barWidgets | any(.[]; .id == "test.marketplace-widget")'
wait_for_writes
run_omarchy plugin remove test.marketplace-widget --yes >/dev/null || fail "plugin remove failed"
[[ ! -e "$plugins_dir/test.marketplace-widget" ]] || fail "removed plugin checkout remains"
plugin_list=$(run_omarchy plugin list --json) || fail "plugin list after remove failed"
jq -e 'all(.[]; .id != "test.marketplace-widget")' <<<"$plugin_list" >/dev/null || fail "removed plugin remains listed"

health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health) || fail "shell health query failed"
jq -e '.configValid == true and .pluginStateValid == true and (.pluginErrors | length == 0)' <<<"$health" >/dev/null \
  || fail "shell health reported invalid config, state, or plugin errors"

stop_shell
[[ $(sha256sum -- "$defaults_template") == "$defaults_checksum" ]] || fail "repository default checksum changed"
git -C "$repo_root" diff --quiet -- "$defaults_template" || fail "repository rendered defaults changed"

printf 'PASS: marketplace plugin lifecycle\n'
