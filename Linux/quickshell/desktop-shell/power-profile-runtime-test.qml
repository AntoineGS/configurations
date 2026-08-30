import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root
  property int checks: 0
  property bool switched: false

  function fail() {
    console.error("Power profile capability fixture failed", PowerState.profileServiceAvailable,
      PowerState.profileError, PowerState.reconciliationGeneration, PowerState.profileProbeGeneration,
      PowerState.profileProbeCompletedGeneration, PowerState.profileProbeStarted,
      PowerState.profileProbeInFlight)
    Qt.exit(1)
  }

  function startRecoveryScenario() {
    PowerState.profileProbeInterval = 100
    PowerState.profileCheckExecutable = "/definitely/missing-powerprofilesctl"
    PowerState.profileServiceAvailable = false
    PowerState.discoverProfileService()
  }

  Timer {
    interval: 500
    repeat: false
    running: true
    onTriggered: root.startRecoveryScenario()
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
        console.log("Power profile capability fixture passed", PowerState.reconciliationGeneration)
        Qt.exit(0)
      }
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      if (root.checks >= 200) root.fail()
    }
  }
}
