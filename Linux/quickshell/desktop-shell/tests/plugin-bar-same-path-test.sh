#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: quickshell unavailable\n'
  exit 0
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
isolated_shell_dir="$tmp_dir/desktop-shell"
plugins_dir="$tmp_dir/plugins/acme.bar"
watch_fifo="$tmp_dir/watcher.fifo"
state_file="$tmp_dir/state/shell.json"
mkdir -p -- "$plugins_dir" "$tmp_dir/bin" "$tmp_dir/state"
cp -a -- "$shell_dir" "$isolated_shell_dir"
mkfifo -- "$watch_fifo"
printf '%s\n' '{"version":1,"bar":{"id":"acme.bar","position":"top","layout":{"left":[],"center":[],"right":[]}},"plugins":[],"disabledPlugins":[]}' >"$isolated_shell_dir/config/shell.json"
printf '%s\n' '{"schemaVersion":1,"id":"acme.bar","name":"Acme Bar","version":"1.0.0","kinds":["bar"],"entryPoints":{"bar":"Bar.qml"}}' >"$plugins_dir/manifest.json"
printf '%s\n' 'import QtQuick' 'Item {' ' readonly property string version: "1.0.0"' ' property var shell: null' ' Component.onDestruction: if (shell && typeof shell.recordPluginBarDestroyed === "function") shell.recordPluginBarDestroyed()' '}' >"$plugins_dir/Bar.qml"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'while IFS= read -r path; do printf "%s\n" "$path"; done < "$PLUGIN_REGISTRY_WATCH_FIFO"' >"$tmp_dir/bin/inotifywait"
chmod 0755 -- "$tmp_dir/bin/inotifywait"

env PATH="$tmp_dir/bin:$PATH" \
  HOME="$tmp_dir/home" XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  DESKTOP_SHELL_TEST_ALLOW_PLUGIN_STATE_MUTATION=1 \
  DESKTOP_SHELL_TEST_LOAD_PLUGIN_BAR=1 \
  DESKTOP_SHELL_STATE_PATH="$state_file" \
  DESKTOP_SHELL_PLUGINS_DIR="$tmp_dir/plugins" \
  PLUGIN_REGISTRY_WATCH_FIFO="$watch_fifo" \
  quickshell -n -p "$isolated_shell_dir" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!
trap 'kill "$shell_pid" 2>/dev/null || true; wait "$shell_pid" 2>/dev/null || true; rm -rf -- "$tmp_dir"' EXIT
probe=""
for _ in {1..150}; do
  probe=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell-test pluginBarTestProbe 2>/dev/null || true)
  if jq -e '.loadCount == 1 and .version == "1.0.0"' <<<"$probe" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
jq -e '.loadCount == 1 and .version == "1.0.0"' <<<"$probe" >/dev/null

stage="$tmp_dir/stage"
mkdir -p -- "$stage"
printf '%s\n' 'import QtQuick' 'Item {' ' readonly property string version: "2.0.0"' ' property var shell: null' ' Component.onDestruction: if (shell && typeof shell.recordPluginBarDestroyed === "function") shell.recordPluginBarDestroyed()' '}' >"$stage/Bar.qml"
printf '%s\n' '{"schemaVersion":1,"id":"acme.bar","name":"Acme Bar","version":"2.0.0","kinds":["bar"],"entryPoints":{"bar":"Bar.qml"}}' >"$stage/manifest.json"
mv -- "$stage/Bar.qml" "$plugins_dir/Bar.qml"
mv -- "$stage/manifest.json" "$plugins_dir/manifest.json"
rmdir -- "$stage"
printf '%s\n' "$plugins_dir/manifest.json" >"$watch_fifo"

for _ in {1..150}; do
  probe=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell-test pluginBarTestProbe 2>/dev/null || true)
  if jq -e '.loadCount == 2 and .destroyedCount == 1 and .instanceGeneration == 2 and .version == "2.0.0"' <<<"$probe" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! jq -e '.loadCount == 2 and .destroyedCount == 1 and .instanceGeneration == 2 and .version == "2.0.0"' <<<"$probe" >/dev/null; then
  printf '%s\n' "$probe" >&2
  sed -n '1,260p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi
printf 'PASS: production same-path full-bar lifecycle\n'
