import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root

  moduleName: "desktop.network"
  ipcTarget: "desktop.network"
  manageIpc: false
  property var pluginRegistry: null

  property bool iwdAvailable: false
  property string iwdDevice: ""
  property string stationPath: ""
  property string connectionState: ""
  property string connectedSsid: ""
  property int iwdSignal: 0
  property var iwdNetworks: []
  readonly property bool capabilityAvailable: iwdAvailable || stationPath !== ""
  readonly property color foreground: panelForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string kind: {
    if (connectionState === "connected" && connectedSsid !== "") return "wifi"
    return "disconnected"
  }
  readonly property int signalStrength: iwdSignal
  readonly property string icon: Model.connectionIcon(kind, signalStrength)
  readonly property bool hasConfiguredProfile: connectedSsid !== ""

  property var wifiNetworks: []
  property string dnsProvider: "DHCP"
  property string pendingDnsProvider: ""
  property string actionKind: ""
  property string actionDevice: ""
  property string actionProfile: ""
  property string actionPassword: ""
  property string queuedActionKind: ""
  property string queuedActionDevice: ""
  property string queuedActionProfile: ""
  property string queuedActionPassword: ""
  property string queuedDnsProvider: ""
  property bool pendingStateRefresh: false
  property bool pendingScan: false
  property string healthError: ""
  property string passwordSsid: ""
  property string passwordText: ""
  property bool cursorActive: false
  property string focusSection: "wifi"
  property int selectedIndex: 0
  property int dnsIndex: 0

  readonly property bool actionReserved: actionKind !== "" || queuedActionKind !== ""
  readonly property bool busy: actionReserved || stateProcess.running
  readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google"]

  function reportHealth() {
    var registry = pluginRegistry || (bar && bar.shell ? bar.shell.pluginRegistry : null)
    if (!registry) return
    if (healthError === "") registry.clearPluginError(moduleName)
    else registry.recordPluginError(moduleName, healthError)
  }

  function setHealthError(message) {
    healthError = message
    reportHealth()
  }

  function syncWifiNetworks() {
    var rows = []
    for (var i = 0; i < iwdNetworks.length; i++) {
      var row = Model.wifiRow(iwdNetworks[i])
      if (row && row.ssid !== "") rows.push(row)
    }
    wifiNetworks = Model.sortWifiRows(rows)
    if (selectedIndex >= wifiNetworks.length) selectedIndex = Math.max(0, wifiNetworks.length - 1)
  }

  function refresh() {
    syncWifiNetworks()
    requestRefresh(true)
  }

  function networkForSsid(ssid) {
    for (var i = 0; i < wifiNetworks.length; i++) {
      if (wifiNetworks[i] && String(wifiNetworks[i].ssid || "") === String(ssid))
        return wifiNetworks[i]
    }
    return null
  }

  function isProtected(network) {
    return Model.isProtected(network ? network.security : null, "open")
  }

  function openPasswordPrompt(ssid) {
    passwordSsid = String(ssid || "")
    passwordText = ""
  }

  function cancelPasswordPrompt() {
    passwordSsid = ""
    passwordText = ""
  }

  function startAction(kindName, device, profile, password, dnsProvider) {
    actionKind = kindName
    actionDevice = String(device || "")
    actionProfile = String(profile || "")
    actionPassword = String(password || "")
    pendingDnsProvider = String(dnsProvider || "")
    if (kindName === "connect")
      actionProcess.command = ["desktop-connectivity-action", "network", "connect", actionDevice, actionProfile]
    else if (kindName === "disconnect")
      actionProcess.command = ["desktop-connectivity-action", "network", "disconnect", actionDevice]
    else if (kindName === "forget")
      actionProcess.command = ["desktop-connectivity-action", "network", "forget", actionProfile]
    else if (kindName === "set-dns")
      actionProcess.command = ["desktop-connectivity-action", "network", "set-dns", actionDevice, pendingDnsProvider]
    else if (kindName === "scan")
      actionProcess.command = ["desktop-connectivity-action", "network", "scan", actionDevice]
    else return false
    actionProcess.running = true
    return true
  }

  function queueOrStartAction(kindName, device, profile, password, dnsProvider) {
    if (actionReserved) return false
    if (stateProcess.running) {
      queuedActionKind = kindName
      queuedActionDevice = String(device || "")
      queuedActionProfile = String(profile || "")
      queuedActionPassword = String(password || "")
      queuedDnsProvider = String(dnsProvider || "")
      return true
    }
    return startAction(kindName, device, profile, password, dnsProvider)
  }

  function runConnect(ssid, password) {
    if (!ssid) return false
    return queueOrStartAction("connect", iwdDevice, ssid, password, "")
  }

  function runNetworkAction(kindName, profile) {
    if (!profile) return false
    return queueOrStartAction(kindName, iwdDevice, profile, "", "")
  }

  function connectWithPassword() {
    if (!passwordSsid || !passwordText) return
    if (runConnect(passwordSsid, passwordText)) cancelPasswordPrompt()
  }

  function connectRow(row) {
    if (actionReserved || !row) return
    var network = networkForSsid(row.ssid)
    if (!network) return
    if (row.connected) {
      runNetworkAction("disconnect", row.ssid)
    } else if (isProtected(network) && !row.known) {
      openPasswordPrompt(row.ssid)
    } else {
      runConnect(row.ssid, "")
    }
  }

  function forgetRow(row) {
    if (!row || !row.known || row.connected) return
    var network = networkForSsid(row.ssid)
    if (network) runNetworkAction("forget", row.ssid)
  }

  function setDns(provider) {
    if (!hasConfiguredProfile) return false
    return queueOrStartAction("set-dns", iwdDevice, "", "", provider)
  }

  function requestRefresh(scan) {
    pendingStateRefresh = true
    if (scan) pendingScan = true
    schedule()
  }

  function schedule() {
    if (actionProcess.running || stateProcess.running) return
    if (queuedActionKind !== "") {
      var kindName = queuedActionKind
      var device = queuedActionDevice
      var profile = queuedActionProfile
      var password = queuedActionPassword
      var dnsProvider = queuedDnsProvider
      startAction(kindName, device, profile, password, dnsProvider)
      queuedActionKind = ""
      queuedActionDevice = ""
      queuedActionProfile = ""
      queuedActionPassword = ""
      queuedDnsProvider = ""
      return
    }
    if (pendingScan && iwdDevice === "") {
      if (pendingStateRefresh) {
        pendingStateRefresh = false
        stateProcess.running = true
      }
      return
    }
    if (pendingScan) {
      pendingScan = false
      startAction("scan", iwdDevice, "", "", "")
      return
    }
    if (pendingStateRefresh) {
      pendingStateRefresh = false
      stateProcess.running = true
    }
  }

  function applyState(raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (error) {
      setHealthError("iwd state query failed")
      return
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)
        || typeof parsed.available !== "boolean" || !Array.isArray(parsed.networks)) {
      setHealthError("iwd state query failed")
      return
    }
    var previousSession = Model.connectionSessionKey(iwdDevice, connectionState, connectedSsid)
    var nextDevice = parsed.device === null ? "" : String(parsed.device || "")
    var nextState = String(parsed.state || "")
    var nextSsid = parsed.connectedSsid === null ? "" : String(parsed.connectedSsid || "")
    if (previousSession !== Model.connectionSessionKey(nextDevice, nextState, nextSsid)) dnsProvider = "DHCP"
    iwdAvailable = parsed.available
    iwdDevice = nextDevice
    stationPath = parsed.stationPath === null ? "" : String(parsed.stationPath || "")
    connectionState = nextState
    connectedSsid = nextSsid
    iwdSignal = Math.max(0, Math.min(100, Math.round(Number(parsed.signal || 0))))
    iwdNetworks = parsed.networks
    syncWifiNetworks()
    healthError = iwdAvailable ? "" : "iwd station capability unavailable"
    reportHealth()
  }

  function visibleSections() {
    var sections = []
    if (hasConfiguredProfile) sections.push("dns")
    if (wifiNetworks.length > 0) sections.push("wifi")
    return sections
  }

  function moveCursor(delta) {
    var sections = visibleSections()
    if (sections.length === 0) return
    var sectionIndex = sections.indexOf(focusSection)
    if (sectionIndex < 0) sectionIndex = 0
    if (focusSection === "dns") {
      if (delta !== 0) dnsIndex = Math.max(0, Math.min(dnsProviders.length - 1, dnsIndex + delta))
      if (delta > 0 && wifiNetworks.length > 0) { focusSection = "wifi"; selectedIndex = 0 }
      return
    }
    if (delta > 0 && selectedIndex < wifiNetworks.length - 1) { selectedIndex++; return }
    if (delta < 0 && selectedIndex > 0) { selectedIndex--; return }
    var next = sectionIndex + (delta > 0 ? 1 : -1)
    if (next < 0 || next >= sections.length) return
    focusSection = sections[next]
    selectedIndex = focusSection === "wifi" ? 0 : 0
  }

  function activateCursor() {
    if (focusSection === "dns") setDns(dnsProviders[dnsIndex])
    else connectRow(wifiNetworks[selectedIndex])
  }

  function close() {
    root.controller.hide()
    cancelPasswordPrompt()
  }

  onOpenedChanged: {
    if (opened) {
      syncWifiNetworks()
      focusSection = wifiNetworks.length > 0 ? "wifi" : "dns"
      selectedIndex = 0
      cursorActive = false
      requestRefresh(true)
    }
  }

  onPluginRegistryChanged: reportHealth()
  onBarChanged: reportHealth()
  onCapabilityAvailableChanged: reportHealth()
  Component.onCompleted: {
    reportHealth()
    requestRefresh(false)
  }

  visible: capabilityAvailable
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Timer {
    id: idleRefreshTimer
    interval: 15000
    repeat: true
    running: !root.opened
    onTriggered: root.requestRefresh(false)
  }

  Timer {
    id: openRefreshTimer
    interval: 3000
    repeat: true
    running: root.opened
    onTriggered: root.requestRefresh(false)
  }

  Process {
    id: stateProcess
    command: ["desktop-iwd-state"]
    stdout: StdioCollector {
      id: stateStdout
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (Number(exitCode) === 0) {
        root.applyState(stateStdout.text || "")
      } else root.setHealthError("iwd state query failed")
      root.schedule()
    }
  }

  Process {
    id: actionProcess
    command: []
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: if (root.actionKind === "connect") write(root.actionPassword + "\n")
    onExited: function(exitCode) {
      var actionCompleted = root.actionKind !== ""
      if ((root.actionKind === "connect" || root.actionKind === "disconnect") && exitCode === 0)
        root.dnsProvider = "DHCP"
      if (root.actionKind === "set-dns" && exitCode === 0) root.dnsProvider = root.pendingDnsProvider
      root.pendingDnsProvider = ""
      root.actionKind = ""
      root.actionDevice = ""
      root.actionProfile = ""
      root.actionPassword = ""
      if (actionCompleted) root.pendingStateRefresh = true
      root.schedule()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: root.toggle()
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
      blocked: root.passwordSsid !== ""
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0 && root.focusSection === "dns") root.moveCursor(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
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
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)
            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.icon
              color: root.panelSecondary
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                text: root.kind === "wifi"
                  ? (root.connectedSsid || "Wi-Fi")
                  : "Disconnected"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }
              Text {
                text: root.kind === "wifi"
                  ? Math.round(root.signalStrength) + "% SIGNAL"
                  : (root.kind === "disconnected" ? "NOT CONNECTED" : "WIRED")
                color: root.panelSecondary
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }
          }

          Column {
            width: parent.width
            visible: root.hasConfiguredProfile
            spacing: Style.space(6)
            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "DNS PROVIDER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Row {
              spacing: Style.space(6)
              Repeater {
                model: root.dnsProviders
                Button {
                  required property string modelData
                  text: modelData
                  selected: root.dnsProvider === modelData
                  hasCursor: root.cursorActive && root.focusSection === "dns"
                    && root.dnsProviders[root.dnsIndex] === modelData
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.setDns(modelData)
                  onHovered: function(hovered) {
                    if (hovered) {
                      root.cursorActive = true
                      root.focusSection = "dns"
                      root.dnsIndex = index
                    }
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            visible: root.passwordSsid !== ""
            spacing: Style.space(6)
            PanelSectionHeader {
              text: "PASSWORD FOR " + root.passwordSsid
              foreground: root.foreground
              fontFamily: root.fontFamily
              elide: Text.ElideRight
              width: parent.width
            }
            Row {
              width: parent.width
              spacing: Style.space(6)
              TextField {
                id: passwordField
                width: parent.width - submitPassword.implicitWidth - Style.space(6)
                password: true
                text: root.passwordText
                foreground: root.foreground
                onTextChanged: root.passwordText = text
                onAccepted: root.connectWithPassword()
              }
              Button {
                id: submitPassword
                text: "Connect"
                foreground: root.foreground
                onClicked: root.connectWithPassword()
              }
            }
          }

          Column {
            width: parent.width
            visible: root.wifiNetworks.length > 0
            spacing: Style.space(6)
            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "WI-FI NETWORKS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: root.wifiNetworks
              WifiRow {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                rowData: modelData
                rowIndex: index
              }
            }
          }

          Text {
            visible: root.wifiNetworks.length === 0
            text: root.iwdDevice ? "Scanning for networks..." : "No iwd Wi-Fi device"
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  component WifiRow: CursorSurface {
    id: wifiRow
    required property var rowData
    required property int rowIndex

    readonly property bool isCurrent: rowData && rowData.connected
    readonly property bool canForget: rowData && rowData.known && !rowData.connected
    hasCursor: root.cursorActive && root.focusSection === "wifi" && root.selectedIndex === rowIndex
    current: isCurrent
    foreground: root.foreground
    fill: Style.hoverFillFor(root.foreground, Color.accent)
    currentFill: Style.selectedFillFor(root.foreground, Color.accent)
    implicitHeight: Style.space(42)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: Model.wifiIconFor(rowData ? rowData.signal : 0)
      color: root.panelSecondary
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(38)
      anchors.right: forgetButton.visible ? forgetButton.left : parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: (rowData ? rowData.ssid : "") + (rowData && rowData.known ? "  KNOWN" : "")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: wifiRow.isCurrent
      elide: Text.ElideRight
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: rowData && rowData.connected ? "CONNECTED" : (rowData ? rowData.signal + "%" : "")
      color: root.panelSecondary
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    PanelActionButton {
      id: forgetButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: wifiRow.canForget && (wifiRow.hasCursor || rowMouse.containsMouse)
      iconText: "󰅙"
      tooltipText: "Forget"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.forgetRow(rowData)
    }
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "wifi"
        root.selectedIndex = rowIndex
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton && wifiRow.canForget) root.forgetRow(rowData)
        else if (mouse.button === Qt.LeftButton) root.connectRow(rowData)
      }
    }
  }
}
