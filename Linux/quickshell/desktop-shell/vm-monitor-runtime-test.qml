import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/panels/vm"

Item {
  id: root
  property string fixtureStatePath: Qt.resolvedUrl("tests/fixtures/vm/state-mode")
  property string watcherModePath: Quickshell.env("VM_FIXTURE_WATCHER_MODE")
    || Qt.resolvedUrl("tests/fixtures/vm/watcher-mode")
  property string fakeVirsh: Qt.resolvedUrl("tests/fixtures/vm/fake-virsh").toString().replace("file://", "")
  property string fakeState: Qt.resolvedUrl("tests/fixtures/vm/fake-state").toString().replace("file://", "")
  property bool sawRunning: false
  property bool sawStopped: false
  property bool sawStale: false
  property bool sawMultiple: false
  property bool installed: false
  property bool sawWatcherStop: false
  property bool forceWatcherStartFailure: false
  property int checks: 0
  property bool sawUtilization: false
  property bool sawReconciliation: false
  property bool sawStartupPhase: false
  property bool sawSteadyPhase: false
  property int watcherStartEvents: 0
  property int reconciliationStartEvents: 0

  function finish() {
    var success = sawRunning && sawStopped && sawStale && sawMultiple && sawUtilization
      && sawReconciliation && sawStartupPhase && sawSteadyPhase
      && watcherStartEvents >= 1 && reconciliationStartEvents >= 4
    modeFile.setText("running-missing\n")
    watcherModeFile.setText("stable\n")
    if (!success) console.error("VmMonitor fixture failed", sawRunning, sawStopped, sawStale, sawMultiple,
      sawUtilization, sawReconciliation, watcherStartEvents, reconciliationStartEvents,
      monitor.capabilityAvailable, monitor.watcherRunning, monitor.reconciliationRunning)
    else console.log("VmMonitor fake-process fixture passed")
    Qt.exit(success ? 0 : 1)
  }

  VmMonitor {
    id: monitor
    virshExecutable: installed && !root.forceWatcherStartFailure ? root.fakeVirsh : root.fakeVirsh + ".missing"
    stateHelperExecutable: root.fakeState
    capabilityProbeInterval: 100
    startupReconciliationInterval: 100
    steadyReconciliationInterval: 300
    stabilityInterval: 200
    utilizationInterval: 100
    processStartGraceInterval: 50
    onStateChanged: {
      if (state.confirmedRunning) root.sawRunning = true
      if (!state.available && !state.stale) root.sawStopped = true
      if (state.stale && state.error === "fixture stale") root.sawStale = true
      if (state.error === "more than one running VM was found") root.sawMultiple = true
    }
  }

  Connections {
    target: monitor
    function onWatcherRunningChanged() {
      if (monitor.watcherRunning) root.watcherStartEvents++
    }
    function onReconciliationRunningChanged() {
      if (monitor.reconciliationRunning) root.reconciliationStartEvents++
    }
  }

  FileView {
    id: modeFile
    path: root.fixtureStatePath
    preload: false
    printErrors: false
    blockWrites: false
  }

  FileView {
    id: watcherModeFile
    path: root.watcherModePath
    preload: false
    printErrors: false
    blockWrites: false
  }

  Timer {
    interval: 200
    repeat: false
    running: true
    onTriggered: {
      root.installed = true
      Qt.callLater(function() { monitor.probeNow() })
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      root.sawUtilization = root.sawUtilization || monitor.utilizationRunning
      root.sawReconciliation = root.sawReconciliation || monitor.reconciliationRunning
        || reconciliationStartEvents > 0
      root.sawStartupPhase = root.sawStartupPhase || monitor.monitorState.startupPhase
      root.sawSteadyPhase = root.sawSteadyPhase || !monitor.monitorState.startupPhase
      if (root.checks >= 200) {
        stop()
        root.finish()
        return
      }
      if (root.sawRunning && !root.sawUtilization && !root.forceWatcherStartFailure && !root.sawWatcherStop) {
        return
      } else if (root.sawRunning && !root.forceWatcherStartFailure && !root.sawWatcherStop) {
        watcherModeFile.setText("flap\n")
        root.forceWatcherStartFailure = true
      } else if (root.forceWatcherStartFailure && !monitor.watcherRunning
          && monitor.backoffSeconds >= 4) {
        root.sawWatcherStop = true
        watcherModeFile.setText("stable\n")
        root.forceWatcherStartFailure = false
        modeFile.setText("stopped\n")
        monitor.refreshNow()
      } else if (root.sawWatcherStop && root.sawStopped && !root.sawStale) {
        modeFile.setText("stale\n")
        monitor.refreshNow()
      } else if (root.sawStale && !root.sawMultiple) {
        modeFile.setText("multiple\n")
        monitor.refreshNow()
      } else if (root.sawMultiple) {
        stop()
        root.finish()
      }
    }
  }
}
