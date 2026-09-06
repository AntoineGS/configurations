import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/vm"

Item {
  id: root

  readonly property string stateHoldPath: Quickshell.env("VM_FIXTURE_STATE_HOLD") || ""
  readonly property string stateEnteredPath: Quickshell.env("VM_FIXTURE_STATE_ENTERED") || ""
  readonly property string actionModePath: Quickshell.env("VM_FIXTURE_ACTION_MODE") || ""
  readonly property string actionReleasePath: Quickshell.env("VM_FIXTURE_ACTION_RELEASE") || ""
  readonly property string actionEnteredPath: Quickshell.env("VM_FIXTURE_ACTION_ENTERED") || ""
  readonly property string fakeVirsh: Qt.resolvedUrl("tests/fixtures/vm/fake-virsh").toString().replace("file://", "")
  readonly property string fakeState: Qt.resolvedUrl("tests/fixtures/vm/fake-state").toString().replace("file://", "")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/vm/fake-action").toString().replace("file://", "")

  property int phase: 0
  property int checks: 0
  property bool actionAccepted: false
  property string stateEnteredText: ""
  property string actionEnteredText: ""

  QtObject {
    id: fakeShell
    property bool previewMode: false
    function widgetSettingsFor(pluginId) { return ({}) }
    function serviceFor(pluginId) {
      return String(pluginId) === "desktop.host-metrics" ? hostService : null
    }
  }

  SharedService {
    id: hostService
    shell: fakeShell
    manifest: ({ id: "desktop.host-metrics" })
    property var cpuState: ({ available: true, percent: 10 })
    property var memoryState: ({ available: true, percent: 20 })
  }

  Service {
    id: service
    shell: fakeShell
    manifest: ({ id: "desktop.vm" })
    virshExecutable: root.fakeVirsh
    stateHelperExecutable: root.fakeState
    actionExecutable: root.fakeAction
    capabilityProbeInterval: 50
    startupReconciliationInterval: 100
    steadyReconciliationInterval: 500
    stabilityInterval: 50
    utilizationInterval: 100
    processStartGraceInterval: 50
  }

  ServiceConsumer {
    id: consumer
    service: service
    details: true
  }

  FileView { id: stateHoldFile; path: root.stateHoldPath; printErrors: false }
  FileView { id: actionModeFile; path: root.actionModePath; printErrors: false }
  FileView { id: actionReleaseFile; path: root.actionReleasePath; printErrors: false }

  FileView {
    id: stateEnteredFile
    path: root.stateEnteredPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.stateEnteredText = text()
    onFileChanged: reload()
  }

  FileView {
    id: actionEnteredFile
    path: root.actionEnteredPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.actionEnteredText = text()
    onFileChanged: reload()
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      root.advance()
      if (root.checks >= 750) {
        console.error("VM service lifecycle fixture timed out", root.phase,
          service.consumerCount, service.collecting, service.operationPending,
          service.watcherRunning, service.reconciliationRunning, service.resizePending,
          root.stateEnteredText, root.actionEnteredText)
        Qt.exit(1)
      }
    }
  }

  function fail(message) {
    console.error("VM service lifecycle fixture failed: " + String(message), root.phase,
      service.consumerCount, service.collecting, service.operationPending,
      service.watcherRunning, service.reconciliationRunning, service.resizePending)
    Qt.exit(1)
  }

  function advance() {
    try {
      if (root.phase === 0) {
        if (!service.watcherRunning || !service.state.confirmedRunning || !service.state.canResize
            || service.reconciliationRunning)
          return
        stateHoldFile.setText("hold\n")
        service.refreshNow()
        root.phase = 1
        return
      }

      if (root.phase === 1) {
        if (!service.reconciliationRunning || String(root.stateEnteredText).trim() !== "held") return
        consumer.active = false
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (service.consumerCount !== 0) return
        if (service.collecting)
          return root.fail("last VM consumer retained a routine held query")
        stateHoldFile.setText("release\n")
        consumer.active = true
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        if (!service.watcherRunning || !service.state.confirmedRunning || !service.state.canResize
            || service.reconciliationRunning)
          return
        stateHoldFile.setText("hold\n")
        actionModeFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        actionEnteredFile.reload()
        root.actionAccepted = service.requestMemory(1)
        if (!root.actionAccepted) return root.fail("fake VM memory action was not accepted")
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        if (String(root.actionEnteredText).trim() !== "held") return
        consumer.active = false
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (service.consumerCount !== 0) return
        if (!service.collecting || !service.operationPending || !service.resizePending)
          return root.fail("in-flight VM action did not retain collection")
        actionReleaseFile.setText("release\n")
        root.phase = 6
        return
      }

      if (root.phase === 6) {
        if (!service.collecting || !service.operationPending || !service.resizePending
            || !service.reconciliationRunning)
          return
        stateHoldFile.setText("release\n")
        root.phase = 7
        return
      }

      if (root.phase === 7) {
        if (service.collecting || service.operationPending || service.resizePending
            || service.reconciliationRunning) return
        console.log("VM service lifecycle fixture passed")
        Qt.exit(0)
      }
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }
}
