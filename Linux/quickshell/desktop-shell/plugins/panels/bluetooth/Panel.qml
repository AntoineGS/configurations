import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root

  moduleName: "desktop.bluetooth"
  ipcTarget: "desktop.bluetooth"
  manageIpc: false
  property var pluginRegistry: null
  property var batteryDevices: ({})
  property bool batteryCollectorLoaded: true
  property bool batteryRefreshQueued: false
  property int batteryRefreshGeneration: 0
  property int batteryProcessGeneration: 0

  readonly property bool capabilityAvailable: !!Bluetooth.defaultAdapter
  readonly property var adapter: capabilityAvailable ? Bluetooth.defaultAdapter : null
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var deviceGroups: Model.deviceLists(devices)
  readonly property var connectedDevices: deviceGroups.connected || []
  readonly property var knownDevices: deviceGroups.known || []
  readonly property var discoveredDevices: deviceGroups.discovered || []
  readonly property var visibleSections: Model.visibleSections(deviceGroups, adapter && adapter.discovering)
  readonly property color warningColor: "#fab387"
  readonly property bool lowBattery: Model.hasLowBattery(connectedDevices, batteryDevices)
  readonly property string batteryTooltip: Model.batteryTooltip(connectedDevices, batteryDevices, warningColor)
  readonly property string icon: {
    if (!adapter) return ""
    if (!adapter.enabled) return "󰂲"
    if (connectedDevices.length > 0) return "󰂱"
    return "󰂯"
  }
  readonly property string heroStatus: {
    if (!adapter) return "No adapter"
    if (!adapter.enabled) return "Turned off"
    if (connectedDevices.length > 0) return connectedDevices.length + " connected"
    return adapter.discovering ? "Scanning" : "Ready"
  }

  function reportCapability() {
    var registry = pluginRegistry || (bar && bar.shell ? bar.shell.pluginRegistry : null)
    if (!registry) return
    if (capabilityAvailable) registry.clearPluginError(moduleName)
    else registry.recordPluginError(moduleName, "BlueZ capability unavailable")
  }

  function refreshBatteries() {
    if (!batteryCollectorLoaded) return
    batteryRefreshGeneration++
    if (batteryProcess.running) {
      batteryRefreshQueued = true
      return
    }
    batteryProcessGeneration = batteryRefreshGeneration
    batteryProcess.running = true
  }

  function applyBatteryState(raw) {
    batteryDevices = Model.parseBatteryState(raw)
  }

  property var pendingActions: ({})
  property string focusSection: "header"
  property int selectedIndex: 0
  property bool cursorActive: false
  readonly property bool busy: Object.keys(pendingActions).length > 0

  function helper(args) {
    Quickshell.execDetached(["desktop-connectivity-action"].concat(args))
  }

  function toggleBluetooth() {
    if (!adapter) return
    helper(["bluetooth", "power", adapter.enabled ? "off" : "on"])
  }

  function scan(enabled) {
    if (!adapter) return
    helper(["bluetooth", "scan", enabled ? "on" : "off"])
  }

  function deviceFor(row) {
    if (!row || !row.address) return null
    for (var i = 0; i < devices.length; i++) {
      if (devices[i] && String(devices[i].address || "") === row.address) return devices[i]
    }
    return null
  }

  function pendingAction(address) {
    return Model.pendingAction(pendingActions, address)
  }

  function setPendingAction(address, action) {
    if (!address) return
    pendingActions = Model.withPendingAction(pendingActions, address, action)
  }

  function runDeviceAction(row, action, pending) {
    if (!row || !row.address || root.pendingAction(row.address) !== "") return
    setPendingAction(row.address, pending)
    helper(["bluetooth", action, row.address])
    pendingTimer.restart()
    pendingTimeout.restart()
  }

  function activateDevice(row) {
    if (!row) return
    if (row.connected) runDeviceAction(row, "disconnect", "disconnecting")
    else if (row.paired) runDeviceAction(row, "connect", "connecting")
    else runDeviceAction(row, "pair", "pairing")
  }

  function removeDevice(row) {
    if (!row || !row.paired) return
    runDeviceAction(row, "remove", "removing")
  }

  function sectionRows(section) {
    var list = Model.sectionDevices(deviceGroups, section)
    var rows = []
    for (var i = 0; i < list.length; i++) {
      var row = Model.deviceRow(list[i], batteryDevices, warningColor)
      if (row) rows.push(row)
    }
    return rows
  }

  function sectionCount(section) {
    return Model.sectionDevices(deviceGroups, section).length
  }

  function deviceAt(section, index) {
    var list = sectionRows(section)
    return index >= 0 && index < list.length ? list[index] : null
  }

  function moveCursor(delta) {
    if (focusSection === "header") {
      if (delta > 0 && visibleSections.length > 0) {
        focusSection = visibleSections[0]
        selectedIndex = 0
      }
      return
    }
    var sectionIndex = visibleSections.indexOf(focusSection)
    if (sectionIndex < 0) {
      focusSection = "header"
      return
    }
    var maximum = sectionCount(focusSection) - 1
    if (delta > 0 && selectedIndex < maximum) {
      selectedIndex++
      return
    }
    if (delta < 0 && selectedIndex > 0) {
      selectedIndex--
      return
    }
    var next = sectionIndex + (delta > 0 ? 1 : -1)
    if (next < 0) {
      focusSection = "header"
      return
    }
    if (next < visibleSections.length) {
      focusSection = visibleSections[next]
      selectedIndex = 0
    }
  }

  function activateCursor() {
    if (focusSection === "header") toggleBluetooth()
    else activateDevice(deviceAt(focusSection, selectedIndex))
  }

  function removeCursorDevice() {
    if (focusSection !== "connected" && focusSection !== "known") return
    removeDevice(deviceAt(focusSection, selectedIndex))
  }

  function syncPendingActions() {
    var next = Model.cloneMap(pendingActions)
    var changed = false
    for (var address in next) {
      var row = null
      for (var i = 0; i < devices.length; i++) {
        if (devices[i] && String(devices[i].address || "") === address) {
          row = devices[i]
          break
        }
      }
      var action = next[address]
      var finished = (action === "connecting" && row && row.connected)
        || (action === "disconnecting" && row && !row.connected)
        || (action === "pairing" && row && (row.paired || row.bonded || row.trusted))
        || (action === "removing" && (!row || (!row.paired && !row.bonded && !row.trusted)))
      if (finished) {
        delete next[address]
        changed = true
      }
    }
    if (changed) pendingActions = next
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      if (connectedDevices.length > 0) { focusSection = "connected"; selectedIndex = 0 }
      else if (knownDevices.length > 0) { focusSection = "known"; selectedIndex = 0 }
      else { focusSection = "header"; selectedIndex = 0 }
      refreshBatteries()
      scan(true)
    } else {
      scan(false)
    }
  }

  onVisibleSectionsChanged: {
    if (focusSection !== "header" && visibleSections.indexOf(focusSection) < 0) focusSection = "header"
    if (focusSection !== "header") selectedIndex = Math.max(0, Math.min(selectedIndex, sectionCount(focusSection) - 1))
  }
  onPluginRegistryChanged: reportCapability()
  onBarChanged: reportCapability()
  onCapabilityAvailableChanged: reportCapability()
  onConnectedDevicesChanged: refreshBatteries()
  Component.onCompleted: {
    reportCapability()
    refreshBatteries()
  }
  Component.onDestruction: {
    batteryCollectorLoaded = false
    batteryRefreshQueued = false
    batteryRefreshTimer.stop()
  }

  visible: adapter !== null
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Timer {
    id: pendingTimer
    interval: 500
    repeat: true
    running: root.opened && Object.keys(root.pendingActions).length > 0
    onTriggered: root.syncPendingActions()
  }

  Timer {
    id: pendingTimeout
    interval: 20000
    repeat: false
    onTriggered: root.pendingActions = ({})
  }

  Timer {
    id: batteryRefreshTimer
    interval: 60000
    repeat: true
    running: root.batteryCollectorLoaded
    onTriggered: root.refreshBatteries()
  }

  Process {
    id: batteryProcess
    command: ["desktop-hardware-state", "bluetooth"]
    stdout: StdioCollector {
      id: batteryStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: batteryStderr
      waitForEnd: true
    }
    onExited: {
      var completedGeneration = root.batteryProcessGeneration
      root.batteryProcessGeneration = 0
      if (!root.batteryCollectorLoaded) return
      if (completedGeneration === root.batteryRefreshGeneration)
        root.applyBatteryState(batteryStdout.text || "")
      if (!root.batteryRefreshQueued) return
      root.batteryRefreshQueued = false
      root.refreshBatteries()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.lowBattery
    activeColor: root.warningColor
    tooltipText: root.batteryTooltip
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.toggleBluetooth()
      else root.toggle()
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
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onDeleteRequested: if (root.cursorActive) root.removeCursorDevice()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "b" || text === "B") root.toggleBluetooth()
      }

      Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)
            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.icon
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              opacity: root.adapter && root.adapter.enabled ? 1.0 : 0.5
            }
            ToggleSwitch {
              id: powerSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: !!root.adapter
              checked: !!root.adapter && root.adapter.enabled
              hasCursor: root.cursorActive && root.focusSection === "header"
              foreground: root.foreground
              onHovered: function(hovered) { if (hovered) { root.cursorActive = true; root.focusSection = "header" } }
              onToggled: root.toggleBluetooth()
              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.adapter && root.adapter.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
                fontFamily: root.fontFamily
              }
            }
            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: powerSwitch.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                text: "Bluetooth"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: root.heroStatus.toUpperCase()
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          DeviceSection {
            visible: root.connectedDevices.length > 0
            title: "CONNECTED"
            sectionName: "connected"
            rows: root.sectionRows("connected")
          }
          DeviceSection {
            visible: root.knownDevices.length > 0
            title: "PAIRED"
            sectionName: "known"
            rows: root.sectionRows("known")
          }
          DeviceSection {
            visible: root.adapter && root.adapter.discovering && root.discoveredDevices.length > 0
            title: "AVAILABLE"
            sectionName: "discovered"
            rows: root.sectionRows("discovered")
          }
          Text {
            visible: root.connectedDevices.length === 0 && root.knownDevices.length === 0
              && root.discoveredDevices.length === 0
            text: !root.adapter ? "No Bluetooth adapter"
              : !root.adapter.enabled ? "Turn Bluetooth on to scan" : "Scanning for devices..."
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  component DeviceSection: Column {
    id: sectionRoot
    required property string title
    required property string sectionName
    required property var rows
    width: parent ? parent.width : 0
    spacing: Style.space(6)
    PanelSectionHeader {
      text: parent.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Repeater {
      model: sectionRoot.rows
      DeviceRow {
        required property var modelData
        required property int index
        width: parent ? parent.width : 0
        rowData: modelData
        rowIndex: index
        sectionName: sectionRoot.sectionName
      }
    }
  }

  component DeviceRow: CursorSurface {
    id: deviceRow
    required property var rowData
    required property int rowIndex
    required property string sectionName

    readonly property string pending: root.pendingAction(rowData ? rowData.address : "")
    readonly property bool connected: rowData && rowData.connected
    readonly property bool canRemove: rowData && rowData.paired && !root.busy
    hasCursor: root.cursorActive && root.focusSection === sectionName && root.selectedIndex === rowIndex
    current: connected
    foreground: root.foreground
    fill: Style.hoverFillFor(root.foreground, Color.accent)
    currentFill: Style.selectedFillFor(root.foreground, Color.accent)
    implicitHeight: Style.space(42)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: deviceRow.connected ? "󰂱" : "󰂯"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
    Column {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(38)
      anchors.right: removeButton.visible ? removeButton.left : parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)
      Text {
        text: rowData ? Model.deviceLabel(rowData) || "Device" : "Device"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        visible: deviceRow.statusText !== ""
        text: deviceRow.statusText
        textFormat: Text.RichText
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
    readonly property string statusText: {
      if (!rowData) return ""
      if (pending !== "") return pending
      if (connected) return rowData.batteryStatus || "Connected"
      return sectionName === "discovered" ? "Available" : ""
    }
    PanelActionButton {
      id: removeButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: deviceRow.canRemove && (deviceRow.hasCursor || rowMouse.containsMouse)
      iconText: "󰅙"
      tooltipText: "Remove"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.removeDevice(rowData)
    }
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = sectionName
        root.selectedIndex = rowIndex
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton && deviceRow.canRemove) root.removeDevice(rowData)
        else if (mouse.button === Qt.LeftButton) root.activateDevice(rowData)
      }
    }
  }
}
