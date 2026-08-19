#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"
ROLLBACK_HELPER="$ROOT/Linux/os/helpers/desktop-shell-rollback"
SELECTED_PLUGINS="$SHELL_ROOT/SELECTED_PLUGINS"

grep -Fxq 'commit=7be59e1f4b7451d352d4673c560168290792590f' "$SHELL_ROOT/SOURCE"
grep -Fq 'Copyright (c) David Heinemeier Hansson' "$SHELL_ROOT/LICENSE.omarchy"
grep -Fxq 'selected_polkit_paths=shell/plugins/polkit/manifest.json shell/plugins/polkit/PolkitAgent.qml shell/plugins/polkit/PolkitModel.js' \
  "$SHELL_ROOT/SOURCE"
grep -Fxq 'desktop.polkit|omarchy.polkit|shell/plugins/polkit/manifest.json shell/plugins/polkit/PolkitAgent.qml shell/plugins/polkit/PolkitModel.js' \
  "$SELECTED_PLUGINS"

for path in \
  shell.qml \
  Commons/Color.qml Commons/Style.qml Commons/Util.qml Commons/Border.qml Commons/BorderGeometry.js Commons/qmldir \
  Ui/qmldir Ui/BarWidget.qml Ui/BarIconButton.qml Ui/BarIndicator.qml Ui/Panel.qml Ui/PanelController.qml \
  services/PluginRegistry.qml services/BarWidgetRegistry.qml; do
  test -f "$SHELL_ROOT/$path"
done

runtime_paths=("$SHELL_ROOT/shell.qml" "$SHELL_ROOT/Commons" "$SHELL_ROOT/Ui" "$SHELL_ROOT/services")
for optional in plugins config; do
  [[ ! -e "$SHELL_ROOT/$optional" ]] || runtime_paths+=("$SHELL_ROOT/$optional")
done

if grep -RInE 'OMARCHY_PATH|omarchy-shell|omarchy-[[:alnum:]_-]+|org\.omarchy|\.config/omarchy|\.local/state/omarchy' \
  "${runtime_paths[@]}" --exclude=SOURCE --exclude=LICENSE.omarchy --exclude='*.md'; then
  echo 'active Omarchy runtime reference found' >&2
  exit 1
fi

rollback_source=$(<"$ROLLBACK_HELPER")
grep -Fq -- "readonly MAKO_INPUT=\"\${DESKTOP_SHELL_MAKO:-/usr/bin/mako}\"" <<<"$rollback_source"
grep -Fq -- "readonly SWAYOSD_SERVER_INPUT=\"\${DESKTOP_SHELL_SWAYOSD_SERVER:-/usr/bin/swayosd-server}\"" <<<"$rollback_source"
grep -Fq -- "readlink -f -- \"/proc/\$pid/exe\"" <<<"$rollback_source"
grep -Fq -- 'local -a revoke_command=(pkcheck --revoke-temp)' <<<"$rollback_source"
grep -Fq -- 'pkcheck -a org.freedesktop.policykit.exec' <<<"$rollback_source"
grep -Fq -- '((probe_status == 124))' <<<"$rollback_source"
if grep -Fq -- '-d program' <<<"$rollback_source"; then
  printf '%s\n' 'rollback polkit probe must remain noninteractive' >&2
  exit 1
fi
grep -Fq -- 'timeout --signal=TERM --kill-after=1s' <<<"$rollback_source"
if grep -Fq -- 'query_named_pids' <<<"$rollback_source" ||
  grep -Fq -- "\${executable##*/}" <<<"$rollback_source" ||
  grep -Fq -- 'pkill' <<<"$rollback_source"; then
  printf '%s\n' 'unsafe rollback process matching found' >&2
  exit 1
fi
