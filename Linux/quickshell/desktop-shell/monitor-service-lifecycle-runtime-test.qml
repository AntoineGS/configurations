import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/monitor" as Monitor

Item {
  id: root

  readonly property string stateModePath: Quickshell.env("MONITOR_FIXTURE_STATE_MODE") || ""
  readonly property string oldStateHoldPath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_OLD_HOLD") || ""
  readonly property string oldStateReleasePath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_OLD_RELEASE") || ""
  readonly property string oldStateEnteredPath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_OLD_ENTERED") || ""
  readonly property string newStateHoldPath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_NEW_HOLD") || ""
  readonly property string newStateReleasePath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_NEW_RELEASE") || ""
  readonly property string newStateEnteredPath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_NEW_ENTERED") || ""
  readonly property string actionModePath: Quickshell.env("MONITOR_FIXTURE_ACTION_MODE") || ""
  readonly property string actionReleasePath: Quickshell.env("MONITOR_FIXTURE_ACTION_RELEASE") || ""
  readonly property string fakeState: Qt.resolvedUrl("tests/fixtures/monitor/fake-state-restart")
    .toString().replace("file://", "")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/monitor/fake-action")
    .toString().replace("file://", "")
  readonly property string fakeHostname: Qt.resolvedUrl("tests/fixtures/monitor/fake-hostname")
    .toString().replace("file://", "")

  property int phase: 0
  property int checks: 0
  property var oldWorker: null
  property int postActionGeneration: 0
  property string oldStateEnteredText: ""
  property string newStateEnteredText: ""

  QtObject {
    id: fakeShell
    property bool previewMode: false
    function widgetSettingsFor(pluginId) { return ({}) }
  }

  Monitor.Service {
    id: service
    shell: fakeShell
    manifest: ({ id: "desktop.monitor" })
    stateExecutable: root.fakeState
    actionExecutable: root.fakeAction
    hostnameExecutable: root.fakeHostname
    processStartGraceInterval: 50
  }

  ServiceConsumer {
    id: consumer
    service: service
  }

  FileView { id: stateModeFile; path: root.stateModePath; printErrors: false }
  FileView { id: oldStateHoldFile; path: root.oldStateHoldPath; printErrors: false }
  FileView { id: oldStateReleaseFile; path: root.oldStateReleasePath; printErrors: false }
  FileView { id: newStateHoldFile; path: root.newStateHoldPath; printErrors: false }
  FileView { id: newStateReleaseFile; path: root.newStateReleasePath; printErrors: false }
  FileView { id: actionModeFile; path: root.actionModePath; printErrors: false }
  FileView { id: actionReleaseFile; path: root.actionReleasePath; printErrors: false }

  FileView {
    id: oldStateEnteredFile
    path: root.oldStateEnteredPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.oldStateEnteredText = text()
    onFileChanged: reload()
  }

  FileView {
    id: newStateEnteredFile
    path: root.newStateEnteredPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.newStateEnteredText = text()
    onFileChanged: reload()
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      root.advance()
      if (root.checks >= 600) {
        console.error("Monitor service lifecycle fixture timed out", root.phase,
          service.consumerCount, service.collecting, service.operationPending,
          service.reconciliationRunning, service.stateWorker, service.actionWorker,
          service.brightnessPercent, root.oldStateEnteredText, root.newStateEnteredText)
        Qt.exit(1)
      }
    }
  }

  function fail(message) {
    console.error("Monitor service lifecycle fixture failed: " + String(message), root.phase,
      service.consumerCount, service.collecting, service.operationPending,
      service.brightnessPercent)
    Qt.exit(1)
  }

  function advance() {
    try {
      if (root.phase === 0) {
        if (!service.hardwareState.available) return
        stateModeFile.setText("old\n")
        oldStateHoldFile.setText("hold\n")
        oldStateReleaseFile.setText("wait\n")
        service.refresh()
        root.phase = 1
        return
      }

      if (root.phase === 1) {
        if (String(root.oldStateEnteredText).trim() !== "held") return
        root.oldWorker = service.stateWorker
        consumer.active = false
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (service.consumerCount !== 0 || service.collecting) return
        if (service.stateWorker || service.operationPending)
          return root.fail("last consumer did not cancel routine monitor query")
        stateModeFile.setText("new\n")
        newStateHoldFile.setText("hold\n")
        newStateReleaseFile.setText("wait\n")
        consumer.active = true
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        if (!service.stateWorker || !service.stateWorker.running || service.stateWorker === root.oldWorker)
          return
        if (service.brightnessPercent !== 40)
          return root.fail("restarted query published stale state before the new result")
        oldStateReleaseFile.setText("release\n")
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        if (service.brightnessPercent !== 40) return root.fail("stale canceled callback replaced state")
        if (String(root.newStateEnteredText).trim() !== "held") return
        newStateReleaseFile.setText("release\n")
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (service.brightnessPercent !== 90) return
        root.postActionGeneration = service.reconciliationGeneration
        actionModeFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        newStateHoldFile.setText("hold\n")
        newStateReleaseFile.setText("wait\n")
        service.setBrightness(75)
        root.phase = 6
        return
      }

      if (root.phase === 6) {
        if (!service.actionWorker || !service.actionWorker.running) return
        consumer.active = false
        root.phase = 7
        return
      }

      if (root.phase === 7) {
        if (service.consumerCount !== 0) return
        if (!service.collecting || !service.operationPending)
          return root.fail("accepted monitor action did not retain collection")
        actionReleaseFile.setText("release\n")
        root.phase = 8
        return
      }

      if (root.phase === 8) {
        if (!service.collecting || !service.operationPending || service.actionWorker
            || !service.stateWorker || !service.stateWorker.running
            || service.reconciliationGeneration <= root.postActionGeneration)
          return
        newStateReleaseFile.setText("release\n")
        root.phase = 9
        return
      }

      if (root.phase === 9) {
        if (service.collecting || service.operationPending || service.stateWorker) return
        console.log("Monitor service lifecycle fixture passed")
        Qt.exit(0)
      }
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }
}
