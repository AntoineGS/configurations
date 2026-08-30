pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import "../plugins/panels/power/Model.js" as PowerModel

QtObject {
  id: root

  readonly property var device: root.reconciliationGeneration >= 0 ? UPower.displayDevice : null
  readonly property bool batteryAvailable: root.reconciliationGeneration >= 0
    && !!device && device.ready && device.isPresent
  readonly property int batteryPercent: PowerModel.nativeBatteryPercent(
    root.reconciliationGeneration >= 0 && batteryAvailable, device ? device.percentage : -1)
  readonly property string batteryState: root.reconciliationGeneration >= 0 && batteryAvailable
    ? PowerModel.nativeBatteryState(device.state) : "unknown"
  readonly property bool batteryOnBattery: root.reconciliationGeneration >= 0 ? UPower.onBattery : false
  property bool profileServiceAvailable: false
  property string profileError: ""
  property string profileCheckExecutable: "powerprofilesctl"
  property int profileProbeInterval: 60000
  property int profileProbeGeneration: 0
  property int profileProbeCompletedGeneration: 0
  property bool profileProbeInFlight: false
  property bool profileProbeStarted: false
  readonly property string activeProfile: root.reconciliationGeneration >= 0 && profileServiceAvailable
    ? PowerModel.nativeProfileName(PowerProfiles.profile) : ""
  readonly property var profiles: root.reconciliationGeneration >= 0 && profileServiceAvailable
    ? PowerModel.profileNames(PowerProfiles.hasPerformanceProfile) : []
  readonly property bool capabilityAvailable: root.reconciliationGeneration >= 0
    && (batteryAvailable || profileServiceAvailable)
  readonly property int remainingSeconds: root.reconciliationGeneration < 0 || !batteryAvailable ? 0
    : (batteryOnBattery ? Number(device.timeToEmpty) : Number(device.timeToFull))
  readonly property real energyRate: root.reconciliationGeneration >= 0 && batteryAvailable
    ? Number(device.changeRate) : 0
  property int reconciliationGeneration: 0

  function reconcile() {
    reconciliationGeneration++
  }

  function discoverProfileService() {
    if (profileCheckProcess.running || profileProbeInFlight) return
    profileProbeGeneration++
    profileProbeInFlight = true
    profileProbeStarted = false
    profileCheckProcess.running = true
    profileProbeGraceTimer.generation = profileProbeGeneration
    profileProbeGraceTimer.start()
  }

  function finishProfileProbe(generation, available, error) {
    if (generation !== profileProbeGeneration || profileProbeCompletedGeneration === generation) return
    profileProbeCompletedGeneration = generation
    profileProbeInFlight = false
    profileProbeGraceTimer.stop()
    profileError = available ? "" : error
    profileServiceAvailable = available
    reconcile()
  }

  function markProfileActionFailed(error) {
    profileError = error || "Power profile action failed"
    reconcile()
  }

  property Timer startupReconciliation: Timer {
    interval: 0
    running: true
    repeat: false
    onTriggered: {
      root.reconcile()
      root.discoverProfileService()
    }
  }

  property Timer periodicReconciliation: Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      root.reconcile()
      if (!root.profileServiceAvailable) root.discoverProfileService()
    }
  }

  property Timer profileRecovery: Timer {
    interval: root.profileProbeInterval
    running: !root.profileServiceAvailable && !root.profileProbeInFlight
    repeat: true
    triggeredOnStart: false
    onTriggered: root.discoverProfileService()
  }

  property Timer profileProbeGraceTimer: Timer {
    property int generation: 0
    interval: 100
    repeat: false
    onTriggered: {
      if (!profileCheckProcess.running)
        root.finishProfileProbe(generation, false, "power profile capability probe failed to start")
    }
  }

  property Process profileCheckProcess: Process {
    command: ["sh", "-c", "command -v -- \"$1\" >/dev/null 2>&1 || exit 127; exec \"$1\" get",
      "power-profile-probe", root.profileCheckExecutable]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      root.profileProbeStarted = true
      profileProbeGraceTimer.stop()
    }
    onExited: function(exitCode, exitStatus) {
      var succeeded = root.profileProbeStarted && Number(exitCode) === 0 && Number(exitStatus) === 0
      root.finishProfileProbe(root.profileProbeGeneration, succeeded,
        succeeded ? "" : "power profile capability probe failed")
    }
    onRunningChanged: {
      if (!profileCheckProcess.running && root.profileProbeInFlight
          && profileProbeCompletedGeneration !== profileProbeGeneration) {
        profileProbeGraceTimer.generation = profileProbeGeneration
        profileProbeGraceTimer.start()
      }
    }
  }

  property Connections powerProfilesEvents: Connections {
    target: PowerProfiles
    function onProfileChanged() { root.reconcile() }
    function onHasPerformanceProfileChanged() { root.reconcile() }
  }
}
