import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "EmptyWorkspaceBorderModel.js" as BorderModel

Item {
  id: root

  property bool surfaceAllowed: false
  // Hyprland Lua sessions can leave Quickshell's monitor focus/workarea fields unset.
  // Query monitor metadata on events; keep the native workspace model for app counts.
  property var monitorSnapshot: []
  property int workspaceGeneration: 0
  property bool refreshPending: false

  function monitorFor(screenName) {
    for (var i = 0; i < monitorSnapshot.length; i++) {
      var snapshot = monitorSnapshot[i]
      if (snapshot.name !== screenName) continue
      if (!Number.isFinite(snapshot.scale) || snapshot.scale <= 0) return null
      return {
        name: snapshot.name,
        focused: snapshot.focused,
        activeWorkspace: snapshot.activeWorkspace,
        width: snapshot.width / snapshot.scale,
        height: snapshot.height / snapshot.scale,
        lastIpcObject: snapshot
      }
    }
    return null
  }

  function workspaceFor(id) {
    workspaceGeneration
    if (!Number.isInteger(id) || id <= 0) return null
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function refreshSnapshot() {
    if (!surfaceAllowed) return
    if (monitorQuery.running) {
      refreshPending = true
      return
    }
    monitorQuery.running = true
  }

  onSurfaceAllowedChanged: {
    if (surfaceAllowed) refreshDelay.restart()
    else monitorSnapshot = []
  }

  Timer {
    id: refreshDelay
    interval: 50
    onTriggered: root.refreshSnapshot()
  }

  Process {
    id: monitorQuery
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector { id: monitorOutput; waitForEnd: true }

    onExited: function(exitCode) {
      var next = []
      if (exitCode === 0) {
        try {
          var parsed = JSON.parse(monitorOutput.text)
          if (Array.isArray(parsed)) next = parsed
        } catch (error) {
          console.warn("empty-workspace focus border: monitor snapshot unavailable:", error)
        }
      }
      root.monitorSnapshot = next
      if (root.refreshPending) {
        root.refreshPending = false
        refreshDelay.restart()
      }
    }
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.workspaceGeneration++ }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.surfaceAllowed) return
      var name = String(event.name || "")
      if ((name === "openlayer" || name === "closelayer")
          && String(event.data || "") === "desktop-shell-empty-workspace-focus") return
      if (name === "focusedmon" || name === "focusedmonv2"
          || name === "workspace" || name === "workspacev2"
          || name === "moveworkspace" || name === "moveworkspacev2"
          || name === "monitoradded" || name === "monitoraddedv2"
          || name === "monitorremoved" || name === "monitorremovedv2"
          || name === "openlayer" || name === "closelayer") {
        root.monitorSnapshot = []
        refreshDelay.restart()
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: panel
        required property var modelData

        property int windowGeneration: 0
        readonly property var monitor: root.monitorFor(modelData.name)
        readonly property var workspace: root.workspaceFor(monitor && monitor.activeWorkspace
          ? monitor.activeWorkspace.id : -1)
        readonly property var borderFrame: {
          windowGeneration
          var values = workspace && workspace.toplevels ? workspace.toplevels.values : null
          return BorderModel.frame(modelData.name, monitor, values ? values.length : undefined)
        }

        screen: modelData
        visible: root.surfaceAllowed && borderFrame !== null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "desktop-shell-empty-workspace-focus"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Rectangle {
          x: panel.borderFrame ? panel.borderFrame.x : 0
          y: panel.borderFrame ? panel.borderFrame.y : 0
          width: panel.borderFrame ? panel.borderFrame.width : 0
          height: panel.borderFrame ? panel.borderFrame.height : 0
          color: "transparent"
          border.width: 1
          border.color: "#cba6f7"
        }

        Connections {
          target: panel.workspace && panel.workspace.toplevels ? panel.workspace.toplevels : null
          function onValuesChanged() { panel.windowGeneration++ }
        }
      }
    }
  }
}
