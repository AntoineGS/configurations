import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
  id: root

  property bool opened: false
  property var model: null
  property string fontFamily: Style.font.family
  property int selectedIndex: 0

  signal closeRequested()
  signal activationRequested(int index)

  visible: root.opened || historyColumn.opacity > 0
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  mask: Region { item: root.opened ? inputRegion : null }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-notification-history"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  function select(delta) {
    var count = root.model ? root.model.count : 0
    if (count <= 0) return
    root.selectedIndex = (root.selectedIndex + delta + count) % count
    Qt.callLater(function() {
      historyList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function activateSelected() {
    if (root.model && root.model.count > 0) root.activationRequested(root.selectedIndex)
  }

  onOpenedChanged: {
    if (!opened) {
      keyCatcher.focus = false
      return
    }
    selectedIndex = 0
    keyCatcher.focus = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  readonly property real availableHeight: Math.max(0, root.height - Style.gapsOut * 2)
  readonly property real cardWidth: Math.min(Style.space(380), Math.max(0, root.width - Style.gapsOut * 2))
  readonly property bool showHeader: root.availableHeight >= historyHeader.implicitHeight + Style.space(8)
  readonly property bool showFooter: root.availableHeight >= historyHeader.implicitHeight
    + historyFooter.implicitHeight + Style.space(48)
  readonly property real chromeHeight: (historyHeader.visible ? historyHeader.implicitHeight : 0)
    + (historyFooter.visible ? historyFooter.implicitHeight : 0)
    + (historyHeader.visible || historyFooter.visible ? Style.space(8) : 0)
    + (historyHeader.visible && historyFooter.visible ? Style.space(8) : 0)
  readonly property real emptyStateHeight: !root.model || root.model.count === 0
    ? Math.min(Math.max(Style.space(48), emptyStateLabel.implicitHeight + Style.space(16)),
      Math.max(0, root.availableHeight - root.chromeHeight)) : 0
  readonly property real listViewportHeight: Math.max(
    0, Math.min(Math.max(historyList.contentHeight, root.emptyStateHeight),
      root.availableHeight - root.chromeHeight)
  )

  Item {
    id: inputRegion
    anchors.fill: parent
  }

  Rectangle {
    anchors.fill: parent
    color: Color.modal.scrim
    opacity: root.opened ? 1 : 0
    enabled: root.opened
    Behavior on opacity { NumberAnimation { duration: 140 } }

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: false
    enabled: root.opened
    Keys.priority: Keys.BeforeItem

    Keys.onPressed: function(event) {
      var control = event.modifiers & Qt.ControlModifier
      if (control && event.key === Qt.Key_J) {
        root.select(1); event.accepted = true
      } else if (control && event.key === Qt.Key_K) {
        root.select(-1); event.accepted = true
      } else if (event.key === Qt.Key_Down) {
        root.select(1); event.accepted = true
      } else if (event.key === Qt.Key_Up) {
        root.select(-1); event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.activateSelected(); event.accepted = true
      } else if (event.key === Qt.Key_Escape) {
        root.closeRequested(); event.accepted = true
      }
    }
  }

  ColumnLayout {
    id: historyColumn
    width: root.cardWidth
    height: Math.min(root.availableHeight, root.chromeHeight + root.listViewportHeight)
    anchors.centerIn: parent
    opacity: root.opened ? 1 : 0
    enabled: root.opened
    z: 1
    spacing: Style.space(8)

    Behavior on opacity { NumberAnimation { duration: 140 } }

    Text {
      id: historyHeader
      Layout.fillWidth: true
      visible: root.showHeader
      text: "NOTIFICATIONS  " + String(root.model ? root.model.count : 0)
      color: Color.notifications.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: Style.spaceReal(0.8)
      horizontalAlignment: Text.AlignHCenter
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: root.listViewportHeight
      Layout.minimumHeight: root.listViewportHeight
      Layout.maximumHeight: root.listViewportHeight
      clip: true

      ListView {
        id: historyList
        anchors.fill: parent
        model: root.model
        clip: true
        spacing: Style.space(8)
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
          id: cardSlot
          required property int index
          required property string app
          required property string appIcon
          required property string summary
          required property string body
          required property string image
          required property int urgency
          required property double timestamp
          required property bool actionAvailable

          width: ListView.view.width
          height: card.implicitHeight

          NotificationCard {
            id: card
            anchors.fill: parent
            app: cardSlot.app
            appIcon: cardSlot.appIcon
            summary: cardSlot.summary
            body: cardSlot.body
            image: cardSlot.image
            urgency: cardSlot.urgency
            timestamp: cardSlot.timestamp
            actions: []
            fontFamily: root.fontFamily
            historyMode: true
            keyboardSelected: index === root.selectedIndex
            actionAvailable: cardSlot.actionAvailable
            onCardClicked: {
              root.selectedIndex = index
              root.activationRequested(index)
            }
          }
        }
      }

      Text {
        id: emptyStateLabel
        anchors.centerIn: parent
        visible: !root.model || root.model.count === 0
        text: "No notification history"
        color: Color.notifications.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    Text {
      id: historyFooter
      Layout.fillWidth: true
      visible: root.showFooter
      text: "UP/DOWN or CTRL+J/K  •  ENTER TO OPEN  •  ESC TO CLOSE"
      color: Color.notifications.text
      opacity: 0.72
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }
}
