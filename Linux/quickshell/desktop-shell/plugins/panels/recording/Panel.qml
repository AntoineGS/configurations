import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "desktop.recording"
  ipcTarget: "desktop.recording"
  manageIpc: false

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")
  readonly property string statePath: runtimeDir ? runtimeDir + "/desktop-shell/recording.json" : ""
  property var recordingState: null
  property bool loaded: false
  property bool runtimeReady: false
  property string prepareExecutable: "cmd-screenrecord"
  property int prepareGeneration: 0
  property int prepareFinalizedGeneration: 0
  property bool prepareInFlight: false
  property string prepareError: ""
  property int initialPrepareInterval: 15000
  property int recoveryPrepareInterval: 60000

  readonly property bool recording: recordingState !== null
  readonly property string outputPath: recording ? String(recordingState.output || "") : ""

  function applyState(content) {
    loaded = true
    try {
      var parsed = JSON.parse(String(content || ""))
      if (!parsed || parsed.version !== 1 || parsed.active !== true || typeof parsed.output !== "string"
          || parsed.output.charAt(0) !== "/") {
        recordingState = null
        return
      }
      recordingState = parsed
    } catch (error) {
      recordingState = null
    }
  }

  function refresh() {
    if (!runtimeReady || reconciliationProcess.running) return
    reconciliationProcess.running = true
  }

  function startPrepare() {
    if (prepareProcess.running || prepareInFlight) return
    prepareGeneration++
    prepareInFlight = true
    prepareError = ""
    prepareStartCheckTimer.generation = prepareGeneration
    prepareProcess.running = true
    prepareStartCheckTimer.start()
  }

  function finishPrepare(exitCode, failedStart) {
    if (!prepareInFlight || prepareFinalizedGeneration === prepareGeneration) return
    prepareFinalizedGeneration = prepareGeneration
    prepareInFlight = false
    prepareStartCheckTimer.stop()
    if (!failedStart && Number(exitCode) === 0) {
      runtimeReady = true
      prepareError = ""
      stateFile.reload()
      Qt.callLater(root.refresh)
    } else {
      runtimeReady = false
      prepareError = failedStart ? "Recording state preparation failed to start" :
        "Recording state preparation failed"
    }
  }

  visible: loaded && recording
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  FileView {
    id: stateFile
    path: root.runtimeReady ? root.statePath : ""
    watchChanges: true
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("")
    onFileChanged: reload()
  }

  Process {
    id: prepareProcess
    command: [root.prepareExecutable, "--prepare-state"]
    onStarted: prepareStartCheckTimer.stop()
    onExited: function(exitCode) {
      root.finishPrepare(exitCode, false)
    }
    onRunningChanged: {
      if (!prepareProcess.running && root.prepareInFlight
          && root.prepareFinalizedGeneration !== root.prepareGeneration) {
        prepareStartCheckTimer.generation = root.prepareGeneration
        prepareStartCheckTimer.start()
      }
    }
  }

  Timer {
    id: prepareStartCheckTimer
    property int generation: 0
    interval: 100
    repeat: false
    onTriggered: {
      if (!prepareProcess.running && generation === root.prepareGeneration)
        root.finishPrepare(1, true)
    }
  }

  Timer {
    id: startupTimer
    interval: root.initialPrepareInterval
    running: true
    repeat: false
    onTriggered: {
      if (!root.runtimeReady) root.startPrepare()
      else root.refresh()
      recoveryTimer.start()
    }
  }

  Timer {
    id: recoveryTimer
    interval: root.recoveryPrepareInterval
    repeat: true
    onTriggered: {
      if (!root.runtimeReady) root.startPrepare()
      else root.refresh()
    }
  }

  Component.onCompleted: startPrepare()

  Process {
    id: reconciliationProcess
    command: ["cmd-screenrecord", "--reconcile-state"]
    onExited: {
      stateFile.reload()
      reconciliationProcess.running = false
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰑋"
    active: root.recording
    tooltipText: root.outputPath
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) Util.execDetached("cmd-screenrecord")
    }
  }
}
