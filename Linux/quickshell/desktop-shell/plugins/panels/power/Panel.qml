import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "desktop.power"
  ipcTarget: "desktop.power"
  manageIpc: false
  property var pluginRegistry: null
  property var hardwareState: ({ available: false, stale: false, data: {} })
  property bool loaded: true
  property bool cursorActive: false
  property int profileIndex: 0

  readonly property bool capabilityAvailable: hardwareState && hardwareState.available === true
  readonly property var stateData: hardwareState && hardwareState.data ? hardwareState.data : ({})
  readonly property var battery: stateData.battery || ({})
  readonly property var profile: stateData.profile || ({})
  readonly property var profiles: Array.isArray(profile.profiles) ? profile.profiles : []
  readonly property string activeProfile: String(profile.active || "")
  readonly property int batteryPercent: Model.batteryPercentage(battery.status)
  readonly property string batteryState: String(battery.state || "")
  readonly property var batteryOnBattery: battery.onBattery
  readonly property bool batteryAvailable: String(battery.status || "") !== ""
  readonly property color foreground: panelForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function reportCapability() {
    var registry = pluginRegistry || (bar && bar.shell ? bar.shell.pluginRegistry : null)
    if (!registry) return
    var scope = "capability:panel:" + moduleName
    if (capabilityAvailable) registry.clearPluginError(moduleName, scope)
    else registry.recordPluginError(moduleName, "Battery capability unavailable", scope)
  }

  function applyState(raw) {
    var parsed = Model.parseState(raw)
    if (!parsed) {
      hardwareState = { available: false, stale: true, error: "Invalid hardware state", data: {} }
      reportCapability()
      return
    }
    hardwareState = parsed
    reportCapability()
    if (profileIndex >= profiles.length) profileIndex = Math.max(0, profiles.length - 1)
  }

  function refresh() {
    if (!stateProcess.running) stateProcess.running = true
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function setProfile(profileName) {
    var name = String(profileName || "")
    if (name === "" || actionProcess.running) return
    actionProcess.command = ["desktop-hardware-action", "power", "set-profile", name]
    actionProcess.running = true
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  visible: capabilityAvailable
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  onCapabilityAvailableChanged: reportCapability()
  onPluginRegistryChanged: reportCapability()
  onBarChanged: reportCapability()
  Component.onCompleted: {
    reportCapability()
    refresh()
  }
  Component.onDestruction: {
    loaded = false
    refreshTimer.stop()
  }

  Timer {
    id: refreshTimer
    interval: 5000
    running: root.loaded
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProcess
    command: ["desktop-hardware-state", "power"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: root.refresh()
  }

  BarMetricButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconText: !root.batteryAvailable
      ? Model.profileIcon(root.activeProfile)
      : Model.batteryBarIcon(root.batteryPercent, root.batteryState, root.batteryOnBattery)
    valueText: root.batteryAvailable
      ? Model.batteryBarValue(root.batteryPercent, root.batteryState, root.batteryOnBattery)
      : ""
    valueIsIcon: root.batteryAvailable
      && Model.batteryBarValueIsIcon(root.batteryPercent, root.batteryState, root.batteryOnBattery)
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.capabilityAvailable
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(440))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0) root.selectProfileByDelta(dy)
        else if (dx !== 0) root.selectProfileByDelta(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.batteryAvailable ? "Battery" : "Power profile"
            meta: root.batteryAvailable ? Model.modeLabel(root.batteryState) : root.activeProfile
            detail: root.batteryAvailable && root.batteryPercent >= 0 ? root.batteryPercent + "%" : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: root.batteryAvailable
                ? Model.batteryIcon(root.batteryPercent, root.batteryState)
                : Model.profileIcon(root.activeProfile)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          width: parent.width
          visible: root.batteryAvailable
          text: root.battery.status || "Battery state unavailable"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        PanelSeparator { foreground: root.foreground }

        PanelSectionHeader {
          text: "POWER PROFILE"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Row {
          width: parent.width
          spacing: Style.space(6)
          visible: root.profiles.length > 0

          Repeater {
            model: root.profiles
            Button {
              required property string modelData
              required property int index
              width: Math.max(0, (parent.width - Style.space(6) * (root.profiles.length - 1)) / root.profiles.length)
              iconText: Model.profileIcon(modelData)
              text: modelData
              foreground: root.foreground
              fontFamily: root.fontFamily
              active: root.activeProfile === modelData
              hasCursor: root.cursorActive && root.profileIndex === index
              bordered: true
              onClicked: root.setProfile(modelData)
              onHovered: function(hovered) {
                if (hovered) {
                  root.cursorActive = true
                  root.profileIndex = index
                }
              }
            }
          }
        }

        Text {
          visible: root.profiles.length === 0
          text: "Power profiles unavailable"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
