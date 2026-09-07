import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/monitor" as Monitor

Item {
  id: root

  readonly property string stateModePath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_MODE") || ""
  readonly property string stateHoldPath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_HOLD") || ""
  readonly property string stateReleasePath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_RELEASE") || ""
  readonly property string stateFinalHoldPath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_FINAL_HOLD") || ""
  readonly property string stateFinalReleasePath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_FINAL_RELEASE") || ""
  readonly property string stateEnteredPath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_ENTERED") || ""
  readonly property string stateLogPath: Quickshell.env("MONITOR_BRIGHTNESS_STATE_LOG") || ""
  readonly property string actionModePath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_MODE") || ""
  readonly property string actionHoldPath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_HOLD") || ""
  readonly property string actionReleasePath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_RELEASE") || ""
  readonly property string actionEnteredPath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_ENTERED") || ""
  readonly property string actionLogPath: Quickshell.env("MONITOR_BRIGHTNESS_ACTION_LOG") || ""
  readonly property string fakeState: Qt.resolvedUrl("tests/fixtures/monitor-brightness/fake-state")
    .toString().replace("file://", "")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/monitor-brightness/fake-action")
    .toString().replace("file://", "")
  readonly property string fakeHostname: Qt.resolvedUrl("tests/fixtures/monitor/fake-hostname")
    .toString().replace("file://", "")
  readonly property bool panelScenario: Quickshell.env("MONITOR_BRIGHTNESS_SCENARIO") === "panel"
  readonly property bool budgetScenario: Quickshell.env("MONITOR_BRIGHTNESS_SCENARIO") === "budget"

  readonly property string oldTopology: "4c05fc30acaebba57ab4c39415d88198f02eaacc232fc25b6b5e17bd8316ec90"
  readonly property string newTopology: "36bd9a2d1c574957d5f82ba206180062053f13e120183d56b3eb60233c717185"
  readonly property string panelIdentityA: "015ccccd35030ddfd6877a55e25abf43378d3daf4f161a45be1afb1e75374b39"
  readonly property string panelIdentityB: "13b3c77907272de8206d3701924fa98425edb5769afaf3f01d665592d62e588f"
  readonly property string panelIdentityC: "c075d1fbb04102f6e00b541357d598fa79d4528d2d6546a6e7208155415463d9"
  property int phase: 0
  property int checks: 0
  property int panelPhase: 0
  property int panelChecks: 0
  property double panelMoveStartedAt: 0
  property double panelBlockedAttemptStartedAt: 0
  property var stoppedWorker: null
  property string stateEnteredText: ""
  property string actionEnteredText: ""
  property string stateLogText: ""
  property string actionLogText: ""
  property string stateModeText: ""
  property string stateHoldText: ""
  property string stateReleaseText: ""
  property string actionModeText: ""
  property string actionHoldText: ""
  property string actionReleaseText: ""
  property string expectedStateMode: ""
  property bool finalActionPrepared: false
  property bool mismatchStarted: false
  property bool mismatchActionReleased: false
  property bool mismatchStateReleased: false
  property bool cancelActionReleased: false
  property bool cancelStateReleased: false

  QtObject {
    id: fakeShell
    property bool previewMode: false
    function widgetSettingsFor(pluginId) { return ({}) }
    function serviceFor(pluginId) {
      return pluginId === "desktop.monitor" && root.panelScenario ? service : null
    }
  }

  Monitor.Service {
    id: service
    shell: fakeShell
    manifest: ({ id: "desktop.monitor" })
    stateExecutable: root.fakeState
    actionExecutable: root.fakeAction
    hostnameExecutable: root.fakeHostname
    processStartGraceInterval: 50
    processTimeoutInterval: root.budgetScenario ? 100 : 30000
    stateDiscoveryTimeoutInterval: root.budgetScenario ? 100 : 16000
    stateMonitorTimeoutInterval: root.budgetScenario ? 100 : 6000
    stateMonitorCountLimit: root.budgetScenario ? 8 : 8
    Component.onCompleted: {
      if (root.budgetScenario && "stateProcessTimeoutInterval" in service)
        service.stateProcessTimeoutInterval = 0
    }
  }

  ServiceConsumer { id: leftConsumer; service: service; active: !root.panelScenario }
  ServiceConsumer { id: rightConsumer; service: service; active: !root.panelScenario }

  QtObject {
    id: panelBar
    property var shell: fakeShell
    property bool vertical: false
    property int barSize: 30
    property string fontFamily: Style.font.family
    property real fontSize: 12
    property int iconFontSize: 16
    property int fontWeight: Font.Bold
    property color barForeground: "white"
    property color foreground: "white"
    property color background: "black"
    property color activeColor: "white"
    property string position: "top"
    property var activePopout: null
    property int barH: 30
    property int barW: 30
    property bool foregroundAnimationEnabled: false
    property bool tooltipShown: false
    property var tooltipTarget: null
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(target) {}
    function releasePopout(target) {}
    function switchPanelFrom(panel, direction) { return false }
  }

  PanelWindow {
    id: panelTestWindow
    screen: Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: root.panelScenario
    color: "transparent"
    implicitWidth: 1
    implicitHeight: 1

    Monitor.Panel {
      id: panelLeft
      anchors.fill: parent
      bar: panelBar
      testBarMonitor: "DP-1"
      visible: false
    }

    Monitor.Panel {
      id: panelRight
      anchors.fill: parent
      bar: panelBar
      testBarMonitor: "HDMI-1"
      visible: false
    }
  }

  FileView {
    id: stateModeFile
    path: root.stateModePath
    preload: true
    watchChanges: true
    printErrors: false
    onLoaded: root.stateModeText = text()
    onFileChanged: reload()
  }
  FileView {
    id: stateHoldFile
    path: root.stateHoldPath
    preload: true
    watchChanges: true
    printErrors: false
    onLoaded: root.stateHoldText = text()
    onFileChanged: reload()
  }
  FileView {
    id: stateReleaseFile
    path: root.stateReleasePath
    preload: true
    watchChanges: true
    printErrors: false
    onLoaded: root.stateReleaseText = text()
    onFileChanged: reload()
  }
  FileView {
    id: stateFinalHoldFile
    path: root.stateFinalHoldPath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: stateFinalReleaseFile
    path: root.stateFinalReleasePath
    preload: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  FileView {
    id: actionModeFile
    path: root.actionModePath
    preload: true
    watchChanges: true
    printErrors: false
    onLoaded: root.actionModeText = text()
    onFileChanged: reload()
  }
  FileView {
    id: actionHoldFile
    path: root.actionHoldPath
    preload: true
    watchChanges: true
    printErrors: false
    onLoaded: root.actionHoldText = text()
    onFileChanged: reload()
  }
  FileView {
    id: actionReleaseFile
    path: root.actionReleasePath
    preload: true
    watchChanges: true
    printErrors: false
    onLoaded: root.actionReleaseText = text()
    onFileChanged: reload()
  }

  FileView {
    id: stateEnteredFile
    path: root.stateEnteredPath
    preload: true
    watchChanges: true
    blockWrites: true
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

  FileView {
    id: stateLogFile
    path: root.stateLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.stateLogText = text()
    onFileChanged: reload()
  }

  FileView {
    id: actionLogFile
    path: root.actionLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.actionLogText = text()
    onFileChanged: reload()
  }

  function lines(value) {
    return String(value || "").split("\n").filter(function(line) { return line !== "" })
  }

  function stateLogEntry(mode, connector) {
    var entries = root.lines(root.stateLogText)
    var found = null
    for (var i = 0; i < entries.length; i++) {
      try {
        var entry = JSON.parse(entries[i])
        if (entry.mode === mode && entry.connector === connector) found = entry
      } catch (error) {
      }
    }
    return found
  }

  function fail(message) {
    console.error("Monitor brightness runtime fixture failed: " + String(message), root.phase,
      service.consumerCount, service.collecting, service.operationPending,
      service.stateWorker, service.actionWorker, service.topologyRefreshPending,
      service.queuedFullReconciliation, service.queuedReconciliationConnector,
      service.brightnessSnapshot, JSON.stringify(service.operationState),
      service.pendingConfirmationConnector, service.pendingConfirmationRecord,
      service.postActionPending, service.postActionReconciliationPending,
      root.mismatchStarted, root.mismatchActionReleased, root.mismatchStateReleased,
      JSON.stringify(service.brightnessFor("DP-1")), JSON.stringify(service.brightnessFor("HDMI-1")),
      root.stateLogText, root.actionLogText)
    Qt.exit(1)
  }

  function setStateMode(mode) {
    root.expectedStateMode = mode
    stateModeFile.setText(mode + "\n")
  }

  function setActionMode(mode) { actionModeFile.setText(mode + "\n") }
  function releaseState() { stateReleaseFile.setText("release\n") }
  function releaseAction() { actionReleaseFile.setText("release\n") }

  function controlText(file) { return String(file.text() || "").trim() }

  function queuePercent(index) {
    var args = service.operationState.actionQueue[index]
    return args && args.length === 4 ? String(args[2]) : ""
  }

  function activeConnector() {
    return service.activeActionTarget && service.activeActionTarget.connector
      ? String(service.activeActionTarget.connector) : ""
  }

  function panelActionEntries() {
    actionLogFile.reload()
    return root.lines(root.actionLogText)
  }

  function panelFail(message) {
    console.error("Monitor brightness panel fixture failed: " + String(message), root.panelPhase,
      root.panelChecks, service.consumerCount, service.operationPending,
      JSON.stringify(service.operationState), JSON.stringify(service.brightnessFor("DP-1")),
      JSON.stringify(service.brightnessFor("HDMI-1")), panelLeft.barMonitor, panelRight.barMonitor,
      panelLeft.brightnessActionable, panelRight.brightnessActionable,
      panelLeft.brightnessPreviewPercent, panelRight.brightnessPreviewPercent,
      JSON.stringify(panelLeft.brightness), JSON.stringify(panelRight.brightness), root.actionLogText)
    Qt.exit(1)
  }

  function advancePanel() {
    root.panelChecks++
    try {
      var leftSlider = panelLeft.displayBrightnessControl
      var rightSlider = panelRight.displayBrightnessControl
      if (!leftSlider || !rightSlider) return root.panelFail("real panel sliders are not accessible")
      if (panelLeft.monitorService !== service || panelRight.monitorService !== service)
        return root.panelFail("panel fixture did not use the real monitor service")

      if (root.panelPhase === 0) {
        var initialLeft = service.brightnessFor("DP-1")
        var initialRight = service.brightnessFor("HDMI-1")
        if (service.consumerCount !== 2 || initialLeft.available !== true || initialRight.available !== true
            || initialLeft.percent !== 40 || initialRight.percent !== 60
            || service.stateWorker || service.actionWorker || service.operationPending) return
        panelLeft.open()
        root.panelPhase = 1
        return
      }

      if (root.panelPhase === 1) {
        if (!panelLeft.opened || service.stateWorker || service.actionWorker || service.operationPending) return
        if (panelActionEntries().length !== 0) return root.panelFail("panel action log was not initially empty")
        root.panelMoveStartedAt = Date.now()
        leftSlider.dragging = true
        leftSlider.liveValue = 70
        leftSlider.moved(leftSlider.liveValue)
        root.panelPhase = 2
        return
      }

      if (root.panelPhase === 2) {
        var firstDelay = Date.now() - root.panelMoveStartedAt
        var firstActions = panelActionEntries()
        if (firstDelay < 80) {
          if (firstActions.length !== 0 || service.actionWorker)
            return root.panelFail("display live value dispatched before the 100 ms throttle")
          return
        }
        if (firstActions.length === 0) {
          if (firstDelay > 500) return root.panelFail("display live throttle did not dispatch")
          return
        }
        if (firstDelay > 500 || firstActions.length !== 1 || firstActions[0] !== "DP-1:70"
            || !service.actionWorker || !service.actionWorker.running || activeConnector() !== "DP-1"
            || service.activeActionTarget.identity !== root.panelIdentityA
            || panelLeft.brightnessPreviewPercent !== 70 || leftSlider.liveValue !== 70)
          return root.panelFail("display live throttle did not submit the captured first target")

        root.setStateMode("target-a-70")
        leftSlider.liveValue = 80
        leftSlider.moved(leftSlider.liveValue)
        leftSlider.releaseCurrentValue()
        root.panelPhase = 3
        return
      }

      if (root.panelPhase === 3) {
        var queuedActions = panelActionEntries()
        if (queuedActions.length !== 1 || !service.actionWorker || activeConnector() !== "DP-1"
            || service.operationState.actionQueue.length !== 1 || queuePercent(0) !== "80"
            || !service.brightnessPending("DP-1") || panelLeft.brightnessPreviewPercent !== 80)
          return
        releaseAction()
        root.panelPhase = 4
        return
      }

      if (root.panelPhase === 4) {
        var releasedActions = panelActionEntries()
        if (releasedActions.length < 2 || !service.actionWorker || !service.actionWorker.running) return
        if (releasedActions[0] !== "DP-1:70" || releasedActions[1] !== "DP-1:80"
            || activeConnector() !== "DP-1" || service.brightnessError("DP-1") !== ""
            || service.brightnessFor("DP-1").percent !== 70 || panelLeft.brightnessPreviewPercent !== 80
            || leftSlider.liveValue !== 80)
          return root.panelFail("queued release did not dispatch the latest display value")
        root.setStateMode("target-a-80")
        releaseAction()
        root.panelPhase = 5
        return
      }

      if (root.panelPhase === 5) {
        if (service.stateWorker || service.actionWorker || service.operationPending
            || service.brightnessPending("DP-1")) return
        if (service.brightnessFor("DP-1").percent !== 80 || service.brightnessError("DP-1") !== ""
            || panelLeft.brightnessPreviewPercent !== 80 || leftSlider.liveValue !== 80)
          return root.panelFail("display preview did not reconcile after confirmation")
        var untouchedRight = service.brightnessFor("HDMI-1")
        if (untouchedRight.available !== true || untouchedRight.percent !== 60
            || untouchedRight.identity !== root.panelIdentityB || service.brightnessError("HDMI-1") !== "")
          return root.panelFail("display action changed the unrelated HDMI-1 target")
        root.setStateMode("new-full")
        leftSlider.dragging = true
        leftSlider.liveValue = 85
        leftSlider.moved(leftSlider.liveValue)
        service.refresh()
        root.panelPhase = 6
        return
      }

      if (root.panelPhase === 6) {
        if (service.brightnessSnapshot.topology !== root.newTopology) return
        if (service.stateWorker || service.operationPending) return
        if (panelActionEntries().length !== 2 || service.brightnessFor("DP-1").identity !== root.panelIdentityC
            || panelLeft.brightnessPreviewPercent !== 85 || leftSlider.liveValue !== 85)
          return root.panelFail("topology change redirected or overwrote the active drag preview")
        leftSlider.releaseCurrentValue()
        root.panelPhase = 7
        return
      }

      if (root.panelPhase === 7) {
        if (panelLeft.brightnessPreviewPercent === 85) return
        if (panelActionEntries().length !== 2 || panelLeft.brightnessPreviewPercent !== 55
            || leftSlider.liveValue !== 55)
          return root.panelFail("invalidated drag did not reconcile after the deferred turn")
        root.setStateMode("initial")
        service.refresh()
        root.panelPhase = 8
        return
      }

      if (root.panelPhase === 8) {
        if (service.stateWorker || service.operationPending) return
        if (service.brightnessSnapshot.topology !== root.oldTopology
            || service.brightnessFor("DP-1").identity !== root.panelIdentityA
            || service.brightnessFor("DP-1").percent !== 40) return
        root.setActionMode("success")
        root.setStateMode("malformed-confirmation")
        leftSlider.dragging = true
        leftSlider.liveValue = 90
        leftSlider.moved(leftSlider.liveValue)
        root.panelMoveStartedAt = Date.now()
        root.panelPhase = 9
        return
      }

      if (root.panelPhase === 9) {
        var failureActions = panelActionEntries()
        if (failureActions.length < 3) {
          if (Date.now() - root.panelMoveStartedAt > 500)
            return root.panelFail("display failure action did not dispatch")
          return
        }
        if (failureActions[2] !== "DP-1:90" || service.stateWorker || service.actionWorker
            || service.operationPending) return
        var failedLeft = service.brightnessFor("DP-1")
        var healthyRight = service.brightnessFor("HDMI-1")
        if (failedLeft.available !== false || !failedLeft.stale || service.brightnessError("DP-1") === "")
          return root.panelFail("failed display did not expose its target error")
        if (healthyRight.available !== true || healthyRight.percent !== 60
            || panelRight.brightnessActionable !== true || panelRight.brightnessError !== ""
            || panelRight.brightnessPreviewPercent !== 60)
          return root.panelFail("DP-1 failure damaged HDMI-1 state or preview")
        if (!panelLeft.brightnessPopup.open || !panelLeft.brightnessPopup.visible
            || !panelLeft.brightnessUnavailableMessage.visible
            || panelLeft.brightnessUnavailableMessage.text !== panelLeft.brightnessError
            || panelLeft.brightnessValueLabel.visible || panelLeft.displayBrightnessControl.visible)
          return root.panelFail("unavailable display did not render only its reason text")
        root.panelBlockedAttemptStartedAt = Date.now()
        leftSlider.dragging = true
        leftSlider.liveValue = 95
        leftSlider.moved(leftSlider.liveValue)
        leftSlider.releaseCurrentValue()
        root.panelPhase = 10
        return
      }

      if (root.panelPhase === 10) {
        if (Date.now() - root.panelBlockedAttemptStartedAt < 150) return
        if (panelActionEntries().length !== 3 || service.actionWorker || service.stateWorker
            || service.operationPending || service.operationState.actionQueue.length !== 0)
          return root.panelFail("unavailable display accepted a moved or released value")
        root.setActionMode("success")
        root.setStateMode("target-b-20")
        rightSlider.dragging = true
        rightSlider.liveValue = 20
        rightSlider.moved(rightSlider.liveValue)
        rightSlider.releaseCurrentValue()
        root.panelPhase = 11
        return
      }

      if (root.panelPhase === 11) {
        var finalActions = panelActionEntries()
        if (finalActions.length < 4) {
          if (root.panelChecks > 500) return root.panelFail("healthy display action did not dispatch")
          return
        }
        if (finalActions[3] !== "HDMI-1:20" || service.stateWorker || service.actionWorker
            || service.operationPending || service.brightnessPending("HDMI-1")) return
        var finalRight = service.brightnessFor("HDMI-1")
        if (finalRight.available !== true || finalRight.percent !== 20
            || service.brightnessError("HDMI-1") !== "" || panelRight.brightnessActionable !== true
            || panelRight.brightnessPreviewPercent !== 20 || service.brightnessError("DP-1") === "")
          return root.panelFail("healthy display did not remain actionable after DP-1 failure")
        console.log("Monitor brightness panel fixture passed")
        panelLeft.close()
        panelRight.close()
        Qt.exit(0)
      }
    } catch (error) {
      root.panelFail(error && error.message ? error.message : error)
    }
    if (root.panelChecks >= 1500) root.panelFail("panel timing/target barrier timed out")
  }

  function advance() {
    if (root.panelScenario) return root.advancePanel()
    try {
      if (root.budgetScenario) {
        var budgetFirst = service.brightnessFor("DP-1")
        var budgetSecond = service.brightnessFor("HDMI-1")
        var budgetThird = service.brightnessFor("DP-2")
        if (root.phase === 0) {
          if (budgetFirst.available !== true || budgetSecond.available !== true || budgetThird.available !== true)
            return
          stateModeFile.setText("budget\n")
          root.phase = 1
          return
        }
        if (root.phase === 1) {
          if (String(stateModeFile.text() || "").trim() !== "budget") return
          service.refresh()
          root.phase = 2
          return
        }
        if (service.stateWorker || service.operationPending || budgetThird.available !== true) return
        if (service.hardwareState.stale === true || budgetThird.percent !== 55)
          return root.fail("three-external degraded budget did not complete a valid snapshot")
        console.log("Monitor brightness budget fixture passed")
        Qt.exit(0)
        return
      }
      if (root.phase === 0) {
        var first = service.brightnessFor("DP-1")
        var second = service.brightnessFor("HDMI-1")
        if (first.available !== true || second.available !== true) return
        if (first.percent !== 40 || second.percent !== 60)
          return root.fail("initial full snapshot was not published")
        if (service.runAction(["monitor", "set-display-brightness", "70", "not-json"]) !== false)
          return root.fail("malformed generic brightness action was accepted")
        if (service.operationState.actionQueue.length !== 0 || service.operationPending)
          return root.fail("malformed generic brightness action changed operation state")
        stateModeFile.setText("hold-old\n")
        stateHoldFile.setText("hold\n")
        stateReleaseFile.setText("wait\n")
        if (root.controlText(stateModeFile) !== "hold-old"
            || root.controlText(stateHoldFile) !== "hold"
            || root.controlText(stateReleaseFile) !== "wait") return
        service.refresh()
        root.phase = 1
        return
      }

      if (root.phase === 1) {
        if (String(root.stateEnteredText).trim() !== "held:hold-old") return
        root.stoppedWorker = service.stateWorker
        root.setStateMode("cancel-a-65")
        actionModeFile.setText("hold\n")
        actionHoldFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        if (service.setBrightness("DP-1", 65) !== true)
          return root.fail("queued action behind routine read was rejected")
        leftConsumer.active = false
        rightConsumer.active = false
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (service.consumerCount !== 0) return
        if (root.stoppedWorker && service.stateWorker === root.stoppedWorker)
          return root.fail("routine read retained demand after the last consumer left")
        if (!root.cancelActionReleased) {
          if (!service.actionWorker || !service.actionWorker.running || activeConnector() !== "DP-1") return
          releaseAction()
          root.cancelActionReleased = true
          return
        }
        if (!root.cancelStateReleased) {
          if (!service.stateWorker || !service.stateWorker.running
              || String(service.stateWorker.requestedConnector) !== "DP-1") return
          if (String(root.stateEnteredText).trim() !== "held:cancel-a-65") return
          releaseState()
          root.cancelStateReleased = true
          return
        }
        if (service.stateWorker || service.operationPending) return
        if (service.brightnessFor("DP-1").percent !== 65)
          return root.fail("cancelled routine read did not complete bounded action confirmation")
        stateModeFile.setText("restart-old\n")
        stateHoldFile.setText("hold\n")
        stateReleaseFile.setText("wait\n")
        leftConsumer.active = true
        rightConsumer.active = true
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        if (!service.stateWorker || !service.stateWorker.running || service.stateWorker === root.stoppedWorker)
          return
        if (service.brightnessFor("DP-1").percent !== 65)
          return root.fail("restarted worker published a stale canceled callback")
        releaseState()
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        if (service.brightnessFor("DP-1").percent !== 45 || service.brightnessFor("HDMI-1").percent !== 65)
          return
        stateModeFile.setText("target-a-70\n")
        stateHoldFile.setText("hold\n")
        stateReleaseFile.setText("wait\n")
        actionModeFile.setText("hold\n")
        actionHoldFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        var alteredTarget = service.brightnessFor("DP-1")
        alteredTarget.current = 1
        alteredTarget.percent = 1
        if (service.runAction(["monitor", "set-display-brightness", "70", JSON.stringify(alteredTarget)]) !== true)
          return root.fail("valid targeted request was rejected")
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (!service.actionWorker || !service.actionWorker.running || activeConnector() !== "DP-1") return
        if (service.activeActionTarget.current !== 45 || service.activeActionTarget.percent !== 45)
          return root.fail("generic brightness action forwarded an altered target record")
        if (service.refresh() !== true)
          return root.fail("full refresh request was rejected while an action was active")
        if (service.setBrightness("DP-1", 80) !== true || service.setBrightness("HDMI-1", 30) !== true
            || service.setBrightness("HDMI-1", 20) !== true)
          return root.fail("rapid targeted requests were not accepted")
        if (service.operationState.actionQueue.length !== 2
            || queuePercent(0) !== "80" || queuePercent(1) !== "20"
            || !service.brightnessPending("DP-1") || !service.brightnessPending("HDMI-1"))
          return root.fail("target queue did not retain one latest value per monitor")
        releaseAction()
        root.phase = 6
        return
      }

      if (root.phase === 6) {
        if (!service.stateWorker || !service.stateWorker.running
            || String(service.stateWorker.requestedConnector) !== "")
          return root.fail("queued post-action refresh was not a full read")
        if (String(root.stateEnteredText).trim() !== "held:target-a-70") return
        if (root.controlText(stateModeFile) !== "target-a-80") {
          root.setStateMode("target-a-80")
          actionHoldFile.setText("hold\n")
          actionReleaseFile.setText("wait\n")
          return
        }
        if (root.controlText(actionReleaseFile) !== "wait") return
        releaseState()
        root.phase = 7
        return
      }

      if (root.phase === 7) {
        if (service.brightnessFor("DP-1").percent !== 70 || activeConnector() !== "DP-1"
            || String(root.actionEnteredText).trim() !== "DP-1:80") return
        if (service.pendingConfirmationConnector !== "")
          return root.fail("full post-action read left a stale confirmation reservation")
        stateModeFile.setText("target-a-80\n")
        stateHoldFile.setText("hold\n")
        stateReleaseFile.setText("wait\n")
        if (!service.actionWorker || !service.actionWorker.running) return
        releaseAction()
        root.phase = 8
        return
      }

      if (root.phase === 8) {
        if (!service.stateWorker || !service.stateWorker.running
            || String(service.stateWorker.requestedConnector) !== "DP-1") return
        if (String(root.stateEnteredText).trim() !== "held:target-a-80") return
        actionHoldFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        releaseState()
        root.phase = 9
        return
      }

      if (root.phase === 9) {
        if (service.brightnessFor("HDMI-1").available !== true)
          return root.fail("targeted partial read dropped the unrelated monitor")
        if (service.brightnessFor("DP-1").percent !== 80 || activeConnector() !== "HDMI-1"
            || String(root.actionEnteredText).trim() !== "HDMI-1:20") return
        var targetA80Read = root.stateLogEntry("target-a-80", "DP-1")
        if (!targetA80Read) return
        if (targetA80Read.previous.topology !== root.oldTopology
            || targetA80Read.previous.monitors["DP-1"].percent !== 70
            || targetA80Read.previous.monitors["HDMI-1"].percent !== 60)
          return root.fail("target-a-80 read did not receive the unchanged prior snapshot")
        if (root.controlText(stateModeFile) !== "target-b-20") {
          root.setStateMode("target-b-20")
          stateHoldFile.setText("hold\n")
          stateReleaseFile.setText("wait\n")
          return
        }
        releaseAction()
        root.phase = 10
        return
      }

      if (root.phase === 10) {
        if (!service.stateWorker || !service.stateWorker.running
            || String(service.stateWorker.requestedConnector) !== "HDMI-1") return
        if (String(root.stateEnteredText).trim() !== "held:target-b-20") return
        var targetA80Read = root.stateLogEntry("target-a-80", "DP-1")
        var targetB20Read = root.stateLogEntry("target-b-20", "HDMI-1")
        if (!targetA80Read || !targetB20Read) return
        if (targetB20Read.previous.topology !== root.oldTopology
            || targetB20Read.previous.monitors["DP-1"].percent !== 80
            || targetB20Read.previous.monitors["HDMI-1"].percent !== 60)
          return root.fail("target-b-20 read did not receive the unchanged prior snapshot")
        if (JSON.stringify(targetA80Read.previous) === JSON.stringify(targetB20Read.previous))
          return root.fail("successive targeted reads reused an indistinct previous snapshot")
        releaseState()
        root.phase = 11
        return
      }

      if (root.phase === 11) {
        if (!root.mismatchStarted) {
          if (service.brightnessFor("DP-1").percent !== 80 || service.brightnessFor("HDMI-1").percent !== 20)
            return
          if (service.operationPending || service.brightnessPending("DP-1") || service.brightnessPending("HDMI-1"))
            return
          root.setStateMode("mismatch-a-75")
          stateHoldFile.setText("hold\n")
          stateReleaseFile.setText("wait\n")
          actionModeFile.setText("hold\n")
          actionHoldFile.setText("hold\n")
          actionReleaseFile.setText("wait\n")
          if (service.setBrightness("DP-1", 90) !== true)
            return root.fail("confirmation mismatch setup request was rejected")
          root.mismatchStarted = true
          return
        }
        if (!root.mismatchActionReleased) {
          if (!service.actionWorker || !service.actionWorker.running || activeConnector() !== "DP-1"
              || String(root.actionEnteredText).trim() !== "DP-1:90") return
          releaseAction()
          root.mismatchActionReleased = true
          return
        }
        if (!root.mismatchStateReleased) {
          if (!service.stateWorker || !service.stateWorker.running
              || String(service.stateWorker.requestedConnector) !== "DP-1") return
          if (String(root.stateEnteredText).trim() !== "held:mismatch-a-75") return
          releaseState()
          root.mismatchStateReleased = true
          return
        }
        if (service.stateWorker || service.operationPending) return
        var mismatch = service.brightnessFor("DP-1")
        if (mismatch.available !== true || mismatch.percent !== 75)
          return root.fail("mismatched confirmation replaced the fresh hardware record")
        if (service.brightnessError("DP-1") === "")
          return root.fail("mismatched confirmation did not publish an error")
        stateModeFile.setText("changed-a-55\n")
        stateHoldFile.setText("hold\n")
        stateReleaseFile.setText("wait\n")
        actionModeFile.setText("hold\n")
        actionHoldFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        if (service.setBrightness("DP-1", 55) !== true || service.setBrightness("HDMI-1", 25) !== true)
          return root.fail("topology barrier setup request was rejected")
        root.phase = 12
        return
      }

      if (root.phase === 12) {
        if (!service.actionWorker || !service.actionWorker.running || activeConnector() !== "DP-1"
            || String(root.actionEnteredText).trim() !== "DP-1:55") return
        releaseAction()
        root.phase = 13
        return
      }

      if (root.phase === 13) {
        if (!service.stateWorker || !service.stateWorker.running
            || String(service.stateWorker.requestedConnector) !== "DP-1") return
        if (String(root.stateEnteredText).trim() !== "held:changed-a-55") return
        if (root.controlText(stateModeFile) !== "new-full") {
          root.setStateMode("new-full")
          return
        }
        stateHoldFile.setText("wait\n")
        releaseState()
        root.phase = 14
        return
      }

      if (root.phase === 14) {
        if (service.brightnessSnapshot.topology !== root.newTopology) return
        if (service.brightnessPending("HDMI-1") || service.brightnessError("HDMI-1") === "")
          return root.fail("queued old topology target was not rejected")
        if (root.lines(root.actionLogText).indexOf("HDMI-1:25") !== -1)
          return root.fail("stale queued target reached the action helper")
        if (!service.operationPending) {
          if (!root.finalActionPrepared) {
            root.setStateMode("target-a-95")
            actionModeFile.setText("osd-fail\n")
            actionHoldFile.setText("hold\n")
            actionReleaseFile.setText("wait\n")
            root.finalActionPrepared = true
            return
          }
          if (service.setBrightness("DP-1", 95) !== true)
            return root.fail("accepted action was rejected after topology refresh")
          root.phase = 15
        }
        return
      }

      if (root.phase === 15) {
        if (!service.actionWorker || !service.actionWorker.running || activeConnector() !== "DP-1"
            || String(root.actionEnteredText).trim() !== "DP-1:95") return
        leftConsumer.active = false
        rightConsumer.active = false
        if (!service.collecting || !service.operationPending)
          return root.fail("accepted action did not retain bounded demand")
        releaseAction()
        root.phase = 16
        return
      }

      if (root.phase === 16) {
        if (!service.stateWorker || !service.stateWorker.running
            || String(service.stateWorker.requestedConnector) !== "DP-1") return
        if (String(root.stateEnteredText).trim() !== "held:target-a-95") return
        releaseState()
        stateFinalReleaseFile.setText("release\n")
        root.phase = 17
        return
      }

      if (root.phase === 17) {
        var confirmed = service.brightnessFor("DP-1")
        if (confirmed.percent !== 95 || confirmed.available !== true) return
        if (service.brightnessError("DP-1") !== "OSD delivery failed")
          return root.fail("OSD-only failure did not preserve confirmed hardware data")
        if (service.collecting || service.operationPending || service.stateWorker) return
        if (root.lines(root.actionLogText).length < 4)
          return root.fail("action temporal barrier log is incomplete")
        console.log("Monitor brightness runtime fixture passed")
        Qt.exit(0)
      }
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      if (root.panelScenario) {
        root.advance()
        if (root.panelChecks >= 1500) root.panelFail("panel timing/target barrier timed out")
      } else {
        root.checks++
        root.advance()
        if (root.checks >= 1500) root.fail("readiness/completion barrier timed out")
      }
    }
  }
}
