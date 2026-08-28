import QtQuick
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
  readonly property int currentPosition: root.modelCount > 0
    ? Math.min(root.selectedIndex + 1, root.modelCount) : 0
  readonly property real cardSpacing: Style.space(12)
  readonly property real cardStride: root.focusedCardWidth + root.cardSpacing
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

  function select(delta) {
    if (root.modelCount <= 0) return
    var next = root.clampIndex(root.selectedIndex + delta)
    if (next === root.selectedIndex) return
    root.selectedIndex = next
  }

  function activateSelected() {
    if (root.modelCount > 0) root.activationRequested(root.selectedIndex)
  }

  onOpenedChanged: {
    if (!root.opened) return
    root.selectedIndex = 0
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  onModelCountChanged: {
    var next = root.clampIndex(root.selectedIndex)
    if (next !== root.selectedIndex) root.selectedIndex = next
  }

  headerData: Text {
    width: parent.width
    height: Style.space(24)
    text: "NOTIFICATIONS  " + root.currentPosition + "/" + root.modelCount
    color: Color.barPanels.text
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
        if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
          root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
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

    Item {
      id: carouselViewport
      anchors.fill: parent
      clip: true

      Row {
        id: historyTrack
        height: parent.height
        spacing: root.cardSpacing
        x: root.modelCount > 0
          ? (carouselViewport.width - root.focusedCardWidth) / 2
            - root.selectedIndex * root.cardStride
          : 0

        Behavior on x {
          enabled: Motion.enabled
          NumberAnimation {
            duration: Motion.spatialDuration
            easing.type: Motion.spatialEasing
          }
        }

        Repeater {
          model: root.model

          delegate: Item {
            id: cardSlot
            required property int index
            required property int originalId
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property int urgency
            required property double timestamp
            required property bool actionAvailable

            width: root.focusedCardWidth
            height: historyTrack.height
            readonly property bool focused: index === root.selectedIndex
            readonly property var snapshot: ({
              identity: String(cardSlot.timestamp) + ":" + String(cardSlot.originalId),
              app: cardSlot.app,
              appIcon: cardSlot.appIcon,
              summary: cardSlot.summary,
              body: cardSlot.body,
              image: cardSlot.image,
              urgency: cardSlot.urgency,
              timestamp: cardSlot.timestamp,
              actions: []
            })

            NotificationCard {
              anchors.centerIn: parent
              width: root.focusedCardWidth
              snapshot: cardSlot.snapshot
              countdown: ({ identity: "", fraction: 1, visible: false })
              interactive: true
              fontFamily: root.fontFamily
              historyMode: true
              keyboardSelected: cardSlot.focused
              actionAvailable: cardSlot.actionAvailable
              opacity: cardSlot.focused ? 1 : 0.52
              scale: cardSlot.focused ? 1 : 0.9

              Behavior on opacity {
                enabled: Motion.enabled
                NumberAnimation {
                  duration: Motion.fastDuration
                  easing.type: Motion.effectEasing
                }
              }

              Behavior on scale {
                enabled: Motion.enabled
                NumberAnimation {
                  duration: Motion.spatialDuration
                  easing.type: Motion.spatialEasing
                }
              }

              onCardClicked: {
                if (root.selectedIndex === index) root.activationRequested(index)
                else root.selectedIndex = index
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
        color: Color.barPanels.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }
  }
}
