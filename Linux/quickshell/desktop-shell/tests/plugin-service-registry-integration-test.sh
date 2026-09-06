#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP: quickshell or jq unavailable\n'
  exit 0
fi
if ! command -v timeout >/dev/null 2>&1; then
  printf 'FAIL: timeout unavailable\n' >&2
  exit 1
fi

if [[ ${DESKTOP_SHELL_REGISTRY_INTEGRATION_TIMEOUT_GUARD:-} != 1 ]]; then
  exec env DESKTOP_SHELL_REGISTRY_INTEGRATION_TIMEOUT_GUARD=1 \
    timeout --foreground --kill-after=2s 45s bash "$0" "$@"
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
fixture_dir="$shell_dir/tests/fixtures/plugin-registry"
tmp_dir=$(mktemp -d)
shell_pid=""
trap '[[ -z $shell_pid ]] || kill "$shell_pid" 2>/dev/null || true; wait "$shell_pid" 2>/dev/null || true; rm -rf -- "$tmp_dir"' EXIT

isolated_shell_dir="$tmp_dir/desktop-shell"
plugins_dir="$tmp_dir/plugins"
bar_plugin_dir="$plugins_dir/acme.integration-bar"
discovered_plugin_dir="$plugins_dir/acme.discovered-service"
state_file="$tmp_dir/state/shell.json"
config_file="$isolated_shell_dir/config/shell.json"
bin_dir="$tmp_dir/bin"
home_dir="$tmp_dir/home"
state_home="$tmp_dir/state-home"
runtime_dir="$tmp_dir/runtime"
host_runtime_dir="${XDG_RUNTIME_DIR:-}"
wayland_display="${WAYLAND_DISPLAY:-wayland-0}"
updates_log="$tmp_dir/configuration-updates.log"
hostname_log="$tmp_dir/hostname.log"

mkdir -p -- "$plugins_dir" "$bar_plugin_dir" "$tmp_dir/state" "$bin_dir" \
  "$home_dir/.config" "$state_home" "$runtime_dir"
chmod 0700 -- "$runtime_dir"
qt_platform=offscreen
if [[ -S "$host_runtime_dir/$wayland_display" ]]; then
  ln -s -- "$host_runtime_dir/$wayland_display" "$runtime_dir/$wayland_display"
  qt_platform=wayland
fi
cp -a -- "$shell_dir" "$isolated_shell_dir"
rm -rf -- "$isolated_shell_dir/plugins/notifications" "$isolated_shell_dir/plugins/polkit" \
  "$isolated_shell_dir/plugins/services/battery"
cp -- "$fixture_dir/integration-bar/manifest.json" "$bar_plugin_dir/manifest.json"
cp -- "$fixture_dir/integration-bar/Bar.qml" "$bar_plugin_dir/Bar.qml"
cp -- "$fixture_dir/fake-configuration-updates" "$bin_dir/desktop-shell-configuration-updates"
cp -- "$fixture_dir/fake-hostname" "$bin_dir/hostname"
chmod 0755 -- "$bin_dir/desktop-shell-configuration-updates" "$bin_dir/hostname"
: >"$updates_log"
: >"$hostname_log"
printf '%s\n' '{"version":1,"bar":{"id":"desktop.bar","position":"top","layout":{"left":[],"center":[],"right":[]}},"plugins":[],"disabledPlugins":[]}' >"$config_file"
printf '%s\n' '{"version":1,"barPluginId":"acme.integration-bar"}' >"$state_file"

env PATH="$bin_dir:$PATH" \
  HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" \
  XDG_STATE_HOME="$state_home" XDG_RUNTIME_DIR="$runtime_dir" \
  WAYLAND_DISPLAY="$wayland_display" QT_QPA_PLATFORM="$qt_platform" \
  DESKTOP_SHELL_PREVIEW=1 \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  DESKTOP_SHELL_TEST_ALLOW_PLUGIN_STATE_MUTATION=1 \
  DESKTOP_SHELL_TEST_LOAD_SERVICES=1 \
  DESKTOP_SHELL_TEST_LOAD_PLUGIN_BAR=1 \
  DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1 \
  DESKTOP_SHELL_STATE_PATH="$state_file" \
  DESKTOP_SHELL_PLUGINS_DIR="$plugins_dir" \
  REGISTRY_INTEGRATION_UPDATES_LOG="$updates_log" \
  REGISTRY_INTEGRATION_HOSTNAME_LOG="$hostname_log" \
  quickshell -n -p "$isolated_shell_dir" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!

