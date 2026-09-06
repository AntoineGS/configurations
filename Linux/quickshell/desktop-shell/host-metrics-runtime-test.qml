import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/panels/vm"

Item {
  id: root

  property bool sawInitialUnavailable: false
  property bool sawAvailable: false
  property bool fixtureAdvanced: false
  property bool initialCpuConfirmed: false
  property bool cpuInterruptionStarted: false
  property bool sawCpuStop: false
  property bool sawCpuRestart: false
  property bool sawLateCpuIgnored: false
  property bool sawLateCpuAfterRestart: false
  property bool restartBaselineReached: false
  property int stoppedCpuGeneration: 0
  property int stoppedCollectionGeneration: 0
  property var stoppedCpuWorker: null
  property var stoppedMemoryWorker: null
  property var stoppedTmpWorker: null
  property var confirmedTmpSnapshot: null
  property bool sawLateTmpIgnored: false
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
    if (!success) console.error("HostMetrics transition failed", root.sawInitialUnavailable, root.sawAvailable,
      metrics.cpuPhase, metrics.cpuState.available, metrics.memoryState.available,
      root.sawCpuStop, root.sawCpuRestart, root.sawLateCpuIgnored, root.sawLateCpuAfterRestart,
      root.sawLateTmpIgnored)
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

  Connections {
    target: metrics
    function onCpuStateChanged() {
      if (metrics.cpuState.available && !root.initialCpuConfirmed) {
        root.initialCpuConfirmed = true
        root.confirmedCpuState = metrics.cpuState
        root.confirmedMemoryState = metrics.memoryState
        Qt.callLater(function() { metrics.beginCpuSample() })
      }
    }

    function onCpuPhaseChanged() {
      if (metrics.cpuPhase === "sample-wait" && !root.fixtureAdvanced) {
        root.fixtureAdvanced = true
        cpuFixture.setText("cpu 140 25 35 440 10 5 15 2 0 0\n")
        return
      }

      if (metrics.cpuPhase !== "sample-wait" || !root.fixtureAdvanced || !root.initialCpuConfirmed) return
      if (!root.cpuInterruptionStarted) {
        root.cpuInterruptionStarted = true
        root.stoppedCpuGeneration = metrics.cpuGeneration
        root.stoppedCollectionGeneration = metrics.collectionGeneration
        root.stoppedCpuWorker = metrics.cpuFile
        root.stoppedMemoryWorker = metrics.memoryFile
        metrics.refreshTmp()
        root.stoppedTmpWorker = metrics.tmpProcess
        root.confirmedTmpSnapshot = metrics.tmpSnapshot
        root.confirmedCpuState = metrics.cpuState
        root.confirmedMemoryState = metrics.memoryState
        metrics.collecting = false
        metrics.applyCpuText("cpu 240 40 60 500 10 5 15 2 0 0\n")
        metrics.applyMemoryText("not a memory snapshot\n")
        root.sawCpuStop = !metrics.cpuInFlight && metrics.cpuPhase === ""
          && metrics.cpuGeneration > root.stoppedCpuGeneration
        root.sawLateCpuIgnored = root.sameState(metrics.cpuState, root.confirmedCpuState)
          && root.sameState(metrics.memoryState, root.confirmedMemoryState)
        cpuFixture.setText("cpu 300 50 70 600 10 5 15 2 0 0\n")
        metrics.collecting = true
        metrics.applyTmpText("Filesystem 1024-blocks Used Available Capacity Mounted on\nfixture 900 800 100 88% /tmp\n",
          metrics.activeCollectionGeneration, root.stoppedTmpWorker)
        root.sawLateTmpIgnored = root.stoppedTmpWorker
          && root.sameState(metrics.tmpSnapshot, root.confirmedTmpSnapshot)
        root.sawCpuRestart = metrics.cpuGeneration > root.stoppedCpuGeneration
        return
      }

      if (!root.restartBaselineReached) {
        root.restartBaselineReached = true
        metrics.applyCpuText("cpu 240 40 60 500 10 5 15 2 0 0\n",
          metrics.activeCpuGeneration, root.stoppedCpuWorker)
        metrics.applyMemoryText("not a memory snapshot\n",
          metrics.activeCollectionGeneration, root.stoppedMemoryWorker)
        root.sawLateCpuAfterRestart = root.sameState(metrics.cpuState, root.confirmedCpuState)
          && root.sameState(metrics.memoryState, root.confirmedMemoryState)
        cpuFixture.setText("cpu 360 60 80 680 10 5 15 2 0 0\n")
        checkTimer.start()
      }
    }
  }

  Timer {
    id: checkTimer
    property int checks: 0
    interval: 50
    repeat: false
    onTriggered: {
      checks++
      root.sawAvailable = metrics.cpuState.available && metrics.memoryState.available
      if (!root.sawInitialUnavailable || !root.fixtureAdvanced || !root.initialCpuConfirmed
          || !root.cpuInterruptionStarted || !root.sawCpuStop || !root.sawCpuRestart
          || !root.sawLateCpuIgnored || !root.sawLateCpuAfterRestart || !root.sawLateTmpIgnored
          || !root.restartBaselineReached
          || !root.sawAvailable) {
        if (checks < 100) {
          start()
          return
        }
        root.finish(false)
        return
      }
      root.finish(true)
    }
  }
}
