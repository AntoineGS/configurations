import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "WorkspacesModel.js" as WorkspacesModel

SharedService {
  id: root

  property var activeWorkspaceIds: ({})
  property bool collectorLoaded: true
  property bool activeRefreshQueued: false
  property int activeRefreshGeneration: 0
  property int activeRefreshFinalizedGeneration: 0
  property int collectionGeneration: 0
  property string queryExecutable: "hyprctl"
  property int processStartGraceInterval: 100
  property var activeRefreshWorker: null
  property var confirmedRemovedNames: ({})

  function isWorkspaceEvent(name) {
    return name === "workspace" || name === "workspacev2"
      || name === "focusedmon" || name === "focusedmonv2"
      || name === "monitoradded" || name === "monitoraddedv2"
      || name === "monitorremoved" || name === "monitorremovedv2"
      || name === "moveworkspace" || name === "moveworkspacev2"
  }

  function refreshActiveWorkspace() {
    if (!root.collecting || !root.collectorLoaded) return false
    if (root.activeRefreshWorker
        || root.activeRefreshGeneration > root.activeRefreshFinalizedGeneration) {
      root.activeRefreshQueued = true
      return true
    }
    root.activeRefreshGeneration++
    var worker = activeRefreshComponent.createObject(root, {
      generation: root.activeRefreshGeneration,
      collectionGeneration: root.collectionGeneration
    })
    if (!worker) {
      root.finishActiveRefresh(null, 1, true)
      return true
    }
    root.activeRefreshWorker = worker
    worker.running = true
    return true
  }

  function queueActiveWorkspaceRefresh() {
    if (!root.collecting || !root.collectorLoaded) return false
    activeRefreshDebounce.restart()
    return true
  }

  function parsedSnapshot(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (error) {
      return null
    }
    if (!Array.isArray(parsed)) return null
    var names = ({})
    for (var i = 0; i < parsed.length; i++) {
      var monitor = parsed[i]
      var name = monitor && typeof monitor === "object" ? String(monitor.name || "") : ""
      if (!name || names[name]) return null
      names[name] = true
    }
    return { monitors: parsed, names: names }
  }

  function applySnapshot(raw) {
    var snapshot = parsedSnapshot(raw)
    if (!snapshot) return false
    var monitors = snapshot.monitors
    var next = Object.assign({}, root.activeWorkspaceIds)
    for (var i = 0; i < monitors.length; i++) {
      var name = String(monitors[i].name || "")
      if (name) next[name] = WorkspacesModel.confirmedActiveWorkspaceId(
        next[name] === undefined ? -1 : next[name], monitors, name)
    }
    var removals = Object.assign({}, root.confirmedRemovedNames)
    for (var removedName in removals) {
      if (snapshot.names[removedName]) delete removals[removedName]
      else delete next[removedName]
    }
    root.confirmedRemovedNames = removals
    root.activeWorkspaceIds = next
    return true
  }

  function noteTopologyEvent(event) {
    var eventName = String(event.name || "")
    if (eventName !== "monitorremoved" && eventName !== "monitorremovedv2") return
    var name = String(event.data || "").split(",")[0].trim()
    if (!name) return
    var next = Object.assign({}, root.confirmedRemovedNames)
    next[name] = true
    root.confirmedRemovedNames = next
  }

  function handleWorkerRunningChanged(worker) {
    if (worker.running || worker !== root.activeRefreshWorker || !root.collecting
        || worker.generation !== root.activeRefreshGeneration
        || worker.collectionGeneration !== root.collectionGeneration) return
    activeRefreshStartCheck.worker = worker
    activeRefreshStartCheck.generation = worker.generation
    activeRefreshStartCheck.collectionGeneration = worker.collectionGeneration
    activeRefreshStartCheck.start()
  }

  function finishActiveRefresh(worker, exitCode, failedStart) {
    if (worker !== null && worker !== root.activeRefreshWorker) return
    if (worker && (worker.generation !== root.activeRefreshGeneration
        || worker.collectionGeneration !== root.collectionGeneration)) return
    if (root.activeRefreshFinalizedGeneration === root.activeRefreshGeneration) return

    root.activeRefreshFinalizedGeneration = root.activeRefreshGeneration
    activeRefreshStartCheck.stop()
    activeRefreshStartCheck.worker = null
    if (worker && root.activeRefreshWorker === worker) root.activeRefreshWorker = null
    if (worker && !failedStart && Number(exitCode) === 0)
      root.applySnapshot(worker.stdoutOutput.text || "")
    root.destroyWorker(worker)

    if (root.activeRefreshQueued) {
      root.activeRefreshQueued = false
      Qt.callLater(root.refreshActiveWorkspace)
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
    activeRefreshDebounce.stop()
    activeRefreshStartCheck.stop()
    activeRefreshStartCheck.worker = null
    root.activeRefreshFinalizedGeneration = root.activeRefreshGeneration
    root.activeRefreshQueued = false
    var oldWorker = root.activeRefreshWorker
    root.activeRefreshWorker = null
    root.destroyWorker(oldWorker)
  }

  onCollectingChanged: {
    if (!root.collecting) {
      root.stopCollection()
      return
    }
    root.refreshActiveWorkspace()
  }

  Timer {
    id: activeRefreshDebounce
    interval: 50
    repeat: false
    onTriggered: root.refreshActiveWorkspace()
  }

  Timer {
    id: activeRefreshStartCheck
    property int generation: 0
    property int collectionGeneration: 0
    property var worker: null
    interval: root.processStartGraceInterval
    repeat: false
    onTriggered: {
      if (root.collecting && worker && worker === root.activeRefreshWorker
          && worker.generation === generation && worker.collectionGeneration === collectionGeneration
          && !worker.running)
        root.finishActiveRefresh(worker, 1, true)
    }
  }

  Component {
    id: activeRefreshComponent
    Process {
      id: process
      property int generation: 0
      property int collectionGeneration: 0
      command: [root.queryExecutable, "-j", "monitors", "all"]
      stdout: StdioCollector {
        id: stdoutCollector
        waitForEnd: true
      }
      stderr: StdioCollector { waitForEnd: true }
      property alias stdoutOutput: stdoutCollector
      onExited: function(exitCode) { root.finishActiveRefresh(process, Number(exitCode), false) }
      onRunningChanged: root.handleWorkerRunningChanged(process)
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      root.noteTopologyEvent(event)
      if (root.isWorkspaceEvent(String(event.name || ""))) root.queueActiveWorkspaceRefresh()
    }
  }

  Component.onDestruction: {
    root.collectorLoaded = false
    root.stopCollection()
  }
}
