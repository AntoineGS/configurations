import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "desktop.monitor-layout"
  ipcTarget: "desktop.monitor-layout"
  manageIpc: false

  property int topologyGeneration: 0
  property bool cursorActive: false
  property int selectedIndex: 0

  readonly property color foreground: panelForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var barWindow: button.QsWindow.window
  readonly property string barMonitor: barWindow && barWindow.screen ? String(barWindow.screen.name || "") : ""
  readonly property var activeMonitors: {
    root.topologyGeneration
    var result = []
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i] && monitors[i].name) result.push(String(monitors[i].name))
    }
    return result
  }
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

  function modeIndex(mode) {
    for (var i = 0; i < layoutOptions.length; i++) {
      if (layoutOptions[i].mode === mode) return i
    }
    return 0
  }

  function open() {
    selectedIndex = modeIndex(layoutMode)
    cursorActive = false
    controller.show()
  }

  function moveCursor(delta) {
    cursorActive = true
    selectedIndex = (selectedIndex + delta + layoutOptions.length) % layoutOptions.length
  }

  function applySelected() {
    applyLayout(layoutOptions[selectedIndex].mode)
  }

  function applyLayout(mode) {
    if (mode === "single" && barMonitor === "") return
    var command = ["desktop-hardware-action", "monitor", "set-layout", mode]
    if (mode === "single") command.push(barMonitor)
    close()
    Quickshell.execDetached(command)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Connections {
    target: Hyprland.monitors
    function onValuesChanged() { root.topologyGeneration++ }
  }

  BarMetricButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconText: "󰍺"
    valueText: root.modeLetter
    active: root.layoutMode === "headless" || root.layoutMode === "single"
    tooltipText: root.modeLabel + "; click to choose a layout"
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
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy !== 0 ? dy : dx) }
      onActivateRequested: root.applySelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "p" || text === "P") root.applyLayout("physical")
        else if (text === "h" || text === "H") root.applyLayout("headless")
        else if (text === "s" || text === "S") root.applyLayout("single")
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(8)

        PanelHero {
          width: parent.width
          title: "Monitor layout"
          meta: root.barMonitor || "Unknown monitor"
          detail: root.modeLetter
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

        Repeater {
          model: root.layoutOptions

          Button {
            required property var modelData
            required property int index
            width: contentColumn.width
            iconText: modelData.letter
            text: modelData.label
            leftAlign: true
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            active: root.layoutMode === modelData.mode
            hasCursor: root.cursorActive && root.selectedIndex === index
            onClicked: root.applyLayout(modelData.mode)
            onHovered: function(hovered) {
              if (hovered) {
                root.cursorActive = true
                root.selectedIndex = index
              }
            }
          }
        }
      }
    }
  }
}
