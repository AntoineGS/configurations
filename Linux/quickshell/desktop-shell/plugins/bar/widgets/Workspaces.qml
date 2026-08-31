import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "WorkspacesModel.js" as WorkspacesModel

BarWidget {
  id: root
  moduleName: "desktop.workspaces"
  readonly property var window: root.QsWindow.window
  readonly property string screenName: window && window.screen ? String(window.screen.name || "") : ""
  readonly property var labels: root.setting("labels", ({}))
  property int workspaceGeneration: 0
  property int activeWorkspaceId: -1
  property bool activeRefreshQueued: false
  property int activeRefreshGeneration: 0
  property int activeRefreshFinalizedGeneration: 0

  function workspaceById(id) {
    workspaceGeneration
    var values = WorkspacesModel.objectModelValues(Hyprland.workspaces.values)
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = []
    workspaceGeneration
    var values = WorkspacesModel.objectModelValues(Hyprland.workspaces.values)

    for (var i = 0; i < values.length; i++) {
      var workspace = values[i]
      if (!workspace || !workspace.monitor || workspace.monitor.name !== root.screenName) continue
      var id = workspace.id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function workspaceLabel(id, workspace) {
    var configured = labels[String(id)]
    if (configured !== undefined && configured !== null && String(configured) !== "") return String(configured)
    if (workspace && workspace.name) return String(workspace.name)
    return id === 10 ? "0" : String(id)
  }

  function focusWorkspace(id) {
    Hyprland.dispatch("hl.dsp.focus({workspace=" + String(id) + "})")
  }

  function refreshActiveWorkspace() {
    if (!screenName) return
    if (activeWorkspaceProcess.running
        || activeRefreshGeneration > activeRefreshFinalizedGeneration) {
      activeRefreshQueued = true
      return
    }
    activeRefreshGeneration++
    activeRefreshStartCheck.generation = activeRefreshGeneration
    activeWorkspaceProcess.running = true
  }

  function queueActiveWorkspaceRefresh() {
    activeRefreshDebounce.restart()
  }

  function finishActiveRefresh(exitCode) {
    if (activeRefreshFinalizedGeneration === activeRefreshGeneration) return
    activeRefreshFinalizedGeneration = activeRefreshGeneration
    activeRefreshStartCheck.stop()
    if (Number(exitCode) === 0) {
      try {
        activeWorkspaceId = WorkspacesModel.confirmedActiveWorkspaceId(
          activeWorkspaceId, JSON.parse(activeWorkspaceStdout.text || "[]"), screenName)
      } catch (error) {
        // Keep the last confirmed workspace when Hyprland returns an incomplete snapshot.
      }
    }
    if (activeRefreshQueued) {
      activeRefreshQueued = false
      Qt.callLater(root.refreshActiveWorkspace)
    }
  }

  function isWorkspaceEvent(name) {
    return name === "workspace" || name === "workspacev2"
      || name === "focusedmon" || name === "focusedmonv2"
      || name === "monitoradded" || name === "monitoraddedv2"
      || name === "monitorremoved" || name === "monitorremovedv2"
      || name === "moveworkspace" || name === "moveworkspacev2"
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: modelData === root.activeWorkspaceId
        readonly property string displayName: root.workspaceLabel(modelData, workspace)

        bar: root.bar
        text: displayName
        active: focused
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : -1
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }

  Process {
    id: activeWorkspaceProcess
    command: ["hyprctl", "-j", "monitors", "all"]
    stdout: StdioCollector {
      id: activeWorkspaceStdout
      waitForEnd: true
    }
    onStarted: activeRefreshStartCheck.stop()
    onExited: function(exitCode) { root.finishActiveRefresh(exitCode) }
    onRunningChanged: {
      if (!running && root.activeRefreshGeneration > root.activeRefreshFinalizedGeneration) {
        activeRefreshStartCheck.generation = root.activeRefreshGeneration
        activeRefreshStartCheck.restart()
      }
    }
  }

  Timer {
    id: activeRefreshStartCheck
    property int generation: 0
    interval: 100
    onTriggered: {
      if (!activeWorkspaceProcess.running && generation === root.activeRefreshGeneration)
        root.finishActiveRefresh(1)
    }
  }

  Timer {
    id: activeRefreshDebounce
    interval: 50
    onTriggered: root.refreshActiveWorkspace()
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.workspaceGeneration++ }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.isWorkspaceEvent(String(event.name || ""))) return
      root.workspaceGeneration++
      root.queueActiveWorkspaceRefresh()
    }
  }

  onScreenNameChanged: {
    if (!screenName) activeWorkspaceId = -1
    else queueActiveWorkspaceRefresh()
  }
  Component.onCompleted: refreshActiveWorkspace()
}
