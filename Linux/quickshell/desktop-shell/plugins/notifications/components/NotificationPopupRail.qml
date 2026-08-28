import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../NotificationLogic.js" as NotificationLogic

PanelWindow {
  id: root

  required property var output
  required property var presentationFrame
  required property bool ownsOutput
  property bool surfacesSuppressed: false
  property var shell: null
  property bool cueVisible: false
  property string fontFamily: Style.font.family
  property string barPosition: "top"
  property real barSize: Style.bar.sizeHorizontal
  property string cueGlyph: ""

  readonly property var visual: root.presentationFrame.visual || ({})
  readonly property var incoming: root.visual.incoming || root.presentationFrame.active
  readonly property var outgoing: root.visual.outgoing
  readonly property var incomingDeck: NotificationLogic.normalizedDeck(root.visual.incomingDeck)
  readonly property var outgoingDeck: NotificationLogic.normalizedDeck(root.visual.outgoingDeck)
  readonly property string incomingIdentity: root.incoming ? String(root.incoming.identity || "") : ""
  readonly property string outgoingIdentity: root.outgoing ? String(root.outgoing.identity || "") : ""
  readonly property bool hasCards: root.incoming !== null || root.outgoing !== null
  readonly property bool barAttached: root.barPosition === "top"
    && root.shell && root.shell.barVisible !== false
  readonly property real shoulderRadius: Style.popupOuterRadius
  readonly property real bodyWidth: Math.min(Style.space(380),
    Math.max(1, width - Style.gapsOut * (barAttached ? 2 : 1)
      - shoulderRadius * (barAttached ? 2 : 0)))
  readonly property real collarExtent: Style.space(36)
  readonly property real attachedContentTopInset: Style.space(32)

  signal dismissRequested(string identity)
  signal cardClicked(string identity)
  signal actionClicked(string identity, string identifier)
  signal hoverChanged(string identity, bool hovered)
  signal transitionFinished(int token, string kind, string outputName)
  signal stateObserved(string outputName, bool ownsOutput, bool hasCards, bool windowVisible,
    string phase, string incomingIdentity)

  property real _progress: 1
  property real _metadataOpacity: 1
  property real _contentOpacity: 1
  property bool _incomingVisible: true
  property string _latchedKind: ""
  property int _latchedToken: 0
  property string _latchedOutput: ""
  property var _latchedIncoming: null
  property var _latchedOutgoing: null
  property var _latchedIncomingDeck: null
  property var _latchedOutgoingDeck: null
  property var _paintedSnapshot: null
  property var _paintedDeck: null
  property bool _stateObservationPending: false
  property real _animationStartProgress: 0
  property real _animationStartMetadata: 0
  property real _animationStartContent: 0
  property string _lastTransition: ""
  property real _deckSettleOffset: 0
  readonly property real deckProgress: root.presentationFrame.phase === "closing"
    ? root._progress : (root.presentationFrame.phase === "opening" || root.presentationFrame.phase === "switching"
      ? root._progress : 1)
  readonly property var deckProjection: NotificationLogic.deckProjection(
    root.presentationFrame.phase, root._progress, root._incomingVisible)
  readonly property var deckOpacityProjection: NotificationLogic.deckOpacityProjection(
    root.presentationFrame.phase, root._progress, root._incomingVisible)
  readonly property real deckOpacity: root.deckOpacityProjection.selected

  screen: root.output
  visible: !root.surfacesSuppressed && (root.cueVisible || (root.ownsOutput && root.hasCards
    && root.presentationFrame.phase !== "closed" && root.presentationFrame.phase !== "hidden"))
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-shell-notification-rail"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // The installed Region API cannot subtract transparent shoulder gutters.
  // Body-only input is exact and avoids making the painted shoulders clickable.
  mask: Region { item: stableInputRegion.visible ? stableInputRegion : null }

  function identity(snapshot) { return snapshot ? String(snapshot.identity || "") : "" }
  function urgencyColor(snapshot) {
    if (!snapshot) return "transparent"
    return Number(snapshot.urgency) === 0 ? Color.notifications.low
      : Number(snapshot.urgency) === 2 ? Color.notifications.critical : Color.notifications.background
  }
  function frameKey(frame) {
    var v = frame.visual || {}
    return String(frame.phase || "") + ":" + String(v.token || 0) + ":" + String(v.kind || "")
      + ":" + String(v.output || "") + ":" + identity(v.incoming) + ":" + identity(v.outgoing)
  }
  function latchTransition() {
    if (root.surfacesSuppressed) return
    var frame = root.presentationFrame
    var v = frame.visual || {}
    var kind = String(v.kind || "")
    var paintedSnapshot = root._paintedSnapshot
    var paintedDeck = root._paintedDeck
    var paintedProgress = root._progress
    var paintedMetadata = root._metadataOpacity
    var paintedContent = root._contentOpacity
    if (!kind || !v.token) return
    if (root._lastTransition === root.frameKey(frame)) {
      root._latchedIncomingDeck = NotificationLogic.normalizedDeck(v.incomingDeck)
      return
    }
    if (root._latchedKind) {
      paintedSnapshot = root._incomingVisible ? root._latchedIncoming : root._latchedOutgoing
      paintedDeck = root._incomingVisible ? root._latchedIncomingDeck : root._latchedOutgoingDeck
    }
    openMotion.stop(); closeMotion.stop(); switchMotion.stop()
    root._lastTransition = root.frameKey(frame)
    root._latchedKind = kind
    root._latchedToken = Number(v.token)
    root._latchedOutput = String(v.output || "")
    root._latchedIncoming = v.incoming || null
    root._latchedOutgoing = kind === "close" || kind === "switch"
      ? (paintedSnapshot || v.outgoing || null) : (v.outgoing || null)
    root._latchedIncomingDeck = NotificationLogic.normalizedDeck(v.incomingDeck)
    root._latchedOutgoingDeck = kind === "close" || kind === "switch"
      ? NotificationLogic.normalizedDeck(paintedDeck || v.outgoingDeck)
      : NotificationLogic.normalizedDeck(v.outgoingDeck)
    root._incomingVisible = kind === "open"
    root._progress = kind === "close" || kind === "switch" ? paintedProgress : 0
    root._metadataOpacity = kind === "close" || kind === "switch" ? paintedMetadata : 0
    root._contentOpacity = kind === "close" || kind === "switch" ? paintedContent : 0
    root._animationStartProgress = root._progress
    root._animationStartMetadata = root._metadataOpacity
    root._animationStartContent = root._contentOpacity
    openMotion.token = root._latchedToken; openMotion.output = root._latchedOutput
    closeMotion.token = root._latchedToken; closeMotion.output = root._latchedOutput
    switchMotion.token = root._latchedToken; switchMotion.output = root._latchedOutput
    if (!Motion.enabled) {
      root._incomingVisible = kind !== "close"
      root._progress = 1
      root.scheduleCompletion(root._latchedToken, root._latchedKind, root._latchedOutput)
    } else if (kind === "open") openMotion.restart()
    else if (kind === "close") closeMotion.restart()
    else switchMotion.restart()
  }
  function finishTransition() {
    if (root.surfacesSuppressed) return
    var route = root.presentationFrame.route || ({})
    if (!root.ownsOutput || !route.visible || String(route.output || "") !== String(root._latchedOutput)
        || !root._latchedKind || root._latchedToken <= 0
        || Number(root.presentationFrame.visual.token) !== root._latchedToken
        || String(root.presentationFrame.visual.kind || "") !== root._latchedKind
        || String(root.presentationFrame.visual.output || "") !== root._latchedOutput) return
    var token = root._latchedToken
    var kind = root._latchedKind
    var outputName = root._latchedOutput
    root._progress = kind === "close" ? 0 : 1
    root._metadataOpacity = kind === "close" ? 0 : 1
    root._contentOpacity = kind === "close" ? 0 : 1
    root._incomingVisible = kind !== "close"
    root._latchedKind = ""
    root._latchedToken = 0
    root._latchedOutput = ""
    root.transitionFinished(token, kind, outputName)
  }
  function completeAnimation(token, kind, outputName) {
    if (Number(token) !== root._latchedToken || String(kind) !== root._latchedKind
        || String(outputName) !== root._latchedOutput) return
    root.finishTransition()
  }
  function scheduleCompletion(token, kind, outputName) {
    Qt.callLater(function() { root.completeAnimation(token, kind, outputName) })
  }
  function stableDeck() {
    var frame = root.presentationFrame
    if (frame.phase === "switching")
      return NotificationLogic.normalizedDeck(root._incomingVisible ? root._latchedIncomingDeck : root._latchedOutgoingDeck)
    if (frame.phase === "closing") return NotificationLogic.normalizedDeck(root._latchedOutgoingDeck)
    return root.incomingDeck
  }
  function beginDeckSettle() {
    if (!Motion.enabled) { root._deckSettleOffset = 0; return }
    root._deckSettleOffset = -Style.space(12)
    deckSettle.restart()
  }

  function scheduleStateObservation() {
    if (root._stateObservationPending) return
    root._stateObservationPending = true
    Qt.callLater(function() {
      root._stateObservationPending = false
      root.stateObserved(String(root.output && root.output.name || ""), root.ownsOutput, root.hasCards,
        root.visible, String(root.presentationFrame.phase || ""), root.incomingIdentity)
    })
  }

  function syncPresentationFrame() {
    var frame = root.presentationFrame
    if (root.surfacesSuppressed || !root.ownsOutput) {
      openMotion.stop(); closeMotion.stop(); switchMotion.stop()
    } else if (frame.phase === "opening" || frame.phase === "closing" || frame.phase === "switching") root.latchTransition()
    else if (frame.phase === "open") {
      root._latchedIncoming = frame.visual.incoming || frame.active
      root._latchedIncomingDeck = NotificationLogic.normalizedDeck(frame.visual.incomingDeck)
      root._paintedSnapshot = root._latchedIncoming
      root._paintedDeck = root._latchedIncomingDeck
      root._incomingVisible = true
      root._progress = 1; root._metadataOpacity = 1; root._contentOpacity = 1
    }
  }
  onPresentationFrameChanged: { root.syncPresentationFrame(); root.scheduleStateObservation() }
  onVisibleChanged: {
    if (root.visible && root.presentationFrame) root.beginDeckSettle()
    root.scheduleStateObservation()
  }
  onOwnsOutputChanged: root.scheduleStateObservation()
  onHasCardsChanged: root.scheduleStateObservation()
  Component.onCompleted: { root.syncPresentationFrame(); root.scheduleStateObservation() }

  Connections {
    target: Motion
    function onEnabledChanged() {
      if (Motion.enabled) return
      openMotion.stop(); closeMotion.stop(); switchMotion.stop(); deckSettle.stop()
      root._deckSettleOffset = 0
      root.scheduleCompletion(root._latchedToken, root._latchedKind, root._latchedOutput)
    }
  }

  NumberAnimation { id: deckSettle; target: root; property: "_deckSettleOffset"; to: 0; duration: 180; easing.type: PopupMotion.overlayContentOpenEasing }
  ParallelAnimation {
    id: openMotion
    property int token: 0
    property string output: ""
    onFinished: root.completeAnimation(openMotion.token, "open", openMotion.output)
    NumberAnimation { target: root; property: "_progress"; from: root._animationStartProgress; to: 1; duration: 360; easing.type: PopupMotion.surfaceOpenEasing }
    SequentialAnimation {
      PauseAnimation { duration: PopupMotion.overlayHeaderOpenDelay }
      NumberAnimation {
        target: root; property: "_metadataOpacity"; from: root._animationStartMetadata; to: 1
        duration: PopupMotion.overlayHeaderOpenDuration; easing.type: PopupMotion.overlayContentOpenEasing
      }
    }
    SequentialAnimation {
      PauseAnimation { duration: PopupMotion.overlayBodyOpenDelay }
      NumberAnimation {
        target: root; property: "_contentOpacity"; from: root._animationStartContent; to: 1
        duration: PopupMotion.overlayBodyOpenDuration; easing.type: PopupMotion.overlayContentOpenEasing
      }
    }
  }
  ParallelAnimation {
    id: closeMotion
    property int token: 0
    property string output: ""
    onFinished: root.completeAnimation(closeMotion.token, "close", closeMotion.output)
    NumberAnimation { target: root; property: "_progress"; from: root._animationStartProgress; to: 0; duration: 320; easing.type: PopupMotion.surfaceCloseEasing }
    NumberAnimation { target: root; property: "_metadataOpacity"; from: root._animationStartMetadata; to: 0; duration: PopupMotion.overlayHeaderCloseDuration; easing.type: PopupMotion.overlayContentCloseEasing }
    NumberAnimation { target: root; property: "_contentOpacity"; from: root._animationStartContent; to: 0; duration: PopupMotion.overlayBodyCloseDuration; easing.type: PopupMotion.overlayContentCloseEasing }
  }
  SequentialAnimation {
    id: switchMotion
    property int token: 0
    property string output: ""
    ParallelAnimation {
      NumberAnimation { target: root; property: "_progress"; from: root._animationStartProgress; to: 0; duration: 320; easing.type: PopupMotion.surfaceCloseEasing }
      NumberAnimation { target: root; property: "_metadataOpacity"; from: root._animationStartMetadata; to: 0; duration: PopupMotion.overlayHeaderCloseDuration; easing.type: PopupMotion.overlayContentCloseEasing }
      NumberAnimation { target: root; property: "_contentOpacity"; from: root._animationStartContent; to: 0; duration: PopupMotion.overlayBodyCloseDuration; easing.type: PopupMotion.overlayContentCloseEasing }
    }
    ScriptAction { script: { root._incomingVisible = true; root._paintedSnapshot = root._latchedIncoming; root._paintedDeck = root._latchedIncomingDeck; root._progress = 0; root._metadataOpacity = 0; root._contentOpacity = 0; root._animationStartProgress = 0; root._animationStartMetadata = 0; root._animationStartContent = 0 } }
    ParallelAnimation {
      NumberAnimation { target: root; property: "_progress"; from: 0; to: 1; duration: 360; easing.type: PopupMotion.surfaceOpenEasing }
      SequentialAnimation {
        PauseAnimation { duration: PopupMotion.overlayHeaderOpenDelay }
        NumberAnimation {
          target: root; property: "_metadataOpacity"; to: 1
          duration: PopupMotion.overlayHeaderOpenDuration; easing.type: PopupMotion.overlayContentOpenEasing
        }
      }
      SequentialAnimation {
        PauseAnimation { duration: PopupMotion.overlayBodyOpenDelay }
        NumberAnimation {
          target: root; property: "_contentOpacity"; to: 1
          duration: PopupMotion.overlayBodyOpenDuration; easing.type: PopupMotion.overlayContentOpenEasing
        }
      }
    }
    ScriptAction { script: root.completeAnimation(switchMotion.token, "switch", switchMotion.output) }
  }

  Rectangle {
    id: thirdDeck
    property var deck: root.stableDeck()
    property var snapshot: deck.snapshots && deck.snapshots.length > 1 ? deck.snapshots[1] : null
    visible: !root.surfacesSuppressed && root.ownsOutput && root.hasCards && snapshot !== null
    x: cardFrame.x + root.shoulderRadius + Style.space(16)
    y: cardFrame.y + Style.space(18) + root._deckSettleOffset
    width: Math.max(1, root.bodyWidth - Style.space(32)); height: Math.max(Style.space(36), cardFrame.deckCardHeight)
    radius: Style.popupInnerRadius; bottomLeftRadius: Style.popupOuterRadius; bottomRightRadius: Style.popupOuterRadius
    color: root.urgencyColor(snapshot); opacity: root.deckOpacity; z: -2
  }
  Rectangle {
    id: nextDeck
    property var deck: root.stableDeck()
    property var snapshot: deck.snapshots && deck.snapshots.length > 0 ? deck.snapshots[0] : null
    visible: !root.surfacesSuppressed && root.ownsOutput && root.hasCards && snapshot !== null
    x: cardFrame.x + root.shoulderRadius + Style.space(8)
    y: cardFrame.y + Style.space(9) + root._deckSettleOffset
    width: Math.max(1, root.bodyWidth - Style.space(16)); height: Math.max(Style.space(42), cardFrame.deckCardHeight)
    radius: Style.popupInnerRadius; bottomLeftRadius: Style.popupOuterRadius; bottomRightRadius: Style.popupOuterRadius
    color: root.urgencyColor(snapshot); opacity: root.deckOpacity; z: -1
  }
  Rectangle {
    property var deck: root.stableDeck()
    visible: root.ownsOutput && root.hasCards && deck.criticalPending && root.presentationFrame.hovered
    opacity: root.deckOpacity
    x: cardFrame.x + cardFrame.width - Style.space(10); y: cardFrame.y - Style.space(8)
    width: Style.space(6); height: width; radius: width / 2; color: Color.notifications.critical
  }
  Text {
    property var deck: root.stableDeck()
    visible: root.ownsOutput && root.hasCards && deck.queuedCount > 0
    x: cardFrame.x + cardFrame.width - Style.space(34); y: cardFrame.y + Style.space(5)
    text: "+" + deck.queuedCount; color: Color.notifications.text; font.family: root.fontFamily; opacity: root.deckOpacity
    font.pixelSize: Style.font.caption; font.bold: true; z: 2
  }

  Item {
    id: cardFrame
    x: root.width - Style.gapsOut - width; y: root.barAttached ? root.barSize : Style.gapsOut
    width: root.bodyWidth + (root.barAttached ? root.shoulderRadius * 2 : 0)
    property real deckCardHeight: (root.presentationFrame.phase === "closing"
      || (root.presentationFrame.phase === "switching" && !root._incomingVisible))
      ? (outgoingLoader.item ? outgoingLoader.item.implicitHeight : 0)
      : (incomingLoader.item ? incomingLoader.item.implicitHeight : 0)
    height: Math.max(outgoingLoader.item ? outgoingLoader.item.height : 0, incomingLoader.item ? incomingLoader.item.height : 0)
      + (root.barAttached ? root.shoulderRadius : 0); z: 1

    Item {
      id: outgoingSlot
      x: 0; width: parent.width; height: parent.height
      visible: root.ownsOutput && root._latchedOutgoing !== null
        && (root.presentationFrame.phase === "closing"
          || (root.presentationFrame.phase === "switching" && !root._incomingVisible))
      opacity: root._progress
      transform: Scale { origin.x: outgoingSlot.width / 2; origin.y: 0; yScale: opacity }
      Loader {
        id: outgoingLoader
        active: !root.surfacesSuppressed && root._latchedOutgoing !== null
        sourceComponent: NotificationCard {
          x: root.barAttached ? root.shoulderRadius : 0; width: root.bodyWidth
          snapshot: root._latchedOutgoing; interactive: false; fontFamily: root.fontFamily
           attachedMode: root.barAttached; attachedContentTopInset: root.attachedContentTopInset
           gradientStartColor: Color.barPanels.background; gradientExtent: root.collarExtent
          metadataOpacity: root._metadataOpacity; contentOpacity: root._contentOpacity
          countdown: ({ identity: "", fraction: 1, visible: false })
        }
      }
      BarAttachedShoulders {
       x: 0; visible: root.barAttached; bodyWidth: root.bodyWidth
         gradientStartColor: Color.barPanels.background; gradientExtent: root.collarExtent; gradientEndColor: root.urgencyColor(root._latchedOutgoing)
      }
    }
    Item {
      id: incomingSlot
      x: 0; width: parent.width; height: parent.height
      visible: root.ownsOutput && root._latchedIncoming !== null && root._incomingVisible
      opacity: root.presentationFrame.phase === "opening" || root.presentationFrame.phase === "switching" ? root._progress : 1
      transform: Scale { origin.x: incomingSlot.width / 2; origin.y: 0; yScale: opacity }
      Loader {
        id: incomingLoader
       active: !root.surfacesSuppressed && root._latchedIncoming !== null
        sourceComponent: NotificationCard {
          x: root.barAttached ? root.shoulderRadius : 0; width: root.bodyWidth
           snapshot: root._latchedIncoming; interactive: root.presentationFrame.phase === "open"
            && root.incomingIdentity === identity(root._latchedIncoming)
           fontFamily: root.fontFamily; attachedMode: root.barAttached; attachedContentTopInset: root.attachedContentTopInset
           gradientStartColor: Color.barPanels.background; gradientExtent: root.collarExtent
          metadataOpacity: root._metadataOpacity; contentOpacity: root._contentOpacity
          countdown: root.presentationFrame.countdown
          onHoveredChanged: root.hoverChanged(identity(root._latchedIncoming), hovered)
          onCloseRequested: root.dismissRequested(identity(root._latchedIncoming))
          onCardClicked: root.cardClicked(identity(root._latchedIncoming))
          onActionClicked: function(identifier) { root.actionClicked(identity(root._latchedIncoming), identifier) }
        }
      }
      BarAttachedShoulders {
        x: 0; visible: root.barAttached; bodyWidth: root.bodyWidth
         gradientStartColor: Color.barPanels.background; gradientExtent: root.collarExtent; gradientEndColor: root.urgencyColor(root._latchedIncoming)
        onHoveredChanged: root.hoverChanged(identity(root._latchedIncoming), hovered)
      }
    }
    Item {
      id: stableInputRegion
      x: root.barAttached ? root.shoulderRadius : 0; y: 0; width: root.bodyWidth
      height: incomingLoader.item ? incomingLoader.item.height : 0
      visible: !root.surfacesSuppressed && root.ownsOutput && root.presentationFrame.phase === "open" && root.incoming !== null
    }
  }

  ElevatedSurface {
    id: cueSurface
     visible: !root.surfacesSuppressed && root.cueVisible
     revealed: !root.surfacesSuppressed && root.cueVisible; entranceX: Style.space(12); concealedScale: 1.0
    motionDuration: 160; shadowBlurMax: 48; shadowBlurAmount: 1.0; shadowOpacityAmount: 0.78; shadowOffsetY: 14
    shadowScaleAmount: 1.03; effectPaddingRect: Qt.rect(-8, -8, 16, 30); anchors.right: parent.right; anchors.top: parent.top
    anchors.topMargin: (root.barPosition === "top" && root.shell && root.shell.barVisible !== false
      ? root.barSize + Style.gapsOut : Style.gapsOut) + Style.space(24)
    anchors.rightMargin: (root.barPosition === "right" && root.shell && root.shell.barVisible !== false
      ? root.barSize + Style.gapsOut : Style.gapsOut) + Style.space(24)
    implicitWidth: Style.space(250); implicitHeight: Style.space(48); radius: 0
    color: Color.notifications.background; borderSpec: Border.none()
    Text { anchors.centerIn: parent; text: root.cueGlyph; color: Color.notifications.text; font.family: Style.font.family; font.pixelSize: Style.font.display }
  }
}
