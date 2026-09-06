import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/power" as Power

Item {
  id: root
  property int checks: 0
  property bool switched: false
  property bool profileRecoveryPassed: false
  property bool actionStartFailureSeen: false
  property bool actionRetainedDemand: false
  property bool actionFinished: false
  property bool batteryDemandChecked: false
  property bool batteryOutputChecked: false
  property bool batteryOneReleaseRetained: false
  property bool batteryAllReleasedCancelled: false
  property bool batteryAllReleasePending: false
  property var heldBatteryWorker: null
  property bool recoveryStarted: false
  property string actionLogText: ""
  readonly property string actionLogPath: Quickshell.env("POWER_FIXTURE_ACTION_LOG")
  readonly property string actionModePath: Quickshell.env("POWER_FIXTURE_ACTION_MODE")
  readonly property string actionReleasePath: Quickshell.env("POWER_FIXTURE_ACTION_RELEASE")
  readonly property string batteryModePath: Quickshell.env("POWER_FIXTURE_BATTERY_MODE")
  readonly property string batteryReleasePath: Quickshell.env("POWER_FIXTURE_BATTERY_RELEASE")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/monitor/fake-power-action")
    .toString().replace("file://", "")
  readonly property string fakeBatteryStatus: Qt.resolvedUrl("tests/fixtures/monitor/fake-battery-status")
    .toString().replace("file://", "")

  function fail(message) {
    console.error("Power profile shared fixture failed: " + String(message), root.actionLogText,
      root.batteryDemandChecked, root.batteryOutputChecked,
      root.batteryOneReleaseRetained, root.batteryAllReleasedCancelled,
      PowerState.profileServiceAvailable, PowerState.profileError,
      PowerState.reconciliationGeneration, PowerState.profileProbeGeneration,
      PowerState.profileProbeCompletedGeneration, PowerState.profileProbeStarted,
      PowerState.profileProbeInFlight)
    Qt.exit(1)
  }

  function startRecoveryScenario() {
    if (PowerState.profileProbeInFlight) {
      Qt.callLater(root.startRecoveryScenario)
      return
    }
    PowerState.profileProbeInterval = 100
    PowerState.profileCheckExecutable = "/definitely/missing-powerprofilesctl"
    PowerState.profileServiceAvailable = false
    PowerState.discoverProfileService()
  }

  function lines(text) {
    return String(text || "").split("\n").filter(function(line) { return line !== "" })
  }

  function startActionScenario() {
    root.profileRecoveryPassed = true
    powerService.actionExecutable = "/definitely/missing-power-action"
    powerService.setProfile("balanced")
  }

  function advance() {
    try {
      if (!root.batteryDemandChecked) {
        if (!root.batteryAllReleasePending) {
          if (!powerService.batteryAvailable || !powerService.batteryWorker
              || !powerService.batteryWorker.running || powerService.consumerCount !== 2) return
          root.heldBatteryWorker = powerService.batteryWorker
          powerLeft.active = false
          root.batteryOneReleaseRetained = powerService.consumerCount === 1
            && powerService.detailed
            && powerService.batteryWorker === root.heldBatteryWorker
            && root.heldBatteryWorker.running
          powerRight.active = false
          root.batteryAllReleasePending = true
          return
        }
        if (powerService.consumerCount !== 0 || powerService.collecting
            || powerService.batteryWorker !== null) return
        root.batteryAllReleasedCancelled = !root.heldBatteryWorker
          || !root.heldBatteryWorker.running
        if (!root.batteryAllReleasedCancelled) return
        batteryModeFile.setText("wait\n")
        powerLeft.active = true
        powerRight.active = true
        root.batteryDemandChecked = root.batteryOneReleaseRetained
          && root.batteryAllReleasedCancelled
        return
      }
      if (!root.batteryOutputChecked) {
        if (powerService.batteryStatusOutput !== "fixture battery detail") return
        root.batteryOutputChecked = true
        if (!root.recoveryStarted) {
          root.recoveryStarted = true
          root.startRecoveryScenario()
        }
        return
      }
      if (!root.profileRecoveryPassed) return
      if (!root.actionStartFailureSeen) {
        if (powerService.actionError !== "Power profile action failed to start") return
        root.actionStartFailureSeen = true
        powerService.actionExecutable = root.fakeAction
        actionModeFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        powerService.setProfile("balanced")
        return
      }
      if (!root.actionRetainedDemand) {
        if (!powerService.actionWorker || !powerService.actionWorker.running) return
        root.actionRetainedDemand = powerService.operationPending
          && powerService.consumerCount === 2
        powerLeft.active = false
        powerRight.active = false
        root.actionRetainedDemand = root.actionRetainedDemand
          && powerService.consumerCount === 0 && powerService.collecting
        actionReleaseFile.setText("release\n")
        return
      }
      actionLog.reload()
      var actions = root.lines(root.actionLogText)
      if (powerService.operationPending || powerService.collecting) return
      root.actionFinished = actions.indexOf("power set-profile balanced") !== -1
      if (!root.actionFinished) return
      if (!root.batteryDemandChecked || !root.batteryOutputChecked) return
      console.log("Power profile capability fixture passed", PowerState.reconciliationGeneration)
      Qt.exit(0)
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }

  QtObject {
    id: fakeShell
    property bool previewMode: false
    function widgetSettingsFor(pluginId) { return ({}) }
  }

  Power.Service {
    id: powerService
    shell: fakeShell
    manifest: ({ id: "desktop.power" })
    actionExecutable: "/definitely/missing-power-action"
    batteryStatusExecutable: root.fakeBatteryStatus
    batteryAvailableOverride: true
    processStartGraceInterval: 50
  }

  ServiceConsumer { id: powerLeft; service: powerService; details: true }
  ServiceConsumer { id: powerRight; service: powerService; details: true }

  FileView {
    id: actionLog
    path: root.actionLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.actionLogText = text()
  }

  FileView { id: actionModeFile; path: root.actionModePath; printErrors: false }
  FileView { id: actionReleaseFile; path: root.actionReleasePath; printErrors: false }
  FileView { id: batteryModeFile; path: root.batteryModePath; printErrors: false }
  FileView { id: batteryReleaseFile; path: root.batteryReleasePath; printErrors: false }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: root.advance()
  }

  Timer {
    interval: 500
    repeat: false
    running: false
  }

  Connections {
    target: PowerState
    function onProfileErrorChanged() {
      if (!root.switched && PowerState.profileError !== "") {
        root.switched = true
        PowerState.profileCheckExecutable = "powerprofilesctl"
        PowerState.discoverProfileService()
      }
    }
    function onProfileServiceAvailableChanged() {
      if (root.switched && PowerState.profileServiceAvailable && PowerState.profileError === "") {
        root.startActionScenario()
      }
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      if (root.checks >= 1500) root.fail("watchdog expired")
    }
  }
}
