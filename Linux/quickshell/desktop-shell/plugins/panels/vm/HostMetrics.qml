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
  property var cpuSnapshot: null
  property bool cpuInFlight: false

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
    if (cpuInFlight) return
    cpuInFlight = true
    cpuFile.reload()
  }

  function applyCpuText(raw) {
    if (!cpuInFlight) return
    var snapshot = Model.parseCpuSnapshot(raw)
    var percent = Model.cpuUsage(cpuSnapshot, snapshot)
    cpuState = percent === null
      ? Model.emptyHostStat()
      : metric("", percent + "%", "CPU usage: " + percent + "%", percent)
    cpuSnapshot = snapshot
    cpuInFlight = false
  }

  function applyMemoryText(raw) {
    memorySnapshot = Model.parseMemorySnapshot(raw)
    updateMemoryState()
  }

  function applyTmpText(raw) {
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
    if (!tmpProcess.running) tmpProcess.running = true
  }

  FileView {
    id: cpuFile
    path: root.cpuPath
    preload: true
    printErrors: false
    onLoaded: root.applyCpuText(text())
    onLoadFailed: {
      root.cpuState = Model.emptyHostStat()
      root.cpuSnapshot = null
      root.cpuInFlight = false
    }
  }

  FileView {
    id: memoryFile
    path: root.memoryPath
    preload: true
    printErrors: false
    onLoaded: root.applyMemoryText(text())
    onLoadFailed: {
      root.memorySnapshot = null
      root.updateMemoryState()
    }
  }

  Process {
    id: tmpProcess
    command: ["df", "-Pk", "/tmp"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyTmpText(text)
    }
  }

  Timer {
    id: cpuRefreshTimer
    interval: 10000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.beginCpuSample()
  }

  Timer {
    id: memoryRefreshTimer
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: memoryFile.reload()
  }
}
