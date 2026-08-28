import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
  id: root

  required property var output
  property bool requestedVisible: false
  property string routeKey: ""
  property string glyph: ""
  signal dismissRequested(string routeKey)

  readonly property real elevationInset: Math.max(Style.popupOuterRadius, Style.space(24))
  readonly property real bodyWidth: Math.min(Style.space(380),
    Math.max(1, output ? output.width - Style.gapsOut * 2 - Style.popupOuterRadius * 2 : 1))

  property string _displayRouteKey: ""
  property string _displayGlyph: ""

  function syncDisplayedValues() {
    if (!requestedVisible) return
    _displayRouteKey = routeKey
    _displayGlyph = glyph
  }

  screen: output
  visible: requestedVisible || cueBody.revealProgress > 0
  implicitWidth: bodyWidth + elevationInset * 2
  implicitHeight: Style.space(48) + 28
  anchors { top: true; right: true }
  margins { top: 0; right: Style.gapsOut }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-shell-notification-route-cue"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  onRequestedVisibleChanged: {
    syncDisplayedValues()
  }
  onRouteKeyChanged: syncDisplayedValues()
  onGlyphChanged: syncDisplayedValues()
  Component.onCompleted: syncDisplayedValues()

  ElevatedSurface {
    id: cueBody
    x: root.elevationInset
    y: 0
    width: root.bodyWidth
    height: Style.space(48)
    color: Color.notifications.background
    radius: Style.popupOuterRadius
    topLeftRadius: 0
    topRightRadius: 0
    bottomLeftRadius: Style.popupOuterRadius
    bottomRightRadius: Style.popupOuterRadius
    revealed: root.requestedVisible
    revealDuration: PopupMotion.surfaceOpenDuration
    concealDuration: PopupMotion.surfaceCloseDuration
    revealEasing: PopupMotion.surfaceOpenEasing
    concealEasing: PopupMotion.surfaceCloseEasing
    concealedXScale: 1
    concealedYScale: 0
    scaleOriginX: width / 2
    scaleOriginY: 0

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      onClicked: root.dismissRequested(root._displayRouteKey)
    }

    Text {
      anchors.centerIn: parent
      text: root._displayGlyph
      color: Color.notifications.text
      font.family: Style.font.family
      font.pixelSize: Style.font.display
    }
  }

  BarAttachedShoulders {
    id: cueShoulders
    z: 1
    x: root.elevationInset - Style.popupOuterRadius
    y: 0
    bodyWidth: root.bodyWidth
    surfaceColor: Color.notifications.background
    gradientStartColor: Color.notifications.background
    gradientEndColor: Color.notifications.background
    gradientExtent: Style.popupOuterRadius
    revealProgress: cueBody.revealProgress
    onClicked: button => {
      if (button === Qt.LeftButton) root.dismissRequested(root._displayRouteKey)
    }
  }
}
