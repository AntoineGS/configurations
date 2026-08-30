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
  property var operationState: Model.monitorOperationState()
  property string actionName: ""
  property bool cursorActive: false
  property int selectedIndex: 0
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
      brightnessPercent = lastConfirmedBrightnessPercent
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
    brightnessPercent = reconciled.brightnessPercent
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
    reportCapability()
    if (selectedIndex >= displays.length) selectedIndex = Math.max(0, displays.length - 1)
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

  function setKeyboardBrightness(action) {
    runAction(["monitor", "set-keyboard-brightness", String(action)])
  }

  function toggleInternal() {
    runAction(["monitor", "toggle-internal"])
  }

  function toggleMirror() {
    runAction(["monitor", "toggle-mirror"])
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
    function onValuesChanged() { root.refreshNativeTopology() }
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
              value: root.brightnessPercent
              onMoved: root.brightnessPercent = Math.round(liveValue)
              onReleased: root.setBrightness(value)
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
