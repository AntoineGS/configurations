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

  readonly property color foreground: panelForeground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool capabilityAvailable: tailscale.available
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color barIconForeground: bar ? bar.foreground : Color.foreground
  readonly property color barIconDim: Qt.darker(barIconForeground, 1.5)

  function reportCapability() {
    var registry = pluginRegistry || (bar && bar.shell ? bar.shell.pluginRegistry : null)
    if (!registry) return
    if (capabilityAvailable) registry.clearPluginError(moduleName)
    else registry.recordPluginError(moduleName, "Tailscale unavailable or logged out")
  }

  function moveCursor(delta) {
    if (tailscale.peers.length === 0) return
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(tailscale.peers.length - 1, selectedIndex + delta))
  }

  function selectedPeer() {
    if (tailscale.peers.length === 0) return null
    return tailscale.peers[Math.max(0, Math.min(selectedIndex, tailscale.peers.length - 1))]
  }

  function activateCursor() {
    var peer = selectedPeer()
    if (peer) tailscale.copyPeerAddress(peer)
  }

  function refresh() { tailscale.refresh() }
  function up() { tailscale.up() }
  function down() { tailscale.down() }
  function logout() { tailscale.logout() }

  Service {
    id: tailscale
    pluginRegistry: root.pluginRegistry
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
    foreground: tailscale.active ? root.barIconForeground : root.barIconDim
    iconComponent: Component {
      TailscaleIcon {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: Style.space(2)
        anchors.verticalCenterOffset: Style.space(2)
        iconSize: Style.space(12)
        color: button.contentColor
        badgeColor: root.urgent
        badgeBackground: Color.bar.background
        crossed: !tailscale.active
        warning: tailscale.needsLogin
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) tailscale.toggleTailscale()
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
        else if (dx !== 0) tailscale.toggleTailscale()
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "t" || text === "T") tailscale.toggleTailscale()
        else if (text === "c" || text === "C") tailscale.copyPeerAddress(root.selectedPeer())
        else if (text === "n" || text === "N") tailscale.copyPeerName(root.selectedPeer())
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
            title: tailscale.selfName || "Tailscale"
            meta: tailscale.statusText
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              TailscaleIcon {
                iconSize: Style.font.display
                color: tailscale.active ? root.panelSecondary : root.dim
                badgeBackground: Color.barPanels.background
                crossed: !tailscale.active
                warning: tailscale.needsLogin
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                checked: tailscale.active
                busy: tailscale.busy
                foreground: root.foreground
                onToggled: tailscale.toggleTailscale()
              }
            }
          }

          Text {
            visible: tailscale.actionStatus !== "" || tailscale.lastError !== ""
            width: parent.width
            text: tailscale.actionStatus !== "" ? tailscale.actionStatus : tailscale.lastError
            color: tailscale.lastError !== "" && tailscale.actionStatus === "" ? root.urgent : root.panelSecondary
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
              text: tailscale.selfAddresses.length > 0 ? tailscale.selfAddresses.join(" · ") : "No Tailscale address"
                      color: root.panelSecondary
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          Column {
            visible: tailscale.peers.length > 0
            width: parent.width
            spacing: Style.space(6)
            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "PEERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: tailscale.peers
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
                    if (mouse.button === Qt.RightButton) tailscale.setExitNode(modelData)
                    else tailscale.copyPeerAddress(modelData)
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
                    color: root.foreground
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
                    onClicked: tailscale.copyPeerName(modelData)
                  }
                  Button {
                    id: copyAddress
                    text: "C"
                    tooltipText: "Copy address"
                    foreground: root.foreground
                    onClicked: tailscale.copyPeerAddress(modelData)
                  }
                }

              }
            }
          }

          Text {
            visible: tailscale.peers.length === 0
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
