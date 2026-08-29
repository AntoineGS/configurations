import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../NotificationLogic.js" as NotificationLogic

Item {
  id: root

  required property var snapshot
  property var countdown: ({ identity: "", fraction: 1, visible: false })
  property bool interactive: true
  property string fontFamily: Style.font.family
  property bool historyMode: false
  property bool keyboardSelected: false
  property bool actionAvailable: true
  property bool actionExpired: false
  property bool attachedMode: false
  property real attachedContentTopInset: 0
  property real metadataOpacity: 1
  property real contentOpacity: 1

  readonly property var safeSnapshot: root.snapshot || ({})
  readonly property bool hovered: hoverTracker.hovered
  readonly property string renderedIdentity: String(safeSnapshot.identity || "")
  readonly property string renderedApp: String(safeSnapshot.app || "")
  readonly property string renderedAppIcon: String(safeSnapshot.appIcon || "")
  readonly property string renderedSummary: String(safeSnapshot.summary || "")
  readonly property string renderedBody: String(safeSnapshot.body || "")
  readonly property string renderedImage: String(safeSnapshot.image || "")
  readonly property int renderedUrgency: Number(safeSnapshot.urgency)
  readonly property double renderedTimestamp: Number(safeSnapshot.timestamp)
  readonly property var renderedActions: safeSnapshot.actions || []
  readonly property bool countdownShown: root.countdown.visible === true
    && String(root.countdown.identity || "") === root.renderedIdentity
  readonly property real countdownFraction: Math.max(0, Math.min(1, Number(root.countdown.fraction) || 0))
  readonly property string smallIconSource: renderedImage.length > 0
    ? NotificationLogic.normalizeImageSource(renderedImage) : iconSource(renderedAppIcon)
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property string sanitizedBody: sanitizeBody(renderedBody)
  readonly property string styledBody: sanitizedBody.replace(/\r\n|\r|\n/g, "<br/>")
  readonly property color surfaceColor: renderedUrgency === 0
    ? Color.notifications.low : renderedUrgency === 2
      ? Color.notifications.critical : Color.notifications.background
  readonly property real contentTopInset: attachedMode
    ? Math.max(0, attachedContentTopInset) : 0
  readonly property color inkColor: Color.notifications.text
  readonly property string sourceLabel: String(renderedApp || "SYSTEM").toUpperCase()
  readonly property string timeLabel: formatTime(renderedTimestamp)

  signal closeRequested()
  signal cardClicked()
  signal actionClicked(string identifier)

  function sanitizeBody(value) {
    return NotificationLogic.sanitizeBody(value, renderedApp, renderedAppIcon)
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

  implicitHeight: contentTopInset + mainColumn.implicitHeight

  HoverHandler {
    id: hoverTracker
    enabled: root.interactive
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
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
    anchors.topMargin: root.contentTopInset
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: 0

    RowLayout {
      opacity: root.metadataOpacity
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
      opacity: root.contentOpacity
    }

    Text {
      opacity: root.contentOpacity
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: Style.space(10)
      Layout.bottomMargin: root.sanitizedBody.length > 0 ? 0 : Style.space(10)
      visible: root.renderedSummary.length > 0
      text: root.renderedSummary
      color: root.inkColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Text {
      opacity: root.contentOpacity
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
      visible: !root.historyMode && !!root.renderedActions && root.renderedActions.length > 0
      height: Math.max(1, Style.space(1))
      color: root.inkColor
      opacity: root.contentOpacity
    }

    Item {
      opacity: root.contentOpacity
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: Style.space(8)
      Layout.bottomMargin: Style.space(10)
      implicitHeight: actionFlow.implicitHeight
      visible: !root.historyMode && !!root.renderedActions && root.renderedActions.length > 0

      Flow {
        id: actionFlow
        anchors.left: parent.left
        anchors.right: parent.right
        layoutDirection: Qt.RightToLeft
        spacing: Style.space(6)

        Repeater {
          model: root.renderedActions || []

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
            enabled: root.interactive
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
      visible: root.historyMode && root.actionExpired
      text: "ACTION EXPIRED"
      color: root.inkColor
      opacity: 0.62 * root.contentOpacity
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: Style.spaceReal(0.6)
      horizontalAlignment: Text.AlignRight
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    anchors.bottomMargin: Style.space(5)
    height: Math.max(1, Style.space(2))
    visible: root.countdownShown
    color: Util.alpha(root.inkColor, 0.2)

    Rectangle {
      width: parent.width * root.countdownFraction
      height: parent.height
      color: Color.notifications.countdown
    }
  }

  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Style.space(3) + root.contentTopInset
    anchors.rightMargin: Style.space(3)
    width: Style.space(18)
    height: Style.space(18)
    visible: root.interactive && !root.historyMode && opacity > 0
    opacity: root.interactive && root.hovered ? 1 : 0

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
      enabled: root.interactive
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
  }
}
