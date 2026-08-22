import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../NotificationLogic.js" as NotificationLogic

BorderSurface {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property int urgency: 1
  property double timestamp: 0
  property var actions: []
  property int cornerRadius: 0
  property string fontFamily: Style.font.family

  readonly property bool hovered: hoverTracker.hovered
  readonly property string smallIconSource: image.length > 0
    ? NotificationLogic.normalizeImageSource(image) : iconSource(appIcon)
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property string sanitizedBody: sanitizeBody(body)
  readonly property string styledBody: sanitizedBody.replace(/\r\n|\r|\n/g, "<br/>")
  readonly property color dimColor: Qt.darker(Color.notifications.text, 1.4)
  readonly property color bodyColor: Color.notifications.secondaryText
  readonly property bool urgencyBadgeVisible: urgency === 0 || urgency === 2
  readonly property string urgencyBadgeGlyph: urgency === 2 ? "!" : "i"
  readonly property color urgencyBadgeColor: urgency === 2
    ? Color.notifications.critical : Color.notifications.low
  readonly property var cardBorderSpec: Border.surfaceSpec(
    "notifications", "border", Color.notifications.border, Math.max(1, Style.space(2)))

  signal closeRequested()
  signal cardClicked()
  signal actionClicked(string identifier)

  function sanitizeBody(value) {
    return NotificationLogic.sanitizeBody(value, app, appIcon)
  }

  function iconSource(icon) {
    var value = NotificationLogic.normalizeAppIconSource(icon)
    if (value.length === 0) return ""
    if (value.indexOf("image://") === 0) return value
    return Quickshell.iconPath(value, true)
  }

  implicitWidth: Style.space(380)
  implicitHeight: mainColumn.implicitHeight + borderTop + borderBottom
  radius: cornerRadius
  color: Color.notifications.background
  borderSpec: cardBorderSpec
  clip: true

  HoverHandler { id: hoverTracker }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.closeRequested()
      else root.cardClicked()
    }
  }

  ColumnLayout {
    id: mainColumn
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.borderTop
    anchors.leftMargin: root.borderLeft
    anchors.rightMargin: root.borderRight
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: root.sanitizedBody.length === 0 ? Style.space(7) : Style.space(10)
      Layout.bottomMargin: root.sanitizedBody.length === 0 ? Style.space(7) : Style.space(10)
      spacing: Style.space(10)

      Item {
        id: smallIconSlot
        Layout.preferredWidth: visible ? Style.space(40) : 0
        Layout.preferredHeight: visible ? Style.space(40) : 0
        Layout.alignment: Qt.AlignVCenter
        visible: root.hasSmallIcon && smallIconImage.status !== Image.Error

        Image {
          id: smallIconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
          sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Layout.rightMargin: Style.space(10)
        spacing: Style.space(2)

        RowLayout {
          Layout.fillWidth: true
          visible: root.summary.length > 0 || root.urgencyBadgeVisible
          spacing: Style.space(6)

          Rectangle {
            Layout.preferredWidth: Style.space(18)
            Layout.preferredHeight: Style.space(18)
            Layout.alignment: Qt.AlignVCenter
            visible: root.urgencyBadgeVisible
            radius: width / 2
            color: root.urgencyBadgeColor

            Text {
              anchors.centerIn: parent
              text: root.urgencyBadgeGlyph
              color: Color.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.summary.length > 0
            text: root.summary
            font.family: root.fontFamily
            color: Color.notifications.text
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          visible: root.sanitizedBody.length > 0
          text: root.styledBody
          textFormat: Text.StyledText
          font.family: root.fontFamily
          color: root.bodyColor
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: 3
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.bottomMargin: Style.space(8)
      spacing: Style.space(6)
      visible: !!root.actions && root.actions.length > 0

      Repeater {
        model: root.actions || []

        Button {
          required property var modelData
          Layout.fillWidth: true
          text: modelData.text
          foreground: Color.notifications.text
          accent: Color.notifications.countdown
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(4)
          bordered: true
          onClicked: root.actionClicked(String(modelData.identifier || ""))
        }
      }
    }
  }

  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.borderTop + Style.space(3)
    anchors.rightMargin: root.borderRight + Style.space(3)
    width: Style.space(18)
    height: Style.space(18)
    visible: opacity > 0
    opacity: root.hovered ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: "x"
      color: closeArea.containsMouse ? Color.notifications.text : root.dimColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: closeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
  }
}
