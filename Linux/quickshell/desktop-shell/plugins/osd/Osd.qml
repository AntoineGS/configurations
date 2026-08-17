import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "OsdModel.js" as OsdModel

Item {
  id: root

  property bool opened: false
  property string icon: OsdModel.widestIcon
  property string message: ""
  property string iconKey: ""
  property real value: 0
  property real maxValue: 100
  property bool hasProgress: false
  property int duration: 1200
  property var targetScreen: null
  property var displayedState: ({
    valid: false,
    iconKey: "",
    icon: "",
    message: "",
    value: 0,
    maxValue: 100,
    hasProgress: false,
    duration: 1200,
    error: ""
  })

  readonly property string focusedMonitorName: Hyprland.focusedMonitor
    ? String(Hyprland.focusedMonitor.name || "") : ""
  readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0
  readonly property int pad: Style.space(12)
  readonly property int gap: Style.space(12)
  readonly property int messageGap: Math.round(root.gap * 2 / 3)
  readonly property int barWidth: Style.space(142)
  readonly property int maxMessageWidth: root.mediaOsd ? Style.space(325) : Style.space(190)
  readonly property int iconInkWidth: Math.ceil(iconMetrics.tightBoundingRect.width)
  readonly property int iconWidth: root.hasProgress
    ? Math.max(root.iconInkWidth, Math.ceil(widestIconMetrics.tightBoundingRect.width))
    : root.iconInkWidth
  readonly property int valueWidth: Math.ceil(Math.max(valueMetrics.advanceWidth, messageMetrics.advanceWidth))
  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  readonly property int contentWidth: root.hasProgress
    ? root.iconWidth + root.gap + root.barWidth + root.gap + root.valueWidth
    : (root.message === "" ? root.iconWidth : root.iconWidth + root.messageGap + root.messageWidth)

  // Prefer the focused compositor monitor. The pure selector falls back to
  // the first available Quickshell screen until the focused output appears.
  function updateScreen() {
    root.targetScreen = OsdModel.screenForMonitor(Quickshell.screens, root.focusedMonitorName)
  }

  onFocusedMonitorNameChanged: if (root.opened) root.updateScreen()

  /**
   * Apply a normalized payload without parsing or validating it in QML.
   *
   * @param {string} payloadJson
   * @returns {string}
   */
  function show(payloadJson) {
    var next = OsdModel.normalizePayload(payloadJson)
    if (!next.valid) return "invalid"

    root.updateScreen()
    root.displayedState = next
    root.iconKey = next.iconKey
    root.maxValue = next.maxValue
    root.hasProgress = next.hasProgress
    root.value = next.value
    root.message = next.message
    root.icon = next.icon
    root.duration = next.duration
    root.opened = true

    if (root.duration > 0) hideTimer.restart()
    else hideTimer.stop()
    return "ok"
  }

  /**
   * Hide the surface while retaining the last valid model state.
   *
   * @returns {string}
   */
  function close() {
    hideTimer.stop()
    root.opened = false
    return "ok"
  }

  /**
   * Serialize the last valid model state and current visibility.
   *
   * @returns {string}
   */
  function state() {
    var snapshot = {}
    for (var key in root.displayedState) snapshot[key] = root.displayedState[key]
    snapshot.opened = root.opened
    return JSON.stringify(snapshot)
  }

  /**
   * Report that the overlay IPC endpoint is available.
   *
   * @returns {string}
   */
  function ping() { return "pong" }

  Timer {
    id: hideTimer
    interval: root.duration
    repeat: false
    onTriggered: root.opened = false
  }

  TextMetrics {
    id: messageMetrics
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Style.font.title
    text: root.message
  }

  TextMetrics {
    id: valueMetrics
    font: messageMetrics.font
    text: "100%"
  }

  TextMetrics {
    id: iconMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.displayLarge
    text: root.icon
  }

  TextMetrics {
    id: widestIconMetrics
    font: iconMetrics.font
    text: OsdModel.widestIcon
  }

  IpcHandler {
    target: "desktop.osd"

    function show(payloadJson: string): string { return root.show(payloadJson) }
    function close(): string { return root.close() }
    function state(): string { return root.state() }
    function ping(): string { return root.ping() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "desktop-shell-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual-only surface: keep the layer-shell input region empty so the OSD
    // never blocks clicks to the desktop below it.
    mask: Region {}

    BorderSurface {
      id: card
      width: card.borderLeft + root.pad + root.contentWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + Style.font.displayLarge + root.pad + card.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(67)
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.space(8)
      opacity: root.opened ? 1 : 0

      Row {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.pad
        anchors.rightMargin: card.borderRight + root.pad
        anchors.bottomMargin: card.borderBottom + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: root.hasProgress ? root.gap : root.messageGap

        Item {
          width: root.iconWidth
          height: parent.height

          Text {
            x: Math.round((root.iconWidth - root.iconInkWidth) / 2 - iconMetrics.tightBoundingRect.x)
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font: iconMetrics.font
            color: Color.popups.text
          }
        }

        Rectangle {
          visible: root.hasProgress
          width: root.barWidth
          height: Math.max(Style.space(6), Style.spacing.sm)
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(Color.popups.text, 0.45)

          Rectangle {
            height: parent.height
            width: parent.width * (root.hasProgress ? root.value / root.maxValue : 0)
            color: Color.accent

            Behavior on width {
              enabled: root.opened
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
          }
        }

        Text {
          visible: root.message !== ""
          width: root.hasProgress ? root.valueWidth : root.messageWidth
          horizontalAlignment: root.hasProgress ? Text.AlignRight : Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
          text: root.message
          font: messageMetrics.font
          color: Color.popups.text
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }
    }
  }
}
