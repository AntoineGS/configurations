import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
  id: root

  required property var output
  required property var popupModel
  property var shell: null
  property bool cardsVisible: false
  property bool cueVisible: false
  property bool opened: false
  property int transitionGeneration: 0
  property real remainingFraction: 1
  property bool countdownVisible: false
  property bool criticalPending: false
  property string fontFamily: Style.font.family
  property string barPosition: "top"
  property real barSize: Style.bar.sizeHorizontal
  property string cueGlyph: ""

  readonly property var activeRow: popupModel && popupModel.count > 0
    ? popupModel.get(0) : null
  readonly property string activeIdentity: activeRow
    ? String(activeRow.timestamp) + ":" + String(activeRow.originalId) : ""
  readonly property var nextRow: popupModel && popupModel.count > 1
    ? popupModel.get(1) : null
  readonly property var thirdRow: popupModel && popupModel.count > 2
    ? popupModel.get(2) : null
  readonly property int queuedCount: popupModel ? Math.max(0, popupModel.count - 1) : 0
  readonly property real shoulderRadius: Style.popupOuterRadius
  readonly property real bodyWidth: Math.min(Style.space(380),
    Math.max(1, width - Style.gapsOut * (barAttached ? 2 : 1)
      - shoulderRadius * (barAttached ? 2 : 0)))
  readonly property real collarExtent: Style.space(60)
  readonly property bool barAttached: root.barPosition === "top"
    && root.shell && root.shell.barVisible !== false
  readonly property string motionState: root._motionState

  signal dismissRequested(string identity)
  signal cardClicked(string identity)
  signal actionClicked(string identity, string identifier)
  signal activeHoverChanged(bool hovered)
  signal openFinished(string identity, int generation, string outputName)
  signal closeFinished(string identity, int generation, string outputName)

  property real materialYScale: 0
  property real metadataOpacity: 0
  property real contentOpacity: 0
  property string _motionState: "closed"
  property string _transitionIdentity: ""
  property int _transitionGeneration: 0
  property string _transitionKind: ""
  property bool _completionEmitted: false
  property string _lastActiveIdentity: ""
  property bool _syncScheduled: false
  property bool _syncForcePending: false
  property bool _syncedOpened: false
  property int _syncedGeneration: -1
  property real _deckSettleOffset: 0
  property int _previousQueuedCount: 0

  screen: root.output
  visible: root.cardsVisible || root.cueVisible || root.motionState !== "closed"
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-shell-notification-rail"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  mask: Region {
    Region { item: root.cardsVisible && root.activeRow ? card : null }
    Region { item: root.cardsVisible && root.barAttached ? shoulders : null }
  }

  function urgencyColor(row) {
    if (!row) return "transparent"
    return Number(row.urgency) === 0 ? Color.notifications.low
      : Number(row.urgency) === 2 ? Color.notifications.critical
        : Color.notifications.background
  }

  function outputName() {
    return String(root.output.name)
  }

  function settleOpenMotion() {
    root.materialYScale = 1
    root.metadataOpacity = 1
    root.contentOpacity = 1
    root._motionState = "open"
    if (!root._completionEmitted && root._transitionKind === "open") {
      root._completionEmitted = true
      root.openFinished(root._transitionIdentity, root._transitionGeneration, root.outputName())
    }
  }

  function settleClosedMotion() {
    root.materialYScale = 0
    root.metadataOpacity = 0
    root.contentOpacity = 0
    root._motionState = "closed"
    if (!root._completionEmitted && root._transitionKind === "close") {
      root._completionEmitted = true
      root.closeFinished(root._transitionIdentity, root._transitionGeneration, root.outputName())
    }
  }

  function beginOpenMotion() {
    closeMotion.stop()
    root._transitionIdentity = root.activeIdentity
    root._transitionGeneration = root.transitionGeneration
    root._transitionKind = "open"
    root._completionEmitted = false
    if (root._motionState === "closed") {
      root.materialYScale = 0
      root.metadataOpacity = 0
      root.contentOpacity = 0
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
    root._transitionIdentity = root._lastActiveIdentity || root.activeIdentity
    root._transitionGeneration = root.transitionGeneration
    root._transitionKind = "close"
    root._completionEmitted = false
    if (root._motionState === "closed") {
      root.settleClosedMotion()
      return
    }
    root._motionState = "closing"
    if (!Motion.enabled) {
      root.settleClosedMotion()
      return
    }
    closeMotion.restart()
  }

  function scheduleTransitionSync(force) {
    if (force) root._syncForcePending = true
    if (root._syncScheduled) return
    root._syncScheduled = true
    Qt.callLater(function() {
      root._syncScheduled = false
      var forcePending = root._syncForcePending
      root._syncForcePending = false
      if (!forcePending && root._syncedOpened === root.opened
          && root._syncedGeneration === root.transitionGeneration) return
      root._syncedOpened = root.opened
      root._syncedGeneration = root.transitionGeneration
      if (root.opened) root.beginOpenMotion()
      else root.beginCloseMotion()
    })
  }

  function beginDeckSettle() {
    if (!Motion.enabled) {
      root._deckSettleOffset = 0
      return
    }
    root._deckSettleOffset = -Style.space(12)
    deckSettleAnimation.restart()
  }

  onActiveIdentityChanged: if (root.activeIdentity !== "") root._lastActiveIdentity = root.activeIdentity
  onOpenedChanged: root.scheduleTransitionSync()
  onTransitionGenerationChanged: root.scheduleTransitionSync()
  onQueuedCountChanged: {
    if (root.queuedCount > root._previousQueuedCount) root.beginDeckSettle()
    root._previousQueuedCount = root.queuedCount
  }

  Component.onCompleted: {
    if (root.activeIdentity !== "") root._lastActiveIdentity = root.activeIdentity
    root._syncedOpened = root.opened
    root._syncedGeneration = root.transitionGeneration
    if (root.opened) root.scheduleTransitionSync(true)
  }

  Connections {
    target: Motion
    function onEnabledChanged() {
      if (Motion.enabled) return
      openMotion.stop()
      closeMotion.stop()
      deckSettleAnimation.stop()
      root._deckSettleOffset = 0
      if (root.opened) root.settleOpenMotion()
      else root.settleClosedMotion()
    }
  }

  ParallelAnimation {
    id: openMotion
    onFinished: root.settleOpenMotion()

    NumberAnimation {
      target: root
      property: "materialYScale"
      to: 1
      duration: PopupMotion.surfaceOpenDuration
      easing.type: PopupMotion.surfaceOpenEasing
    }
    SequentialAnimation {
      PauseAnimation { duration: PopupMotion.overlayHeaderOpenDelay }
      NumberAnimation {
        target: root
        property: "metadataOpacity"
        to: 1
        duration: PopupMotion.overlayHeaderOpenDuration
        easing.type: PopupMotion.overlayContentOpenEasing
      }
    }
    SequentialAnimation {
      PauseAnimation { duration: PopupMotion.overlayBodyOpenDelay }
      NumberAnimation {
        target: root
        property: "contentOpacity"
        to: 1
        duration: PopupMotion.overlayBodyOpenDuration
        easing.type: PopupMotion.overlayContentOpenEasing
      }
    }
  }

  NumberAnimation {
    id: deckSettleAnimation
    target: root
    property: "_deckSettleOffset"
    to: 0
    duration: PopupMotion.overlayBodyOpenDuration
    easing.type: PopupMotion.overlayContentOpenEasing
  }

  ParallelAnimation {
    id: closeMotion
    onFinished: root.settleClosedMotion()

    NumberAnimation {
      target: root
      property: "metadataOpacity"
      to: 0
      duration: PopupMotion.overlayHeaderCloseDuration
      easing.type: PopupMotion.overlayContentCloseEasing
    }
    NumberAnimation {
      target: root
      property: "contentOpacity"
      to: 0
      duration: PopupMotion.overlayBodyCloseDuration
      easing.type: PopupMotion.overlayContentCloseEasing
    }
    NumberAnimation {
      target: root
      property: "materialYScale"
      to: 0
      duration: PopupMotion.surfaceCloseDuration
      easing.type: PopupMotion.surfaceCloseEasing
    }
  }

  Rectangle {
    id: thirdDeck
    visible: (root.cardsVisible || root.motionState !== "closed") && root.thirdRow !== null
    x: cardFrame.x + root.shoulderRadius + Style.space(16)
    y: cardFrame.y + Style.space(18) + root._deckSettleOffset
    width: Math.max(1, root.bodyWidth - Style.space(32))
    height: Math.max(Style.space(36), card.implicitHeight)
    radius: Style.popupInnerRadius
    bottomLeftRadius: Style.popupOuterRadius
    bottomRightRadius: Style.popupOuterRadius
    color: root.urgencyColor(root.thirdRow)
    opacity: root.cardsVisible ? 1 : 0
    z: -2
    Behavior on opacity {
      NumberAnimation { duration: PopupMotion.overlayBodyOpenDuration; easing.type: PopupMotion.overlayContentOpenEasing }
    }
  }

  Rectangle {
    id: nextDeck
    visible: (root.cardsVisible || root.motionState !== "closed") && root.nextRow !== null
    x: cardFrame.x + root.shoulderRadius + Style.space(8)
    y: cardFrame.y + Style.space(9) + root._deckSettleOffset
    width: Math.max(1, root.bodyWidth - Style.space(16))
    height: Math.max(Style.space(42), card.implicitHeight)
    radius: Style.popupInnerRadius
    bottomLeftRadius: Style.popupOuterRadius
    bottomRightRadius: Style.popupOuterRadius
    color: root.urgencyColor(root.nextRow)
    opacity: root.cardsVisible ? 1 : 0
    z: -1
    Behavior on opacity {
      NumberAnimation { duration: PopupMotion.overlayBodyOpenDuration; easing.type: PopupMotion.overlayContentOpenEasing }
    }
  }

  Rectangle {
    visible: root.cardsVisible && root.criticalPending
    x: cardFrame.x + cardFrame.width - Style.space(10)
    y: cardFrame.y - Style.space(8)
    width: Style.space(6)
    height: width
    radius: width / 2
    color: Color.notifications.critical
  }

  Text {
    visible: root.cardsVisible && root.queuedCount > 0
    x: cardFrame.x + cardFrame.width - Style.space(34)
    y: cardFrame.y + Style.space(5)
    text: "+" + root.queuedCount
    color: Color.notifications.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    z: 2
  }

  Item {
    id: cardFrame
    x: root.width - Style.gapsOut - width
    y: root.barAttached ? root.barSize : Style.gapsOut
    width: root.bodyWidth + (root.barAttached ? root.shoulderRadius * 2 : 0)
    height: card.height + (root.barAttached ? root.shoulderRadius : 0)
    z: 1

    transform: Scale {
      origin.x: cardFrame.width / 2
      origin.y: 0
      xScale: 1
      yScale: root.materialYScale
    }

    NotificationCard {
      id: card
      x: root.barAttached ? root.shoulderRadius : 0
      width: root.bodyWidth
      visible: (root.cardsVisible || root.motionState !== "closed") && root.activeRow !== null
      app: root.activeRow ? String(root.activeRow.app || "") : ""
      appIcon: root.activeRow ? String(root.activeRow.appIcon || "") : ""
      summary: root.activeRow ? String(root.activeRow.summary || "") : ""
      body: root.activeRow ? String(root.activeRow.body || "") : ""
      image: root.activeRow ? String(root.activeRow.image || "") : ""
      urgency: root.activeRow ? Number(root.activeRow.urgency) : 1
      timestamp: root.activeRow ? Number(root.activeRow.timestamp) : 0
      actions: root.activeRow ? (root.activeRow.actions || []) : []
      fontFamily: root.fontFamily
      attachedMode: root.barAttached
      gradientStartColor: Color.barPanels.background
      gradientExtent: root.collarExtent
      metadataOpacity: root.metadataOpacity
      contentOpacity: root.contentOpacity
      remainingFraction: root.remainingFraction
      showCountdown: root.countdownVisible

      onHoveredChanged: root.activeHoverChanged(card.hovered || shoulders.hovered)
      onCloseRequested: root.dismissRequested(root.activeIdentity)
      onCardClicked: root.cardClicked(root.activeIdentity)
      onActionClicked: function(identifier) {
        root.actionClicked(root.activeIdentity, identifier)
      }
    }

    BarAttachedShoulders {
      id: shoulders
      x: 0
      visible: (root.cardsVisible || root.motionState !== "closed") && root.barAttached
      bodyWidth: root.bodyWidth
      gradientStartColor: Color.barPanels.background
      gradientEndColor: root.urgencyColor(root.activeRow)
      gradientExtent: root.collarExtent
      onHoveredChanged: root.activeHoverChanged(card.hovered || shoulders.hovered)
    }
  }

  ElevatedSurface {
    id: cueSurface
    visible: root.cueVisible
    revealed: root.cueVisible
    entranceX: Style.space(12)
    concealedScale: 1.0
    motionDuration: 160
    shadowBlurMax: 48
    shadowBlurAmount: 1.0
    shadowOpacityAmount: 0.78
    shadowOffsetY: 14
    shadowScaleAmount: 1.03
    effectPaddingRect: Qt.rect(-8, -8, 16, 30)
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: (root.barPosition === "top" && root.shell
      && root.shell.barVisible !== false ? root.barSize + Style.gapsOut : Style.gapsOut) + Style.space(24)
    anchors.rightMargin: (root.barPosition === "right" && root.shell
      && root.shell.barVisible !== false ? root.barSize + Style.gapsOut : Style.gapsOut) + Style.space(24)
    implicitWidth: Style.space(250)
    implicitHeight: Style.space(48)
    radius: 0
    color: Color.notifications.background
    borderSpec: Border.none()

    Text {
      anchors.centerIn: parent
      text: root.cueGlyph
      color: Color.notifications.text
      font.family: Style.font.family
      font.pixelSize: Style.font.display
    }
  }
}
