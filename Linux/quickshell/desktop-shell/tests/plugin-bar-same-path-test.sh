#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: quickshell unavailable\n'
  exit 0
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
fixture="$repo_root/Linux/quickshell/desktop-shell/tests/fixtures/plugin-bar-same-path/shell.qml"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
plugin_path="$tmp_dir/Bar.qml"
result="$tmp_dir/result.json"
printf '%s\n' 'import QtQuick' 'Item {' ' property string version: "1.0.0"' ' property var harness: null' ' Component.onDestruction: if (harness) harness.destroyedCount++' '}' >"$plugin_path"
[[ -f "$plugin_path" ]]

env PLUGIN_BAR_PATH="$plugin_path" PLUGIN_BAR_RESULT="$result" \
  quickshell -n -p "$fixture" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!
trap 'kill "$shell_pid" 2>/dev/null || true; wait "$shell_pid" 2>/dev/null || true; rm -rf -- "$tmp_dir"' EXIT
for _ in {1..100}; do
  [[ -f "$result" ]] && break
  sleep 0.1
done
if [[ ! -f "$result" ]]; then
  sed -n '1,240p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi
if ! jq -e '.ok == true and .loadCount == 2 and .destroyedCount == 1 and .observedVersions == ["1.0.0", "2.0.0"]' "$result" >/dev/null; then
  jq . "$result" >&2
  sed -n '1,240p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi
printf 'PASS: same-path full-bar lifecycle\n'
