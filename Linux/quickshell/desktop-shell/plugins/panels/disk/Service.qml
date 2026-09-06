import QtQuick
import Quickshell.Io
import qs.Commons
import "../../bar/BarModel.js" as BarModel

SharedService {
  id: root

  property string statusExecutable: "desktop-shell-status"
  property bool collectorLoaded: true
  property bool refreshQueued: false
  property int refreshGeneration: 0
  property int refreshFinalizedGeneration: 0
  property int collectionGeneration: 0
  property int processStartGraceInterval: 100
  property var refreshWorker: null

  property string outputText: ""
  property string outputIcon: ""
  property string outputValue: ""
  property string outputTooltip: ""
  property bool outputActive: false
  property bool outputMuted: false

  readonly property var remoteSummary: ({
    available: root.outputText !== "",
    text: root.outputText,
    icon: root.outputIcon,
    value: root.outputValue,
    tooltip: root.outputTooltip,
    active: root.outputActive,
    muted: root.outputMuted
  })

  function refresh() {
    if (!root.collectorLoaded || !root.collecting) return false
    if (root.refreshWorker) {
      root.refreshQueued = true
      return true
    }

    root.refreshGeneration++
    var worker = refreshComponent.createObject(root, {
      generation: root.refreshGeneration,
      collectionGeneration: root.collectionGeneration
    })
    if (!worker) {
      root.finishRefresh(null, 1, true)
      return false
    }

    root.refreshWorker = worker
    refreshStartCheckTimer.worker = worker
    refreshStartCheckTimer.generation = worker.generation
    refreshStartCheckTimer.collectionGeneration = worker.collectionGeneration
    worker.running = true
    refreshStartCheckTimer.start()
    return true
  }

  function applyOutput(raw) {
    var state = BarModel.commandModuleState(Util.parseModuleJson(raw), raw, {})
    root.outputText = state.text
    root.outputIcon = state.icon
    root.outputValue = state.value
    root.outputTooltip = state.tooltip
    root.outputActive = state.active
    root.outputMuted = state.muted
  }

  function handleRefreshStarted(worker) {
    if (worker === root.refreshWorker && worker.generation === root.refreshGeneration
        && worker.collectionGeneration === root.collectionGeneration)
      refreshStartCheckTimer.stop()
  }

  function handleRefreshRunningChanged(worker) {
    if (worker.running || worker !== root.refreshWorker || !root.collecting
        || worker.generation !== root.refreshGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    refreshStartCheckTimer.worker = worker
    refreshStartCheckTimer.generation = worker.generation
    refreshStartCheckTimer.collectionGeneration = worker.collectionGeneration
    refreshStartCheckTimer.start()
  }

  function finishRefresh(worker, exitCode, failedStart) {
    if (worker !== null && worker !== root.refreshWorker) return
    if (worker && (worker.generation !== root.refreshGeneration
        || worker.collectionGeneration !== root.collectionGeneration)) return
    if (root.refreshFinalizedGeneration === root.refreshGeneration) return

    root.refreshFinalizedGeneration = root.refreshGeneration
    refreshStartCheckTimer.stop()
    refreshStartCheckTimer.worker = null
    if (worker && root.refreshWorker === worker) root.refreshWorker = null
    if (!failedStart && Number(exitCode) === 0 && root.collecting
        && worker && worker.collectionGeneration === root.collectionGeneration)
      root.applyOutput(worker.stdoutOutput.text || "")
    root.destroyWorker(worker)

    if (root.refreshQueued) {
      root.refreshQueued = false
      if (root.collecting) Qt.callLater(root.refresh)
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
    root.refreshQueued = false
    refreshStartCheckTimer.stop()
    refreshStartCheckTimer.worker = null
    root.refreshFinalizedGeneration = root.refreshGeneration
    var oldWorker = root.refreshWorker
    root.refreshWorker = null
    root.destroyWorker(oldWorker)
  }

  onCollectingChanged: {
    if (!root.collecting) root.stopCollection()
    else root.refresh()
  }

  Timer {
    interval: 300000
    running: root.collecting
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshStartCheckTimer
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.refreshWorker
          && worker.generation === generation && worker.collectionGeneration === collectionGeneration
          && !worker.running)
        root.finishRefresh(worker, 1, true)
    }
  }

  Component {
    id: refreshComponent

    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      command: [root.statusExecutable, "disk"]
      stdout: StdioCollector {
        id: stdoutCollector
        waitForEnd: true
      }
      stderr: StdioCollector { waitForEnd: true }
      property alias stdoutOutput: stdoutCollector
      onStarted: root.handleRefreshStarted(process)
      onExited: function(exitCode) { root.finishRefresh(process, Number(exitCode), false) }
      onRunningChanged: root.handleRefreshRunningChanged(process)
    }
  }

  Component.onDestruction: {
    root.collectorLoaded = false
    root.stopCollection()
  }
}
