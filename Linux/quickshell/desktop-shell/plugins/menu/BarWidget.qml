import QtQuick
import Quickshell
import qs.Ui

BarWidget {
  id: root
  moduleName: "desktop.menu"

  function openRoot() {
    Quickshell.execDetached(["desktop-shell", "summon", "desktop.menu", "{\"menu\":\"root\"}"])
  }

  function openTerminal() {
    Quickshell.execDetached(["xdg-terminal-exec"])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u2630"
    horizontalMargin: 7.5

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openTerminal()
      else if (buttonCode === Qt.LeftButton) root.openRoot()
    }
  }
}
