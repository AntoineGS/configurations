import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

TopBarOverlay {
  id: root

  property var model: null
  property string fontFamily: Style.font.family
  property int selectedIndex: 0

  readonly property int modelCount: root.model ? root.model.count : 0
  readonly property real focusedCardWidth: Math.min(Style.space(380),
    Math.max(Style.space(220), root.bodyWidth * 0.56))
  signal closeRequested()
  signal activationRequested(int index)

  overlayId: "desktop.notification-history"
  layerNamespace: "desktop-notification-history"
  requestedCardWidth: Style.centeredMenuWidth(Style.space(760), width - Style.gapsOut * 2)
  requestedCardHeight: Style.space(300)
  headerHeight: Style.space(24)
  contentSpacing: Style.space(10)
  onDismissRequested: root.closeRequested()

  function clampIndex(index) {
    if (root.modelCount <= 0) return 0
    return Math.max(0, Math.min(root.modelCount - 1, Number(index) || 0))
  }

  function positionSelected() {
    if (!root.opened || root.modelCount <= 0) return
    Qt.callLater(function() {
      if (!root.opened || root.modelCount <= 0) return
      historyList.positionViewAtIndex(root.selectedIndex, ListView.Center)
    })
  }

  function select(delta) {
    if (root.modelCount <= 0) return
    var next = root.clampIndex(root.selectedIndex + delta)
    if (next === root.selectedIndex) return
    root.selectedIndex = next
    root.positionSelected()
  }

  function activateSelected() {
    if (root.modelCount > 0) root.activationRequested(root.selectedIndex)
  }

  onOpenedChanged: {
    if (!root.opened) return
    root.selectedIndex = 0
    root.positionSelected()
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  onModelCountChanged: {
    var next = root.clampIndex(root.selectedIndex)
    if (next !== root.selectedIndex) root.selectedIndex = next
    if (root.modelCount > 0) root.positionSelected()
  }

  headerData: Text {
    width: parent.width
    height: Style.space(24)
    text: "NOTIFICATIONS  " + root.modelCount
    color: Color.notifications.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: Style.spaceReal(0.8)
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  Item {
    id: body
    anchors.fill: parent

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.opened
      enabled: root.opened
      Keys.priority: Keys.BeforeItem

      Keys.onPressed: function(event) {
        var control = event.modifiers & Qt.ControlModifier
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up
            || (control && event.key === Qt.Key_K)) {
          root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down
            || (control && event.key === Qt.Key_J)) {
          root.select(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.closeRequested()
          event.accepted = true
        }
      }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true

        ListView {
          id: historyList
          anchors.fill: parent
          orientation: ListView.Horizontal
          model: root.model
          spacing: Style.space(12)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: false
          currentIndex: root.selectedIndex
          highlightFollowsCurrentItem: true
          highlightMoveDuration: Motion.enabled ? Motion.spatialDuration : 0
          preferredHighlightBegin: (width - root.focusedCardWidth) / 2
          preferredHighlightEnd: preferredHighlightBegin + root.focusedCardWidth
          highlightRangeMode: ListView.StrictlyEnforceRange
          header: Item { width: Math.max(0, (historyList.width - root.focusedCardWidth) / 2) }
          footer: Item { width: Math.max(0, (historyList.width - root.focusedCardWidth) / 2) }

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

            width: root.focusedCardWidth
            height: historyList.height
            readonly property bool focused: index === root.selectedIndex

            NotificationCard {
              anchors.centerIn: parent
              width: root.focusedCardWidth
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
              keyboardSelected: cardSlot.focused
              actionAvailable: cardSlot.actionAvailable
              opacity: cardSlot.focused ? 1 : 0.52
              scale: cardSlot.focused ? 1 : 0.9
              Behavior on opacity { NumberAnimation { duration: Motion.fastDuration } }
              Behavior on scale { NumberAnimation { duration: Motion.spatialDuration; easing.type: Motion.spatialEasing } }
              onCardClicked: {
                if (root.selectedIndex === index) root.activationRequested(index)
                else {
                  root.selectedIndex = index
                  root.positionSelected()
                }
              }
            }
          }
        }

        WheelHandler {
          onWheel: function(event) {
            var delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
            if (delta === 0) return
            root.select(delta > 0 ? -1 : 1)
            event.accepted = true
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.modelCount === 0
          text: "No notification history"
          color: Color.notifications.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        text: "LEFT/RIGHT or CTRL+J/K  •  ENTER TO OPEN  •  ESC TO CLOSE"
        color: Color.notifications.text
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }
}
