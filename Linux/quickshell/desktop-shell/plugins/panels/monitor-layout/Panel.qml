import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "desktop.monitor-layout"
  ipcTarget: "desktop.monitor-layout"
  manageIpc: false

  property int topologyGeneration: 0
  property bool cursorActive: false
  property real previewScale: 1
  property string hostname: ""

  readonly property color foreground: panelForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var barWindow: button.QsWindow.window
  readonly property string barMonitor: barWindow && barWindow.screen ? String(barWindow.screen.name || "") : ""
  readonly property var activeDisplays: {
    root.topologyGeneration
    var result = []
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (!monitor || !monitor.name) continue
      result.push({
        name: String(monitor.name),
        description: String(monitor.description || ""),
        width: Number(monitor.width || 0),
        height: Number(monitor.height || 0),
        scale: Number(monitor.scale || 1)
      })
    }
    return result
  }
  readonly property var activeMonitors: activeDisplays.map(function(display) { return display.name })
  readonly property string selectedMonitor: barMonitor
  readonly property var selectedDisplay: displayForMonitor(selectedMonitor)
  readonly property real selectedScale: scaleForMonitor(barMonitor)
  readonly property var scaleOptions: validScaleOptions(selectedDisplay)
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
    { mode: "single", letter: "S", label: "Single monitor: " + (selectedMonitor || barMonitor || "current") }
  ]

  function scaleForMonitor(name) {
    var display = displayForMonitor(name)
    return display ? display.scale : 1
  }

  function displayForMonitor(name) {
    for (var i = 0; i < activeDisplays.length; i++)
      if (activeDisplays[i].name === name) return activeDisplays[i]
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

  function open() {
    previewScale = scaleOptions[nearestScaleIndex(selectedScale)].value
    cursorActive = false
    controller.show()
  }

  function moveCursor(delta) {
    cursorActive = true
    var index = Math.max(0, Math.min(scaleOptions.length - 1, nearestScaleIndex(previewScale) + delta))
    previewScale = scaleOptions[index].value
  }

  function formatScale(scale) {
    return Number(scale).toFixed(2).replace(/0+$/, "").replace(/\.$/, "")
  }

  function applyScale(scale) {
    if (selectedMonitor === "") return
    var option = scaleOptions[nearestScaleIndex(scale)]
    previewScale = option.value
    Quickshell.execDetached([
      "desktop-hardware-action", "monitor", "set-scale", selectedMonitor, option.command
    ])
  }

  function applyLayout(mode) {
    if (!presetLayoutsAvailable) return
    if (mode === "single" && selectedMonitor === "") return
    var command = ["desktop-hardware-action", "monitor", "set-layout", mode]
    if (mode === "single") command.push(selectedMonitor)
    close()
    Quickshell.execDetached(command)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Connections {
    target: Hyprland.monitors
    function onValuesChanged() {
      root.topologyGeneration++
      if (root.opened && !scaleSlider.dragging)
        Qt.callLater(root.syncPreviewScale)
    }
  }

  function syncPreviewScale() {
    previewScale = scaleOptions[nearestScaleIndex(selectedScale)].value
  }

  Process {
    command: ["hostname"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.hostname = String(text || "").trim()
    }
  }

  BarMetricButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconText: "󰍺"
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
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy !== 0 ? dy : dx) }
      onActivateRequested: root.applyScale(root.previewScale)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "p" || text === "P") root.applyLayout("physical")
        else if (text === "h" || text === "H") root.applyLayout("headless")
        else if (text === "s" || text === "S") root.applyLayout("single")
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(8)

          PanelHero {
            width: parent.width
            title: "Monitor layout"
            meta: root.selectedMonitor || "No active monitor"
            detail: root.formatScale(root.previewScale) + "x"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰍺"
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
            hasCursor: root.cursorActive

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
                width: contentColumn.width
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
        }
      }
    }
  }
}
