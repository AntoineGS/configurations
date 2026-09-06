import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/disk" as Disk

Item {
  id: root

  property string phase: "no-demand"
  property int expectedQueries: 0
  property string lifecycleLogText: ""
  property bool missingChecked: false
  property bool nonzeroChecked: false
  property bool queuedChecked: false
  property bool restartChecked: false
  readonly property string fakeExecutable: Quickshell.env("DISK_FIXTURE_LIFECYCLE_EXECUTABLE")
    || Qt.resolvedUrl("tests/fixtures/disk/fake-status-lifecycle").toString().replace("file://", "")
  readonly property string missingExecutable: Quickshell.env("DISK_FIXTURE_MISSING_EXECUTABLE")
  readonly property string lifecycleLogPath: Quickshell.env("DISK_FIXTURE_LIFECYCLE_LOG")
  readonly property string lifecycleModePath: Quickshell.env("DISK_FIXTURE_LIFECYCLE_MODE")
  readonly property string lifecycleHeldPath: Quickshell.env("DISK_FIXTURE_LIFECYCLE_HELD")
  readonly property string lifecycleReleasePath: Quickshell.env("DISK_FIXTURE_LIFECYCLE_RELEASE")
  readonly property string lifecycleOldOutputPath: Quickshell.env("DISK_FIXTURE_LIFECYCLE_OLD_OUTPUT")
  property var afterModeSaved: null
  property string lifecycleHeldText: ""
  property string lifecycleOldOutputText: ""

  QtObject {
    id: fakeShell
    property bool previewMode: false
    function widgetSettingsFor(pluginId) { return ({}) }
  }

  Disk.Service {
    id: service
    shell: fakeShell
    manifest: ({ id: "desktop.disk" })
    statusExecutable: root.fakeExecutable
    processStartGraceInterval: 40
  }

  ServiceConsumer {
    id: consumer
    service: service
    active: false
  }

  FileView {
    id: lifecycleLog
    path: root.lifecycleLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.lifecycleLogText = text()
    onFileChanged: reload()
  }

  FileView {
    id: heldMarker
    path: root.lifecycleHeldPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.lifecycleHeldText = text()
    onFileChanged: reload()
  }

  FileView {
    id: oldOutputMarker
    path: root.lifecycleOldOutputPath
    preload: root.lifecycleOldOutputPath !== ""
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.lifecycleOldOutputText = text()
    onFileChanged: reload()
  }

  FileView {
    id: modeWriter
    path: root.lifecycleModePath
    atomicWrites: false
    blockWrites: false
    printErrors: false
    onSaved: {
      var callback = root.afterModeSaved
      root.afterModeSaved = null
      if (callback) callback()
    }
  }

  Timer {
    interval: 10
    repeat: true
    running: true
    onTriggered: root.advance()
  }

  Timer {
    interval: 8000
    repeat: false
    running: true
    onTriggered: root.fail("watchdog phase=" + root.phase + " queries=" + root.queryCount()
      + " worker=" + !!service.refreshWorker + " output=" + service.outputText)
  }

  function queryCount() {
    return String(root.lifecycleLogText || "").split("\n").filter(function(line) { return line !== "" }).length
  }

  function setMode(value, callback) {
    root.afterModeSaved = callback || null
    modeWriter.setText(value + "\n")
  }

  function waitForFinish(nextPhase) {
    if (service.refreshWorker || service.refreshGeneration <= service.refreshFinalizedGeneration) return
    root.phase = nextPhase
  }

  function advance() {
    lifecycleLog.reload()
    heldMarker.reload()
    if (root.lifecycleOldOutputPath !== "") oldOutputMarker.reload()
    if (root.phase === "no-demand") {
      if (root.queryCount() !== 0) root.fail("collector ran without demand")
      service.statusExecutable = root.missingExecutable
      consumer.active = true
      root.phase = "missing-start"
      return
    }
    if (root.phase === "missing-start") {
      if (service.refreshWorker || service.refreshGeneration === 0
          || service.refreshFinalizedGeneration !== service.refreshGeneration) return
      if (service.outputText !== "") root.fail("missing start changed output")
      root.missingChecked = true
      service.statusExecutable = root.fakeExecutable
      root.setMode("success", function() {
        service.refresh()
        root.phase = "success-after-missing"
      })
      return
    }
    if (root.phase === "success-after-missing") {
      if (service.outputText !== "N new") return
      service.statusExecutable = root.fakeExecutable
      root.setMode("nonzero", function() {
        service.refresh()
        root.phase = "nonzero"
      })
      return
    }
    if (root.phase === "nonzero") {
      if (service.refreshWorker || service.refreshGeneration === 0
          || service.refreshFinalizedGeneration !== service.refreshGeneration) return
      if (service.outputText !== "N new") root.fail("nonzero exit replaced last-good output")
      root.nonzeroChecked = true
      root.setMode("hold", function() {
        service.refresh()
        root.phase = "queued-stop"
      })
      return
    }
    if (root.phase === "queued-stop") {
      if (!service.refreshWorker || root.lifecycleHeldText.trim() !== "held"
          || root.lifecycleOldOutputText.trim() !== "old") return
      service.refresh()
      if (!service.refreshQueued) root.fail("refresh was not queued")
      consumer.active = false
      if (service.collecting || service.refreshQueued) root.fail("stop retained queued refresh")
      root.queuedChecked = true
      root.setMode("success", function() {
        consumer.active = true
        root.phase = "restart"
      })
      return
    }
    if (root.phase === "restart") {
      if (service.outputText !== "N new" || service.refreshGeneration < 5
          || service.refreshFinalizedGeneration !== service.refreshGeneration) return
      root.restartChecked = true
      root.phase = "release-old"
      root.releaseOldWorker()
      return
    }
    if (root.phase === "release-old") {
      if (!root.missingChecked || !root.nonzeroChecked || !root.queuedChecked || !root.restartChecked
          || root.lifecycleOldOutputText.trim() !== "old") return
      if (service.outputText !== "N new") root.fail("obsolete held output replaced restarted output")
      console.log("Disk lifecycle fixture passed", root.queryCount(), service.refreshGeneration)
      Qt.exit(0)
    }
  }

  function releaseOldWorker() {
    var writer = Qt.createQmlObject(
      "import Quickshell.Io; FileView { atomicWrites: false; blockWrites: false; printErrors: false }",
      root)
    writer.path = root.lifecycleReleasePath
    writer.onSaved.connect(function() { writer.destroy() })
    writer.setText("release\n")
  }

  function fail(message) {
    console.error("disk-service-runtime-test: " + String(message))
    Qt.exit(1)
  }
}
