import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/monitor" as Monitor

Item {
  id: root

  readonly property string stateModePath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_MODE") || ""
  readonly property string stateHoldPath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_HOLD") || ""
  readonly property string stateReleasePath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_RELEASE") || ""
  readonly property string stateNewReleasePath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_NEW_RELEASE") || ""
  readonly property string stateOldCallbackReleasePath:
    Quickshell.env("MONITOR_BRIGHTNESS_STATE_OLD_CALLBACK_RELEASE") || ""
  readonly property string stateOldCallbackPath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_OLD_CALLBACK") || ""
  readonly property string stateEnteredPath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_ENTERED") || ""
  readonly property string stateHelperEnteredPath:
    Quickshell.env("MONITOR_BRIGHTNESS_STATE_HELPER_ENTERED") || ""
  readonly property string actionModePath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_MODE") || ""
  readonly property string actionHoldPath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_HOLD") || ""
  readonly property string actionReleasePath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_RELEASE") || ""
  readonly property string actionNewReleasePath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_NEW_RELEASE") || ""
  readonly property string actionOldCallbackReleasePath:
    Quickshell.env("MONITOR_BRIGHTNESS_ACTION_OLD_CALLBACK_RELEASE") || ""
  readonly property string actionOldCallbackPath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_OLD_CALLBACK") || ""
  readonly property string actionEnteredPath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_ENTERED") || ""
  readonly property string actionHelperEnteredPath:
    Quickshell.env("MONITOR_BRIGHTNESS_ACTION_HELPER_ENTERED") || ""
  readonly property string fakeState: Qt.resolvedUrl("tests/fixtures/monitor-brightness/fake-state")
    .toString().replace("file://", "")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/monitor-brightness/fake-action")
    .toString().replace("file://", "")
  readonly property string fakeHostname: Qt.resolvedUrl("tests/fixtures/monitor/fake-hostname")
    .toString().replace("file://", "")
  property int phase: 0
  property int checks: 0
  property string stateOldCallbackText: ""
  property string actionOldCallbackText: ""
  property string stateEnteredText: ""
  property string actionEnteredText: ""
  property string stateHelperEnteredText: ""
  property string actionHelperEnteredText: ""
  property var oldStateWorker: null
  property var oldActionWorker: null
  property bool oldStateStreamFinished: false
  property bool oldStateExited: false
  property bool oldActionStreamFinished: false
  property bool oldActionExited: false
  property int oldStateGeneration: 0
  property int oldActionGeneration: 0

  QtObject {
    id: fakeShell
    property bool previewMode: false
    function widgetSettingsFor(pluginId) { return ({}) }
    function serviceFor(pluginId) { return pluginId === "desktop.monitor" ? service : null }
  }

  Monitor.Service {
    id: service
    shell: fakeShell
    manifest: ({ id: "desktop.monitor" })
    stateExecutable: root.fakeState
    actionExecutable: root.fakeAction
    hostnameExecutable: root.fakeHostname
    processStartGraceInterval: 50
    processTimeoutInterval: 5000
    stateProcessTimeoutInterval: 5000
  }

  ServiceConsumer { service: service; active: true }
  ServiceConsumer { service: service; active: true }

  FileView {
    id: stateModeFile
    path: root.stateModePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: stateNewReleaseFile
    path: root.stateNewReleasePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: stateHoldFile
    path: root.stateHoldPath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: actionNewReleaseFile
    path: root.actionNewReleasePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: stateReleaseFile
    path: root.stateReleasePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: stateOldCallbackReleaseFile
    path: root.stateOldCallbackReleasePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: stateOldCallbackFile
    path: root.stateOldCallbackPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.stateOldCallbackText = text()
    onFileChanged: reload()
  }
  FileView {
    id: stateHelperEnteredFile
    path: root.stateHelperEnteredPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.stateHelperEnteredText = text()
    onFileChanged: reload()
  }
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
    id: actionModeFile
    path: root.actionModePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: actionHoldFile
    path: root.actionHoldPath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: actionReleaseFile
    path: root.actionReleasePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: actionOldCallbackReleaseFile
    path: root.actionOldCallbackReleasePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: actionOldCallbackFile
    path: root.actionOldCallbackPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.actionOldCallbackText = text()
    onFileChanged: reload()
  }
  FileView {
    id: actionHelperEnteredFile
    path: root.actionHelperEnteredPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.actionHelperEnteredText = text()
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

  Connections {
    target: root.oldStateWorker
    function onExited() { root.oldStateExited = true }
  }

  Connections {
    target: root.oldStateWorker && root.oldStateWorker.stdoutOutput
    function onStreamFinished() { root.oldStateStreamFinished = true }
  }

  Connections {
    target: root.oldActionWorker
    function onExited() { root.oldActionExited = true }
  }

  Connections {
    target: root.oldActionWorker ? root.oldActionWorker.stdout : null
    function onStreamFinished() { root.oldActionStreamFinished = true }
  }

  function fail(message) {
    console.error("Monitor brightness generation fixture failed: " + String(message), root.phase,
      service.operationPending, service.stateWorker, service.actionWorker, service.activeActionTarget,
      JSON.stringify(service.brightnessFor("DP-1")), JSON.stringify(service.brightnessFor("HDMI-1")))
    Qt.exit(1)
  }

  function setStateMode(mode) { stateModeFile.setText(mode + "\n") }
  function setActionMode(mode) { actionModeFile.setText(mode + "\n") }
  function controlText(file) { return String(file.text() || "").trim() }
  function lastLine(value) {
    var values = String(value || "").split("\n").filter(function(line) { return line !== "" })
    return values.length > 0 ? values[values.length - 1].trim() : ""
  }

  function guardedStateOutput() {
    return JSON.stringify({ available: false, stale: true, error: "guard-test", data: {} })
  }

  function exerciseStateGenerationGuard() {
    var worker = service.stateWorker
    var generation = worker.generation
    worker.generation = generation - 1
    service.applyStateFromWorker(worker, root.guardedStateOutput())
    worker.generation = generation
    if (service.hardwareState.available !== true || service.hardwareState.stale === true)
      return root.fail("state generation guard did not reject the current worker's old generation")
  }

  function exerciseStateIdentityGuard() {
    var worker = root.oldStateWorker
    worker.generation = service.reconciliationGeneration
    worker.collectionGeneration = service.collectionGeneration
    service.applyStateFromWorker(worker, root.guardedStateOutput())
    if (service.hardwareState.available !== true || service.hardwareState.stale === true)
      return root.fail("state identity guard did not reject the old worker identity")
  }

  function exerciseActionGenerationGuard() {
    var worker = service.actionWorker
    var generation = worker.generation
    worker.generation = generation - 1
    service.handleActionOutputFinished(worker, "not-json")
    worker.generation = generation
    if (worker.stdoutFinished === true || worker.actionOutput !== "")
      return root.fail("action generation guard accepted the current worker's old generation")
  }

  function exerciseActionIdentityGuard() {
    var worker = root.oldActionWorker
    worker.generation = service.actionGeneration
    worker.collectionGeneration = service.collectionGeneration
    service.handleActionOutputFinished(worker, "not-json")
    service.handleActionExited(worker, 99)
    if (worker.stdoutFinished === true || worker.actionExited === true)
      return root.fail("action identity guard accepted the old worker identity")
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      try {
        if (root.phase === 0) {
          if (service.brightnessFor("DP-1").percent !== 40 || service.brightnessFor("HDMI-1").percent !== 60)
            return
          if (root.lastLine(root.stateHelperEnteredText) !== "initial") return
          setStateMode("hold-old-callback")
          stateHoldFile.setText("hold\n")
          stateReleaseFile.setText("wait\n")
          stateOldCallbackReleaseFile.setText("wait\n")
          service.refresh()
          root.phase = 1
          return
        }

        if (root.phase === 1) {
          if (!service.stateWorker || !service.stateWorker.running
              || root.lastLine(root.stateHelperEnteredText) !== "hold-old-callback"
              || String(root.stateEnteredText).trim() !== "held:hold-old-callback") return
          root.oldStateGeneration = service.stateWorker.generation
          root.oldStateWorker = service.stateWorker
          service.stateWorker = null
          setStateMode("hold-new")
          stateHoldFile.setText("hold\n")
          stateReleaseFile.setText("wait\n")
          stateNewReleaseFile.setText("wait\n")
          root.phase = 2
          return
        }

        if (root.phase === 2) {
          if (root.controlText(stateModeFile) !== "hold-new") return
          service.startStateProcess("")
          root.phase = 3
          return
        }

        if (root.phase === 3) {
          if (!service.stateWorker || !service.stateWorker.running
              || service.stateWorker.generation <= root.oldStateGeneration
              || root.lastLine(root.stateHelperEnteredText) !== "hold-new"
              || String(root.stateEnteredText).trim() !== "held:hold-new") return
          root.exerciseStateGenerationGuard()
          root.exerciseStateIdentityGuard()
          stateOldCallbackReleaseFile.setText("release\n")
          root.phase = 4
          return
        }

        if (root.phase === 4) {
          if (String(root.stateOldCallbackText).trim() !== "callback:hold-old-callback"
              || !root.oldStateStreamFinished || !root.oldStateExited) return
          if (service.brightnessFor("DP-1").percent !== 40 || service.brightnessFor("HDMI-1").percent !== 60)
            return root.fail("old state callback changed the newer state generation")
          stateNewReleaseFile.setText("release\n")
          root.phase = 5
          return
        }

        if (root.phase === 5) {
          if (service.brightnessFor("DP-1").percent !== 45 || service.brightnessFor("HDMI-1").percent !== 65)
            return
          setActionMode("hold-old-callback")
          actionHoldFile.setText("hold\n")
          actionReleaseFile.setText("wait\n")
          actionOldCallbackReleaseFile.setText("wait\n")
          root.phase = 6
          return
        }

        if (root.phase === 6) {
          if (!service.actionWorker) {
            if (root.controlText(actionModeFile) !== "hold-old-callback") return
            if (service.setBrightness("DP-1", 55) !== true)
              return root.fail("old action callback setup request was rejected")
            return
          }
          if (!service.actionWorker.running) return
          if (root.lastLine(root.actionHelperEnteredText) !== "hold-old-callback"
              || String(root.actionEnteredText).trim() !== "DP-1:55") return
          root.oldActionGeneration = service.actionWorker.generation
          root.oldActionWorker = service.actionWorker
          service.actionWorker = null
          setActionMode("hold-new")
          actionHoldFile.setText("hold\n")
          actionReleaseFile.setText("wait\n")
          actionNewReleaseFile.setText("wait\n")
          root.phase = 7
          return
        }

        if (root.phase === 7) {
          if (root.controlText(actionModeFile) !== "hold-new") return
          service.startAction(["monitor", "set-display-brightness", "66",
            JSON.stringify(service.brightnessFor("DP-1"))])
          root.phase = 8
          return
        }

        if (root.phase === 8) {
          if (!service.actionWorker || !service.actionWorker.running
              || service.actionWorker.generation <= root.oldActionGeneration
              || root.lastLine(root.actionHelperEnteredText) !== "hold-new"
              || String(root.actionEnteredText).trim() !== "DP-1:66") return
          root.exerciseActionGenerationGuard()
          root.exerciseActionIdentityGuard()
          actionOldCallbackReleaseFile.setText("release\n")
          root.phase = 9
          return
        }

        if (root.phase === 9) {
          if (String(root.actionOldCallbackText).trim() !== "callback:hold-old-callback"
              || !root.oldActionStreamFinished || !root.oldActionExited) return
          if (!service.actionWorker || !service.actionWorker.running
              || !service.activeActionTarget || service.activeActionTarget.percent !== 45)
            return root.fail("old action callback changed the newer action generation")
          actionNewReleaseFile.setText("release\n")
          root.phase = 10
          return
        }

        if (root.phase === 10) {
          if (service.actionWorker) return
          service.stopCollection()
          console.log("Monitor brightness generation fixture passed")
          Qt.exit(0)
        }
      } catch (error) {
        root.fail(error && error.message ? error.message : error)
      }
      if (root.checks >= 1500) root.fail("generation barrier timed out")
    }
  }
}
