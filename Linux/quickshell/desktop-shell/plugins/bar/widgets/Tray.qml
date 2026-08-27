import Quickshell
import QtQuick
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "TrayModel.js" as TrayModel

BarWidget {
  id: root
  moduleName: "desktop.tray"

  property var activeMenuAnchor: null
  readonly property bool expanded: drawerHover.hovered || activeMenuAnchor !== null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var drawerItems: bucket()
  readonly property int drawerCount: drawerItems.length
  readonly property int trayItemExtent: Style.bar.iconSlot
  readonly property int trayItemGap: 0
  readonly property int drawerExtent: drawerCount > 0
    ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap
    : 0
  readonly property int animationDuration: 600
  property real revealProgress: expanded ? 1 : 0
  readonly property real revealExtent: drawerExtent * revealProgress

  function bucket() {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      if (values[i].status !== Status.Passive) result.push(values[i])
    }
    return result
  }

  function trayTooltip(item) {
    return TrayModel.displayName(item)
  }

  function trayIconSource(icon) {
    return String(icon || "")
  }

  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  visible: drawerCount > 0
  clip: false
  implicitWidth: drawerCount > 0 ? drawerContent.implicitWidth : 0
  implicitHeight: drawerCount > 0 ? root.barSize : 0

  Behavior on revealProgress {
    enabled: root.activeMenuAnchor === null
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  Item {
    id: drawerContent
    width: drawerBlockWidth
    height: root.barSize
    implicitWidth: drawerBlockWidth
    implicitHeight: root.barSize

    readonly property int drawerBlockWidth: root.drawerCount > 0
      ? expandIcon.implicitWidth + root.drawerExtent
      : 0

    containmentMask: QtObject {
      function contains(point: point): bool {
        if (point.y < 0 || point.y > drawerContent.height) return false
        var chevronX = root.drawerExtent - root.revealExtent
        return point.x >= chevronX && point.x <= drawerContent.drawerBlockWidth
      }
    }

    HoverHandler {
      id: drawerHover
    }

    BarIconButton {
      id: expandIcon
      bar: root.bar
      width: implicitWidth
      height: implicitHeight
      x: root.drawerExtent - root.revealExtent
      text: "\uf053"
    }

    Item {
      id: trayClip
      x: expandIcon.width
      anchors.verticalCenter: parent.verticalCenter
      width: root.drawerExtent
      height: root.barSize
      clip: true

      Row {
        id: trayIcons
        x: root.drawerExtent - root.revealExtent
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayItemGap
        layer.enabled: true

        Repeater {
          model: root.drawerItems
          TrayItem {}
        }
      }
    }
  }

  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    property color tint: root.foreground
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Behavior on tint {
      ColorAnimation { duration: 160 }
    }

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon)
      visible: !trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: trayIconRoot.symbolic
      colorization: 1.0
      colorizationColor: trayIconRoot.tint
    }
  }

  component TrayItem: BorderSurface {
    id: trayItemRoot
    required property var modelData
    readonly property bool hot: mouseArea.containsMouse

    color: mouseArea.pressed
      ? Style.pressedFillFor(root.foreground, Color.accent)
      : (hot ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
    borderSpec: hot
      ? Border.controlSpec("hover-cursor", root.foreground, Color.accent)
      : Border.none()
    radius: Style.cornerRadius

    Behavior on color {
      ColorAnimation { duration: 120 }
    }

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0

    function displayMenu() {
      if (!trayMenu.menu) return
      root.activeMenuAnchor = trayMenu
      menuOpenTimer.restart()
    }

    Timer {
      id: menuOpenTimer
      interval: 0
      onTriggered: {
        trayMenu.open()
        if (!trayMenu.visible && root.activeMenuAnchor === trayMenu) root.activeMenuAnchor = null
      }
    }

    QsMenuAnchor {
      id: trayMenu
      menu: trayItemRoot.modelData.menu
      anchor.item: trayItemRoot
      anchor.edges: Edges.Bottom | Edges.Left
      anchor.gravity: Edges.Bottom | Edges.Right

      onVisibleChanged: {
        if (visible) root.activeMenuAnchor = trayMenu
        else if (root.activeMenuAnchor === trayMenu) root.activeMenuAnchor = null
      }
    }

    TrayIcon {
      anchors.centerIn: parent
      width: Style.space(16)
      height: Style.space(16)
      icon: trayItemRoot.modelData.icon
      tint: mouseArea.pressed
        ? Style.pressedStateColor(root.foreground, Color.accent)
        : (trayItemRoot.hot
          ? Style.hoverStateColor(root.foreground, Color.accent)
          : root.foreground)
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu()
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.modelData.onlyMenu || trayItemRoot.modelData.menu) {
          trayItemRoot.displayMenu()
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
