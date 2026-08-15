#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"

grep -Fxq 'commit=7be59e1f4b7451d352d4673c560168290792590f' "$SHELL_ROOT/SOURCE"
grep -Fq 'Copyright (c) David Heinemeier Hansson' "$SHELL_ROOT/LICENSE.omarchy"

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
