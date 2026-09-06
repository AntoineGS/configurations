import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/recording" as Recording

Item {
  id: root
  property string modePath: Quickshell.env("RECORDING_FIXTURE_MODE")
  property string countPath: Quickshell.env("RECORDING_FIXTURE_COUNT")
  property string activePath: Quickshell.env("RECORDING_FIXTURE_ACTIVE")
  property string prepareReleasePath: Quickshell.env("RECORDING_FIXTURE_PREPARE_RELEASE")
    || root.countPath + ".prepare-release"
  property string prepareOverlapPath: Quickshell.env("RECORDING_FIXTURE_PREPARE_OVERLAP")
    || root.countPath + ".prepare-overlap"
  property string reconcileLogPath: Quickshell.env("RECORDING_FIXTURE_RECONCILE_LOG")
    || root.countPath + ".reconcile.log"
  property string reconcileActivePath: Quickshell.env("RECORDING_FIXTURE_RECONCILE_ACTIVE")
    || root.countPath + ".reconcile-active"
  property string reconcileOverlapPath: Quickshell.env("RECORDING_FIXTURE_RECONCILE_OVERLAP")
    || root.countPath + ".reconcile-overlap"
  property string toggleLogPath: Quickshell.env("RECORDING_FIXTURE_TOGGLE_LOG")
    || root.countPath + ".toggle.log"
  property string toggleActivePath: Quickshell.env("RECORDING_FIXTURE_TOGGLE_ACTIVE")
    || root.countPath + ".toggle-active"
  property string toggleReleasePath: Quickshell.env("RECORDING_FIXTURE_TOGGLE_RELEASE")
    || root.countPath + ".toggle-release"
  property string toggleOverlapPath: Quickshell.env("RECORDING_FIXTURE_TOGGLE_OVERLAP")
    || root.countPath + ".toggle-overlap"
  property string statePath: Quickshell.env("RECORDING_FIXTURE_STATE")
    || Quickshell.env("XDG_RUNTIME_DIR") + "/desktop-shell/recording.json"
  property string fakePrepare: Qt.resolvedUrl("tests/fixtures/recording/fake-prepare").toString().replace("file://", "")
  property string fakeReconcile: Qt.resolvedUrl("tests/fixtures/recording/fake-reconcile").toString()
    .replace("file://", "")
  property string fakeToggle: Qt.resolvedUrl("tests/fixtures/recording/fake-toggle").toString()
    .replace("file://", "")
  property bool switched: false
  property int checks: 0
  property int phase: 0
  property var secondConsumer: null
  property int activeCollectionGeneration: -1
  property var staleStateReader: ({})
  property string staleStateText: '{"version":1,"active":true,"output":"/tmp/stale-recording.mp4"}\n'
  property int prepareHoldStartChecks: -1
  property int prepareCountAtStop: 0
  property int reconcileCountAtStop: 0
  property string countText: ""
  property string reconcileLogText: ""
  property string toggleLogText: ""
  property string prepareOverlapText: ""
  property string reconcileOverlapText: ""
  property string toggleOverlapText: ""

  QtObject {
    id: fakeShell
    property bool previewMode: false

    function widgetSettingsFor(pluginId) { return ({}) }
  }

  Recording.Service {
    id: recordingService
    shell: fakeShell
    manifest: ({ id: "desktop.recording" })
    prepareExecutable: root.fakePrepare
    reconcileExecutable: root.fakeReconcile
    toggleExecutable: root.fakeToggle
    initialPrepareInterval: 1000
    recoveryPrepareInterval: 100
  }

  ServiceConsumer {
    id: first
    service: recordingService
    active: false
  }

  Component {
    id: consumerComponent

    ServiceConsumer { }
  }

  FileView {
    id: modeFile
    path: root.modePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: countFile
    path: root.countPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.countText = text()
    onLoadFailed: root.countText = ""
    onFileChanged: reload()
  }

  FileView {
    id: reconcileLog
    path: root.reconcileLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.reconcileLogText = text()
    onLoadFailed: root.reconcileLogText = ""
    onFileChanged: reload()
  }

  FileView {
    id: toggleLog
    path: root.toggleLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.toggleLogText = text()
    onLoadFailed: root.toggleLogText = ""
    onFileChanged: reload()
  }

  FileView {
    id: prepareOverlapFile
    path: root.prepareOverlapPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.prepareOverlapText = text()
    onLoadFailed: root.prepareOverlapText = ""
    onFileChanged: reload()
  }

  FileView {
    id: prepareReleaseFile
    path: root.prepareReleasePath
    preload: true
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: reconcileOverlapFile
    path: root.reconcileOverlapPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.reconcileOverlapText = text()
    onLoadFailed: root.reconcileOverlapText = ""
    onFileChanged: reload()
  }

  FileView {
    id: toggleOverlapFile
    path: root.toggleOverlapPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.toggleOverlapText = text()
    onLoadFailed: root.toggleOverlapText = ""
    onFileChanged: reload()
  }

  FileView {
    id: toggleReleaseFile
    path: root.toggleReleasePath
    preload: true
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: stateFile
    path: root.statePath
    preload: true
    watchChanges: true
    blockWrites: false
    printErrors: false
  }

  Connections {
    target: recordingService
    function onPrepareErrorChanged() {
      if (!root.switched && recordingService.prepareError !== "") {
        root.switched = true
        modeFile.setText("hold\n")
      }
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      root.advance()
      if (root.checks >= 600) {
        console.error("Recording bootstrap fixture timed out", root.phase,
          recordingService.prepareGeneration, recordingService.prepareFinalizedGeneration,
          recordingService.prepareInFlight, recordingService.prepareError,
          recordingService.consumerCount, recordingService.collecting,
          recordingService.operationPending)
        Qt.exit(1)
      }
    }
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  function lines(text) {
    return String(text || "").split("\n").filter(function(line) { return line !== "" })
  }

  function fail(message) {
    console.error("recording-bootstrap-runtime-test: " + String(message))
    Qt.exit(1)
  }

  function finish() {
    console.log("Recording shared lifecycle fixture passed", recordingService.prepareGeneration,
      lines(reconcileLog.text()).length, lines(toggleLog.text()).length)
    Qt.exit(0)
  }

  function advance() {
    try {
      if (!first.ready) return
      if (root.phase === 0 && !root.secondConsumer) {
        root.secondConsumer = consumerComponent.createObject(root, {
          service: recordingService,
          active: false
        })
        check(root.secondConsumer !== null, "second consumer is created dynamically")
        return
      }
      if (root.phase === 0 && !root.secondConsumer.ready) return

      countFile.reload()
      reconcileLog.reload()
      toggleLog.reload()
      var prepareCount = Number(String(root.countText || "0").trim()) || 0
      var reconcileCount = lines(root.reconcileLogText).length
      var toggleCount = lines(root.toggleLogText).length

      if (root.phase === 0) {
        check(recordingService.consumerCount === 0 && !recordingService.collecting,
          "inactive consumers do not activate collection")
        check(recordingService.prepareGeneration === 0 && !recordingService.runtimeReady,
          "service construction does not start preparation")
        first.active = true
        root.secondConsumer.active = true
        root.phase = 1
        return
      }

      if (root.phase === 1) {
        if (root.checks < 6) return
        check(prepareCount >= 1, "first prepare starts on collection activation")
        if (recordingService.prepareError === "") return
        check(recordingService.prepareGeneration === 1 && !recordingService.prepareInFlight,
          "failed prepare finalizes exactly once")
        check(recordingService.consumerCount === 2, "both consumers receive the failed bootstrap")
        check(!recordingService.runtimeReady, "failed prepare does not publish runtime readiness")
        first.active = false
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (prepareCount < 2 || recordingService.prepareGeneration < 2 || !recordingService.prepareInFlight)
          return
        if (root.prepareHoldStartChecks < 0) root.prepareHoldStartChecks = root.checks
        if (root.checks < root.prepareHoldStartChecks + 6) return
        check(first.active === false && recordingService.consumerCount === 1,
          "removing the first consumer leaves the recovery consumer attached")
        check(prepareCount === 2, "held bootstrap has one in-flight prepare worker")
        check(root.prepareOverlapText === "", "prepare calls do not overlap")
        check(!recordingService.startPrepare(), "prepare requests coalesce while a worker is held")
        check(prepareCount === 2, "coalesced prepare requests do not spawn another worker")
        prepareReleaseFile.setText("release\n")
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        if (!recordingService.runtimeReady || reconcileCount < 1) return
        check(recordingService.prepareGeneration === 2 && !recordingService.prepareInFlight,
          "bootstrap retries once after the initial failure")
        check(reconcileCount === 1, "bootstrap runs one reconciliation")
        stateFile.setText('{"version":1,"active":true,"output":"/tmp/fake-recording.mp4"}\n')
        root.activeCollectionGeneration = recordingService.collectionGeneration
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        if (!recordingService.loaded || !recordingService.recording) return
        check(recordingService.outputPath === "/tmp/fake-recording.mp4",
          "state watcher publishes the validated output path")
        check(recordingService.toggleRecording(), "first toggle request is accepted")
        check(!recordingService.toggleRecording(), "second toggle request is rejected")
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (toggleCount !== 1 || !recordingService.operationPending) return
        var removedConsumer = root.secondConsumer
        root.secondConsumer = null
        removedConsumer.destroy()
        root.phase = 51
        return
      }

      if (root.phase === 51) {
        if (recordingService.consumerCount !== 0) return
        check(recordingService.consumerCount === 0 && recordingService.collecting,
          "destroying the last consumer keeps the toggle operation alive")
        toggleReleaseFile.setText("release\n")
        root.phase = 6
        return
      }

      if (root.phase === 6) {
        if (recordingService.collecting || recordingService.operationPending || reconcileCount < 2) return
        check(toggleCount === 1 && root.toggleOverlapText === "",
          "toggle launches one fake action")
        check(root.reconcileOverlapText === "", "reconciliation calls do not overlap")
        root.prepareCountAtStop = prepareCount
        root.reconcileCountAtStop = reconcileCount
        stateFile.setText('{"version":1,"active":true,"output":"/tmp/new-recording.mp4"}\n')
        root.checks = 0
        first.active = true
        check(!recordingService.runtimeReady && !recordingService.loaded && !recordingService.recording,
          "reactivation starts from unavailable state")
        root.phase = 7
        return
      }

      if (root.phase === 7) {
        if (!recordingService.runtimeReady || !recordingService.loaded
            || !recordingService.recording || reconcileCount < root.reconcileCountAtStop + 1) return
        check(prepareCount === root.prepareCountAtStop + 1,
          "reactivation prepares the runtime again")
        check(recordingService.outputPath === "/tmp/new-recording.mp4",
          "reactivation publishes only the new cycle state")
        check(!recordingService.applyState(root.staleStateText, root.activeCollectionGeneration,
          root.staleStateReader), "late state callback from the old collection is ignored")
        check(recordingService.outputPath === "/tmp/new-recording.mp4",
          "late state callback cannot overwrite reactivated state")
        first.active = false
        root.checks = 0
        root.phase = 8
        return
      }

      if (root.phase === 8) {
        if (recordingService.collecting) return
        if (root.checks < 10) return
        countFile.reload()
        reconcileLog.reload()
        prepareCount = Number(String(root.countText || "0").trim()) || 0
        reconcileCount = lines(root.reconcileLogText).length
        check(prepareCount === root.prepareCountAtStop + 1,
          "stopped collection does not retry preparation")
        check(reconcileCount === root.reconcileCountAtStop + 1,
          "stopped collection does not retry reconciliation")
        check(root.prepareOverlapText === "", "prepare overlap marker remains absent")
        finish()
      }
    } catch (error) {
      fail(error && error.message ? error.message : error)
    }
  }
}
