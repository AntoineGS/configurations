import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "BatteryModel.js" as BatteryModel

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var deliveryState: ({ active: null, queued: null, processRunning: false })
  property int warningGeneration: 0
  property int warningFinalizedGeneration: 0
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
    var scope = "capability:service:desktop.battery"
    if (available) pluginRegistry.clearPluginError("desktop.battery", scope)
    else pluginRegistry.recordPluginError("desktop.battery", "Battery capability unavailable", scope)
  }

  function checkBattery() {
    reportCapability(PowerState.batteryAvailable)
    if (!PowerState.batteryAvailable || PowerState.batteryOnBattery === false) {
      var reset = BatteryModel.warningDeliveryTransition(deliveryState, "ac-reset")
      deliveryState = reset.state
      persisted.lowNotified = false
      persisted.criticalNotified = false
      return
    }
    var result = BatteryModel.warningState(
      PowerState.batteryPercent,
      PowerState.batteryOnBattery,
      lowBatteryThreshold,
      criticalBatteryThreshold,
      persisted.lowNotified,
      persisted.criticalNotified
    )
    var transition = BatteryModel.warningDeliveryTransition(deliveryState, "warning", result)
    deliveryState = transition.state
    if (transition.action === "send") {
      sendLowBatteryWarning(result)
    }
  }

  function sendLowBatteryWarning(result) {
    deliveryState = BatteryModel.warningDeliveryTransition(deliveryState, "started").state
    var critical = result.urgency === "critical"
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
    warningGeneration++
    warningProcess.running = true
  }

  function finishWarning(exitCode, failedStart) {
    if (warningFinalizedGeneration === warningGeneration) return
    warningFinalizedGeneration = warningGeneration
    warningStartCheckTimer.stop()
    var event = failedStart || Number(exitCode) !== 0 ? "failure" : "success"
    var transition = BatteryModel.warningDeliveryTransition(root.deliveryState, event)
    root.deliveryState = transition.state
    if (transition.committed) {
      persisted.lowNotified = transition.committed.lowNotified
      persisted.criticalNotified = transition.committed.criticalNotified
    }
    if (transition.action === "retry") root.checkBattery()
  }

  Component.onCompleted: checkBattery()

  Connections {
    target: PowerState
    function onBatteryAvailableChanged() { root.checkBattery() }
    function onBatteryPercentChanged() { root.checkBattery() }
    function onBatteryStateChanged() { root.checkBattery() }
    function onBatteryOnBatteryChanged() { root.checkBattery() }
    function onReconciliationGenerationChanged() { root.checkBattery() }
  }

  Process {
    id: warningProcess
    onStarted: warningStartCheckTimer.stop()
    onExited: function(exitCode) { root.finishWarning(exitCode, false) }
    onRunningChanged: {
      if (!warningProcess.running && warningGeneration > warningFinalizedGeneration) {
        warningStartCheckTimer.generation = warningGeneration
        warningStartCheckTimer.start()
      }
    }
  }

  Timer {
    id: warningStartCheckTimer
    property int generation: 0
    interval: 100
    repeat: false
    onTriggered: if (!warningProcess.running && generation === root.warningGeneration)
      root.finishWarning(1, true)
  }

}
