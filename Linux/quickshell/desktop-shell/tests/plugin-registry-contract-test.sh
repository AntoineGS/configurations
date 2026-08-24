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
trap '[[ -z $shell_pid ]] || kill "$shell_pid" 2>/dev/null || true; rm -rf -- "$tmp_dir"' EXIT

result="$tmp_dir/result.json"
config="$tmp_dir/config"
mkdir -p -- "$config"
cp -- "$fixture" "$config/shell.qml"
ln -s -- "$shell_dir/services" "$config/services"
ln -s -- "$shell_dir/Commons" "$config/Commons"

env \
  HOME="$tmp_dir/home" \
  XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1 \
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

jq -e '.ok == true' "$result" >/dev/null
printf 'PASS: plugin registry contract\n'
