import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "desktop.monitor"
  ipcTarget: "desktop.monitor"
  manageIpc: false
  property var pluginRegistry: null
  property int brightnessPreviewPercent: monitorService ? monitorService.brightnessPercent : 1
  property bool cursorActive: false
  property int selectedIndex: 0
  property int nativeTopologyGeneration: 0

  readonly property var monitorService: bar && bar.shell ? bar.shell.serviceFor("desktop.monitor") : null
  readonly property var hardwareState: monitorService
    ? monitorService.hardwareState : ({ available: false, stale: false, data: {} })
  readonly property int brightnessPercent: monitorService ? monitorService.brightnessPercent : 1

  function refreshNativeTopology() {
    nativeTopologyGeneration++
  }

  readonly property var nativeTopology: Model.normalizeMonitors(
    nativeTopologyGeneration >= 0 && Hyprland.monitors ? Hyprland.monitors.values : [], Hyprland.focusedMonitor)
  readonly property bool capabilityAvailable: nativeTopology.monitors.length > 0
  readonly property var stateData: hardwareState && hardwareState.data ? hardwareState.data : ({})
  readonly property var displays: nativeTopology.monitors
  readonly property var brightness: stateData.brightness || ({ available: false, percent: 1 })
  readonly property var keyboardBrightness: stateData.keyboardBrightness || ({ available: false, percent: 0 })
  readonly property string internalMonitor: nativeTopology.internalMonitor
  readonly property bool internalEnabled: nativeTopology.internalEnabled
  readonly property string focusedMonitor: nativeTopology.focusedMonitor
  readonly property int enabledDisplayCount: Model.enabledDisplayCount(displays)
  readonly property color foreground: panelForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function reportCapability() {
    var registry = pluginRegistry || (bar && bar.shell ? bar.shell.pluginRegistry : null)
    if (!registry) return
    var scope = "capability:panel:" + moduleName
    if (capabilityAvailable) registry.clearPluginError(moduleName, scope)
    else registry.recordPluginError(moduleName, "Controllable display unavailable", scope)
  }

  function refresh() {
    return monitorService ? monitorService.refresh() : false
  }

  function setBrightness(value) {
    if (monitorService) monitorService.setBrightness(value)
  }

  function syncBrightnessPreview() {
    if (!root.monitorService || brightnessSlider.dragging || root.monitorService.operationPending) return
    root.brightnessPreviewPercent = root.monitorService.brightnessPercent
  }

  function handleBrightnessDraggingChanged(dragging) {
    if (!dragging) Qt.callLater(root.syncBrightnessPreview)
  }

  function releaseBrightness(value) {
    var next = Model.clampBrightness(value)
    root.brightnessPreviewPercent = next
    root.setBrightness(next)
  }

  function setKeyboardBrightness(action) {
    if (monitorService) monitorService.setKeyboardBrightness(action)
  }

  function toggleInternal() {
    if (monitorService) monitorService.runAction(["monitor", "toggle-internal"])
  }

  function toggleMirror() {
    if (monitorService) monitorService.runAction(["monitor", "toggle-mirror"])
  }

  function moveCursor(delta) {
    if (displays.length === 0) return
    selectedIndex = Math.max(0, Math.min(displays.length - 1, selectedIndex + delta))
    cursorActive = true
  }

  function activateCursor() {
    if (selectedIndex >= 0 && selectedIndex < displays.length) toggleInternal()
  }

  visible: capabilityAvailable
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  onCapabilityAvailableChanged: reportCapability()
  onPluginRegistryChanged: reportCapability()
  onBarChanged: reportCapability()
  Component.onCompleted: {
    reportCapability()
    if (monitorService) monitorService.refreshNativeMonitors(false)
    refresh()
  }

  ServiceConsumer {
    id: monitorConsumer
    service: root.monitorService
    active: true
  }

  Connections {
    target: root.monitorService
    function onBrightnessPercentChanged() { root.syncBrightnessPreview() }
    function onOperationPendingChanged() { root.syncBrightnessPreview() }
  }

  Connections {
    target: Hyprland.monitors
    function onValuesChanged() { root.refreshNativeTopology() }
  }

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() { root.refreshNativeTopology() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.displayIcon(root.displays.length)
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.capabilityAvailable
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0 && root.keyboardBrightness.available) {
          root.setKeyboardBrightness(dx > 0 ? "up" : "down")
        }
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Display"
            meta: root.focusedMonitor || "No focused display"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: Model.displayIcon(root.displays.length)
                color: root.panelSecondary
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSectionHeader {
            text: "BRIGHTNESS"
            visible: root.brightness.available
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          CursorSurface {
            width: parent.width
            visible: root.brightness.available
            implicitHeight: brightnessSlider.implicitHeight + Style.spacing.controlGap
            foreground: root.foreground
            outline: true
            hasCursor: root.cursorActive && root.selectedIndex < 0

            PanelSlider {
              id: brightnessSlider
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              bar: root.bar
              minimum: 1
              maximum: 100
              step: 1
              integer: true
              value: root.brightnessPreviewPercent
              onMoved: root.brightnessPreviewPercent = Math.round(liveValue)
              onDraggingChanged: root.handleBrightnessDraggingChanged(dragging)
              onReleased: root.releaseBrightness(value)
            }
          }

          Text {
            width: parent.width
            visible: root.brightness.available
            text: root.brightnessPreviewPercent + "%" + (root.brightness.device ? " · " + root.brightness.device : "")
            color: root.panelSecondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            visible: root.keyboardBrightness.available
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "KEYBOARD BACKLIGHT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Row {
              spacing: Style.space(6)
              Button {
                text: "Down"
                foreground: root.foreground
                onClicked: root.setKeyboardBrightness("down")
              }
              Button {
                text: "Cycle"
                foreground: root.foreground
                onClicked: root.setKeyboardBrightness("cycle")
              }
              Button {
                text: "Up"
                foreground: root.foreground
                onClicked: root.setKeyboardBrightness("up")
              }
              Text {
                text: root.keyboardBrightness.percent + "%"
                color: root.panelSecondary
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "DISPLAYS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.displays
            CursorSurface {
              required property var modelData
              required property int index
              width: column.width
              foreground: root.foreground
              current: modelData.focused
              hasCursor: root.cursorActive && root.selectedIndex === index
              implicitHeight: Style.space(42)

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text {
                  text: modelData.name || "Display"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  width: parent.width - scaleLabel.implicitWidth - Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  id: scaleLabel
                  text: (modelData.scale || 1) + "x"
                  color: root.panelSecondary
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: root.toggleInternal()
              }
            }
          }

          Row {
            spacing: Style.space(6)
            visible: root.internalMonitor !== "" && root.displays.length > 1
            Button {
              text: "Toggle internal"
              foreground: root.foreground
              onClicked: root.toggleInternal()
            }
            Button {
              text: root.nativeTopology.mirrorEnabled === true ? "Unmirror" : "Mirror"
              foreground: root.foreground
              onClicked: root.toggleMirror()
            }
          }
        }
      }
    }
  }
}
