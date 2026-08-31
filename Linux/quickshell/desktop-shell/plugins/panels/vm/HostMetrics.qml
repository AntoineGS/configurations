import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var cpuState: Model.emptyHostStat()
  property var memoryState: Model.emptyHostStat()
  property string cpuPath: "/proc/stat"
  property string memoryPath: "/proc/meminfo"
  property var cpuSnapshot: null
  property string cpuPhase: ""
  property int cpuGeneration: 0
  property int activeCpuGeneration: 0
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
    cpuGeneration += 1
    activeCpuGeneration = cpuGeneration
    cpuInFlight = true
    cpuPhase = "baseline"
    cpuSampleTimer.stop()
    cpuFile.reload()
  }

  function applyCpuText(raw) {
    if (!cpuInFlight) return
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

  function applyMemoryText(raw) {
    var snapshot = Model.parseMemorySnapshot(raw)
    memoryState = snapshot === null
      ? Model.emptyHostStat()
      : metric("", snapshot.percent + "%", Model.formatMemoryTooltip(snapshot), snapshot.percent)
  }

  FileView {
    id: cpuFile
    path: root.cpuPath
    preload: true
    printErrors: false
    onLoaded: root.applyCpuText(text())
    onLoadFailed: {
      root.cpuState = Model.emptyHostStat()
      root.cpuPhase = ""
      root.cpuInFlight = false
    }
  }

  FileView {
    id: memoryFile
    path: root.memoryPath
    preload: true
    printErrors: false
    onLoaded: root.applyMemoryText(text())
    onLoadFailed: root.memoryState = Model.emptyHostStat()
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
    id: cpuSampleTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (root.cpuInFlight && root.cpuPhase === "sample-wait"
          && root.activeCpuGeneration === root.cpuGeneration) {
        root.cpuPhase = "sample-load"
        cpuFile.reload()
      }
    }
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
