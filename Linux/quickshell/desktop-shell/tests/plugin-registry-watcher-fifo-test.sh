#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: quickshell or jq unavailable\n'
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
plugins_dir="$tmp_dir/plugins"
bin_dir="$tmp_dir/bin"
watch_fifo="$tmp_dir/watcher.fifo"
mkdir -p -- "$config" "$plugins_dir/acme.widget" "$bin_dir"
mkfifo -- "$watch_fifo"
# The generated watcher must expand its runtime variables, not this test's.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' '[[ ${1-} == --help ]] && exit 0' 'while IFS= read -r path; do printf "%s\n" "$path"; done < "$PLUGIN_REGISTRY_WATCH_FIFO"' >"$bin_dir/inotifywait"
chmod 0755 -- "$bin_dir/inotifywait"
printf '%s\n' '{"schemaVersion":1,"id":"acme.widget","name":"Acme Widget","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"Widget.qml"}}' >"$plugins_dir/acme.widget/manifest.json"
touch "$plugins_dir/acme.widget/Widget.qml"
cp -- "$fixture" "$config/shell.qml"
mkdir -p -- "$config/firstparty"
cp -R -- "$shell_dir/plugins/." "$config/firstparty/"
ln -s -- "$shell_dir/services" "$config/services"
ln -s -- "$shell_dir/Commons" "$config/Commons"

env PATH="$bin_dir:$PATH" \
    HOME="$tmp_dir/home" \
    XDG_CONFIG_HOME="$tmp_dir/home/.config" \
    DESKTOP_SHELL_WATCH_FIFO_TEST=1 \
    PLUGIN_REGISTRY_WATCH_FIFO="$watch_fifo" \
    PLUGIN_REGISTRY_PLUGINS_DIR="$plugins_dir" \
    PLUGIN_REGISTRY_RESULT="$result" \
    quickshell -n -p "$config" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!

for _ in {1..150}; do
  [[ -f "$result" ]] && break
  kill -0 "$shell_pid" 2>/dev/null || break
  sleep 0.1
done

if [[ ! -f "$result" ]]; then
  sed -n '1,260p' "$tmp_dir/quickshell.log" >&2
  printf 'FIFO watcher fixture did not produce a result\n' >&2
  exit 1
fi
if ! jq -e '.ok == true and .observedVersions == ["1.0.0", "2.0.0", "3.0.0"]' "$result" >/dev/null; then
  jq . "$result" >&2
  sed -n '1,260p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi
printf 'PASS: plugin registry FIFO watcher\n'
