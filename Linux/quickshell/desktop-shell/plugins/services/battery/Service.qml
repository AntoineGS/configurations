import QtQuick
import Quickshell
import Quickshell.Io
import "BatteryModel.js" as BatteryModel

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property bool loaded: true
  readonly property int batteryThreshold: 10
  property bool notifiedLowBattery: false

  PersistentProperties {
    id: persisted
    reloadableId: "desktop-battery"
    property bool notified: false
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
      notifiedLowBattery = false
      persisted.notified = false
      reportCapability(false)
      return
    }

    reportCapability(true)
    var result = BatteryModel.shouldWarnLowBattery(
      envelope.data.battery.status,
      batteryThreshold,
      persisted.notified
    )
    persisted.notified = result.notifiedLowBattery
    notifiedLowBattery = result.notifiedLowBattery
    if (result.notify) sendLowBatteryWarning(result.level)
  }

  function refresh() {
    if (!stateProcess.running) stateProcess.running = true
  }

  function sendLowBatteryWarning(level) {
    if (warningProcess.running) return
    warningProcess.command = ["battery-monitor", String(level)]
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

  Process { id: warningProcess }

  Timer {
    id: refreshTimer
    interval: 30000
    running: root.loaded
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }
}
