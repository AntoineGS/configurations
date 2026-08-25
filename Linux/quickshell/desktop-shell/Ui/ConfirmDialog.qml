import QtQuick
import qs.Commons

Item {
  id: root

  property bool opened: false
  property string message: ""
  property string cancelText: "Cancel"
  property string confirmText: "Confirm"
  property int selectedIndex: 1
  property color foreground: Color.barPanels.text
  property color secondaryForeground: Color.barPanels.secondaryText
  property color scrim: Color.modal.scrim
  property string fontFamily: Style.font.family

  signal canceled()
  signal confirmed()

  function handleKey(event) {
    if (!root.opened) return false

    if (event.key === Qt.Key_Escape) {
      root.canceled()
      return true
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
      return true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.selectedIndex === 0) root.canceled()
      else root.confirmed()
      return true
    }

    return false
  }

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea { anchors.fill: parent; onClicked: root.canceled() }

    PanelSurface {
      id: card
      width: Math.min(parent.width - Style.space(32), Style.space(370))
      // Grows with the wrapped message so narrow hosts (like the menu card)
      // don't squeeze the text into the buttons.
      height: card.contentTopInset + card.contentBottomInset + messageText.implicitHeight + Style.space(20) + Style.space(34)
      anchors.centerIn: parent
      padding: Style.space(18)
      revealed: root.opened

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: messageText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.message
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
        }

        Row {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(10)

          Repeater {
            model: [root.cancelText, root.confirmText]

            Button {
              required property int index
              required property string modelData

              readonly property bool destructive: index === 1

              width: Style.space(88)
              text: modelData
              foreground: root.foreground
              accent: destructive ? Color.urgent : Color.accent
              hasCursor: root.selectedIndex === index
              bordered: true
              fontFamily: root.fontFamily
              onHovered: function(hovered) { if (hovered) root.selectedIndex = index }
              onClicked: {
                if (index === 0) root.canceled()
                else root.confirmed()
              }
            }
          }
        }
      }
    }
  }
}
