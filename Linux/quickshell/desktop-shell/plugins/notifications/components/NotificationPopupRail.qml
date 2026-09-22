import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
  id: root

  required property var output
  required property var presentationFrame
  required property bool ownsOutput
  property bool surfacesSuppressed: false
  property var shell: null
  property string fontFamily: Style.font.family
  property string barPosition: "top"
  property real barSize: Style.bar.sizeHorizontal

  QtObject {
    id: detachedBarPosition
    property string position: "top"
  }

  readonly property var visual: root.presentationFrame.visual || ({})
  readonly property var incoming: root.visual.incoming || root.presentationFrame.active
  readonly property string incomingIdentity: root.incoming ? String(root.incoming.identity || "") : ""
  readonly property bool barAttached: root.barPosition === "top"
    && root.shell && root.shell.barVisible !== false
  readonly property real bodyWidth: Math.min(Style.space(380),
    Math.max(1, width - Style.gapsOut * (barAttached ? 2 : 1)
      - Style.popupOuterRadius * (barAttached ? 2 : 0)))
  readonly property real attachedContentTopInset: Style.space(32)

  signal dismissRequested(string identity)
  signal cardClicked(string identity)
  signal actionClicked(string identity, string identifier)
  signal hoverChanged(string identity, bool hovered)
  signal transitionFinished(int token, string kind, string outputName)

  property var _paintedSnapshot: null
  property bool _popupOpen: false
  property string _stage: ""
  property string _latchedKind: ""
  property int _latchedToken: 0
  property string _latchedOutput: ""
  property var _latchedIncoming: null
  property var _latchedOutgoing: null
  property real _metadataOpacity: 1
  property real _contentOpacity: 1
  property real _animationStartMetadata: 0
  property real _animationStartContent: 0
  property string _lastTransition: ""
  property real _switchProgress: 0
  readonly property bool switching: root._stage === "switching"
  readonly property var nextSnapshot: root.switching ? root._latchedIncoming
    : (root.presentationFrame.pending.length ? root.presentationFrame.pending[0] : null)

  screen: root.output
  visible: !root.surfacesSuppressed && (root.ownsOutput
    && root._paintedSnapshot !== null && root.presentationFrame.phase !== "closed"
    && root.presentationFrame.phase !== "hidden")
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "desktop-shell-notification-rail"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region { item: null }

  function identity(snapshot) { return snapshot ? String(snapshot.identity || "") : "" }
  function frameKey(frame) {
    var v = frame.visual || {}
    return String(frame.phase || "") + ":" + String(v.token || 0) + ":" + String(v.kind || "")
      + ":" + String(v.output || "") + ":" + identity(v.incoming) + ":" + identity(v.outgoing)
  }
  function beginOpening() {
    root._paintedSnapshot = root._latchedIncoming
    root._animationStartMetadata = 0
    root._animationStartContent = 0
    root._stage = "opening"
    root._metadataOpacity = Motion.enabled ? 0 : 1
    root._contentOpacity = Motion.enabled ? 0 : 1
    root._popupOpen = true
    if (Motion.enabled) openContentMotion.restart()
    root.scheduleEndpointCheck()
  }
  function beginClosing() {
    root._paintedSnapshot = root._paintedSnapshot || root._latchedOutgoing
    root._stage = "closing"
    if (!Motion.enabled) {
      root._metadataOpacity = 0
      root._contentOpacity = 0
    }
    root._popupOpen = false
    if (Motion.enabled) closeContentMotion.restart()
    root.scheduleEndpointCheck()
  }
  function beginSwitch() {
    root._paintedSnapshot = root._paintedSnapshot || root._latchedOutgoing
    if (!root.switching) root._switchProgress = 0
    root._stage = "switching"
    root._popupOpen = true
    root._metadataOpacity = 1
    root._contentOpacity = 1
    if (Motion.enabled) switchMotion.restart()
    else Qt.callLater(root.completeSwitch)
  }
  function completeSwitch() {
    if (!root.switching || root.surfacesSuppressed || !root.completionIsCurrent()) return
    root._paintedSnapshot = root._latchedIncoming
    root._switchProgress = 0
    root.finishTransition()
  }
  function latchTransition() {
    if (root.surfacesSuppressed) return
    var frame = root.presentationFrame
    var v = frame.visual || {}
    var kind = String(v.kind || "")
    if (!kind || !v.token) return
    if (root._lastTransition === root.frameKey(frame)) return

    // A repeated dismiss advances the logical front even during the handoff.
    var paintedSnapshot = root.switching ? root._latchedIncoming : root._paintedSnapshot
    var paintedMetadata = root._metadataOpacity
    var paintedContent = root._contentOpacity
    openContentMotion.stop(); closeContentMotion.stop(); switchMotion.stop()
    if (root.switching) {
      root._paintedSnapshot = paintedSnapshot
      root._switchProgress = 0
    }
    root._lastTransition = root.frameKey(frame)
    root._latchedKind = kind
    root._latchedToken = Number(v.token)
    root._latchedOutput = String(v.output || "")
    root._latchedIncoming = v.incoming || null
    root._latchedOutgoing = kind === "close" || kind === "switch"
      ? (paintedSnapshot || v.outgoing || null) : (v.outgoing || null)
    root._metadataOpacity = kind === "close" || kind === "switch" ? paintedMetadata : 0
    root._contentOpacity = kind === "close" || kind === "switch" ? paintedContent : 0
    root._animationStartMetadata = root._metadataOpacity
    root._animationStartContent = root._contentOpacity
    if (kind === "open") root.beginOpening()
    else if (kind === "switch") root.beginSwitch()
    else root.beginClosing()
  }
  function completionIsCurrent() {
    var route = root.presentationFrame.route || ({})
    var v = root.presentationFrame.visual || ({})
    return root.ownsOutput && route.visible
      && String(route.output || "") === root._latchedOutput
      && Number(v.token) === root._latchedToken
      && String(v.kind || "") === root._latchedKind
      && String(v.output || "") === root._latchedOutput
  }
  function finishTransition() {
    if (root.surfacesSuppressed || !root.completionIsCurrent()) return
    var token = root._latchedToken
    var kind = root._latchedKind
    var outputName = root._latchedOutput
    root._latchedKind = ""
    root._latchedToken = 0
    root._latchedOutput = ""
    root._stage = ""
    root.transitionFinished(token, kind, outputName)
  }
  function completeContentTransition() {
    if (root._stage === "opening") root.finishTransition()
  }
  function handleRevealed() { root.completeContentTransition() }
  function handleConcealed() {
    if (root._stage === "closing") root.finishTransition()
  }
  function scheduleEndpointCheck() {
    Qt.callLater(function() {
      if (root._stage === "opening") {
        if (notificationPopup.revealProgress >= 1) root.handleRevealed()
      } else if (root._stage === "closing") {
        if (notificationPopup.revealProgress <= 0) root.handleConcealed()
      }
    })
  }
  function clearPresentationState() {
    openContentMotion.stop(); closeContentMotion.stop(); switchMotion.stop()
    root._latchedKind = ""; root._latchedToken = 0; root._latchedOutput = ""
    root._latchedIncoming = null; root._latchedOutgoing = null
    root._paintedSnapshot = null; root._popupOpen = false; root._stage = ""
    root._metadataOpacity = 1; root._contentOpacity = 1
    root._animationStartMetadata = 0; root._animationStartContent = 0
    root._lastTransition = ""
    root._switchProgress = 0
  }
  function syncPresentationFrame() {
    var frame = root.presentationFrame
    if (frame.phase === "closed" || frame.phase === "hidden") root.clearPresentationState()
    else if (root.surfacesSuppressed || !root.ownsOutput) {
      root.clearPresentationState()
    } else if (frame.phase === "opening" || frame.phase === "closing" || frame.phase === "switching") {
      root.latchTransition()
    } else if (frame.phase === "open") {
      switchMotion.stop()
      root._switchProgress = 0
      root._latchedIncoming = frame.visual.incoming || frame.active
      root._paintedSnapshot = root._latchedIncoming
      root._popupOpen = true; root._stage = ""
      root._metadataOpacity = 1; root._contentOpacity = 1
    }
  }

  onPresentationFrameChanged: root.syncPresentationFrame()
  onSurfacesSuppressedChanged: root.syncPresentationFrame()
  onOwnsOutputChanged: root.syncPresentationFrame()
  Component.onCompleted: root.syncPresentationFrame()

  Connections {
    target: Motion
    function onEnabledChanged() {
      if (Motion.enabled) return
      openContentMotion.stop(); closeContentMotion.stop(); switchMotion.stop()
      if (root.switching) { root.completeSwitch(); return }
      root._metadataOpacity = root._stage === "closing" ? 0 : 1
      root._contentOpacity = root._metadataOpacity
      root.scheduleEndpointCheck()
    }
  }

  NumberAnimation {
    id: switchMotion
    target: root; property: "_switchProgress"; to: 1
    duration: 120; easing.type: Easing.OutCubic
    onFinished: root.completeSwitch()
  }

  ParallelAnimation {
    id: openContentMotion
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
    id: closeContentMotion
    NumberAnimation {
      target: root; property: "_metadataOpacity"; from: root._animationStartMetadata; to: 0
      duration: PopupMotion.overlayHeaderCloseDuration; easing.type: PopupMotion.overlayContentCloseEasing
    }
    NumberAnimation {
      target: root; property: "_contentOpacity"; from: root._animationStartContent; to: 0
      duration: PopupMotion.overlayBodyCloseDuration; easing.type: PopupMotion.overlayContentCloseEasing
    }
  }

  Item {
    id: popupAnchorItem
    x: Math.max(0, root.width - Style.gapsOut - notificationPopup.implicitWidth / 2)
    y: 0
    width: 1
    height: root.barAttached ? root.barSize : 0
  }

  PopupCard {
    id: notificationPopup
    anchorItem: popupAnchorItem
    owner: root
    bar: root.barAttached ? root.shell.bar : detachedBarPosition
    open: root._popupOpen
    triggerMode: "passive"
    coordinateWithBar: false
    inputEnabled: root.ownsOutput && !root.surfacesSuppressed && root.presentationFrame.phase === "open"
      && root.incomingIdentity === root.identity(root._paintedSnapshot)
    attached: root.barAttached
    margin: root.barAttached ? 0 : Style.gapsOut
    padding: 0
    surfaceOffsetY: root.barAttached
      ? -Math.min(root.barSize, Math.max(0, elevationInset - shadowPadding)) : 0
    contentWidth: root.bodyWidth
    contentHeight: cardStack.implicitHeight
    borderSpec: Border.none()
    onRevealFinished: root.handleRevealed()
    onConcealFinished: root.handleConcealed()
    onContainsMouseChanged: {
      if (root._paintedSnapshot) root.hoverChanged(root.identity(root._paintedSnapshot), containsMouse)
    }

    Item {
      id: cardStack
      width: notificationPopup.contentWidth
      height: implicitHeight
      implicitHeight: {
        var front = popupContentLoader.item ? popupContentLoader.item.implicitHeight : 1
        var back = nextContentLoader.item ? nextContentLoader.item.implicitHeight : front
        return root.switching ? front + (back - front) * root._switchProgress : front
      }
      clip: true

      // Keep the next card instantiated beneath the front card before dismissal.
      Loader {
        id: nextContentLoader
        width: parent.width
        active: !root.surfacesSuppressed && root.ownsOutput && root.nextSnapshot !== null
        visible: root.switching
        opacity: root.switching ? root._switchProgress : 0
        sourceComponent: NotificationContent {
          width: notificationPopup.contentWidth
          snapshot: root.nextSnapshot
          interactive: false
          fontFamily: root.fontFamily
          attachedMode: root.barAttached
          attachedContentTopInset: root.attachedContentTopInset
        }
      }

      Loader {
        id: popupContentLoader
        width: parent.width
        x: root.switching ? Style.space(32) * root._switchProgress : 0
        opacity: root.switching ? 1 - root._switchProgress : 1
        active: !root.surfacesSuppressed && root._paintedSnapshot !== null
        sourceComponent: NotificationContent {
          width: notificationPopup.contentWidth
          snapshot: root._paintedSnapshot
          countdown: root.presentationFrame.countdown
          interactive: notificationPopup.inputEnabled
          fontFamily: root.fontFamily
          attachedMode: root.barAttached
          attachedContentTopInset: root.attachedContentTopInset
          metadataOpacity: root._metadataOpacity
          contentOpacity: root._contentOpacity
          onCloseRequested: root.dismissRequested(root.identity(root._paintedSnapshot))
          onCardClicked: root.cardClicked(root.identity(root._paintedSnapshot))
          onActionClicked: identifier => root.actionClicked(root.identity(root._paintedSnapshot), identifier)
        }
      }
    }
  }

}
