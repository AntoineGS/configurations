import QtQuick
import qs.Commons
import qs.Ui

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

  required property var snapshot
  property var countdown: ({ identity: "", fraction: 1, visible: false })
  property bool interactive: true
  property string fontFamily: Style.font.family
  property bool historyMode: false
  property bool keyboardSelected: false
  property bool actionAvailable: true
  property bool attachedMode: false
  property real attachedContentTopInset: 0
  property color gradientStartColor: root.surfaceColor
  property real gradientExtent: Style.space(60)
  property real metadataOpacity: 1
  property real contentOpacity: 1

  readonly property bool hovered: content.hovered
  readonly property color surfaceColor: content.surfaceColor

  signal closeRequested()
  signal cardClicked()
  signal actionClicked(string identifier)

  implicitWidth: Style.space(380)
  implicitHeight: content.implicitHeight
  radius: root.attachedMode ? Style.popupOuterRadius
    : (root.historyMode ? Style.popupInnerRadius : Style.popupOuterRadius)
  topLeftRadius: root.attachedMode ? 0 : radius
  topRightRadius: root.attachedMode ? 0 : radius
  bottomLeftRadius: radius
  bottomRightRadius: radius
  gradient: Gradient {
    orientation: Gradient.Vertical
    GradientStop { position: 0; color: root.gradientStartColor }
    GradientStop { position: Math.min(1, root.gradientExtent / Math.max(1, root.height)); color: root.surfaceColor }
    GradientStop { position: 1; color: root.surfaceColor }
  }
  color: surfaceColor
  borderSpec: root.keyboardSelected
    ? Border.flat(root.content.inkColor, Math.max(2, Style.space(2)))
    : Border.none()
  clip: true

  NotificationContent {
    id: content
    anchors.fill: parent
    snapshot: root.snapshot
    countdown: root.countdown
    interactive: root.interactive
    fontFamily: root.fontFamily
    historyMode: root.historyMode
    keyboardSelected: root.keyboardSelected
    actionAvailable: root.actionAvailable
    attachedMode: root.attachedMode
    attachedContentTopInset: root.attachedContentTopInset
    metadataOpacity: root.metadataOpacity
    contentOpacity: root.contentOpacity
    onCloseRequested: root.closeRequested()
    onCardClicked: root.cardClicked()
    onActionClicked: identifier => root.actionClicked(identifier)
  }
}
