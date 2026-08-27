import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: 0
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property int elevationInset: Math.max(Style.popupOuterRadius, Style.space(24))
  property int shadowPadding: 24
  property int shadowBottomPadding: shadowPadding + 4
  property color borderColor: Color.barPanels.border
  property var borderSpec: Border.localOrSurfaceSpec("bar-panels", "border", borderColor,
    Color.barPanels.border, Math.max(1, Style.space(2)))
  property bool open: false
  property bool centerOnBar: false
  // "click" — uses HyprlandFocusGrab so clicking outside dismisses the popup.
  // "hover" — passive overlay; the owning widget controls open via hover.
  property string triggerMode: "click"

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property bool containsMouse: cardHover.hovered || shoulders.hovered
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : 0
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real entranceX: !bar ? 0 : bar.position === "left" ? -Style.space(6)
    : bar.position === "right" ? Style.space(6) : 0
  readonly property real entranceY: !bar ? 0 : bar.position === "top" ? -Style.space(6)
    : bar.position === "bottom" ? Style.space(6) : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  function clampParallelOrigin(value, popupExtent, cardExtent, availableExtent) {
    var min = root.margin
    var max = availableExtent - popupExtent - root.margin
    if (max < min) {
      min = root.margin - root.elevationInset
      max = availableExtent - cardExtent - root.margin - root.elevationInset
    }
    return Math.max(min, Math.min(value, max))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  visible: open || card.opacity > 0
  color: "transparent"
  implicitWidth: contentWidth + elevationInset * 2
  implicitHeight: contentHeight + elevationInset + shadowBottomPadding
  mask: Region {
    Region { item: card }
    Region { item: shoulders }
  }

  onOpenChanged: {
    if (!bar) return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  // Outside-click dismissal via Hyprland's focus grab. While `active`, input
  // is routed only to the listed windows; clicking anywhere else clears the
  // grab and we close the popup. Skipped for hover-mode popups so the cursor
  // can move freely between the trigger and the popup.
  HyprlandFocusGrab {
    active: root.open && root.triggerMode === "click"
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.close()
  }

  anchor {
    id: popupAnchor
    window: anchorItem ? anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return

      var target = root.anchorItem
      var popupWidth = root.implicitWidth
      var popupHeight = root.implicitHeight
      var localX = target.width / 2 - popupWidth / 2
      var localY = target.height + root.margin - root.elevationInset

      if (root.bar.position === "bottom") {
        localY = -popupHeight - root.margin + root.elevationInset
      } else if (root.bar.position === "left") {
        localX = target.width + root.margin - root.elevationInset
        localY = target.height / 2 - popupHeight / 2
      } else if (root.bar.position === "right") {
        localX = -popupWidth - root.margin + root.elevationInset
        localY = target.height / 2 - popupHeight / 2
      }

      var window = target.QsWindow.window
      if (!window) return

      if (root.centerOnBar) {
        var cx = 0
        var cy = 0
        if (root.bar.position === "top" || root.bar.position === "bottom") {
          cx = window.width / 2 - popupWidth / 2
          cy = root.bar.position === "bottom"
            ? -popupHeight - root.margin + root.elevationInset
            : window.height + root.margin - root.elevationInset
          cx = root.clampParallelOrigin(cx, popupWidth, root.contentWidth, window.width)
        } else {
          cx = root.bar.position === "left"
            ? window.width + root.margin - root.elevationInset
            : -popupWidth - root.margin + root.elevationInset
          cy = window.height / 2 - popupHeight / 2
          cy = root.clampParallelOrigin(cy, popupHeight, root.contentHeight, window.height)
        }

        popupAnchor.rect.x = Math.round(cx)
        popupAnchor.rect.y = Math.round(cy)
        return
      }

      var point = window.contentItem.mapFromItem(target, localX, localY)

      if (root.bar.position === "top" || root.bar.position === "bottom") {
        point.x = root.clampParallelOrigin(point.x, popupWidth, root.contentWidth, window.width)
      } else {
        point.y = root.clampParallelOrigin(point.y, popupHeight, root.contentHeight, window.height)
      }

      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  Item {
    id: cardFrame
    x: root.elevationInset - root.shadowPadding
    y: root.elevationInset
    width: root.contentWidth + root.shadowPadding * 2
    height: root.contentHeight + root.shadowBottomPadding
    clip: true

    ElevatedSurface {
      id: card
      x: root.shadowPadding
      width: root.contentWidth
      height: root.contentHeight
      color: Color.barPanels.background
      borderSpec: root.borderSpec
      padding: root.padding
      radius: Style.popupOuterRadius
      topLeftRadius: 0
      topRightRadius: 0
      bottomLeftRadius: Style.popupOuterRadius
      bottomRightRadius: Style.popupOuterRadius
      revealed: root.open
      revealDuration: Motion.popupOpenDuration
      concealDuration: Motion.popupCloseDuration
      revealEasing: Motion.popupOpenEasing
      concealEasing: Motion.popupCloseEasing
      concealedXScale: 1
      concealedYScale: 0
      scaleOriginX: width / 2
      scaleOriginY: 0

      Item {
        id: contentHolder
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
      }

      HoverHandler {
        id: cardHover
      }
    }

    BarAttachedShoulders {
      id: shoulders
      z: 1
      bodyWidth: card.width
      surfaceColor: card.color
      revealProgress: card.revealProgress
    }
  }
}
