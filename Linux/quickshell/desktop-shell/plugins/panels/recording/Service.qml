import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

SharedService {
  id: root

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")
  readonly property string statePath: runtimeDir ? runtimeDir + "/desktop-shell/recording.json" : ""
  property var recordingState: null
  property bool loaded: false
  property bool runtimeReady: false
  property string prepareExecutable: "cmd-screenrecord"
  property string reconcileExecutable: "cmd-screenrecord"
  property string toggleExecutable: "cmd-screenrecord"
  property int prepareGeneration: 0
  property int prepareFinalizedGeneration: 0
  property bool prepareInFlight: false
  property string prepareError: ""
  property int initialPrepareInterval: 15000
  property int recoveryPrepareInterval: 60000
  property int processStartGraceInterval: 100
  property int collectionGeneration: 0
  property int reconciliationGeneration: 0
  property int reconciliationFinalizedGeneration: 0
  property int toggleGeneration: 0
  property int toggleFinalizedGeneration: 0
  property bool toggleReconciliationPending: false
  property bool collectorLoaded: true
  property var prepareWorker: null
  property var reconciliationWorker: null
  property var toggleWorker: null
  property var stateFile: null

  readonly property bool recording: recordingState !== null
  readonly property string outputPath: recording ? String(recordingState.output || "") : ""

  function applyState(content, generation, reader) {
    if (!root.collecting || !root.runtimeReady) return false
    if (generation !== undefined && generation !== root.collectionGeneration) return false
    if (reader !== undefined && reader !== root.stateFile) return false
    loaded = true
    try {
      var parsed = JSON.parse(String(content || ""))
      if (!parsed || parsed.version !== 1 || parsed.active !== true || typeof parsed.output !== "string"
          || parsed.output.charAt(0) !== "/") {
        recordingState = null
        return false
      }
      recordingState = parsed
      return true
    } catch (error) {
      recordingState = null
      return false
    }
  }

  function refresh() {
    if (!root.collectorLoaded || !root.collecting || !root.runtimeReady
        || root.reconciliationWorker || root.toggleWorker) return false
    root.reconciliationGeneration++
    var worker = reconciliationComponent.createObject(root, {
      generation: root.reconciliationGeneration,
      collectionGeneration: root.collectionGeneration
    })
    if (!worker) {
      root.finishReconciliation(null, 1, true)
      return false
    }
    root.reconciliationWorker = worker
    reconciliationStartCheckTimer.worker = worker
    reconciliationStartCheckTimer.generation = worker.generation
    reconciliationStartCheckTimer.collectionGeneration = worker.collectionGeneration
    worker.running = true
    reconciliationStartCheckTimer.start()
    return true
  }

  function startStateWatch() {
    if (!root.collecting || !root.runtimeReady) return false
    var file = stateFileComponent.createObject(root, {
      collectionGeneration: root.collectionGeneration
    })
    if (!file) return false
    root.stateFile = file
    return true
  }

  function startPrepare() {
    if (!root.collectorLoaded || !root.collecting || root.runtimeReady
        || root.prepareWorker || root.prepareInFlight) return false
    root.prepareGeneration++
    root.prepareInFlight = true
    root.prepareError = ""
    var worker = prepareComponent.createObject(root, {
      generation: root.prepareGeneration,
      collectionGeneration: root.collectionGeneration
    })
    if (!worker) {
      root.finishPrepare(1, true, null)
      return false
    }
    root.prepareWorker = worker
    prepareStartCheckTimer.worker = worker
    prepareStartCheckTimer.generation = worker.generation
    prepareStartCheckTimer.collectionGeneration = worker.collectionGeneration
    worker.running = true
    prepareStartCheckTimer.start()
    return true
  }

  function handlePrepareStarted(worker) {
    if (worker === root.prepareWorker && worker.generation === root.prepareGeneration
        && worker.collectionGeneration === root.collectionGeneration)
      prepareStartCheckTimer.stop()
  }

  function handlePrepareRunningChanged(worker) {
    if (worker.running || worker !== root.prepareWorker || !root.collecting
        || worker.generation !== root.prepareGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    prepareStartCheckTimer.worker = worker
    prepareStartCheckTimer.generation = worker.generation
    prepareStartCheckTimer.collectionGeneration = worker.collectionGeneration
    prepareStartCheckTimer.start()
  }

  function finishPrepare(exitCode, failedStart, worker) {
    var activeWorker = worker === undefined ? root.prepareWorker : worker
    if (activeWorker !== null && activeWorker !== root.prepareWorker) {
      root.destroyWorker(activeWorker)
      return
    }
    if (activeWorker && (activeWorker.generation !== root.prepareGeneration
        || activeWorker.collectionGeneration !== root.collectionGeneration)) {
      root.destroyWorker(activeWorker)
      return
    }
    if (!root.prepareInFlight || root.prepareFinalizedGeneration === root.prepareGeneration) {
      if (activeWorker && activeWorker === root.prepareWorker) {
        root.prepareWorker = null
        root.destroyWorker(activeWorker)
      }
      return
    }

    root.prepareFinalizedGeneration = root.prepareGeneration
    prepareStartCheckTimer.stop()
    prepareStartCheckTimer.worker = null
    if (activeWorker === root.prepareWorker) root.prepareWorker = null
    root.destroyWorker(activeWorker)
    root.prepareInFlight = false

    if (!failedStart && Number(exitCode) === 0) {
      root.runtimeReady = true
      root.prepareError = ""
      root.startStateWatch()
      Qt.callLater(root.refresh)
    } else {
      root.runtimeReady = false
      root.prepareError = failedStart ? "Recording state preparation failed to start" :
        "Recording state preparation failed"
    }
  }

  function handleReconciliationStarted(worker) {
    if (worker === root.reconciliationWorker && worker.generation === root.reconciliationGeneration
        && worker.collectionGeneration === root.collectionGeneration)
      reconciliationStartCheckTimer.stop()
  }

  function handleReconciliationRunningChanged(worker) {
    if (worker.running || worker !== root.reconciliationWorker || !root.collecting
        || worker.generation !== root.reconciliationGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    reconciliationStartCheckTimer.worker = worker
    reconciliationStartCheckTimer.generation = worker.generation
    reconciliationStartCheckTimer.collectionGeneration = worker.collectionGeneration
    reconciliationStartCheckTimer.start()
  }

  function finishReconciliation(worker, exitCode, failedStart) {
    var activeWorker = worker === undefined ? root.reconciliationWorker : worker
    if (activeWorker !== null && activeWorker !== root.reconciliationWorker) {
      root.destroyWorker(activeWorker)
      return
    }
    if (activeWorker && (activeWorker.generation !== root.reconciliationGeneration
        || activeWorker.collectionGeneration !== root.collectionGeneration)) {
      root.destroyWorker(activeWorker)
      return
    }
    if (root.reconciliationFinalizedGeneration === root.reconciliationGeneration) {
      if (activeWorker && activeWorker === root.reconciliationWorker) {
        root.reconciliationWorker = null
        root.destroyWorker(activeWorker)
      }
      return
    }

    root.reconciliationFinalizedGeneration = root.reconciliationGeneration
    reconciliationStartCheckTimer.stop()
    reconciliationStartCheckTimer.worker = null
    if (activeWorker === root.reconciliationWorker) root.reconciliationWorker = null
    if (!failedStart && Number(exitCode) === 0 && root.collecting && root.runtimeReady && root.stateFile)
      root.stateFile.reload()
    root.destroyWorker(activeWorker)

    if (root.toggleReconciliationPending) {
      root.toggleReconciliationPending = false
      root.operationPending = false
    }
  }

  function toggleRecording() {
    if (!root.collectorLoaded || !root.collecting || !root.runtimeReady || root.toggleWorker
        || root.toggleReconciliationPending || root.reconciliationWorker || root.operationPending) return false
    root.operationPending = true
    root.toggleGeneration++
    var worker = toggleComponent.createObject(root, {
      generation: root.toggleGeneration,
      collectionGeneration: root.collectionGeneration
    })
    if (!worker) {
      root.finishToggle(null, 1, true)
      return true
    }
    root.toggleWorker = worker
    toggleStartCheckTimer.worker = worker
    toggleStartCheckTimer.generation = worker.generation
    toggleStartCheckTimer.collectionGeneration = worker.collectionGeneration
    worker.running = true
    toggleStartCheckTimer.start()
    return true
  }

  function handleToggleStarted(worker) {
    if (worker === root.toggleWorker && worker.generation === root.toggleGeneration
        && worker.collectionGeneration === root.collectionGeneration)
      toggleStartCheckTimer.stop()
  }

  function handleToggleRunningChanged(worker) {
    if (worker.running || worker !== root.toggleWorker || !root.collecting
        || worker.generation !== root.toggleGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    toggleStartCheckTimer.worker = worker
    toggleStartCheckTimer.generation = worker.generation
    toggleStartCheckTimer.collectionGeneration = worker.collectionGeneration
    toggleStartCheckTimer.start()
  }

  function finishToggle(worker, exitCode, failedStart) {
    var activeWorker = worker === undefined ? root.toggleWorker : worker
    if (activeWorker !== null && activeWorker !== root.toggleWorker) {
      root.destroyWorker(activeWorker)
      return
    }
    if (activeWorker && (activeWorker.generation !== root.toggleGeneration
        || activeWorker.collectionGeneration !== root.collectionGeneration)) {
      root.destroyWorker(activeWorker)
      return
    }
    if (root.toggleFinalizedGeneration === root.toggleGeneration) {
      if (activeWorker && activeWorker === root.toggleWorker) {
        root.toggleWorker = null
        root.destroyWorker(activeWorker)
      }
      return
    }

    root.toggleFinalizedGeneration = root.toggleGeneration
    toggleStartCheckTimer.stop()
    toggleStartCheckTimer.worker = null
    if (activeWorker === root.toggleWorker) root.toggleWorker = null
    root.destroyWorker(activeWorker)

    root.toggleReconciliationPending = true
    if (!root.refresh()) {
      root.toggleReconciliationPending = false
      root.operationPending = false
    }
  }

  function destroyWorker(worker) {
    if (!worker) return
    worker.running = false
    var staleWorker = worker
    Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
  }

  function stopCollection() {
    root.collectionGeneration++
    startupTimer.stop()
    recoveryTimer.stop()
    prepareStartCheckTimer.stop()
    reconciliationStartCheckTimer.stop()
    toggleStartCheckTimer.stop()
    prepareStartCheckTimer.worker = null
    reconciliationStartCheckTimer.worker = null
    toggleStartCheckTimer.worker = null

    var oldPrepareWorker = root.prepareWorker
    root.prepareWorker = null
    root.destroyWorker(oldPrepareWorker)
    var oldReconciliationWorker = root.reconciliationWorker
    root.reconciliationWorker = null
    root.destroyWorker(oldReconciliationWorker)
    var oldToggleWorker = root.toggleWorker
    root.toggleWorker = null
    root.destroyWorker(oldToggleWorker)

    root.prepareInFlight = false
    root.toggleReconciliationPending = false
    root.operationPending = false
    root.runtimeReady = false
    root.loaded = false
    root.recordingState = null
    var oldStateFile = root.stateFile
    root.stateFile = null
    if (oldStateFile) oldStateFile.destroy()
  }

  onCollectingChanged: {
    if (!root.collecting) {
      root.stopCollection()
      return
    }
    root.startPrepare()
    startupTimer.start()
  }

  Timer {
    id: startupTimer
    interval: root.initialPrepareInterval
    repeat: false
    onTriggered: {
      if (!root.collecting) return
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
      if (!root.collecting) return
      if (!root.runtimeReady) root.startPrepare()
      else root.refresh()
    }
  }

  Component {
    id: stateFileComponent

    FileView {
      id: file
      property int collectionGeneration: 0
      path: root.statePath
      preload: true
      watchChanges: true
      atomicWrites: true
      blockWrites: true
      printErrors: false
      onLoaded: root.applyState(file.text(), file.collectionGeneration, file)
      onLoadFailed: root.applyState("", file.collectionGeneration, file)
      onFileChanged: if (root.collecting && root.runtimeReady
        && file === root.stateFile && file.collectionGeneration === root.collectionGeneration) reload()
    }
  }

  Timer {
    id: prepareStartCheckTimer
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.prepareWorker
          && worker.generation === generation && worker.collectionGeneration === collectionGeneration
          && !worker.running)
        root.finishPrepare(1, true, worker)
    }
  }

  Timer {
    id: reconciliationStartCheckTimer
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.reconciliationWorker
          && worker.generation === generation && worker.collectionGeneration === collectionGeneration
          && !worker.running)
        root.finishReconciliation(worker, 1, true)
    }
  }

  Timer {
    id: toggleStartCheckTimer
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.toggleWorker
          && worker.generation === generation && worker.collectionGeneration === collectionGeneration
          && !worker.running)
        root.finishToggle(worker, 1, true)
    }
  }

  Component {
    id: prepareComponent
    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      command: [root.prepareExecutable, "--prepare-state"]
      onStarted: root.handlePrepareStarted(process)
      onExited: function(exitCode) { root.finishPrepare(Number(exitCode), false, process) }
      onRunningChanged: root.handlePrepareRunningChanged(process)
    }
  }

  Component {
    id: reconciliationComponent
    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      command: [root.reconcileExecutable, "--reconcile-state"]
      onStarted: root.handleReconciliationStarted(process)
      onExited: function(exitCode) { root.finishReconciliation(process, Number(exitCode), false) }
      onRunningChanged: root.handleReconciliationRunningChanged(process)
    }
  }

  Component {
    id: toggleComponent
    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      command: [root.toggleExecutable]
      onStarted: root.handleToggleStarted(process)
      onExited: function(exitCode) { root.finishToggle(process, Number(exitCode), false) }
      onRunningChanged: root.handleToggleRunningChanged(process)
    }
  }

  Component.onDestruction: {
    root.collectorLoaded = false
    root.stopCollection()
  }
}
