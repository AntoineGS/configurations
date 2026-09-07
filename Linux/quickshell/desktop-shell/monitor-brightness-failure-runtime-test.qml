import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/monitor" as Monitor

Item {
  id: root

  readonly property string stateModePath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_MODE") || ""
  readonly property string stateEnteredPath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_ENTERED") || ""
  readonly property string actionEnteredPath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_ENTERED") || ""
  readonly property string failureCase: Quickshell.env("MONITOR_BRIGHTNESS_FAILURE_CASE") || "timeout"
  readonly property string fakeState: Qt.resolvedUrl("tests/fixtures/monitor-brightness/fake-state")
    .toString().replace("file://", "")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/monitor-brightness/fake-action")
    .toString().replace("file://", "")
  readonly property string actionExecutable: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_EXECUTABLE") || root.fakeAction
  readonly property string fakeHostname: Qt.resolvedUrl("tests/fixtures/monitor/fake-hostname")
    .toString().replace("file://", "")
  property int phase: 0
  property int checks: 0
  property bool recoveryRefreshRequested: false
  property string stateEnteredText: ""
  property string actionEnteredText: ""

  QtObject {
    id: fakeShell
    property bool previewMode: false
    function widgetSettingsFor(pluginId) { return ({}) }
    function serviceFor(pluginId) { return pluginId === "desktop.monitor" ? service : null }
  }

  Monitor.Service {
    id: service
    shell: fakeShell
    manifest: ({ id: "desktop.monitor" })
    stateExecutable: root.fakeState
    actionExecutable: root.actionExecutable
    hostnameExecutable: root.fakeHostname
    processStartGraceInterval: 50
    processTimeoutInterval: 100
    stateProcessTimeoutInterval: 100
  }

  ServiceConsumer { service: service; active: true }
  ServiceConsumer { service: service; active: true }

  FileView {
    id: stateModeFile
    path: root.stateModePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  FileView {
    id: stateEnteredFile
    path: root.stateEnteredPath
    preload: true
    watchChanges: true
    printErrors: false
    onLoaded: root.stateEnteredText = text()
    onFileChanged: reload()
  }

  FileView {
    id: actionEnteredFile
    path: root.actionEnteredPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.actionEnteredText = text()
    onFileChanged: reload()
  }

  function fail(message) {
    console.error("Monitor brightness failure fixture failed: " + String(message), root.phase,
      service.consumerCount, service.collecting, service.operationPending, service.stateWorker,
      service.actionWorker, service.brightnessPending("DP-1"), service.brightnessError("DP-1"))
    Qt.exit(1)
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      try {
        if (root.phase === 0) {
          if (service.brightnessFor("DP-1").available !== true) return
          if (root.failureCase === "ordinary-failure" || root.failureCase === "cached-stale") {
            stateModeFile.setText(root.failureCase + "\n")
            service.refresh()
            root.phase = 1
            return
          }
          if (root.failureCase === "targeted-failure") {
            stateModeFile.setText("targeted-failure\n")
            service.refresh("DP-1")
            root.phase = 1
            return
          }
          if (root.failureCase === "timeout") stateModeFile.setText("timeout\n")
          else if (root.failureCase === "malformed-confirmation") stateModeFile.setText("malformed-confirmation\n")
          if (service.setBrightness("DP-1", 70) !== true)
            return root.fail("timeout scenario action was rejected")
          root.phase = 1
          return
        }

        if (root.phase === 1) {
          if (root.failureCase === "ordinary-failure" || root.failureCase === "cached-stale") {
            if (service.stateWorker || service.operationPending) return
            var failedFull = service.brightnessFor("DP-1")
            var failedOther = service.brightnessFor("HDMI-1")
            if (failedFull.available !== false || failedFull.stale !== true || failedFull.current !== 40
                || failedOther.available !== false || failedOther.stale !== true || failedOther.current !== 60
                || service.hardwareState.stale !== true)
              return root.fail(root.failureCase + " did not stale the full snapshot")
            if (service.setBrightness("DP-1", 70) !== false || String(root.actionEnteredText).trim() === "DP-1:70")
              return root.fail(root.failureCase + " accepted a brightness action while stale")
            stateModeFile.setText("initial\n")
            root.recoveryRefreshRequested = false
            root.phase = 2
            return
          }
          if (root.failureCase === "targeted-failure") {
            if (service.stateWorker || service.operationPending) return
            var failedTarget = service.brightnessFor("DP-1")
            var healthyOther = service.brightnessFor("HDMI-1")
            if (failedTarget.available !== false || failedTarget.stale !== true || failedTarget.current !== 40
                || healthyOther.available !== true || healthyOther.stale === true || healthyOther.current !== 60
                || service.hardwareState.stale === true)
              return root.fail("targeted state failure damaged the wrong records")
            if (service.setBrightness("DP-1", 70) !== false || String(root.actionEnteredText).trim() === "DP-1:70")
              return root.fail("targeted stale record accepted a brightness action")
            stateModeFile.setText("target-a-70\n")
            root.recoveryRefreshRequested = false
            root.phase = 2
            return
          }
          if (root.failureCase !== "failed-start" && String(root.actionEnteredText).trim() !== "DP-1:70") return
          if (root.failureCase === "timeout" && String(root.stateEnteredText).trim() !== "started:timeout") return
          root.phase = 2
          return
        }

        if (root.phase === 2) {
          if (root.failureCase === "ordinary-failure" || root.failureCase === "cached-stale"
              || root.failureCase === "targeted-failure") {
            if (!root.recoveryRefreshRequested) {
              var recoveryMode = root.failureCase === "targeted-failure" ? "target-a-70" : "initial"
              if (String(stateModeFile.text() || "").trim() !== recoveryMode) return
              if (root.failureCase === "targeted-failure") service.refresh("DP-1")
              else service.refresh()
              root.recoveryRefreshRequested = true
              return
            }
          }
          if (root.failureCase === "ordinary-failure" || root.failureCase === "cached-stale") {
            if (service.stateWorker || service.operationPending) return
            var recoveredFull = service.brightnessFor("DP-1")
            var recoveredOther = service.brightnessFor("HDMI-1")
            if (recoveredFull.available !== true || recoveredFull.stale !== false || recoveredFull.current !== 40
                || recoveredOther.available !== true || recoveredOther.stale !== false || recoveredOther.current !== 60
                || service.hardwareState.stale === true || service.brightnessError("DP-1") !== "")
              return root.fail(root.failureCase + " did not clear stale state after recovery")
            if (root.failureCase === "cached-stale") {
              console.log("Monitor brightness " + root.failureCase + " fixture passed")
              Qt.exit(0)
              return
            }
            stateModeFile.setText("target-a-70\n")
            if (service.setBrightness("DP-1", 70) !== true)
              return root.fail("healthy recovery did not re-enable brightness actions")
            root.phase = 3
            return
          }
          if (root.failureCase === "targeted-failure") {
            if (service.stateWorker || service.operationPending) return
            var recoveredTarget = service.brightnessFor("DP-1")
            var retainedOther = service.brightnessFor("HDMI-1")
            if (recoveredTarget.available !== true || recoveredTarget.stale !== false
                || recoveredTarget.current !== 70 || retainedOther.available !== true
                || retainedOther.current !== 60 || service.brightnessError("DP-1") !== "")
              return root.fail("targeted healthy recovery did not restore the affected record")
            console.log("Monitor brightness " + root.failureCase + " fixture passed")
            Qt.exit(0)
            return
          }
          if (service.stateWorker || service.operationPending || service.brightnessPending("DP-1")
              || service.pendingConfirmationConnector !== "") return
          if (root.failureCase === "timeout") {
            var timedOut = service.brightnessFor("DP-1")
            var timedOutOther = service.brightnessFor("HDMI-1")
            if (timedOut.available !== false || timedOut.stale !== true || timedOut.current !== 40
                || timedOutOther.available !== true || timedOutOther.stale === true
                || timedOutOther.current !== 60 || service.brightnessError("DP-1") === "")
              return root.fail("state timeout did not preserve the last-good record safely")
            if (service.setBrightness("DP-1", 70) !== false)
              return root.fail("state timeout accepted a new brightness request")
            stateModeFile.setText("target-a-70\n")
            service.refresh("DP-1")
            root.phase = 3
            return
          }
          if (root.failureCase === "malformed-confirmation") {
            var malformed = service.brightnessFor("DP-1")
            if (malformed.available !== false || malformed.stale !== true || malformed.current !== 40
                || malformed.identity === "" || malformed.topology === "")
              return root.fail("malformed confirmation did not preserve the last-good record")
          }
          if (service.brightnessError("DP-1") === "")
            return root.fail(root.failureCase + " did not publish a target error")
          console.log("Monitor brightness " + root.failureCase + " fixture passed")
          Qt.exit(0)
          return
        }

        if (root.phase === 3 && root.failureCase === "timeout") {
          if (service.stateWorker || service.actionWorker || service.operationPending
              || service.brightnessPending("DP-1")) return
          var recoveredTimeout = service.brightnessFor("DP-1")
          if (recoveredTimeout.available !== true || recoveredTimeout.stale !== false
              || recoveredTimeout.current !== 70 || service.brightnessError("DP-1") !== "")
            return root.fail("fresh targeted recovery did not re-enable brightness")
          if (service.setBrightness("DP-1", 70) !== true)
            return root.fail("fresh targeted recovery rejected brightness")
          root.phase = 4
          return
        }

        if (root.phase === 3 && root.failureCase === "ordinary-failure") {
          if (service.stateWorker || service.actionWorker || service.operationPending
              || service.brightnessPending("DP-1")) return
          if (String(root.actionEnteredText).trim() !== "DP-1:70"
              || service.brightnessFor("DP-1").available !== true
              || service.brightnessFor("DP-1").stale !== false
              || service.brightnessFor("DP-1").current !== 70
              || service.brightnessError("DP-1") !== "")
          return root.fail("healthy recovery action did not confirm cleanly")
          console.log("Monitor brightness " + root.failureCase + " fixture passed")
          Qt.exit(0)
          return
        }

        if (root.phase === 4 && root.failureCase === "timeout") {
          if (service.stateWorker || service.actionWorker || service.operationPending
              || service.brightnessPending("DP-1")) return
          var timeoutAction = service.brightnessFor("DP-1")
          if (String(root.actionEnteredText).trim() !== "DP-1:70"
              || timeoutAction.available !== true || timeoutAction.stale !== false
              || timeoutAction.current !== 70 || service.brightnessError("DP-1") !== "")
            return root.fail("recovered timeout action did not confirm cleanly")
          console.log("Monitor brightness " + root.failureCase + " fixture passed")
          Qt.exit(0)
          return
        }
      } catch (error) {
        root.fail(error && error.message ? error.message : error)
      }
      if (root.checks >= 500) root.fail("failure handling barrier timed out")
    }
  }
}
