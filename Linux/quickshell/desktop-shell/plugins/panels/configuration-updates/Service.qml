import QtQuick
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property bool refreshPending: false
  property bool refreshInFlight: false
  property int refreshGeneration: 0
  property int finalizedGeneration: 0
  property string gitState: "clean"
  property bool gitVisible: false
  property string gitTooltip: ""
  property string lastGitTooltip: ""
  property string tidydotsState: "clean"
  property bool tidydotsVisible: false
  property string tidydotsTooltip: ""
  property string lastTidydotsTooltip: ""

  readonly property bool busy: statusProcess.running

  function applyState(raw) {
    var data = Util.parseModuleJson(raw)
    if (!Util.isPlainObject(data) || !Util.isPlainObject(data.git) || !Util.isPlainObject(data.tidydots)) {
      applyFailure("Invalid configuration update status")
      return
    }

    gitState = String(data.git.state || "error")
    gitVisible = data.git.visible === true
    gitTooltip = String(data.git.tooltip || "Git status unavailable")
    if (gitState !== "error") lastGitTooltip = gitTooltip
    tidydotsState = String(data.tidydots.state || "error")
    tidydotsVisible = data.tidydots.visible === true
    tidydotsTooltip = String(data.tidydots.tooltip || "Tidydots status unavailable")
    if (tidydotsState !== "error") lastTidydotsTooltip = tidydotsTooltip
  }

  function applyFailure(message) {
    var detail = String(message || "Configuration update check failed").trim()
    gitState = "error"
    gitVisible = true
    gitTooltip = (lastGitTooltip !== "" ? lastGitTooltip + "\n" : "") + detail
    tidydotsState = "error"
    tidydotsVisible = true
    tidydotsTooltip = (lastTidydotsTooltip !== "" ? lastTidydotsTooltip + "\n" : "") + detail
  }

  function refresh() {
    if (statusProcess.running) {
      refreshPending = true
      return
    }
    refreshGeneration++
    refreshInFlight = true
    statusStartCheckTimer.generation = refreshGeneration
    statusProcess.running = true
    statusStartCheckTimer.start()
  }

  function finishRefresh(exitCode, failedStart) {
    if (!refreshInFlight || finalizedGeneration === refreshGeneration) return
    finalizedGeneration = refreshGeneration
    refreshInFlight = false
    statusStartCheckTimer.stop()

    if (!failedStart && Number(exitCode) === 0) {
      applyState(statusStdout.text || "")
    } else {
      applyFailure(failedStart
        ? "Configuration update helper failed to start"
        : statusStderr.text || "Configuration update check failed")
    }

    if (refreshPending) {
      refreshPending = false
      Qt.callLater(refresh)
    }
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 1800000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    command: ["desktop-shell-configuration-updates", "status"]
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
    }
    onStarted: statusStartCheckTimer.stop()
    onExited: root.finishRefresh(exitCode, false)
    onRunningChanged: {
      if (!statusProcess.running && root.refreshInFlight
          && root.finalizedGeneration !== root.refreshGeneration) {
        statusStartCheckTimer.generation = root.refreshGeneration
        statusStartCheckTimer.start()
      }
    }
  }

  Timer {
    id: statusStartCheckTimer
    property int generation: 0
    interval: 100
    repeat: false
    onTriggered: {
      if (!statusProcess.running && generation === root.refreshGeneration)
        root.finishRefresh(1, true)
    }
  }
}
