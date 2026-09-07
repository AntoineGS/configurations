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
  property string testBarMonitor: ""
  property int brightnessPreviewPercent: root.previewBrightnessValue(root.brightness)
  property int keyboardBrightnessPercent: 0
  property bool cursorActive: false
  property int selectedIndex: -1
  property real previewScale: 1
  property int nativeTopologyGeneration: 0
  property string brightnessDragConnector: ""
  property string brightnessDragIdentity: ""
  property string brightnessDragTopology: ""
  property bool brightnessDragInvalidated: false
  readonly property alias displayBrightnessControl: brightnessSlider
  readonly property alias keyboardBrightnessControl: keyboardBrightnessSlider
  readonly property alias brightnessPopup: popup
  readonly property alias brightnessUnavailableMessage: brightnessUnavailableText
  readonly property alias brightnessValueLabel: brightnessValueText

  readonly property var monitorService: bar && bar.shell ? bar.shell.serviceFor("desktop.monitor") : null
  readonly property string hostname: monitorService && monitorService.hostname
    ? String(monitorService.hostname) : ""
  readonly property var hardwareState: monitorService
    ? monitorService.hardwareState : ({ available: false, stale: false, data: {} })

  function refreshNativeTopology() {
    nativeTopologyGeneration++
  }

  readonly property var nativeTopology: Model.normalizeMonitors(
    nativeTopologyGeneration >= 0 && Hyprland.monitors ? Hyprland.monitors.values : [], Hyprland.focusedMonitor)
  readonly property bool capabilityAvailable: nativeTopology.monitors.length > 0
  readonly property var stateData: hardwareState && hardwareState.data ? hardwareState.data : ({})
  readonly property var displays: nativeTopology.monitors
  readonly property var keyboardBrightness: stateData.keyboardBrightness || ({ available: false, percent: 0 })
  readonly property string internalMonitor: nativeTopology.internalMonitor
  readonly property bool internalEnabled: nativeTopology.internalEnabled
  readonly property string focusedMonitor: nativeTopology.focusedMonitor
  readonly property int enabledDisplayCount: Model.enabledDisplayCount(displays)
  readonly property color foreground: panelForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var barWindow: button.QsWindow.window
  readonly property string barMonitor: root.testBarMonitor !== ""
    ? root.testBarMonitor : (barWindow && barWindow.screen ? String(barWindow.screen.name || "") : "")
  readonly property var selectedDisplay: displayForMonitor(barMonitor)
  readonly property real selectedScale: selectedDisplay ? selectedDisplay.scale : 1
  readonly property var scaleOptions: validScaleOptions(selectedDisplay)
  readonly property var activeMonitors: displays.map(function(display) { return display.name })
  readonly property bool presetLayoutsAvailable: hostname === "antoinews-linux"
  readonly property string layoutMode: {
    if (activeMonitors.length === 1) return "single"
    var right = activeMonitors.indexOf("DP-1") !== -1
    var left = activeMonitors.indexOf("DP-2") !== -1
    var headless = activeMonitors.indexOf("HEADLESS-1") !== -1
    if (right && left && !headless && activeMonitors.length === 2) return "physical"
    if (right && !left && headless && activeMonitors.length === 2) return "headless"
    return "mixed"
  }
  readonly property string modeLetter: layoutMode === "physical" ? "P"
    : layoutMode === "headless" ? "H"
    : layoutMode === "single" ? "S" : "?"
  readonly property string modeLabel: layoutMode === "physical" ? "Both physical monitors"
    : layoutMode === "headless" ? "Headless + right physical"
    : layoutMode === "single" ? "Single monitor: " + (activeMonitors[0] || barMonitor)
    : "Mixed monitor layout"
  readonly property var layoutOptions: [
    { mode: "physical", letter: "P", label: "Both physical monitors" },
    { mode: "headless", letter: "H", label: "Headless + right physical" },
    { mode: "single", letter: "S", label: "Single monitor: " + (barMonitor || "current") }
  ]

  readonly property var brightness: {
    if (!root.monitorService || !root.monitorService.brightnessSnapshot)
      return { available: false, stale: false, percent: null, error: "Brightness service unavailable" }
    return root.monitorService.brightnessFor(root.barMonitor)
  }
  readonly property bool brightnessPending: {
    if (!root.monitorService) return false
    root.monitorService.operationPending
    return root.monitorService.brightnessPending(root.barMonitor)
  }
  readonly property string brightnessError: {
    if (!root.monitorService) return "Brightness service unavailable"
    root.monitorService.brightnessSnapshot
    var error = root.monitorService.brightnessError(root.barMonitor)
    return error === undefined || error === null ? "Brightness unavailable" : String(error)
  }
  readonly property bool brightnessActionable: root.brightness && root.brightness.available === true
    && root.brightness.stale !== true && root.brightness.error === ""
    && root.brightness.percent !== null && root.brightness.percent !== undefined
  readonly property bool brightnessMeasurementKnown: root.brightness && typeof root.brightness.percent === "number"
    && isFinite(root.brightness.percent)

  function displayForMonitor(name) {
    for (var i = 0; i < displays.length; i++)
      if (displays[i].name === name) return displays[i]
    return null
  }

  function validScaleOptions(display) {
    if (!display || display.width <= 0 || display.height <= 0)
      return [{ value: 1, command: "1" }, { value: 2, command: "2" }]
    var result = []
    for (var numerator = 120; numerator <= 240; numerator++) {
      if ((display.width * 120) % numerator !== 0 || (display.height * 120) % numerator !== 0) continue
      var value = numerator / 120
      var command = Math.floor(value * 10000000 + 0.01) / 10000000
      result.push({ value: value, command: String(command) })
    }
    return result
  }

  function nearestScaleIndex(scale) {
    var nearest = 0
    var distance = Infinity
    for (var i = 0; i < scaleOptions.length; i++) {
      var candidateDistance = Math.abs(scaleOptions[i].value - Number(scale))
      if (candidateDistance < distance) {
        nearest = i
        distance = candidateDistance
      }
    }
    return nearest
  }

  function syncPreviewScale() {
    previewScale = scaleOptions[nearestScaleIndex(selectedScale)].value
  }

  function formatScale(scale) {
    return Number(scale).toFixed(2).replace(/0+$/, "").replace(/\.$/, "")
  }

  function moveScale(delta) {
    cursorActive = true
    var index = Math.max(0, Math.min(scaleOptions.length - 1, nearestScaleIndex(previewScale) + delta))
    previewScale = scaleOptions[index].value
  }

  function applyScale(scale) {
    if (!monitorService || barMonitor === "") return
    var option = scaleOptions[nearestScaleIndex(scale)]
    previewScale = option.value
    monitorService.setScale(barMonitor, option.command)
  }

  function applyLayout(mode) {
    if (!monitorService || !presetLayoutsAvailable) return
    if (mode === "single" && barMonitor === "") return
    close()
    monitorService.setLayout(mode, barMonitor)
  }

  function previewBrightnessValue(record) {
    if (!record || typeof record.percent !== "number" || !isFinite(record.percent)) return 1
    return Math.max(0, Math.min(100, Math.round(record.percent)))
  }

  function open() {
    if (monitorService) {
      monitorService.refreshNativeMonitors(true)
      monitorService.refresh()
    }
    syncPreviewScale()
    selectedIndex = -1
    cursorActive = false
    controller.show()
  }

  function close() {
    root.clearBrightnessDrag()
    controller.hide()
  }

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

  function captureBrightnessTarget() {
    if (root.brightnessDragConnector !== "") return
    root.brightnessDragConnector = root.barMonitor
    root.brightnessDragIdentity = root.brightness && root.brightness.identity
      ? String(root.brightness.identity) : ""
    root.brightnessDragTopology = root.brightness && root.brightness.topology
      ? String(root.brightness.topology) : ""
    root.brightnessDragInvalidated = root.brightnessDragConnector === ""
      || root.brightnessDragIdentity === ""
  }

  function clearBrightnessDrag() {
    if (displayApplyTimer) displayApplyTimer.stop()
    root.brightnessDragConnector = ""
    root.brightnessDragIdentity = ""
    root.brightnessDragTopology = ""
    root.brightnessDragInvalidated = false
  }

  function brightnessDragMatchesCurrent() {
    var current = root.brightness
    return !root.brightnessDragInvalidated
      && root.brightnessDragConnector !== ""
      && root.barMonitor === root.brightnessDragConnector
      && current && current.available === true
      && String(current.identity || "") === root.brightnessDragIdentity
      && String(current.topology || "") === root.brightnessDragTopology
  }

  function invalidateBrightnessDragIfNeeded() {
    if (root.brightnessDragConnector === "") return
    if (root.brightnessDragInvalidated || !root.brightnessDragMatchesCurrent()) {
      root.brightnessDragInvalidated = true
      if (displayApplyTimer) displayApplyTimer.stop()
    }
  }

  function submitBrightness(value) {
    if (!root.monitorService) return false
    root.captureBrightnessTarget()
    if (!root.brightnessDragMatchesCurrent()) {
      root.invalidateBrightnessDragIfNeeded()
      return false
    }
    return root.monitorService.setBrightness(root.brightnessDragConnector, Model.clampBrightness(value))
  }

  function syncBrightnessPreview() {
    if (!root.monitorService || brightnessSlider.dragging || root.brightnessPending) return
    root.brightnessPreviewPercent = root.previewBrightnessValue(root.brightness)
  }

  function syncKeyboardBrightnessPreview() {
    if (!root.monitorService || keyboardBrightnessSlider.dragging || root.monitorService.operationPending) return
    root.keyboardBrightnessPercent = Number(root.keyboardBrightness.percent || 0)
  }

  function handleBrightnessDraggingChanged(dragging) {
    if (dragging) root.captureBrightnessTarget()
    if (!dragging) Qt.callLater(root.syncBrightnessPreview)
  }

  function releaseBrightness(value) {
    root.captureBrightnessTarget()
    var next = Model.clampBrightness(value)
    if (!root.brightnessDragMatchesCurrent()) {
      root.clearBrightnessDrag()
      Qt.callLater(root.syncBrightnessPreview)
      return
    }
    root.brightnessPreviewPercent = next
    root.submitBrightness(next)
    root.clearBrightnessDrag()
  }

  function setKeyboardBrightness(action) {
    if (!monitorService) return
    if (typeof action === "number" && !isFinite(action)) return
    monitorService.setKeyboardBrightness(action)
  }

  function toggleInternal() {
    if (monitorService) monitorService.runAction(["monitor", "toggle-internal"])
  }

  function toggleMirror() {
    if (monitorService) monitorService.runAction(["monitor", "toggle-mirror"])
  }

  function moveCursor(delta) {
    selectedIndex = Math.max(-1, Math.min(displays.length - 1, selectedIndex + delta))
    cursorActive = true
  }

  function activateCursor() {
    if (selectedIndex === -1) applyScale(previewScale)
    else if (selectedIndex < displays.length) toggleInternal()
  }

  visible: capabilityAvailable
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  onCapabilityAvailableChanged: reportCapability()
  onPluginRegistryChanged: reportCapability()
  onBarChanged: reportCapability()
  Component.onCompleted: {
    reportCapability()
    if (monitorService) {
      monitorService.refreshNativeMonitors(false)
      syncBrightnessPreview()
      syncKeyboardBrightnessPreview()
    }
    refresh()
  }

  ServiceConsumer {
    id: monitorConsumer
    service: root.monitorService
    active: true
  }

  Connections {
    target: root.monitorService
    ignoreUnknownSignals: true
    function onBrightnessSnapshotChanged() {
      root.invalidateBrightnessDragIfNeeded()
      root.syncBrightnessPreview()
    }
    function onHardwareStateChanged() {
      root.invalidateBrightnessDragIfNeeded()
      root.syncBrightnessPreview()
      root.syncKeyboardBrightnessPreview()
    }
    function onOperationPendingChanged() {
      root.syncBrightnessPreview()
      root.syncKeyboardBrightnessPreview()
    }
    function onOperationStateChanged() { root.syncBrightnessPreview() }
  }

  onBarMonitorChanged: root.invalidateBrightnessDragIfNeeded()
  Component.onDestruction: root.clearBrightnessDrag()

  Connections {
    target: Hyprland.monitors
    function onValuesChanged() {
      root.refreshNativeTopology()
      if (root.selectedIndex >= root.displays.length) root.selectedIndex = root.displays.length - 1
      if (root.opened && !scaleSlider.dragging)
        Qt.callLater(root.syncPreviewScale)
    }
  }

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() { root.refreshNativeTopology() }
  }

  BarMetricButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconText: Model.displayIcon(root.displays.length)
    valueText: root.presetLayoutsAvailable ? root.modeLetter : ""
    active: root.presetLayoutsAvailable && (root.layoutMode === "headless" || root.layoutMode === "single")
    tooltipText: root.presetLayoutsAvailable
      ? root.modeLabel + "; click to configure " + (root.barMonitor || "this monitor")
      : "Configure " + (root.barMonitor || "this monitor")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.capabilityAvailable
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0 && root.selectedIndex === -1) root.moveScale(dx)
        else if (dx !== 0 && root.keyboardBrightness.available) {
          root.setKeyboardBrightness(dx > 0 ? "up" : "down")
        }
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "p" || text === "P") root.applyLayout("physical")
        else if (text === "H") root.applyLayout("headless")
        else if (text === "s" || text === "S") root.applyLayout("single")
      }

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
            meta: root.barMonitor || "No active monitor"
            detail: root.formatScale(root.previewScale) + "x"
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
            text: "SCALE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          CursorSurface {
            width: parent.width
            implicitHeight: scaleSlider.implicitHeight + Style.spacing.controlGap
            foreground: root.foreground
            outline: true
            hasCursor: root.cursorActive && root.selectedIndex === -1

            PanelSlider {
              id: scaleSlider
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              bar: root.bar
              minimum: 0
              maximum: Math.max(0, root.scaleOptions.length - 1)
              step: 1
              integer: true
              tickCount: root.scaleOptions.length
              value: root.nearestScaleIndex(root.previewScale)
              onMoved: function(value) {
                root.selectedIndex = -1
                root.previewScale = root.scaleOptions[Math.round(value)].value
              }
              onReleased: function(value) { root.applyScale(root.scaleOptions[Math.round(value)].value) }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(minimumScaleLabel.implicitHeight, maximumScaleLabel.implicitHeight)

            Text {
              id: minimumScaleLabel
              anchors.left: parent.left
              text: root.formatScale(root.scaleOptions[0].value) + "x"
              color: root.panelSecondary
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              id: maximumScaleLabel
              anchors.right: parent.right
              text: root.formatScale(root.scaleOptions[root.scaleOptions.length - 1].value) + "x"
              color: root.panelSecondary
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            visible: root.presetLayoutsAvailable
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "WORKSTATION LAYOUT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.layoutOptions
              Button {
                required property var modelData
                width: column.width
                iconText: modelData.letter
                text: modelData.label
                leftAlign: true
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                active: root.layoutMode === modelData.mode
                onClicked: root.applyLayout(modelData.mode)
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }
          PanelSectionHeader {
            text: "BRIGHTNESS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          CursorSurface {
            width: parent.width
            visible: root.brightnessActionable
            implicitHeight: brightnessSlider.implicitHeight + Style.spacing.controlGap
            foreground: root.foreground
            outline: true

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
              onMoved: {
                root.captureBrightnessTarget()
                root.brightnessPreviewPercent = Math.round(liveValue)
                if (!displayApplyTimer.running) displayApplyTimer.start()
              }
              onDraggingChanged: root.handleBrightnessDraggingChanged(dragging)
              onReleased: function(value) {
                displayApplyTimer.stop()
                root.releaseBrightness(value)
              }

              Timer {
                id: displayApplyTimer
                interval: 100
                onTriggered: {
                  root.submitBrightness(brightnessSlider.liveValue)
                }
              }
            }
          }

          Text {
            id: brightnessUnavailableText
            width: parent.width
            visible: !root.brightnessActionable
            text: root.brightnessError
            color: root.panelSecondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Text {
            id: brightnessValueText
            width: parent.width
            visible: root.brightnessActionable && root.brightnessMeasurementKnown
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
            CursorSurface {
              width: parent.width
              implicitHeight: keyboardBrightnessSlider.implicitHeight + Style.spacing.controlGap
              foreground: root.foreground
              outline: true

              PanelSlider {
                id: keyboardBrightnessSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                bar: root.bar
                minimum: 0
                maximum: 100
                step: 1
                integer: true
                value: root.keyboardBrightnessPercent
                onMoved: {
                  root.keyboardBrightnessPercent = Math.round(liveValue)
                  if (!keyboardApplyTimer.running) keyboardApplyTimer.start()
                }
                onDraggingChanged: if (!dragging) Qt.callLater(root.syncKeyboardBrightnessPreview)
                onReleased: function(value) {
                  keyboardApplyTimer.stop()
                  root.setKeyboardBrightness(value)
                }

                Timer {
                  id: keyboardApplyTimer
                  interval: 100
                  onTriggered: {
                    if (!root.monitorService) return
                    if (root.monitorService.operationPending) restart()
                    else root.setKeyboardBrightness(keyboardBrightnessSlider.liveValue)
                  }
                }
              }
            }
            Text {
              width: parent.width
              text: root.keyboardBrightnessPercent + "%"
              color: root.panelSecondary
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
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
