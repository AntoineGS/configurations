import QtQuick
import Quickshell
import Quickshell.Hyprland
import "plugins/panels/monitor/Model.js" as Model

Item {
  id: root
  property int topologyChanges: 0

  readonly property var nativeTopology: Model.normalizeMonitors(
    topologyGeneration >= 0 && Hyprland.monitors ? Hyprland.monitors.values : [], Hyprland.focusedMonitor)
  property int topologyGeneration: 0

  function refreshTopology() { topologyGeneration++ }

  Connections {
    target: Hyprland.monitors
    function onValuesChanged() {
      root.topologyChanges++
      root.refreshTopology()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() {
      root.topologyChanges++
      root.refreshTopology()
    }
  }

  Timer {
    interval: 500
    repeat: false
    running: true
    onTriggered: Hyprland.refreshMonitors()
  }

  Timer {
    interval: 2500
    repeat: false
    running: true
    onTriggered: {
      if (root.nativeTopology.monitors.length > 0) {
        console.log("Monitor native topology fixture passed", root.nativeTopology.monitors.length,
          root.nativeTopology.focusedMonitor, root.topologyChanges)
        Qt.exit(0)
      } else {
        console.error("Monitor native topology fixture failed", root.nativeTopology.monitors.length,
          root.topologyChanges)
        Qt.exit(1)
      }
    }
  }
}
