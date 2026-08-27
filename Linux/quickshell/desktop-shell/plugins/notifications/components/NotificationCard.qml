import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../NotificationLogic.js" as NotificationLogic

ElevatedSurface {
  id: root

  revealed: true
  entranceX: Style.space(12)
  concealedScale: 1.0
  motionDuration: 160
  shadowBlurMax: 48
  shadowBlurAmount: 1.0
  shadowOpacityAmount: 0.78
  shadowOffsetY: 14
  shadowScaleAmount: 1.03
  effectPaddingRect: Qt.rect(-8, -8, 16, 30)

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property int urgency: 1
  property double timestamp: 0
  property var actions: []
  property string fontFamily: Style.font.family
  property bool historyMode: false
  property bool keyboardSelected: false
  property bool actionAvailable: true

  readonly property bool hovered: hoverTracker.hovered
  readonly property string smallIconSource: image.length > 0
    ? NotificationLogic.normalizeImageSource(image) : iconSource(appIcon)
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property string sanitizedBody: sanitizeBody(body)
  readonly property string styledBody: sanitizedBody.replace(/\r\n|\r|\n/g, "<br/>")
  readonly property color surfaceColor: urgency === 0
    ? Color.notifications.low : urgency === 2
      ? Color.notifications.critical : Color.notifications.background
  property color inkColor: Color.notifications.text
  readonly property string sourceLabel: String(app || "SYSTEM").toUpperCase()
  readonly property string timeLabel: formatTime(timestamp)

  signal closeRequested()
  signal cardClicked()
  signal actionClicked(string identifier)

  function sanitizeBody(value) {
    return NotificationLogic.sanitizeBody(value, app, appIcon)
  }

  function iconSource(icon) {
    var value = NotificationLogic.normalizeAppIconSource(icon)
    if (value.length === 0 || value.indexOf("image://") === 0) return value
    return Quickshell.iconPath(value, true)
  }

  function formatTime(value) {
    var milliseconds = Number(value)
    if (!isFinite(milliseconds) || milliseconds <= 0) return "NOW"
    return Qt.formatTime(new Date(milliseconds), "HH:mm")
  }

  implicitWidth: Style.space(380)
  implicitHeight: mainColumn.implicitHeight
  radius: root.historyMode ? Style.popupInnerRadius : 0
  color: surfaceColor
  borderSpec: root.keyboardSelected
    ? Border.flat(root.inkColor, Math.max(2, Style.space(2)))
    : Border.none()
  clip: true

  HoverHandler { id: hoverTracker }

  MouseArea {
    anchors.fill: parent
    cursorShape: root.historyMode && !root.actionAvailable ? Qt.ArrowCursor : Qt.PointingHandCursor
    acceptedButtons: root.historyMode ? Qt.LeftButton : Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      mouse.accepted = true
      if (mouse.button === Qt.RightButton) root.closeRequested()
      else root.cardClicked()
    }
  }

  ColumnLayout {
    id: mainColumn
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(34)
      Layout.topMargin: Style.space(10)
      Layout.bottomMargin: Style.space(9)
      spacing: Style.space(8)

      Item {
        Layout.preferredWidth: visible ? Style.space(16) : 0
        Layout.preferredHeight: visible ? Style.space(16) : 0
        visible: root.hasSmallIcon && metadataIcon.status !== Image.Error

        Image {
          id: metadataIcon
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
        }
      }

      Text {
        Layout.fillWidth: true
        text: root.sourceLabel
        color: root.inkColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: Style.spaceReal(0.6)
        elide: Text.ElideRight
      }

      Text {
        text: root.timeLabel
        color: root.inkColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Rectangle {
      id: metadataRule
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      height: Style.space(2)
      color: root.inkColor
    }

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: Style.space(10)
      Layout.bottomMargin: root.sanitizedBody.length > 0 ? 0 : Style.space(10)
      visible: root.summary.length > 0
      text: root.summary
      color: root.inkColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: Style.space(6)
      Layout.bottomMargin: Style.space(9)
      visible: root.sanitizedBody.length > 0
      text: root.styledBody
      textFormat: Text.StyledText
      color: root.inkColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      lineHeight: 1.45
      lineHeightMode: Text.ProportionalHeight
      wrapMode: Text.WordWrap
      maximumLineCount: 3
      elide: Text.ElideRight
    }

    Rectangle {
      id: actionRule
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      visible: !root.historyMode && !!root.actions && root.actions.length > 0
      height: Math.max(1, Style.space(1))
      color: root.inkColor
    }

    Item {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: Style.space(8)
      Layout.bottomMargin: Style.space(10)
      implicitHeight: actionFlow.implicitHeight
      visible: !root.historyMode && !!root.actions && root.actions.length > 0

      Flow {
        id: actionFlow
        anchors.left: parent.left
        anchors.right: parent.right
        layoutDirection: Qt.RightToLeft
        spacing: Style.space(6)

        Repeater {
          model: root.actions || []

          Button {
            required property int index
            required property var modelData
            text: modelData.text
            foreground: index === 0 ? root.surfaceColor : root.inkColor
            background: index === 0 ? root.inkColor : "transparent"
            accent: root.inkColor
            borderSpec: Border.flat(root.inkColor, Math.max(1, Style.space(1)))
            radius: 0
            maximumWidth: Style.space(140)
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(9)
            verticalPadding: Style.space(6)
            onClicked: root.actionClicked(String(modelData.identifier || ""))
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: Style.space(6)
      Layout.bottomMargin: Style.space(10)
      visible: root.historyMode && !root.actionAvailable
      text: "ACTION UNAVAILABLE"
      color: root.inkColor
      opacity: 0.62
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: Style.spaceReal(0.6)
      horizontalAlignment: Text.AlignRight
    }
  }

  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Style.space(3)
    anchors.rightMargin: Style.space(3)
    width: Style.space(18)
    height: Style.space(18)
    visible: !root.historyMode && opacity > 0
    opacity: root.hovered ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: "x"
      color: root.inkColor
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
