#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

for required_command in quickshell jq; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'FAIL: required command is missing: %s\n' "$required_command" >&2
    exit 1
  }
done

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
cp -a -- "$shell_dir" "$shell_config"
jq -n '{version:1,bar:{id:"desktop.bar",layout:{left:[],center:[],right:[]}},plugins:[],disabledPlugins:[]}' \
  >"$shell_config/config/shell.json"
cp -- "$fixture/manifest.json" "$source_repo/manifest.json"
cp -- "$fixture/Widget.qml" "$source_repo/Widget.qml"

git -C "$source_repo" init -q
git -C "$source_repo" -c user.name=test -c user.email=test@example.invalid add .
git -C "$source_repo" -c user.name=test -c user.email=test@example.invalid commit -qm initial

default_paths=(
  "$shell_dir/config/shell.json.tmpl"
  "$shell_dir/config/shell.json"
  "$shell_dir/config/shell.json.tmpl.rendered"
)
checksum_defaults() {
  local path checksum
  for path in "${default_paths[@]}"; do
    if [[ -e $path ]]; then
      read -r checksum _ < <(sha256sum -- "$path")
      printf '%s\t%s\n' "$path" "$checksum"
    else
      printf '%s\tabsent\n' "$path"
    fi
  done
}
defaults_checksum=$(checksum_defaults)
git -C "$repo_root" diff --quiet -- \
  Linux/quickshell/desktop-shell/config/shell.json.tmpl \
  Linux/quickshell/desktop-shell/config/shell.json \
  Linux/quickshell/desktop-shell/config/shell.json.tmpl.rendered \
  || fail "repository defaults are already modified"

start_shell() {
  env \
    HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" \
    PATH="$helper_dir:$PATH" \
    DESKTOP_SHELL_TEST_NO_SURFACES=1 \
    DESKTOP_SHELL_TEST_ALLOW_PLUGIN_STATE_MUTATION=1 \
    DESKTOP_SHELL_TEST_LOAD_PLUGIN_WIDGETS=1 \
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

wait_for_plugin_list() {
  local expression=$1
  for _ in {1..100}; do
    if plugin_list=$(run_omarchy plugin list --json 2>/dev/null) \
      && jq -e "$expression" <<<"$plugin_list" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  fail "plugin list did not satisfy: $expression"
}

wait_for_health() {
  local expression=$1
  for _ in {1..100}; do
    if health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health 2>/dev/null) \
      && jq -e "$expression" <<<"$health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  fail "shell health did not satisfy: $expression"
}

wait_for_widget_readiness() {
  local expected=$1 readiness
  for _ in {1..100}; do
    readiness=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell-test pluginWidgetReady \
      test.marketplace-widget 2>/dev/null || true)
    [[ $readiness == "$expected" ]] && return 0
    sleep 0.1
  done
  fail "widget readiness did not become $expected (last: $readiness)"
}

start_shell

run_omarchy plugin add "$source_repo" --yes >/dev/null || fail "local plugin add failed"
[[ -d "$plugins_dir/test.marketplace-widget/.git" ]] || fail "plugin checkout was not installed"
wait_for_plugin_list 'any(.[]; .id == "test.marketplace-widget" and .firstParty == false)'
wait_for_health '.configValid == true and .pluginStateValid == true'

run_omarchy plugin enable test.marketplace-widget --section right >/dev/null || fail "plugin enable failed"
wait_for_state '.barWidgets | any(.[]; .id == "test.marketplace-widget" and .section == "right")'
wait_for_writes
wait_for_plugin_list 'any(.[]; .id == "test.marketplace-widget" and .firstParty == false and .enabled == true and (.kinds | index("bar-widget")))'
wait_for_widget_readiness ready
jq -e '.bar.layout.right | any(.[]; .id == "test.marketplace-widget")' \
  <<<"$(quickshell ipc --pid "$shell_pid" call -- desktop-shell listShellConfig)" \
  >/dev/null || fail "enabled widget was not registered in shell configuration"

prior_commit=$(git -C "$plugins_dir/test.marketplace-widget" rev-parse HEAD)
next_version=$(jq -r '.version' "$source_repo/manifest.json" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 + 1 }')
jq --arg version "$next_version" '.version = $version' "$source_repo/manifest.json" >"$source_repo/manifest.json.tmp"
mv -- "$source_repo/manifest.json.tmp" "$source_repo/manifest.json"
printf '\n// valid lifecycle update\n' >>"$source_repo/Widget.qml"
git -C "$source_repo" add manifest.json Widget.qml
git -C "$source_repo" -c user.name=test -c user.email=test@example.invalid commit -qm update
run_omarchy plugin update test.marketplace-widget --yes >/dev/null || fail "local plugin update failed"
updated_commit=$(git -C "$plugins_dir/test.marketplace-widget" rev-parse HEAD)
[[ $updated_commit != "$prior_commit" ]] || fail "plugin checkout did not advance after update"
[[ $(jq -r '.version' "$plugins_dir/test.marketplace-widget/manifest.json") == 1.0.1 ]] \
  || fail "updated plugin manifest version was not installed"
wait_for_plugin_list 'any(.[]; .id == "test.marketplace-widget" and .enabled == true)'
wait_for_widget_readiness ready
wait_for_health '.configValid == true and .pluginStateValid == true and (.pluginErrors | length == 0)'

run_omarchy plugin disable test.marketplace-widget >/dev/null || fail "plugin disable failed"
wait_for_state '(.barWidgets // []) | all(.[]; .id != "test.marketplace-widget")'
wait_for_writes
wait_for_plugin_list 'any(.[]; .id == "test.marketplace-widget" and .enabled == false)'
wait_for_widget_readiness absent

# Remove performs its own disable transaction; restore enabled state so that
# the manager's removal transaction has a live widget to disable.
run_omarchy plugin enable test.marketplace-widget --section right >/dev/null || fail "plugin re-enable failed"
wait_for_state '.barWidgets | any(.[]; .id == "test.marketplace-widget")'
wait_for_writes
wait_for_plugin_list 'any(.[]; .id == "test.marketplace-widget" and .enabled == true)'
wait_for_widget_readiness ready
run_omarchy plugin remove test.marketplace-widget --yes >/dev/null || fail "plugin remove failed"
[[ ! -e "$plugins_dir/test.marketplace-widget" ]] || fail "removed plugin checkout remains"
wait_for_plugin_list 'all(.[]; .id != "test.marketplace-widget")'
wait_for_state '(.barWidgets // []) | all(.[]; .id != "test.marketplace-widget")'
wait_for_writes
wait_for_health '.configValid == true and .pluginStateValid == true and (.pluginErrors | length == 0)'

health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health) || fail "shell health query failed"
jq -e '.configValid == true and .pluginStateValid == true and (.pluginErrors | length == 0)' <<<"$health" >/dev/null \
  || fail "shell health reported invalid config, state, or plugin errors"

stop_shell
[[ $(checksum_defaults) == "$defaults_checksum" ]] || fail "repository default checksum changed"
git -C "$repo_root" diff --quiet -- \
  Linux/quickshell/desktop-shell/config/shell.json.tmpl \
  Linux/quickshell/desktop-shell/config/shell.json \
  Linux/quickshell/desktop-shell/config/shell.json.tmpl.rendered \
  || fail "repository rendered defaults changed"

printf 'PASS: marketplace plugin lifecycle\n'
