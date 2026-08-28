import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
  id: root

  required property var output
  required property var presentationFrame
  property var shell: null
  property bool cueVisible: false
  property string fontFamily: Style.font.family
  property string barPosition: "top"
  property real barSize: Style.bar.sizeHorizontal
  property string cueGlyph: ""

  readonly property var visual: root.presentationFrame.visual || ({})
  readonly property var incoming: root.visual.incoming || root.presentationFrame.active
  readonly property var outgoing: root.visual.outgoing
  readonly property var incomingDeck: root.visual.incomingDeck || ({ snapshots: [], queuedCount: 0, criticalPending: false })
  readonly property var outgoingDeck: root.visual.outgoingDeck || ({ snapshots: [], queuedCount: 0, criticalPending: false })
  readonly property string incomingIdentity: root.incoming ? String(root.incoming.identity || "") : ""
  readonly property string outgoingIdentity: root.outgoing ? String(root.outgoing.identity || "") : ""
  readonly property bool onOutput: root.presentationFrame.route
    && String(root.presentationFrame.route.output || "") === String(root.output.name)
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

  property real _progress: 1
  property bool _incomingVisible: true
  property string _latchedKind: ""
  property int _latchedToken: 0
  property string _latchedOutput: ""
  property var _latchedIncoming: null
  property var _latchedOutgoing: null
  property var _latchedIncomingDeck: null
  property var _latchedOutgoingDeck: null
  property string _lastTransition: ""
  property real _deckSettleOffset: 0

  screen: root.output
  visible: root.cueVisible || (root.onOutput && root.hasCards && root.presentationFrame.phase !== "closed"
    && root.presentationFrame.phase !== "hidden")
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
    var frame = root.presentationFrame
    var v = frame.visual || {}
    var kind = String(v.kind || "")
    if (!kind || !v.token || root._lastTransition === root.frameKey(frame)) return
    root._lastTransition = root.frameKey(frame)
    root._latchedKind = kind
    root._latchedToken = Number(v.token)
    root._latchedOutput = String(v.output || "")
    root._latchedIncoming = v.incoming || null
    root._latchedOutgoing = v.outgoing || null
    root._latchedIncomingDeck = v.incomingDeck || ({ snapshots: [], queuedCount: 0, criticalPending: false })
    root._latchedOutgoingDeck = v.outgoingDeck || ({ snapshots: [], queuedCount: 0, criticalPending: false })
    root._incomingVisible = kind !== "close" && kind !== "switch"
    root._progress = kind === "close" ? 1 : 0
    if (!Motion.enabled) {
      root._incomingVisible = kind !== "close"
      root._progress = 1
      root.finishTransition()
    } else if (kind === "open") openMotion.restart()
    else if (kind === "close") closeMotion.restart()
    else switchMotion.restart()
  }
  function finishTransition() {
    if (!root._latchedKind || root._latchedToken <= 0) return
    var token = root._latchedToken
    var kind = root._latchedKind
    var outputName = root._latchedOutput
    root._progress = 1
    root._incomingVisible = kind !== "close"
    root._latchedKind = ""
    root._latchedToken = 0
    root._latchedOutput = ""
    root.transitionFinished(token, kind, outputName)
  }
  function stableDeck() {
    var frame = root.presentationFrame
    if (frame.phase === "switching")
      return root._incomingVisible ? root._latchedIncomingDeck : root._latchedOutgoingDeck
    return root.incomingDeck
  }
  function beginDeckSettle() {
    if (!Motion.enabled) { root._deckSettleOffset = 0; return }
    root._deckSettleOffset = -Style.space(12)
    deckSettle.restart()
  }

  onPresentationFrameChanged: {
    var frame = root.presentationFrame
    if (frame.phase === "opening" || frame.phase === "closing" || frame.phase === "switching") root.latchTransition()
    else if (frame.phase === "open") {
      root._latchedIncoming = frame.visual.incoming || frame.active
      root._latchedIncomingDeck = frame.visual.incomingDeck
      root._incomingVisible = true
      root._progress = 1
    }
  }
  onVisibleChanged: if (root.visible && root.presentationFrame) root.beginDeckSettle()
  Component.onCompleted: root.onPresentationFrameChanged()

  Connections {
    target: Motion
    function onEnabledChanged() {
      if (Motion.enabled) return
      openMotion.stop(); closeMotion.stop(); switchMotion.stop(); deckSettle.stop()
      root._deckSettleOffset = 0
      root.finishTransition()
    }
  }

  NumberAnimation { id: deckSettle; target: root; property: "_deckSettleOffset"; to: 0; duration: 180; easing.type: PopupMotion.overlayContentOpenEasing }
  NumberAnimation { id: openMotion; target: root; property: "_progress"; from: 0; to: 1; duration: 360; easing.type: PopupMotion.surfaceOpenEasing; onFinished: root.finishTransition() }
  NumberAnimation { id: closeMotion; target: root; property: "_progress"; from: 1; to: 0; duration: 320; easing.type: PopupMotion.surfaceCloseEasing; onFinished: root.finishTransition() }
  SequentialAnimation {
    id: switchMotion
    NumberAnimation { target: root; property: "_progress"; from: 1; to: 0; duration: 320; easing.type: PopupMotion.surfaceCloseEasing }
    ScriptAction { script: { root._incomingVisible = true; root._progress = 0 } }
    NumberAnimation { target: root; property: "_progress"; from: 0; to: 1; duration: 360; easing.type: PopupMotion.surfaceOpenEasing }
    ScriptAction { script: root.finishTransition() }
  }

  Rectangle {
    id: thirdDeck
    property var deck: root.stableDeck()
    property var snapshot: deck.snapshots && deck.snapshots.length > 2 ? deck.snapshots[2] : null
    visible: root.onOutput && root.hasCards && snapshot !== null && root.presentationFrame.phase !== "closing"
    x: cardFrame.x + root.shoulderRadius + Style.space(16)
    y: cardFrame.y + Style.space(18) + root._deckSettleOffset
    width: Math.max(1, root.bodyWidth - Style.space(32)); height: Math.max(Style.space(36), incomingCard.implicitHeight)
    radius: Style.popupInnerRadius; bottomLeftRadius: Style.popupOuterRadius; bottomRightRadius: Style.popupOuterRadius
    color: root.urgencyColor(snapshot); opacity: 1; z: -2
  }
  Rectangle {
    id: nextDeck
    property var deck: root.stableDeck()
    property var snapshot: deck.snapshots && deck.snapshots.length > 1 ? deck.snapshots[1] : null
    visible: root.onOutput && root.hasCards && snapshot !== null && root.presentationFrame.phase !== "closing"
    x: cardFrame.x + root.shoulderRadius + Style.space(8)
    y: cardFrame.y + Style.space(9) + root._deckSettleOffset
    width: Math.max(1, root.bodyWidth - Style.space(16)); height: Math.max(Style.space(42), incomingCard.implicitHeight)
    radius: Style.popupInnerRadius; bottomLeftRadius: Style.popupOuterRadius; bottomRightRadius: Style.popupOuterRadius
    color: root.urgencyColor(snapshot); opacity: 1; z: -1
  }
  Rectangle {
    visible: root.onOutput && root.hasCards && root.stableDeck().criticalPending && root.presentationFrame.hovered
    x: cardFrame.x + cardFrame.width - Style.space(10); y: cardFrame.y - Style.space(8)
    width: Style.space(6); height: width; radius: width / 2; color: Color.notifications.critical
  }
  Text {
    visible: root.onOutput && root.hasCards && root.stableDeck().queuedCount > 0
    x: cardFrame.x + cardFrame.width - Style.space(34); y: cardFrame.y + Style.space(5)
    text: "+" + root.stableDeck().queuedCount; color: Color.notifications.text; font.family: root.fontFamily
    font.pixelSize: Style.font.caption; font.bold: true; z: 2
  }

  Item {
    id: cardFrame
    x: root.width - Style.gapsOut - width; y: root.barAttached ? root.barSize : Style.gapsOut
    width: root.bodyWidth + (root.barAttached ? root.shoulderRadius * 2 : 0)
    height: Math.max(outgoingCard.height, incomingCard.height) + (root.barAttached ? root.shoulderRadius : 0); z: 1

    Item {
      id: outgoingSlot
      x: 0; width: parent.width; height: parent.height
      visible: root._latchedOutgoing !== null && (root.presentationFrame.phase === "closing" || root.presentationFrame.phase === "switching")
      opacity: root.presentationFrame.phase === "switching" ? root._progress : (1 - root._progress)
      transform: Scale { origin.x: outgoingSlot.width / 2; origin.y: 0; yScale: opacity }
      NotificationCard {
        id: outgoingCard; x: root.barAttached ? root.shoulderRadius : 0; width: root.bodyWidth
        snapshot: root._latchedOutgoing; interactive: false; fontFamily: root.fontFamily
        attachedMode: root.barAttached; attachedContentTopInset: root.attachedContentTopInset
        gradientStartColor: Color.barPanels.background; gradientExtent: root.collarExtent
        metadataOpacity: 1; contentOpacity: 1; countdown: ({ identity: "", fraction: 1, visible: false })
      }
      BarAttachedShoulders {
        x: 0; visible: root.barAttached; bodyWidth: root.bodyWidth
        gradientStartColor: Color.barPanels.background; gradientEndColor: root.urgencyColor(root._latchedOutgoing)
      }
    }
    Item {
      id: incomingSlot
      x: 0; width: parent.width; height: parent.height
      visible: root._latchedIncoming !== null && root._incomingVisible
      opacity: root.presentationFrame.phase === "opening" || root.presentationFrame.phase === "switching" ? root._progress : 1
      transform: Scale { origin.x: incomingSlot.width / 2; origin.y: 0; yScale: opacity }
      NotificationCard {
        id: incomingCard; x: root.barAttached ? root.shoulderRadius : 0; width: root.bodyWidth
        snapshot: root._latchedIncoming; interactive: root.presentationFrame.phase === "open"
          && root.incomingIdentity === identity(root._latchedIncoming)
        fontFamily: root.fontFamily; attachedMode: root.barAttached; attachedContentTopInset: root.attachedContentTopInset
        gradientStartColor: Color.barPanels.background; gradientExtent: root.collarExtent
        countdown: root.presentationFrame.countdown
        onHoveredChanged: root.hoverChanged(identity(root._latchedIncoming), hovered)
        onCloseRequested: root.dismissRequested(identity(root._latchedIncoming))
        onCardClicked: root.cardClicked(identity(root._latchedIncoming))
        onActionClicked: function(identifier) { root.actionClicked(identity(root._latchedIncoming), identifier) }
      }
      BarAttachedShoulders {
        x: 0; visible: root.barAttached; bodyWidth: root.bodyWidth
        gradientStartColor: Color.barPanels.background; gradientEndColor: root.urgencyColor(root._latchedIncoming)
        onHoveredChanged: root.hoverChanged(identity(root._latchedIncoming), hovered)
      }
    }
    Item {
      id: stableInputRegion
      x: root.barAttached ? root.shoulderRadius : 0; y: 0; width: root.bodyWidth; height: incomingCard.height
      visible: root.onOutput && root.presentationFrame.phase === "open" && root.incoming !== null
    }
  }

  ElevatedSurface {
    id: cueSurface
    visible: root.cueVisible; revealed: root.cueVisible; entranceX: Style.space(12); concealedScale: 1.0
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
