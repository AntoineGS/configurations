import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/panels/vm"

Item {
  id: root

  property bool sawInitialUnavailable: false
  property bool sawAvailable: false
  property bool fixtureAdvanced: false
  readonly property string resultPath: Quickshell.env("HOST_METRICS_RESULT_FILE")

  function finish(success) {
    cpuFixture.setText("cpu 100 20 30 400 10 5 15 2 0 0\n")
    if (resultPath !== "") resultFile.setText(success ? "PASS\n" : "FAIL\n")
    if (!success) console.error("HostMetrics transition failed", root.sawInitialUnavailable, root.sawAvailable,
      metrics.cpuPhase, metrics.cpuState.available, metrics.memoryState.available)
    else console.log("HostMetrics fixture transition passed")
    Qt.callLater(function() { Qt.exit(success ? 0 : 1) })
  }

  HostMetrics {
    id: metrics
    cpuPath: Qt.resolvedUrl("tests/fixtures/vm/proc-stat")
    memoryPath: Qt.resolvedUrl("tests/fixtures/vm/proc-meminfo")
  }

  FileView {
    id: cpuFixture
    path: Qt.resolvedUrl("tests/fixtures/vm/proc-stat")
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
    function onCpuPhaseChanged() {
      if (metrics.cpuPhase === "sample-wait" && !root.fixtureAdvanced) {
        root.fixtureAdvanced = true
        cpuFixture.setText("cpu 140 25 35 440 10 5 15 2 0 0\n")
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
      if (!root.sawInitialUnavailable || !root.fixtureAdvanced || !root.sawAvailable) {
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
