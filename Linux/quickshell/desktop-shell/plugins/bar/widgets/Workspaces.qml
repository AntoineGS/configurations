import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
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
  readonly property var workspaceService: bar && bar.shell ? bar.shell.serviceFor("desktop.workspaces") : null
  readonly property var activeWorkspaceIds: workspaceService ? workspaceService.activeWorkspaceIds : ({})
  readonly property int activeWorkspaceId: workspaceService
    && workspaceService.activeWorkspaceIds[screenName] !== undefined
    ? workspaceService.activeWorkspaceIds[screenName] : -1

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

  ServiceConsumer {
    id: workspaceConsumer
    service: root.workspaceService
    active: true
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.workspaceGeneration++ }
  }

}
