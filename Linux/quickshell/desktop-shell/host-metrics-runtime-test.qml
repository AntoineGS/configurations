import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/panels/vm"

Item {
  id: root

  property bool sawInitialUnavailable: false
  property int samplesChecked: 0
  property bool lifecycleStarted: false
  property bool sawCpuStop: false
  property bool sawCpuRestart: false
  property bool sawLateCpuIgnored: false
  property bool sawLateTmpIgnored: false
  property bool restartBaselineReached: false
  property bool sawLateCpuAfterRestart: false
  property bool sawCpuIdentityBarrier: false
  property var restartCpuWorker: null
  property bool restartSampleRequested: false
  property int stoppedCollectionGeneration: 0
  property var stoppedCpuWorker: null
  property var stoppedMemoryWorker: null
  property var stoppedTmpWorker: null
  property var confirmedTmpSnapshot: null
  property var confirmedCpuState: null
  property var confirmedMemoryState: null
  readonly property string cpuFixturePath: Quickshell.env("HOST_METRICS_CPU_PATH")
    || Qt.resolvedUrl("tests/fixtures/vm/proc-stat")
  readonly property string memoryFixturePath: Quickshell.env("HOST_METRICS_MEMORY_PATH")
    || Qt.resolvedUrl("tests/fixtures/vm/proc-meminfo")
  readonly property string tmpExecutablePath: Qt.resolvedUrl("tests/fixtures/vm/fake-df").toString()
    .replace("file://", "")
  readonly property string resultPath: Quickshell.env("HOST_METRICS_RESULT_FILE")

  function sameState(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  }

  function finish(success) {
    cpuFixture.setText("cpu 100 20 30 400 10 5 15 2 0 0\n")
    if (resultPath !== "") resultFile.setText(success ? "PASS\n" : "FAIL\n")
    if (!success) console.error("HostMetrics transition failed", root.sawInitialUnavailable,
      root.samplesChecked, root.sawCpuStop, root.sawCpuRestart, root.sawLateCpuIgnored,
      root.sawLateTmpIgnored, root.restartBaselineReached, root.sawLateCpuAfterRestart,
      metrics.cpuState.percent, metrics.memoryState.available)
    else console.log("HostMetrics fixture transition passed")
    Qt.callLater(function() { Qt.exit(success ? 0 : 1) })
  }

  HostMetrics {
    id: metrics
    collecting: true
    cpuPath: root.cpuFixturePath
    memoryPath: root.memoryFixturePath
    tmpExecutable: root.tmpExecutablePath
  }

  FileView {
    id: cpuFixture
    path: root.cpuFixturePath
    preload: false
    blockWrites: true
    printErrors: false
  }

  FileView {
    id: resultFile
    path: root.resultPath
    preload: false
    blockWrites: false
    printErrors: false
  }

  Component.onCompleted: root.sawInitialUnavailable = !metrics.cpuState.available && !metrics.memoryState.available

  Timer {
    id: checkTimer
    property int checks: 0
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      checks++
      if (checks >= 160) {
        root.finish(false)
        return
      }
      if (!root.sawInitialUnavailable || metrics.cpuInFlight || !metrics.cpuSnapshot
          || !metrics.memoryState.available)
        return

      if (root.samplesChecked < 2) {
        if (root.samplesChecked === 0) {
          if (metrics.cpuState.available) {
            root.finish(false)
            return
          }
          cpuFixture.setText("cpu 140 25 35 440 10 5 15 2 0 0\n")
        } else {
          if (!metrics.cpuState.available || metrics.cpuState.percent !== 55) {
            root.finish(false)
            return
          }
          cpuFixture.setText("cpu 160 25 35 520 10 5 15 2 0 0\n")
        }
        root.samplesChecked++
        metrics.beginCpuSample()
        return
      }

      if (!root.lifecycleStarted) {
        if (!metrics.cpuState.available || metrics.cpuState.percent !== 20) {
          root.finish(false)
          return
        }
        root.confirmedCpuState = metrics.cpuState
        root.confirmedMemoryState = metrics.memoryState
        root.confirmedTmpSnapshot = metrics.tmpSnapshot
        root.stoppedCollectionGeneration = metrics.activeCollectionGeneration
        metrics.beginCpuSample()
        root.stoppedCpuWorker = metrics.cpuFile
        metrics.refreshMemory()
        root.stoppedMemoryWorker = metrics.memoryFile
        metrics.refreshTmp()
        root.stoppedTmpWorker = metrics.tmpProcess
        if (!root.stoppedCpuWorker || !root.stoppedMemoryWorker || !root.stoppedTmpWorker) {
          root.finish(false)
          return
        }

        metrics.collecting = false
        root.sawCpuStop = !metrics.cpuInFlight && metrics.activeCollectionGeneration === 0
          && metrics.cpuSnapshot === null && metrics.collectionGeneration > root.stoppedCollectionGeneration
        metrics.applyCpuText("cpu 240 40 60 500 10 5 15 2 0 0\n",
          root.stoppedCollectionGeneration, root.stoppedCpuWorker)
        metrics.applyMemoryText("not a memory snapshot\n",
          root.stoppedCollectionGeneration, root.stoppedMemoryWorker)
        metrics.applyTmpText("Filesystem 1024-blocks Used Available Capacity Mounted on\n"
          + "fixture 900 800 100 88% /tmp\n", root.stoppedCollectionGeneration, root.stoppedTmpWorker)
        root.sawLateCpuIgnored = root.sameState(metrics.cpuState, root.confirmedCpuState)
          && root.sameState(metrics.memoryState, root.confirmedMemoryState)
        root.sawLateTmpIgnored = root.sameState(metrics.tmpSnapshot, root.confirmedTmpSnapshot)

        cpuFixture.setText("cpu 300 50 70 600 10 5 15 2 0 0\n")
        metrics.collecting = true
        root.sawCpuRestart = metrics.activeCollectionGeneration > root.stoppedCollectionGeneration
        metrics.applyTmpText("Filesystem 1024-blocks Used Available Capacity Mounted on\n"
          + "fixture 900 800 100 88% /tmp\n", metrics.activeCollectionGeneration, root.stoppedTmpWorker)
        root.sawLateTmpIgnored = root.sawLateTmpIgnored
          && root.sameState(metrics.tmpSnapshot, root.confirmedTmpSnapshot)
        root.lifecycleStarted = true
        return
      }

      if (!root.restartBaselineReached) {
        if (metrics.cpuInFlight || !metrics.cpuSnapshot || metrics.cpuFile === root.stoppedCpuWorker)
          return
        root.restartBaselineReached = true
        metrics.refreshMemory()
        var beforeCpu = metrics.cpuState
        var beforeMemory = metrics.memoryState
        metrics.applyMemoryText("not a memory snapshot\n",
          metrics.activeCollectionGeneration, root.stoppedMemoryWorker)
        root.sawLateCpuAfterRestart = root.sameState(metrics.memoryState, beforeMemory)
        cpuFixture.setText("cpu 360 60 80 680 10 5 15 2 0 0\n")
        metrics.beginCpuSample()
        root.restartCpuWorker = metrics.cpuFile
        root.sawCpuIdentityBarrier = metrics.cpuInFlight
          && root.restartCpuWorker !== root.stoppedCpuWorker
        metrics.applyCpuText("cpu 240 40 60 500 10 5 15 2 0 0\n",
          metrics.activeCollectionGeneration, root.stoppedCpuWorker)
        root.sawLateCpuAfterRestart = root.sawLateCpuAfterRestart
          && root.sameState(metrics.cpuState, beforeCpu)
          && metrics.cpuInFlight && metrics.cpuFile === root.restartCpuWorker
        root.restartSampleRequested = true
        return
      }

      if (!root.restartSampleRequested) return
      root.finish(root.sawCpuStop && root.sawCpuRestart && root.sawLateCpuIgnored
        && root.sawLateTmpIgnored && root.restartBaselineReached && root.sawCpuIdentityBarrier
        && root.sawLateCpuAfterRestart
        && metrics.cpuState.available && metrics.cpuState.percent === 50)
    }
  }
}
