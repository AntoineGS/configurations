#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell unavailable\n'
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: jq unavailable\n'
  exit 0
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
fixture="$shell_dir/tests/fixtures/plugin-registry/shell.qml"
tmp_dir=$(mktemp -d)
shell_pid=""
holder_pid=""
swap2_pid=""
stop_holder() {
  if [[ -n $holder_pid ]]; then
    kill "$holder_pid" 2>/dev/null || true
    wait "$holder_pid" 2>/dev/null || true
    holder_pid=""
  fi
}
trap '[[ -z $shell_pid ]] || kill "$shell_pid" 2>/dev/null || true; stop_holder; [[ -z $swap2_pid ]] || wait "$swap2_pid" 2>/dev/null || true; rm -rf -- "$tmp_dir"' EXIT

result="$tmp_dir/result.json"
config="$tmp_dir/config"
plugins_dir="$tmp_dir/plugins"
release_external="$tmp_dir/release-external"
mkdir -p -- "$config"
mkdir -p -- "$plugins_dir/acme.widget"
mkdir -p -- "$plugins_dir/acme.other"
printf '%s\n' '{"schemaVersion":1,"id":"acme.widget","name":"Acme Widget","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Widget.qml"}}' >"$plugins_dir/acme.widget/manifest.json"
touch "$plugins_dir/acme.widget/Widget.qml"
printf '%s\n' '{"schemaVersion":1,"id":"acme.other","name":"Acme Other","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Widget.qml"}}' >"$plugins_dir/acme.other/manifest.json"
touch "$plugins_dir/acme.other/Widget.qml"
mkdir -p -- "$plugins_dir/.stage.swap1" "$plugins_dir/.stage.swap2"
printf '%s\n' '{"schemaVersion":1,"id":"acme.widget","name":"Acme Widget","version":"2.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Widget.qml"}}' >"$plugins_dir/.stage.swap1/manifest.json"
printf 'import QtQuick\nItem { }\n' >"$plugins_dir/.stage.swap1/Widget.qml"
printf '%s\n' '{"schemaVersion":1,"id":"acme.widget","name":"Acme Widget","version":"3.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Widget.qml"}}' >"$plugins_dir/.stage.swap2/manifest.json"
printf 'import QtQuick\nItem { }\n' >"$plugins_dir/.stage.swap2/Widget.qml"
(
  exec 9>"$plugins_dir/.plugin-manager.lock"
  flock 9
  mv -- "$plugins_dir/acme.widget" "$plugins_dir/.rollback.swap1"
  mv -- "$plugins_dir/.stage.swap1" "$plugins_dir/acme.widget"
  touch "$tmp_dir/lock-held"
  while [[ ! -e $release_external ]]; do sleep 0.01; done
) &
holder_pid=$!
for _ in {1..100}; do
  [[ -f "$tmp_dir/lock-held" ]] && break
  sleep 0.01
done
[[ -f "$tmp_dir/lock-held" ]]
(
  while [[ ! -e $release_external ]]; do sleep 0.01; done
  sleep 0.02
  exec 8>"$plugins_dir/.plugin-manager.lock"
  flock 8
  mv -- "$plugins_dir/acme.widget" "$plugins_dir/.rollback.swap2"
  mv -- "$plugins_dir/.stage.swap2" "$plugins_dir/acme.widget"
  flock -u 8
) &
swap2_pid=$!
cp -- "$fixture" "$config/shell.qml"
mkdir -p -- "$config/firstparty"
cp -R -- "$shell_dir/plugins/." "$config/firstparty/"
ln -s -- "$shell_dir/services" "$config/services"
ln -s -- "$shell_dir/Commons" "$config/Commons"

env \
  HOME="$tmp_dir/home" \
  XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1 \
  PLUGIN_REGISTRY_PLUGINS_DIR="$plugins_dir" \
  PLUGIN_REGISTRY_RELEASE_EXTERNAL="$release_external" \
  PLUGIN_REGISTRY_RESULT="$result" \
  quickshell -n -p "$config" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!

for _ in {1..100}; do
  if [[ -f $result ]]; then break; fi
  if ! kill -0 "$shell_pid" 2>/dev/null; then break; fi
  sleep 0.1
done

if [[ ! -f $result ]]; then
  sed -n '1,240p' "$tmp_dir/quickshell.log" >&2
  printf 'registry fixture did not produce a result\n' >&2
  exit 1
fi

if ! jq -e '.ok == true' "$result" >/dev/null; then
  jq . "$result" >&2
  sed -n '1,240p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi
wait "$holder_pid"
holder_pid=""
printf 'PASS: plugin registry contract\n'