ipc() {
  XDG_RUNTIME_DIR="$runtime_dir" quickshell ipc --pid "$shell_pid" call -- "$@"
}

health=""
for _ in {1..150}; do
  health=$(ipc desktop-shell health 2>/dev/null || true)
  if jq -e '.scanFinishedCount == 1' <<<"$health" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! jq -e '.scanFinishedCount == 1' <<<"$health" >/dev/null 2>&1; then
  printf 'initial registry scan did not finish: %s\n' "$health" >&2
  sed -n '1,260p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi
[[ $(ipc desktop-shell rescanPlugins) == ok ]]

if [[ -s $updates_log || -s $hostname_log ]]; then
  printf 'optional collectors ran before a UI consumer: updates=%s hostname=%s\n' \
    "$(wc -l <"$updates_log")" "$(wc -l <"$hostname_log")" >&2
  exit 1
fi

expected_services='["desktop.agents","desktop.audio","desktop.bluetooth","desktop.configuration-updates","desktop.disk","desktop.host-metrics","desktop.monitor","desktop.network","desktop.power","desktop.recording","desktop.tailscale","desktop.vm","desktop.workspaces"]'
probe=""
for _ in {1..150}; do
  probe=$(ipc desktop-shell-test serviceRegistryProbeForTest 2>/dev/null || true)
  if jq -e --argjson expected "$expected_services" \
    '.services == $expected and .barLoaded == true and .allServiceConsumersAttached == true' <<<"$probe" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! jq -e --argjson expected "$expected_services" \
  '.services == $expected and .barLoaded == true and .allServiceConsumersAttached == true' <<<"$probe" >/dev/null 2>&1; then
  printf 'initial service registry probe failed: %s\n' "$probe" >&2
  sed -n '1,260p' "$tmp_dir/quickshell.log" >&2
  exit 1
fi

mkdir -p -- "$discovered_plugin_dir"
cp -- "$fixture_dir/discovered-service/manifest.json" "$discovered_plugin_dir/manifest.json"
cp -- "$fixture_dir/discovered-service/Service.qml" "$discovered_plugin_dir/Service.qml"
[[ $(ipc desktop-shell rescanPlugins) == ok ]]

for _ in {1..150}; do
  probe=$(ipc desktop-shell-test serviceRegistryProbeForTest 2>/dev/null || true)
  if jq -e '.scanFinishedCount >= 2 and (.installed | index("acme.discovered-service")) != null and (.services | index("acme.discovered-service")) == null' <<<"$probe" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! jq -e '.scanFinishedCount >= 2 and (.installed | index("acme.discovered-service")) != null and (.services | index("acme.discovered-service")) == null' <<<"$probe" >/dev/null 2>&1; then
  printf 'new service discovery probe failed: %s\n' "$probe" >&2
  exit 1
fi

enable_result=$(ipc desktop-shell-test persistPluginStateForTest \
  '{"version":1,"barPluginId":"acme.integration-bar","enabledPlugins":[{"id":"acme.discovered-service"}]}' )
[[ $enable_result == saved || $enable_result == pending ]]
for _ in {1..150}; do
  probe=$(ipc desktop-shell-test serviceRegistryProbeForTest 2>/dev/null || true)
  if jq -e '.services | index("acme.discovered-service") != null' <<<"$probe" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! jq -e '(.services | index("acme.discovered-service")) != null and .created == 1' <<<"$probe" >/dev/null 2>&1; then
  printf 'service enable probe failed: %s\n' "$probe" >&2
  exit 1
fi

disable_result=$(ipc desktop-shell-test persistPluginStateForTest \
  '{"version":1,"barPluginId":"acme.integration-bar"}' )
[[ $disable_result == saved || $disable_result == pending ]]
for _ in {1..150}; do
  probe=$(ipc desktop-shell-test serviceRegistryProbeForTest 2>/dev/null || true)
  if jq -e '(.services | index("acme.discovered-service")) == null and .destroyed == 1' <<<"$probe" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! jq -e '(.services | index("acme.discovered-service")) == null and .destroyed == 1' <<<"$probe" >/dev/null 2>&1; then
  printf 'service disable probe failed: %s\n' "$probe" >&2
  exit 1
fi

printf 'PASS: actual service registry integration\n'
