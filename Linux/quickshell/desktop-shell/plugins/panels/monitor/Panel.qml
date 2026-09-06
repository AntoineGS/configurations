import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "desktop.monitor"
  ipcTarget: "desktop.monitor"
  manageIpc: false
  property var pluginRegistry: null
  property var hardwareState: ({ available: false, stale: false, data: {} })
  property bool loaded: true
  property int brightnessPercent: 1
  property int lastConfirmedBrightnessPercent: 1
  property int keyboardBrightnessPercent: 0
  property var operationState: Model.monitorOperationState()
  readonly property bool actionPending: operationState.actionRunning || operationState.actionQueue.length > 0
  property string actionName: ""
  property bool cursorActive: false
  property int selectedIndex: -1
  property real previewScale: 1
  property string hostname: ""
  property int nativeTopologyGeneration: 0
  property int reconciliationGeneration: 0
  property int reconciliationFinalizedGeneration: 0
  property int actionGeneration: 0
  property int actionFinalizedGeneration: 0

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
  readonly property var barWindow: button.QsWindow.window
  readonly property string barMonitor: barWindow && barWindow.screen ? String(barWindow.screen.name || "") : ""
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
    if (barMonitor === "" || scaleProcess.running) return
    var option = scaleOptions[nearestScaleIndex(scale)]
    previewScale = option.value
    scaleProcess.command = [
      "desktop-hardware-action", "monitor", "set-scale", barMonitor, option.command
    ]
    scaleProcess.running = true
  }

  function applyLayout(mode) {
    if (!presetLayoutsAvailable) return
    if (mode === "single" && barMonitor === "") return
    var command = ["desktop-hardware-action", "monitor", "set-layout", mode]
    if (mode === "single") command.push(barMonitor)
    close()
    Quickshell.execDetached(command)
  }

  function open() {
    Hyprland.refreshMonitors()
    monitorRefreshTimer.restart()
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

  function applyState(raw) {
    var parsed = Model.parseState(raw)
    if (!parsed) {
      if (!brightnessSlider.dragging && !actionPending) brightnessPercent = lastConfirmedBrightnessPercent
      if (!keyboardBrightnessSlider.dragging && !actionPending) keyboardBrightnessPercent = Number(keyboardBrightness.percent || 0)
      hardwareState = {
        available: false,
        stale: true,
        error: "Invalid hardware state",
        data: hardwareState && hardwareState.data ? hardwareState.data : {}
      }
      reportCapability()
      return
    }
    var previousData = hardwareState && hardwareState.data ? hardwareState.data : {}
    var reconciled = Model.brightnessState({
      brightnessPercent: brightnessPercent,
      lastConfirmedBrightnessPercent: lastConfirmedBrightnessPercent,
      brightness: previousData.brightness,
      keyboardBrightness: previousData.keyboardBrightness
    }, parsed.stale === true ? null : parsed.data.brightness,
    parsed.stale === true ? null : parsed.data.keyboardBrightness)
    if (!brightnessSlider.dragging && !actionPending) brightnessPercent = reconciled.brightnessPercent
    lastConfirmedBrightnessPercent = reconciled.lastConfirmedBrightnessPercent
    var nextData = {
      brightness: reconciled.brightness,
      keyboardBrightness: reconciled.keyboardBrightness
    }
    hardwareState = {
      available: parsed.available === true,
      stale: parsed.stale === true,
      error: parsed.error || "",
      data: nextData
    }
    if (!keyboardBrightnessSlider.dragging && !actionPending) keyboardBrightnessPercent = Number(keyboardBrightness.percent || 0)
    reportCapability()
    if (selectedIndex >= displays.length) selectedIndex = displays.length - 1
  }

  function refresh() {
    var transition = Model.monitorOperationTransition(operationState, "reconcile-request")
    operationState = transition.state
    if (transition.startReconciliation && !stateProcess.running) startStateProcess()
  }

  function startStateProcess() {
    reconciliationGeneration++
    stateStartCheckTimer.generation = reconciliationGeneration
    stateProcess.running = true
  }

  function startAction(args) {
    actionProcess.command = ["desktop-hardware-action"].concat(args)
    actionName = String(args[1] || "")
    actionGeneration++
    actionProcess.running = true
  }

  function finishAction(exitCode, failedStart) {
    if (actionFinalizedGeneration === actionGeneration) return
    actionFinalizedGeneration = actionGeneration
    actionStartCheckTimer.stop()
    if (failedStart) actionName = ""
    operationState = Model.monitorOperationTransition(operationState, "action-finished").state
    actionName = ""
    Qt.callLater(root.refresh)
  }

  function runAction(args) {
    if (!Array.isArray(args)) return
    var transition = Model.monitorOperationTransition(operationState, "action-request", args)
    operationState = transition.state
    if (transition.startAction && !actionProcess.running) startAction(transition.startAction)
  }

  function finishReconciliation() {
    if (reconciliationFinalizedGeneration === reconciliationGeneration) return
    reconciliationFinalizedGeneration = reconciliationGeneration
    var transition = Model.monitorOperationTransition(operationState, "reconcile-finished")
    operationState = transition.state
    if (transition.startAction) startAction(transition.startAction)
    else if (transition.startReconciliation && !stateProcess.running) startStateProcess()
  }

  function setBrightness(value) {
    var next = Model.clampBrightness(value)
    brightnessPercent = next
    runAction(["monitor", "set-display-brightness", String(next)])
  }

  function setKeyboardBrightness(value) {
    if (!isFinite(value)) return
    var next = Math.max(0, Math.min(100, Math.round(value)))
    keyboardBrightnessPercent = next
    runAction(["monitor", "set-keyboard-brightness", String(next)])
  }

  function toggleInternal() {
    runAction(["monitor", "toggle-internal"])
  }

  function toggleMirror() {
    runAction(["monitor", "toggle-mirror"])
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
    Hyprland.refreshMonitors()
    refresh()
  }
  Component.onDestruction: {
    loaded = false
    brightnessTimer.stop()
  }

  Timer {
    id: brightnessTimer
    property bool startupPhase: true
    interval: startupPhase ? 30000 : 60000
    running: root.loaded
    repeat: true
    onTriggered: {
      root.refresh()
      startupPhase = false
    }
  }

  Process {
    id: stateProcess
    command: ["desktop-hardware-state", "monitor"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
    onStarted: stateStartCheckTimer.stop()
    onRunningChanged: {
      if (!stateProcess.running && root.reconciliationGeneration > root.reconciliationFinalizedGeneration) {
        stateStartCheckTimer.generation = root.reconciliationGeneration
        stateStartCheckTimer.start()
      }
    }
  }

  Timer {
    id: stateStartCheckTimer
    property int generation: 0
    interval: 100
    repeat: false
    onTriggered: {
      if (!stateProcess.running && generation === root.reconciliationGeneration)
        root.finishReconciliation()
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (Number(exitCode) === 0 && Model.shouldRefreshNativeMonitors(root.actionName)) Hyprland.refreshMonitors()
      root.finishAction(exitCode, false)
    }
    onStarted: actionStartCheckTimer.stop()
    onRunningChanged: {
      if (!actionProcess.running && actionGeneration > actionFinalizedGeneration) {
        actionStartCheckTimer.generation = actionGeneration
        actionStartCheckTimer.start()
      }
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

  Connections {
    target: stateProcess
    function onExited() { Qt.callLater(root.finishReconciliation) }
  }

  Timer {
    id: actionStartCheckTimer
    property int generation: 0
    interval: 100
    repeat: false
    onTriggered: if (!actionProcess.running && generation === root.actionGeneration)
      root.finishAction(1, true)
  }

  Process {
    command: ["hostname"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.hostname = String(text || "").trim()
    }
  }

  Process {
    id: scaleProcess
    command: []
    onExited: function(exitCode) {
      if (Number(exitCode) !== 0) return
      Hyprland.refreshMonitors()
      monitorRefreshTimer.restart()
    }
  }

  Timer {
    id: monitorRefreshTimer
    interval: 150
    repeat: false
    onTriggered: Hyprland.refreshMonitors()
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
          root.runAction(["monitor", "set-keyboard-brightness", dx > 0 ? "up" : "down"])
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
              value: root.brightnessPercent
              onMoved: {
                root.brightnessPercent = Math.round(liveValue)
                if (!displayApplyTimer.running) displayApplyTimer.start()
              }
              onReleased: function(value) {
                displayApplyTimer.stop()
                root.setBrightness(value)
              }

              Timer {
                id: displayApplyTimer
                interval: 100
                onTriggered: {
                  if (root.operationState.actionRunning || root.operationState.reconciliationRunning) restart()
                  else root.setBrightness(brightnessSlider.liveValue)
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.brightness.available
            text: root.brightnessPercent + "%" + (root.brightness.device ? " · " + root.brightness.device : "")
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
                onReleased: function(value) {
                  keyboardApplyTimer.stop()
                  root.setKeyboardBrightness(value)
                }

                Timer {
                  id: keyboardApplyTimer
                  interval: 100
                  onTriggered: {
                    if (root.operationState.actionRunning || root.operationState.reconciliationRunning) restart()
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
