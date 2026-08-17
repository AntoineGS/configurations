#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"
INVENTORY="$SHELL_ROOT/SELECTED_PLUGINS"
UPSTREAM_REPO="${OMARCHY_REPO:-/home/antoinegs/gits/omarchy}"
COMMIT=7be59e1f4b7451d352d4673c560168290792590f

fail() {
  printf 'selected-plugins-test: %s\n' "$1" >&2
  exit 1
}

[[ -f $INVENTORY ]] || fail 'SELECTED_PLUGINS is absent'
git -C "$UPSTREAM_REPO" cat-file -e "$COMMIT^{commit}" 2>/dev/null || fail 'pinned Omarchy commit is unavailable'

expected_ids=(desktop.audio desktop.network desktop.bluetooth desktop.power desktop.monitor desktop.tailscale desktop.battery desktop.notifications desktop.osd)
declare -A upstream_ids=(
  [desktop.audio]=omarchy.audio
  [desktop.network]=omarchy.network
  [desktop.bluetooth]=omarchy.bluetooth
  [desktop.power]=omarchy.power
  [desktop.monitor]=omarchy.monitor
  [desktop.tailscale]=omarchy.tailscale
  [desktop.battery]=omarchy.battery
  [desktop.notifications]=omarchy.notifications
  [desktop.osd]=omarchy.osd
)
declare -A source_sets=(
  [desktop.audio]='shell/plugins/panels/audio/manifest.json shell/plugins/panels/audio/Panel.qml shell/plugins/panels/audio/Model.js'
  [desktop.network]='shell/plugins/panels/network/manifest.json shell/plugins/panels/network/Panel.qml shell/plugins/panels/network/Model.js'
  [desktop.bluetooth]='shell/plugins/panels/bluetooth/manifest.json shell/plugins/panels/bluetooth/Panel.qml shell/plugins/panels/bluetooth/Model.js'
  [desktop.power]='shell/plugins/panels/power/manifest.json shell/plugins/panels/power/Panel.qml shell/plugins/panels/power/Model.js'
  [desktop.monitor]='shell/plugins/panels/monitor/manifest.json shell/plugins/panels/monitor/Panel.qml shell/plugins/panels/monitor/Model.js'
  [desktop.tailscale]='shell/plugins/panels/tailscale/manifest.json shell/plugins/panels/tailscale/Panel.qml shell/plugins/panels/tailscale/Model.js shell/plugins/panels/tailscale/Service.qml shell/plugins/panels/tailscale/TailscaleIcon.qml'
  [desktop.battery]='shell/plugins/services/battery/manifest.json shell/plugins/services/battery/Service.qml shell/plugins/services/battery/BatteryModel.js'
  [desktop.notifications]='shell/plugins/notifications/manifest.json shell/plugins/notifications/Service.qml shell/plugins/notifications/NotificationLogic.js shell/plugins/notifications/components/NotificationCard.qml'
  [desktop.osd]='shell/plugins/osd/manifest.json shell/plugins/osd/Osd.qml shell/plugins/osd/OsdModel.js'
)

actual_ids=()
while IFS='|' read -r neutral_id upstream_id source_list; do
  [[ -n $neutral_id && ${neutral_id:0:1} != '#' ]] || continue
  [[ -v upstream_ids[$neutral_id] ]] || fail "unexpected plugin ID: $neutral_id"
  [[ $upstream_id == "${upstream_ids[$neutral_id]}" ]] || fail "$neutral_id has incorrect upstream ID"
  [[ $source_list == "${source_sets[$neutral_id]}" ]] || fail "$neutral_id has an incomplete or unexpected source set"
  actual_ids+=("$neutral_id")

  read -r -a sources <<<"$source_list"
  manifest=${sources[0]}
  manifest_id=$(git -C "$UPSTREAM_REPO" show "$COMMIT:$manifest" | jq -er '.id') || fail "$neutral_id manifest is invalid"
  [[ $manifest_id == "$upstream_id" ]] || fail "$neutral_id manifest ID does not match its mapping"
  for source in "${sources[@]}"; do
    git -C "$UPSTREAM_REPO" cat-file -e "$COMMIT:$source" 2>/dev/null || fail "missing pinned source: $source"
    grep -Fq "$source" "$SHELL_ROOT/SOURCE" || fail "SOURCE omits $source"
  done
done <"$INVENTORY"

[[ ${actual_ids[*]} == "${expected_ids[*]}" ]] || fail 'selected plugin IDs are missing, duplicated, or out of order'

excluded=(weather media reminders clipboard emojis image-picker wifiqr speedtest disk-speedtest dropbox fireworks)
for name in "${excluded[@]}"; do
  if grep -Fiq "$name" "$INVENTORY"; then
    fail "excluded source listed: $name"
  fi
done

printf 'selected-plugins-test: nine pinned plugin source sets verified\n'
