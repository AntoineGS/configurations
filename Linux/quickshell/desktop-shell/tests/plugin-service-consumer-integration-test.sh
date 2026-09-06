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

if [[ ${DESKTOP_SHELL_CONSUMER_INTEGRATION_TIMEOUT_GUARD:-} != 1 ]]; then
  exec env DESKTOP_SHELL_CONSUMER_INTEGRATION_TIMEOUT_GUARD=1 \
    timeout --foreground --kill-after=2s 45s bash "$0" "$@"
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
fixture_dir="$shell_dir/tests/fixtures/plugin-registry"
tmp_dir=$(mktemp -d)
shell_pid=""

print_log() {
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line"
  done <"$tmp_dir/quickshell.log"
}

cleanup() {
  if [[ -n $shell_pid ]]; then
    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
  fi
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

isolated_shell_dir="$tmp_dir/desktop-shell"
plugins_dir="$tmp_dir/plugins"
bar_plugin_dir="$plugins_dir/acme.two-consumer-bar"
discovered_plugin_dir="$plugins_dir/acme.discovered-service"
state_file="$tmp_dir/state/shell.json"
config_file="$isolated_shell_dir/config/shell.json"
bin_dir="$tmp_dir/bin"
state_home="$tmp_dir/state-home"
runtime_dir="$tmp_dir/runtime"
host_runtime_dir="${XDG_RUNTIME_DIR:-}"
wayland_display="${WAYLAND_DISPLAY:-wayland-0}"
vm_state="$tmp_dir/vm-state"
vm_watcher_mode="$tmp_dir/vm-watcher-mode"
vm_watcher_log="$tmp_dir/vm-watcher.log"

mkdir -p -- "$bar_plugin_dir" "$tmp_dir/state" "$bin_dir" "$state_home" "$runtime_dir"
chmod 0700 -- "$runtime_dir"
qt_platform=offscreen
if [[ -S "$host_runtime_dir/$wayland_display" ]]; then
  ln -s -- "$host_runtime_dir/$wayland_display" "$runtime_dir/$wayland_display"
  qt_platform=wayland
fi
cp -a -- "$shell_dir" "$isolated_shell_dir"
rm -rf -- "$isolated_shell_dir/plugins/notifications" "$isolated_shell_dir/plugins/polkit" \
  "$isolated_shell_dir/plugins/services/battery"
cp -- "$fixture_dir/two-consumer-bar/manifest.json" "$bar_plugin_dir/manifest.json"
cp -- "$fixture_dir/two-consumer-bar/Bar.qml" "$bar_plugin_dir/Bar.qml"
cp -- "$shell_dir/tests/fixtures/vm/fake-virsh" "$bin_dir/virsh"
cp -- "$shell_dir/tests/fixtures/vm/fake-state" "$bin_dir/desktop-hardware-state"
cp -- "$shell_dir/tests/fixtures/vm/fake-df" "$bin_dir/df"
chmod 0755 -- "$bin_dir/virsh" "$bin_dir/desktop-hardware-state" "$bin_dir/df"
: >"$vm_watcher_log"
printf '%s\n' running-missing >"$vm_state"
printf '%s\n' stable >"$vm_watcher_mode"
printf '%s\n' '{"version":1,"bar":{"id":"desktop.bar","position":"top","layout":{"left":[],"center":[],"right":[]}},"plugins":[],"disabledPlugins":["desktop.agents","desktop.audio","desktop.bluetooth","desktop.configuration-updates","desktop.disk","desktop.monitor","desktop.network","desktop.power","desktop.recording","desktop.tailscale","desktop.workspaces"]}' >"$config_file"
printf '%s\n' '{"version":1,"barPluginId":"acme.two-consumer-bar"}' >"$state_file"

env PATH="$bin_dir:$PATH" \
  HOME="$tmp_dir/home" XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  XDG_STATE_HOME="$state_home" XDG_RUNTIME_DIR="$runtime_dir" \
  WAYLAND_DISPLAY="$wayland_display" QT_QPA_PLATFORM="$qt_platform" \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  DESKTOP_SHELL_TEST_ALLOW_PLUGIN_STATE_MUTATION=1 \
  DESKTOP_SHELL_TEST_LOAD_SERVICES=1 \
  DESKTOP_SHELL_TEST_LOAD_PLUGIN_BAR=1 \
  DESKTOP_SHELL_DISABLE_PLUGIN_WATCH=1 \
  DESKTOP_SHELL_STATE_PATH="$state_file" \
  DESKTOP_SHELL_PLUGINS_DIR="$plugins_dir" \
  VM_FIXTURE_STATE="$vm_state" \
  VM_FIXTURE_WATCHER_MODE="$vm_watcher_mode" \
  VM_FIXTURE_WATCHER_LOG="$vm_watcher_log" \
  quickshell -n -p "$isolated_shell_dir" >"$tmp_dir/quickshell.log" 2>&1 &
shell_pid=$!

ipc() {
  XDG_RUNTIME_DIR="$runtime_dir" quickshell ipc --pid "$shell_pid" call -- "$@"
}

for _ in {1..150}; do
  probe=$(ipc desktop-shell health 2>/dev/null || true)
  if jq -e '.scanFinishedCount == 1' <<<"$probe" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! jq -e '.scanFinishedCount == 1' <<<"$probe" >/dev/null 2>&1; then
  printf 'initial registry scan did not finish: %s\n' "$probe" >&2
  print_log >&2
  exit 1
fi
[[ $(ipc desktop-shell rescanPlugins) == ok ]]

probe=""
wait_for_probe() {
  local filter=$1
  for _ in {1..150}; do
    probe=$(ipc desktop-shell-test serviceRegistryProbeForTest 2>/dev/null || true)
    # The jq expression deliberately uses jq's named argument rather than shell expansion.
    # shellcheck disable=SC2016
    if jq -e --argjson expected "$expected_services" "$filter" <<<"$probe" >/dev/null 2>&1; then return 0; fi
    sleep 0.1
  done
  return 1
}

expected_services='["desktop.host-metrics","desktop.vm"]'
if ! wait_for_probe \
  ".scanFinishedCount >= 2 and .services == \$expected and .barLoaded == true
   and .vmConsumersAttached == true and .vmConsumersShareSample == true
   and .vmSampleAvailable == true and .vmCollecting == true and .vmWatcherCount == 1"; then
  printf 'initial two-consumer probe failed: %s\n' "$probe" >&2
  print_log >&2
  exit 1
fi

for _ in {1..100}; do
  [[ -s $vm_watcher_log ]] && break
  sleep 0.1
done
if [[ $(wc -l <"$vm_watcher_log") -ne 1 ]]; then
  printf 'expected one VM watcher, got %s\n' "$(wc -l <"$vm_watcher_log")" >&2
  print_log >&2
  exit 1
fi

[[ $(ipc desktop-shell-test setIntegrationVmSecondaryConsumerActiveForTest false) == ok ]]
if ! wait_for_probe '.vmConsumerCount == 1 and .vmCollecting == true and .vmWatcherCount == 1'; then
  printf 'retained-demand probe failed: %s\n' "$probe" >&2
  print_log >&2
  exit 1
fi

[[ $(ipc desktop-shell-test setIntegrationVmSecondaryConsumerActiveForTest true) == ok ]]
if ! wait_for_probe '.vmConsumerCount == 2 and .vmConsumersShareSample == true and .vmCollecting == true'; then
  printf 'consumer reattachment probe failed: %s\n' "$probe" >&2
  print_log >&2
  exit 1
fi

mkdir -p -- "$discovered_plugin_dir"
cp -- "$fixture_dir/discovered-service/manifest.json" "$discovered_plugin_dir/manifest.json"
cp -- "$fixture_dir/discovered-service/Service.qml" "$discovered_plugin_dir/Service.qml"
[[ $(ipc desktop-shell rescanPlugins) == ok ]]
if ! wait_for_probe '.scanFinishedCount >= 2 and (.installed | index("acme.discovered-service")) != null
  and (.services | index("acme.discovered-service")) == null'; then
  printf 'hotplug discovery probe failed: %s\n' "$probe" >&2
  print_log >&2
  exit 1
fi

enable_result=$(ipc desktop-shell-test persistPluginStateForTest \
  '{"version":1,"barPluginId":"acme.two-consumer-bar","enabledPlugins":[{"id":"acme.discovered-service"}]}' )
[[ $enable_result == saved || $enable_result == pending ]]
if ! wait_for_probe '.hotplugConsumerAttached == true and .hotplugCollecting == true and .created == 1'; then
  printf 'hotplug attach probe failed: %s\n' "$probe" >&2
  print_log >&2
  exit 1
fi

disable_result=$(ipc desktop-shell-test persistPluginStateForTest \
  '{"version":1,"barPluginId":"acme.two-consumer-bar"}' )
[[ $disable_result == saved || $disable_result == pending ]]
if ! wait_for_probe '.hotplugConsumerAttached == false and (.services | index("acme.discovered-service")) == null
  and .destroyed == 1'; then
  printf 'hotplug detach probe failed: %s\n' "$probe" >&2
  print_log >&2
  exit 1
fi

reenable_result=$(ipc desktop-shell-test persistPluginStateForTest \
  '{"version":1,"barPluginId":"acme.two-consumer-bar","enabledPlugins":[{"id":"acme.discovered-service"}]}' )
[[ $reenable_result == saved || $reenable_result == pending ]]
if ! wait_for_probe '.hotplugConsumerAttached == true and .hotplugCollecting == true
  and .created == 2 and .destroyed == 1'; then
  printf 'hotplug replacement probe failed: %s\n' "$probe" >&2
  print_log >&2
  exit 1
fi

printf 'PASS: actual two-consumer service integration\n'
