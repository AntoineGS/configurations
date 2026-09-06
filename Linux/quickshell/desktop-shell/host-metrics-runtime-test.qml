import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/panels/vm"

Item {
  id: root

  property bool sawInitialUnavailable: false
  property int samplesChecked: 0
  readonly property string resultPath: Quickshell.env("HOST_METRICS_RESULT_FILE")

  function finish(success) {
    cpuFixture.setText("cpu 100 20 30 400 10 5 15 2 0 0\n")
    if (resultPath !== "") resultFile.setText(success ? "PASS\n" : "FAIL\n")
    if (!success) console.error("HostMetrics transition failed", root.sawInitialUnavailable, root.samplesChecked,
      metrics.cpuState.percent, metrics.memoryState.available)
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

  Timer {
    id: checkTimer
    property int checks: 0
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      checks++
      if (checks >= 100) {
        root.finish(false)
        return
      }
      if (metrics.cpuInFlight || !metrics.cpuSnapshot || !metrics.memoryState.available) return
      if (!root.sawInitialUnavailable) {
        root.finish(false)
        return
      }
      if (root.samplesChecked === 0) {
        if (metrics.cpuState.available) {
          root.finish(false)
          return
        }
        cpuFixture.setText("cpu 140 25 35 440 10 5 15 2 0 0\n")
      } else if (root.samplesChecked === 1) {
        if (!metrics.cpuState.available || metrics.cpuState.percent !== 55) {
          root.finish(false)
          return
        }
        cpuFixture.setText("cpu 160 25 35 520 10 5 15 2 0 0\n")
      } else {
        root.finish(metrics.cpuState.available && metrics.cpuState.percent === 20)
        return
      }
      root.samplesChecked++
      metrics.beginCpuSample()
    }
  }
}
