import QtQuick
import qs.Commons
import "../../panels/vm"

SharedService {
  id: root

  readonly property var cpuState: metrics.cpuState
  readonly property var memoryState: metrics.memoryState

  function refreshTmp() {
    metrics.refreshTmp()
  }

  HostMetrics {
    id: metrics
    collecting: root.collecting
  }
}
