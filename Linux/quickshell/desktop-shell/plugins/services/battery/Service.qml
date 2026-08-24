import QtQuick
import Quickshell
import Quickshell.Io
import "BatteryModel.js" as BatteryModel

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property bool loaded: true
  property var pendingWarning: null
  readonly property int lowBatteryThreshold: 20
  readonly property int criticalBatteryThreshold: 10

  PersistentProperties {
    id: persisted
    reloadableId: "desktop-battery"
    property bool lowNotified: false
    property bool criticalNotified: false
  }

  function reportCapability(available) {
    if (!pluginRegistry) return
    if (available) pluginRegistry.clearPluginError("desktop.battery")
    else pluginRegistry.recordPluginError("desktop.battery", "Battery capability unavailable")
  }

  function checkBattery(raw) {
    var envelope
    try {
      envelope = JSON.parse(String(raw || ""))
    } catch (error) {
      reportCapability(false)
      return
    }
    if (!envelope || envelope.available !== true || !envelope.data || !envelope.data.battery) {
      reportCapability(false)
      return
    }

    reportCapability(true)
    var battery = envelope.data.battery
    var result = BatteryModel.warningState(
      battery.status,
      battery.onBattery,
      lowBatteryThreshold,
      criticalBatteryThreshold,
      persisted.lowNotified,
      persisted.criticalNotified
    )
    if (result.notify) {
      sendLowBatteryWarning(result)
      return
    }
    if (battery.onBattery === false) pendingWarning = null
    persisted.lowNotified = result.lowNotified
    persisted.criticalNotified = result.criticalNotified
  }

  function refresh() {
    if (!stateProcess.running) stateProcess.running = true
  }

  function sendLowBatteryWarning(result) {
    if (warningProcess.running) return
    var critical = result.urgency === "critical"
    pendingWarning = result
    warningProcess.command = [
      "notify-send",
      "--app-name", "Desktop Shell",
      "--urgency", critical ? "critical" : "normal",
      "--icon", "battery-caution",
      "--expire-time", "30000",
      critical ? "󱐋 Time to recharge!" : "󰁹 Battery low",
      critical
        ? "Battery is down to " + result.level + "%"
        : "Battery is down to " + result.level + "% - consider plugging in"
    ]
    warningProcess.running = true
  }

  Component.onCompleted: refresh()
  Component.onDestruction: {
    loaded = false
    refreshTimer.stop()
  }

  Process {
    id: stateProcess
    command: ["desktop-hardware-state", "power"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.checkBattery(text)
    }
  }

  Process {
    id: warningProcess
    onExited: function(exitCode) {
      if (Number(exitCode) === 0 && root.pendingWarning) {
        persisted.lowNotified = root.pendingWarning.lowNotified
        persisted.criticalNotified = root.pendingWarning.criticalNotified
      }
      root.pendingWarning = null
    }
  }

  Timer {
    id: refreshTimer
    interval: 30000
    running: root.loaded
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }
}
