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
  property int keyboardBrightnessPercent: 0
  property bool cursorActive: false
  property int selectedIndex: -1
  property real previewScale: 1
  property int nativeTopologyGeneration: 0
  readonly property alias displayBrightnessControl: brightnessSlider
  readonly property alias keyboardBrightnessControl: keyboardBrightnessSlider

  readonly property var monitorService: bar && bar.shell ? bar.shell.serviceFor("desktop.monitor") : null
  readonly property string hostname: monitorService && monitorService.hostname
    ? String(monitorService.hostname) : ""
  readonly property var hardwareState: monitorService
    ? monitorService.hardwareState : ({ available: false, stale: false, data: {} })
  readonly property int brightnessPercent: monitorService ? monitorService.brightnessPercent : 1
  readonly property string actionError: monitorService && monitorService.actionError
    ? String(monitorService.actionError) : ""

  function refreshNativeTopology() {
    nativeTopologyGeneration++
  }

  readonly property var nativeTopology: Model.normalizeMonitors(
    nativeTopologyGeneration >= 0 && Hyprland.monitors ? Hyprland.monitors.values : [], Hyprland.focusedMonitor)
  readonly property var monitorInventory: monitorService && Array.isArray(monitorService.monitorInventory)
    ? monitorService.monitorInventory : []
  readonly property var displayRows: Model.mergeMonitorInventory(
    monitorInventory, nativeTopology.monitors, Hyprland.focusedMonitor)
  readonly property bool capabilityAvailable: nativeTopology.monitors.length > 0 || displayRows.length > 0
  readonly property var stateData: hardwareState && hardwareState.data ? hardwareState.data : ({})
  readonly property var displays: displayRows
  readonly property var brightness: stateData.brightness || ({ available: false, percent: 1 })
  readonly property var keyboardBrightness: stateData.keyboardBrightness || ({ available: false, percent: 0 })
  readonly property string internalMonitor: nativeTopology.internalMonitor
  readonly property bool internalEnabled: nativeTopology.internalEnabled
  readonly property string focusedMonitor: nativeTopology.focusedMonitor
  readonly property int enabledDisplayCount: Model.enabledDisplayCount(displayRows)
  readonly property bool monitorInventoryFresh: monitorService
    && monitorService.monitorInventoryFresh === true
  readonly property bool monitorActionsAvailable: monitorService
    && monitorService.monitorActionAvailable === true
  readonly property color foreground: panelForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var barWindow: button.QsWindow.window
  readonly property string barMonitor: barWindow && barWindow.screen ? String(barWindow.screen.name || "") : ""
  readonly property var selectedDisplay: activeDisplayForMonitor(barMonitor)
  readonly property real selectedScale: selectedDisplay ? selectedDisplay.scale : 1
  readonly property var scaleOptions: validScaleOptions(selectedDisplay)
  readonly property var activeMonitors: nativeTopology.monitors.map(function(display) { return display.name })
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

  function displayForMonitor(name) {
    for (var i = 0; i < displays.length; i++)
      if (displays[i].name === name) return displays[i]
    return null
  }

  function activeDisplayForMonitor(name) {
    for (var i = 0; i < nativeTopology.monitors.length; i++)
      if (nativeTopology.monitors[i].name === name) return nativeTopology.monitors[i]
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
    if (!monitorService || !presetLayoutsAvailable || !monitorActionsAvailable) return
    if (mode === "single" && barMonitor === "") return
    close()
    monitorService.setLayout(mode, barMonitor)
  }

  function applyGenericLayout(mode) {
    if (!monitorService || !monitorActionsAvailable) return
    if (mode === "only") {
      if (!activeDisplayForMonitor(barMonitor)) return
      close()
      monitorService.setLayout("only", barMonitor)
    } else if (mode === "all") {
      close()
      monitorService.setLayout("all")
    }
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

  function syncKeyboardBrightnessPreview() {
    if (!root.monitorService || keyboardBrightnessSlider.dragging || root.monitorService.operationPending) return
    root.keyboardBrightnessPercent = Number(root.keyboardBrightness.percent || 0)
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
    if (!monitorService) return
    if (typeof action === "number" && !isFinite(action)) return
    monitorService.setKeyboardBrightness(action)
  }

  function toggleInternal() {
    if (monitorService && monitorActionsAvailable) monitorService.runAction(["monitor", "toggle-internal"])
  }

  function toggleMirror() {
    if (monitorService && monitorActionsAvailable) monitorService.runAction(["monitor", "toggle-mirror"])
  }

  function canToggleMonitor(display) {
    if (!display || !monitorActionsAvailable) return false
    if (!display.enabled) return true
    if (!display.active) return false
    var activeEnabledCount = 0
    for (var i = 0; i < displays.length; i++)
      if (displays[i].enabled && displays[i].active) activeEnabledCount++
    return activeEnabledCount > 1
  }

  function toggleMonitor(display) {
    if (!canToggleMonitor(display)) return false
    var fallback = display.enabled
      ? Model.preferredFallbackMonitor(nativeTopology.monitors, display.name, barMonitor) : ""
    return monitorService.setMonitorEnabled(display.name, !display.enabled, fallback)
  }

  function moveCursor(delta) {
    selectedIndex = Math.max(-1, Math.min(displays.length - 1, selectedIndex + delta))
    cursorActive = true
  }

  function activateCursor() {
    if (selectedIndex === -1) applyScale(previewScale)
    else if (selectedIndex < displays.length) toggleMonitor(displays[selectedIndex])
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
    function onBrightnessPercentChanged() { root.syncBrightnessPreview() }
    function onHardwareStateChanged() {
      root.syncBrightnessPreview()
      root.syncKeyboardBrightnessPreview()
      if (root.selectedIndex >= root.displays.length) root.selectedIndex = root.displays.length - 1
    }
    function onOperationPendingChanged() {
      root.syncBrightnessPreview()
      root.syncKeyboardBrightnessPreview()
    }
  }

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
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "MONITOR ACTIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Button {
              width: parent.width
              iconText: "1"
              text: "Only this monitor"
              leftAlign: true
              bordered: true
              foreground: root.foreground
              enabled: root.monitorActionsAvailable && root.activeDisplayForMonitor(root.barMonitor) !== null
              onClicked: root.applyGenericLayout("only")
            }
            Button {
              width: parent.width
              iconText: "󰍺"
              text: "Enable all physical monitors"
              leftAlign: true
              bordered: true
              foreground: root.foreground
              enabled: root.monitorActionsAvailable
              onClicked: root.applyGenericLayout("all")
            }
          }

          Text {
            width: parent.width
            visible: root.actionError !== ""
            text: root.actionError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: root.monitorInventoryFresh === false && root.actionError === ""
            text: "Display inventory is unavailable; controls are paused."
            color: root.panelSecondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
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
                enabled: root.monitorActionsAvailable
                onClicked: root.applyLayout(modelData.mode)
              }
            }
          }

          PanelSeparator {
            visible: root.brightness.available
            foreground: root.foreground
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
                  if (!root.monitorService) return
                  if (root.monitorService.operationPending) restart()
                  else root.setBrightness(brightnessSlider.liveValue)
                }
              }
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
              implicitHeight: Style.space(50)

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Column {
                  id: monitorLabels
                  width: Math.max(0, parent.width - scaleLabel.implicitWidth
                    - monitorToggle.implicitWidth - Style.space(24))
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: modelData.name || "Display"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: modelData.enabled ? (modelData.active ? "Enabled" : "Waiting for compositor") : "Disabled"
                    color: root.panelSecondary
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
                Text {
                  id: scaleLabel
                  text: root.formatScale(modelData.scale || 1) + "x"
                  color: root.panelSecondary
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
                ToggleSwitch {
                  id: monitorToggle
                  checked: modelData.enabled
                  enabled: root.canToggleMonitor(modelData)
                  interactive: enabled
                  busy: root.monitorService && root.monitorService.operationPending
                  cursorRing: false
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: enabled ? 1 : 0.55
                  onToggled: root.toggleMonitor(modelData)
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
              }
            }
          }

          Row {
            spacing: Style.space(6)
            visible: root.internalMonitor !== "" && root.displays.length > 1
            Button {
              text: "Toggle internal"
              foreground: root.foreground
              enabled: root.monitorActionsAvailable
              onClicked: root.toggleInternal()
            }
            Button {
              text: root.nativeTopology.mirrorEnabled === true ? "Unmirror" : "Mirror"
              foreground: root.foreground
              enabled: root.monitorActionsAvailable
              onClicked: root.toggleMirror()
            }
          }
        }
      }
    }
  }
}
