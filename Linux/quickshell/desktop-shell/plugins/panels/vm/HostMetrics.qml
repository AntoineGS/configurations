import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var cpuState: Model.emptyHostStat()
  property var memoryState: Model.emptyHostStat()
  property var memorySnapshot: null
  property var tmpSnapshot: null
  property string cpuPath: "/proc/stat"
  property string memoryPath: "/proc/meminfo"
  property string tmpExecutable: "df"
  property var cpuSnapshot: null
  property string cpuPhase: ""
  property int cpuGeneration: 0
  property int activeCpuGeneration: 0
  property bool cpuInFlight: false
  property bool collecting: false
  property int collectionGeneration: 0
  property int activeCollectionGeneration: 0
  property var cpuFile: null
  property var memoryFile: null
  property var tmpProcess: null

  function metric(icon, value, tooltip, percent) {
    return {
      available: true,
      stale: false,
      text: icon + " " + value,
      icon: icon,
      value: value,
      tooltip: tooltip,
      percent: percent
    }
  }

  function beginCpuSample() {
    if (!collecting || cpuInFlight) return
    cpuGeneration += 1
    activeCpuGeneration = cpuGeneration
    cpuInFlight = true
    cpuPhase = "baseline"
    cpuSampleTimer.stop()
    startCpuRead(activeCpuGeneration)
  }

  function startCpuRead(generation) {
    if (!collecting || generation !== activeCpuGeneration) return
    if (cpuFile) {
      var previous = cpuFile
      cpuFile = null
      previous.destroy()
    }
    cpuFile = cpuFileComponent.createObject(root, { readGeneration: generation })
    if (!cpuFile) {
      cpuState = Model.emptyHostStat()
      cpuPhase = ""
      cpuInFlight = false
    }
  }

  function applyCpuText(raw, generation, reader) {
    if (!collecting || !cpuInFlight) return
    if (generation !== undefined && generation !== activeCpuGeneration) return
    if (reader !== undefined && reader !== cpuFile) return
    var snapshot = Model.parseCpuSnapshot(raw)
    if (!snapshot) {
      cpuState = Model.emptyHostStat()
      cpuPhase = ""
      cpuInFlight = false
      return
    }
    if (cpuPhase === "baseline") {
      cpuSnapshot = snapshot
      cpuPhase = "sample-wait"
      cpuSampleTimer.start()
      return
    }
    if (cpuPhase !== "sample-load") return
    var percent = Model.cpuUsage(cpuSnapshot, snapshot)
    cpuState = percent === null
      ? Model.emptyHostStat()
      : metric("", percent + "%", "CPU usage: " + percent + "%", percent)
    cpuSnapshot = snapshot
    cpuPhase = ""
    cpuInFlight = false
  }

  function applyCpuLoadFailed(generation, reader) {
    if (!collecting || generation !== activeCpuGeneration || reader !== cpuFile) return
    cpuState = Model.emptyHostStat()
    cpuPhase = ""
    cpuInFlight = false
  }

  function applyMemoryText(raw, generation, reader) {
    if (!collecting) return
    if (generation !== undefined && generation !== activeCollectionGeneration) return
    if (reader !== undefined && reader !== memoryFile) return
    memorySnapshot = Model.parseMemorySnapshot(raw)
    updateMemoryState()
  }

  function refreshMemory() {
    if (!collecting) return
    if (memoryFile) {
      var previous = memoryFile
      memoryFile = null
      previous.destroy()
    }
    memoryFile = memoryFileComponent.createObject(root, { readGeneration: activeCollectionGeneration })
    if (!memoryFile) {
      memorySnapshot = null
      updateMemoryState()
    }
  }

  function applyMemoryLoadFailed(generation, reader) {
    if (!collecting || generation !== activeCollectionGeneration || reader !== memoryFile) return
    memorySnapshot = null
    updateMemoryState()
  }

  function applyTmpText(raw, generation, process) {
    if (!collecting) return
    if (generation !== undefined && generation !== activeCollectionGeneration) return
    if (process !== undefined && process !== tmpProcess) return
    tmpSnapshot = Model.parseFilesystemSnapshot(raw)
    updateMemoryState()
  }

  function updateMemoryState() {
    memoryState = memorySnapshot === null
      ? Model.emptyHostStat()
      : metric("", memorySnapshot.percent + "%", Model.formatMemoryTooltip(memorySnapshot, tmpSnapshot),
        memorySnapshot.percent)
  }

  function refreshTmp() {
    if (!collecting) return
    if (tmpProcess && tmpProcess.running) return
    tmpProcess = tmpProcessComponent.createObject(root, { collectionGeneration: activeCollectionGeneration })
    if (tmpProcess) tmpProcess.running = true
  }

  function finishTmpProcess(process) {
    if (tmpProcess !== process) return
    tmpProcess = null
    process.destroy()
  }

  function destroyLater(worker) {
    if (!worker) return
    var staleWorker = worker
    Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
  }

  onCollectingChanged: {
    if (collecting) {
      collectionGeneration += 1
      activeCollectionGeneration = collectionGeneration
      return
    }
    collectionGeneration += 1
    activeCollectionGeneration = 0
    cpuRefreshTimer.stop()
    memoryRefreshTimer.stop()
    cpuSampleTimer.stop()
    var oldCpuFile = cpuFile
    cpuFile = null
    destroyLater(oldCpuFile)
    var oldMemoryFile = memoryFile
    memoryFile = null
    destroyLater(oldMemoryFile)
    var oldTmpProcess = tmpProcess
    tmpProcess = null
    if (oldTmpProcess) {
      oldTmpProcess.running = false
      destroyLater(oldTmpProcess)
    }
    cpuGeneration += 1
    activeCpuGeneration = cpuGeneration
    cpuSnapshot = null
    cpuPhase = ""
    cpuInFlight = false
  }

  Component {
    id: cpuFileComponent

    FileView {
      id: file
      property int readGeneration: 0
      path: root.cpuPath
      preload: root.collecting
      printErrors: false
      onLoaded: root.applyCpuText(file.text(), file.readGeneration, file)
      onLoadFailed: root.applyCpuLoadFailed(file.readGeneration, file)
    }
  }

  Component {
    id: memoryFileComponent

    FileView {
      id: file
      property int readGeneration: 0
      path: root.memoryPath
      preload: root.collecting
      printErrors: false
      onLoaded: root.applyMemoryText(file.text(), file.readGeneration, file)
      onLoadFailed: root.applyMemoryLoadFailed(file.readGeneration, file)
    }
  }

  Component {
    id: tmpProcessComponent

    Process {
      id: process
      property int collectionGeneration: 0
      command: [root.tmpExecutable, "-Pk", "/tmp"]
      stdout: StdioCollector {
        id: output
        waitForEnd: true
        onStreamFinished: root.applyTmpText(output.text, process.collectionGeneration, process)
      }
      onExited: root.finishTmpProcess(process)
    }
  }

  Timer {
    id: cpuRefreshTimer
    interval: 10000
    repeat: true
    running: root.collecting
    triggeredOnStart: true
    onTriggered: if (root.collecting) root.beginCpuSample()
  }

  Timer {
    id: cpuSampleTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (root.collecting && root.cpuInFlight && root.cpuPhase === "sample-wait"
          && root.activeCpuGeneration === root.cpuGeneration) {
        root.cpuPhase = "sample-load"
        if (cpuFile) cpuFile.reload()
      }
    }
  }

  Timer {
    id: memoryRefreshTimer
    interval: 30000
    repeat: true
    running: root.collecting
    triggeredOnStart: true
    onTriggered: if (root.collecting) root.refreshMemory()
  }
}
