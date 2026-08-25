#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: quickshell and jq unavailable\n'
  exit 0
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
tmp_dir=$(mktemp -d)
shell_pid=""
trap '[[ -z $shell_pid ]] || kill "$shell_pid" 2>/dev/null || true; rm -rf -- "$tmp_dir"' EXIT

isolated_shell_dir="$tmp_dir/desktop-shell"
plugins_dir="$tmp_dir/plugins/acme.service"
watch_fifo="$tmp_dir/watcher.fifo"
state_file="$tmp_dir/state/shell.json"
mkdir -p -- "$plugins_dir" "$tmp_dir/bin" "$tmp_dir/state"
cp -a -- "$shell_dir" "$isolated_shell_dir"
mkfifo -- "$watch_fifo"
printf '%s\n' '{"version":1,"bar":{"id":"desktop.bar","position":"top","layout":{"left":[],"center":[],"right":[]}},"plugins":[{"id":"acme.service"}],"disabledPlugins":[]}' >"$isolated_shell_dir/config/shell.json"
printf '%s\n' '{"schemaVersion":1,"id":"acme.service","name":"Acme Service","version":"1.0.0","kinds":["service"],"entryPoints":{"service":"Service.qml"}}' >"$plugins_dir/manifest.json"
printf '%s\n' 'import QtQuick' 'Item { }' >"$plugins_dir/Service.qml"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' '[[ ${1-} == --help ]] && exit 0' 'while IFS= read -r path; do printf "%s\n" "$path"; done < "$PLUGIN_REGISTRY_WATCH_FIFO"' >"$tmp_dir/bin/inotifywait"
printf '%s\n' '#!/usr/bin/env bash' 'sleep 1' 'exec /usr/bin/find "$@"' >"$tmp_dir/bin/find"
chmod 0755 -- "$tmp_dir/bin/inotifywait" "$tmp_dir/bin/find"

env PATH="$tmp_dir/bin:$PATH" \
  HOME="$tmp_dir/home" XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  DESKTOP_SHELL_STATE_PATH="$state_file" \
  DESKTOP_SHELL_PLUGINS_DIR="$tmp_dir/plugins" \
  PLUGIN_REGISTRY_WATCH_FIFO="$watch_fifo" \
  quickshell -n -p "$isolated_shell_dir" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!

printf '%s\n' "$plugins_dir/manifest.json" >"$watch_fifo"
health=""
for _ in {1..150}; do
  health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health 2>/dev/null || true)
  if jq -e '.scanFinishedCount == 1 and .thirdPartyServiceCreateAttemptCount == 0' <<<"$health" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! jq -e '.scanFinishedCount == 1 and .thirdPartyServiceCreateAttemptCount == 0' <<<"$health" >/dev/null; then
  printf '%s\n' "$health" >&2
  sed -n '1,260p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi

for _ in {1..150}; do
  health=$(quickshell ipc --pid "$shell_pid" call -- desktop-shell health 2>/dev/null || true)
  if jq -e '.scanFinishedCount >= 2 and .thirdPartyServiceCreateAttemptCount == 1' <<<"$health" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! jq -e '.scanFinishedCount >= 2 and .thirdPartyServiceCreateAttemptCount == 1' <<<"$health" >/dev/null; then
  printf '%s\n' "$health" >&2
  sed -n '1,260p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi
printf 'PASS: pending startup scan defers service creation\n'
