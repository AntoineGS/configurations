import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
  id: root

  property string overlayId: ""
  property string layerNamespace: "desktop-top-bar-overlay"
  property var shell: null
  property bool opened: false
  property bool contentReady: true
  property real requestedCardWidth: Style.space(400)
  property real requestedCardHeight: Style.space(500)
  property real headerHeight: 0
  property real contentSpacing: Style.space(10)
  property real contentPadding: Style.spacing.popupPadding
  property real topSpacing: Style.space(12)
  property bool persistent: false
  property real surfaceHorizontalOffset: 0
  property alias surfaceBorderSpec: card.borderSpec
  property alias headerData: headerSlot.data
  default property alias bodyData: bodySlot.data
  property alias foregroundData: foregroundSlot.data

  readonly property string motionState: root._motionState
  readonly property real topBarHeight: root.shell && root.shell.barVisible === false ? 0
    : root.shell && root.shell.bar && Number(root.shell.bar.barSize) > 0
      ? Number(root.shell.bar.barSize) : Style.space(28)
  readonly property real availableCardHeight: Math.max(1,
    root.height - root.topBarHeight - Style.gapsOut)
  readonly property real cardWidth: Math.min(Math.max(0, root.requestedCardWidth),
    Math.max(0, root.width - Style.gapsOut * 2))
  readonly property real cardHeight: Math.min(Math.max(0, root.requestedCardHeight),
    root.availableCardHeight)
  readonly property bool geometryReady: root.contentReady
    && root.cardWidth > 0 && root.cardHeight > 0
  readonly property real cardTop: Math.max(Style.gapsOut, Math.min(root.topBarHeight,
    Math.max(Style.gapsOut, root.height - root.cardHeight - Style.gapsOut)))
  readonly property real contentHorizontalInset: card.contentLeftInset + card.contentRightInset
  readonly property real bodyWidth: bodySlot.width
  readonly property real bodyHeight: bodySlot.height
  readonly property bool _ownsInput: root.overlayId !== "" && root.opened && root.geometryReady
    && TopBarOverlayCoordinator.activeId === root.overlayId

  signal dismissRequested()

  property real _materialYScale: 0
  property real _surfaceOpacity: 0
  property real _headerOpacity: 0
  property real _bodyOpacity: 0
  property real _scrimOpacity: 0
  property string _motionState: "closed"
  readonly property real _shadowPadding: Style.space(24)
  readonly property real _shadowBottomPadding: root._shadowPadding + 4

  visible: root.opened || root._motionState !== "closed" || root._surfaceOpacity > 0
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  mask: Region { item: root._ownsInput ? scrimSurface : null }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: root.layerNamespace
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root._ownsInput
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  function settleOpenMotion() {
    root._materialYScale = 1
    root._surfaceOpacity = 1
    root._headerOpacity = 1
    root._bodyOpacity = 1
    root._scrimOpacity = 1
    root._motionState = "open"
  }

  function settleClosedMotion() {
    root._surfaceOpacity = 0
    root._headerOpacity = 0
    root._bodyOpacity = 0
    root._scrimOpacity = 0
    root._motionState = "closed"
  }

  function beginOpenMotion() {
    closeMotion.stop()
    if (root._motionState === "closed") {
      root._materialYScale = 0
      root._surfaceOpacity = 1
      root._headerOpacity = 0
      root._bodyOpacity = 0
      root._scrimOpacity = 0
    }
    root._motionState = "opening"
    if (!Motion.enabled) {
      root.settleOpenMotion()
      return
    }
    openMotion.restart()
  }

  function beginCloseMotion() {
    openMotion.stop()
    if (root._motionState === "closed") return
    root._motionState = "closing"
    if (!Motion.enabled) {
      root.settleClosedMotion()
      return
    }
    closeMotion.restart()
  }

  onOpenedChanged: {
    if (root.opened) {
      if (!TopBarOverlayCoordinator.claim(root.overlayId, root.persistent)) {
        root.dismissRequested()
        return
      }
      if (root.geometryReady) root.beginOpenMotion()
    } else {
      TopBarOverlayCoordinator.release(root.overlayId)
      root.beginCloseMotion()
    }
  }

  onGeometryReadyChanged: {
    if (root.geometryReady && root.opened) root.beginOpenMotion()
  }

  Component.onCompleted: {
    if (!root.opened) return
    if (!TopBarOverlayCoordinator.claim(root.overlayId, root.persistent)) root.dismissRequested()
    else if (root.geometryReady) root.beginOpenMotion()
  }

  Component.onDestruction: TopBarOverlayCoordinator.release(root.overlayId)

  Connections {
    target: TopBarOverlayCoordinator
    function onActiveIdChanged() {
      if (root.opened && TopBarOverlayCoordinator.activeId !== root.overlayId)
        root.dismissRequested()
    }
  }

  Connections {
    target: Motion
    function onEnabledChanged() {
      if (Motion.enabled) return
      openMotion.stop()
      closeMotion.stop()
      if (root.opened && root.geometryReady) root.settleOpenMotion()
      else root.settleClosedMotion()
    }
  }

  ParallelAnimation {
    id: openMotion
    onFinished: root.settleOpenMotion()

    NumberAnimation {
      target: root
      property: "_materialYScale"
      to: 1
      duration: PopupMotion.surfaceOpenDuration
      easing.type: PopupMotion.surfaceOpenEasing
    }
    SequentialAnimation {
      PauseAnimation { duration: PopupMotion.overlayHeaderOpenDelay }
      NumberAnimation {
        target: root
        property: "_headerOpacity"
        to: 1
        duration: PopupMotion.overlayHeaderOpenDuration
        easing.type: PopupMotion.overlayContentOpenEasing
      }
    }
    SequentialAnimation {
      PauseAnimation { duration: PopupMotion.overlayBodyOpenDelay }
      NumberAnimation {
        target: root
        property: "_bodyOpacity"
        to: 1
        duration: PopupMotion.overlayBodyOpenDuration
        easing.type: PopupMotion.overlayContentOpenEasing
      }
    }
    NumberAnimation {
      target: root
      property: "_scrimOpacity"
      to: 1
      duration: PopupMotion.surfaceOpenDuration
      easing.type: PopupMotion.overlayScrimEasing
    }
  }

  ParallelAnimation {
    id: closeMotion
    onFinished: root.settleClosedMotion()

    NumberAnimation {
      target: root
      property: "_headerOpacity"
      to: 0
      duration: PopupMotion.overlayHeaderCloseDuration
      easing.type: PopupMotion.overlayContentCloseEasing
    }
    NumberAnimation {
      target: root
      property: "_bodyOpacity"
      to: 0
      duration: PopupMotion.overlayBodyCloseDuration
      easing.type: PopupMotion.overlayContentCloseEasing
    }
    NumberAnimation {
      target: root
      property: "_materialYScale"
      to: 0
      duration: PopupMotion.surfaceCloseDuration
      easing.type: PopupMotion.surfaceCloseEasing
    }
    NumberAnimation {
      target: root
      property: "_scrimOpacity"
      to: 0
      duration: PopupMotion.surfaceCloseDuration
      easing.type: PopupMotion.overlayScrimEasing
    }
  }

  Rectangle {
    id: scrimSurface
    anchors {
      top: parent.top
      topMargin: root.topBarHeight
      bottom: parent.bottom
      left: parent.left
      right: parent.right
    }
    color: Color.modal.scrim
    opacity: root._scrimOpacity

    MouseArea {
      anchors.fill: parent
      enabled: root._ownsInput
      onClicked: root.dismissRequested()
    }
  }

  Item {
    id: cardFrame
    width: root.cardWidth + root._shadowPadding * 2
    height: root.cardHeight + root._shadowBottomPadding
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: root.surfaceHorizontalOffset
    y: root.cardTop
    opacity: root._surfaceOpacity
    clip: true

    transform: Scale {
      origin.x: cardFrame.width / 2
      origin.y: 0
      yScale: root._materialYScale
    }

    PanelSurface {
      id: card
      x: root._shadowPadding
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.popupOuterRadius
      padding: root.contentPadding
      topLeftRadius: root.topBarHeight > 0 ? 0 : Style.popupOuterRadius
      topRightRadius: root.topBarHeight > 0 ? 0 : Style.popupOuterRadius
      bottomLeftRadius: Style.popupOuterRadius
      bottomRightRadius: Style.popupOuterRadius
      revealed: true
      motionEnabled: false
      enabled: root._ownsInput

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      FocusScope {
        id: contentScope
        anchors {
          top: parent.top
          topMargin: card.contentTopInset + root.topSpacing
          bottom: parent.bottom
          bottomMargin: card.contentBottomInset
          left: parent.left
          leftMargin: card.contentLeftInset
          right: parent.right
          rightMargin: card.contentRightInset
        }
        enabled: root._ownsInput
        focus: root._ownsInput
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape && !event.accepted) {
            root.dismissRequested()
            event.accepted = true
          }
        }

        Item {
          id: headerSlot
          width: parent.width
          height: Math.max(0, root.headerHeight)
          opacity: root._headerOpacity
        }

        Item {
          id: bodySlot
          y: headerSlot.height + (headerSlot.height > 0 ? root.contentSpacing : 0)
          width: parent.width
          height: Math.max(0, parent.height - y)
          opacity: root._bodyOpacity
        }
      }

      Item {
        id: foregroundSlot
        anchors.fill: parent
        z: 1
      }
    }

    BarAttachedShoulders {
      x: card.x - radius
      z: 1
      visible: root.topBarHeight > 0
      bodyWidth: root.cardWidth
      surfaceColor: Color.barPanels.background
      revealProgress: root._materialYScale
    }
  }
}
