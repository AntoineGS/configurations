import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "desktop.tailscale"
  ipcTarget: "desktop.tailscale"
  manageIpc: false
  property var pluginRegistry: null
  property bool cursorActive: false
  property int selectedIndex: 0

  readonly property var tailscale: bar && bar.shell ? bar.shell.serviceFor("desktop.tailscale") : null
  readonly property bool tailscaleActive: tailscale ? tailscale.active : false
  readonly property bool tailscaleBusy: tailscale ? tailscale.busy : false
  readonly property bool tailscaleNeedsLogin: tailscale ? tailscale.needsLogin : false
  readonly property string tailscaleStatus: tailscale ? tailscale.statusText : "Unavailable"
  readonly property string tailscaleSelfName: tailscale ? tailscale.selfName : ""
  readonly property var tailscaleAddresses: tailscale ? tailscale.selfAddresses : []
  readonly property var tailscalePeers: tailscale ? tailscale.peers : []
  readonly property string tailscaleActionStatus: tailscale ? tailscale.actionStatus : ""
  readonly property string tailscaleLastError: tailscale ? tailscale.lastError : ""
  readonly property color foreground: panelForeground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool capabilityAvailable: !!tailscale && tailscale.available
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color barIconForeground: bar ? bar.foreground : Color.foreground
  readonly property color barIconDim: Qt.darker(barIconForeground, 1.5)

  function reportCapability() {
    var registry = pluginRegistry || (bar && bar.shell ? bar.shell.pluginRegistry : null)
    if (!registry) return
    var scope = "capability:panel:" + moduleName
    if (capabilityAvailable) registry.clearPluginError(moduleName, scope)
    else registry.recordPluginError(moduleName, "Tailscale unavailable or logged out", scope)
  }

  function moveCursor(delta) {
    if (tailscalePeers.length === 0) return
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(tailscalePeers.length - 1, selectedIndex + delta))
  }

  function selectedPeer() {
    if (tailscalePeers.length === 0) return null
    return tailscalePeers[Math.max(0, Math.min(selectedIndex, tailscalePeers.length - 1))]
  }

  function activateCursor() {
    var peer = selectedPeer()
    if (peer && tailscale) tailscale.copyPeerAddress(peer)
  }

  function refresh() { return tailscale ? tailscale.refresh() : false }
  function up() { return tailscale ? tailscale.up() : false }
  function down() { return tailscale ? tailscale.down() : false }
  function logout() { return tailscale ? tailscale.logout() : false }
  function toggleTailscale() { return tailscale ? tailscale.toggleTailscale() : false }
  function copyPeerName(peer) { if (tailscale) tailscale.copyPeerName(peer) }
  function copyPeerAddress(peer) { if (tailscale) tailscale.copyPeerAddress(peer) }
  function setExitNode(peer) { return tailscale ? tailscale.setExitNode(peer) : false }

  ServiceConsumer {
    id: tailscaleConsumer
    service: root.tailscale
    active: true
    details: root.opened
  }

  visible: capabilityAvailable
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  onCapabilityAvailableChanged: reportCapability()
  onPluginRegistryChanged: reportCapability()
  onBarChanged: reportCapability()
  Component.onCompleted: reportCapability()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: root.tailscaleActive ? root.barIconForeground : root.barIconDim
    iconComponent: Component {
      TailscaleIcon {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: Style.space(2)
        anchors.verticalCenterOffset: Style.space(2)
        iconSize: Style.space(12)
        color: button.contentColor
        badgeColor: root.urgent
        badgeBackground: Color.bar.background
        crossed: !root.tailscaleActive
        warning: root.tailscaleNeedsLogin
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleTailscale()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.capabilityAvailable
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.toggleTailscale()
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "t" || text === "T") root.toggleTailscale()
        else if (text === "c" || text === "C") root.copyPeerAddress(root.selectedPeer())
        else if (text === "n" || text === "N") root.copyPeerName(root.selectedPeer())
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
            title: root.tailscaleSelfName || "Tailscale"
            meta: root.tailscaleStatus
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              TailscaleIcon {
                iconSize: Style.font.display
                color: root.tailscaleActive ? root.panelSecondary : root.dim
                badgeBackground: Color.barPanels.background
                crossed: !root.tailscaleActive
                warning: root.tailscaleNeedsLogin
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                checked: root.tailscaleActive
                busy: root.tailscaleBusy
                foreground: root.foreground
                onToggled: root.toggleTailscale()
              }
            }
          }

          Text {
            visible: root.tailscaleActionStatus !== "" || root.tailscaleLastError !== ""
            width: parent.width
            text: root.tailscaleActionStatus !== "" ? root.tailscaleActionStatus : root.tailscaleLastError
            color: root.tailscaleLastError !== "" && root.tailscaleActionStatus === ""
              ? root.urgent : root.panelSecondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            PanelSectionHeader {
              text: "LOCAL ADDRESSES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Text {
              width: parent.width
              text: root.tailscaleAddresses.length > 0
                ? root.tailscaleAddresses.join(" · ") : "No Tailscale address"
              color: root.panelSecondary
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          Column {
            visible: root.tailscalePeers.length > 0
            width: parent.width
            spacing: Style.space(6)
            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "PEERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: root.tailscalePeers
              CursorSurface {
                required property var modelData
                required property int index
                width: column.width
                foreground: root.foreground
                hasCursor: root.cursorActive && root.selectedIndex === index
                implicitHeight: row.implicitHeight + Style.space(14)

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onContainsMouseChanged: if (containsMouse) {
                    root.cursorActive = true
                    root.selectedIndex = index
                  }
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) root.setExitNode(modelData)
                    else root.copyPeerAddress(modelData)
                  }
                }

                Row {
                  id: row
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    text: Model.osIcon(modelData.os)
                    color: root.panelSecondary
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Column {
                    width: parent.width - copyAddress.implicitWidth - copyName.implicitWidth - Style.space(28)
                    spacing: Style.space(1)
                    Text {
                      width: parent.width
                      text: Model.peerLabel(modelData)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      text: Model.peerAddress(modelData) + (modelData.exitNode ? " · EXIT NODE" : "")
                      color: root.panelSecondary
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                  Button {
                    id: copyName
                    text: "N"
                    tooltipText: "Copy name"
                    foreground: root.foreground
                    onClicked: root.copyPeerName(modelData)
                  }
                  Button {
                    id: copyAddress
                    text: "C"
                    tooltipText: "Copy address"
                    foreground: root.foreground
                    onClicked: root.copyPeerAddress(modelData)
                  }
                }

              }
            }
          }

          Text {
            visible: root.tailscalePeers.length === 0
            text: "No peers found on this tailnet"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
