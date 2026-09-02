import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "desktop.configuration-updates"

  readonly property var updates: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent

  function refresh() {
    if (updates) updates.refresh()
  }

  function openGit() {
    Quickshell.execDetached(["launch-tui-large", "desktop-shell-configuration-updates", "git"])
  }

  function openTidydots() {
    Quickshell.execDetached(["launch-tui-large", "desktop-shell-configuration-updates", "tidydots"])
  }

  visible: updates && (updates.gitVisible || updates.tidydotsVisible)
  implicitWidth: visible ? icons.implicitWidth : 0
  implicitHeight: visible ? icons.implicitHeight : 0

  Row {
    id: icons

    BarIconButton {
      bar: root.bar
      text: root.updates && root.updates.gitVisible ? "󰊢" : ""
      foreground: root.updates && (root.updates.gitState === "blocked" || root.updates.gitState === "error")
        ? root.urgent : root.foreground
      tooltipText: root.updates
        ? root.updates.gitTooltip + "\nLeft click: open Lazygit\nRight click: refresh"
        : ""

      onPressed: function(buttonCode) {
        if (Number(buttonCode) === Number(Qt.LeftButton)) root.openGit()
        else if (Number(buttonCode) === Number(Qt.RightButton)) root.refresh()
      }
    }

    BarIconButton {
      bar: root.bar
      text: root.updates && root.updates.tidydotsVisible ? "󰃢" : ""
      foreground: root.updates && root.updates.tidydotsState === "error" ? root.urgent : root.foreground
      active: root.updates && root.updates.tidydotsState === "actionable"
      tooltipText: root.updates
        ? root.updates.tidydotsTooltip + "\nLeft click: open Tidydots actions\nRight click: refresh"
        : ""

      onPressed: function(buttonCode) {
        if (Number(buttonCode) === Number(Qt.LeftButton)) root.openTidydots()
        else if (Number(buttonCode) === Number(Qt.RightButton)) root.refresh()
      }
    }
  }
}
