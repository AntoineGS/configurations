import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "desktop.network"
  ipcTarget: "desktop.network"
  manageIpc: false
  property var pluginRegistry: null

  readonly property var network: bar && bar.shell ? bar.shell.serviceFor("desktop.network") : null
  readonly property bool iwdAvailable: network ? network.iwdAvailable : false
  readonly property string iwdDevice: network ? network.iwdDevice : ""
  readonly property string stationPath: network ? network.stationPath : ""
  readonly property string connectionState: network ? network.connectionState : ""
  readonly property string connectedSsid: network ? network.connectedSsid : ""
  readonly property int iwdSignal: network ? network.iwdSignal : 0
  readonly property bool capabilityAvailable: !!network && (iwdAvailable || stationPath !== "")
  readonly property color foreground: panelForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string kind: {
    if (connectionState === "connected" && connectedSsid !== "") return "wifi"
    return "disconnected"
  }
  readonly property int signalStrength: iwdSignal
  readonly property string icon: Model.connectionIcon(kind, signalStrength)
  readonly property bool hasConfiguredProfile: connectedSsid !== ""

  readonly property var wifiNetworks: network ? network.wifiNetworks : []
  readonly property string dnsProvider: network ? network.dnsProvider : "DHCP"
  readonly property bool actionReserved: network ? network.actionReserved : false
  property string passwordSsid: ""
  property string passwordText: ""
  property bool cursorActive: false
  property string focusSection: "wifi"
  property int selectedIndex: 0
  property int dnsIndex: 0

  readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google"]

  function refresh() {
    if (network) network.requestRefresh(true)
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

  function runConnect(ssid, password) {
    return network ? network.runConnect(ssid, password) : false
  }

  function runNetworkAction(kindName, profile) {
    return network ? network.runNetworkAction(kindName, profile) : false
  }

  function connectWithPassword() {
    if (!passwordSsid || !passwordText) return
    if (network && network.runConnect(passwordSsid, passwordText)) cancelPasswordPrompt()
  }

  function connectRow(row) {
    if (actionReserved || !network || !row) return
    var networkData = networkForSsid(row.ssid)
    if (!networkData) return
    if (row.connected) {
      runNetworkAction("disconnect", row.ssid)
    } else if (isProtected(networkData) && !row.known) {
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
    if (!hasConfiguredProfile || !network) return false
    return network.setDns(provider)
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
      focusSection = wifiNetworks.length > 0 ? "wifi" : "dns"
      selectedIndex = 0
      cursorActive = false
      refresh()
    }
  }

  onWifiNetworksChanged: selectedIndex = Math.min(selectedIndex, Math.max(0, wifiNetworks.length - 1))

  ServiceConsumer {
    id: networkConsumer
    service: root.network
    active: true
    details: root.opened
  }

  visible: capabilityAvailable
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

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
