import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugins/panels/monitor/Model.js" as Model
import "plugins/panels/monitor" as Monitor
import "plugins/bar/widgets" as Workspace

Item {
  id: root
  property int topologyChanges: 0
  readonly property string stateLogPath: Quickshell.env("MONITOR_FIXTURE_STATE_LOG")
  readonly property string actionLogPath: Quickshell.env("MONITOR_FIXTURE_ACTION_LOG")
  readonly property string actionModePath: Quickshell.env("MONITOR_FIXTURE_ACTION_MODE")
  readonly property string actionReleasePath: Quickshell.env("MONITOR_FIXTURE_ACTION_RELEASE")
  readonly property string oldStateHoldPath: Quickshell.env("MONITOR_FIXTURE_OLD_STATE_HOLD")
  readonly property string oldStateReleasePath: Quickshell.env("MONITOR_FIXTURE_OLD_STATE_RELEASE")
  readonly property string oldStateOutputPath: Quickshell.env("MONITOR_FIXTURE_OLD_STATE_OUTPUT")
  readonly property string replacementStateOutputPath: Quickshell.env("MONITOR_FIXTURE_REPLACEMENT_STATE_OUTPUT")
  readonly property string stateModePath: Quickshell.env("MONITOR_FIXTURE_STATE_MODE")
  readonly property string sameStateOldHoldPath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_OLD_HOLD")
  readonly property string sameStateOldReleasePath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_OLD_RELEASE")
  readonly property string sameStateOldOutputPath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_OLD_OUTPUT")
  readonly property string sameStateNewHoldPath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_NEW_HOLD")
  readonly property string sameStateNewReleasePath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_NEW_RELEASE")
  readonly property string sameStateNewOutputPath: Quickshell.env("MONITOR_FIXTURE_SAME_STATE_NEW_OUTPUT")
  readonly property string workspaceLogPath: Quickshell.env("WORKSPACE_FIXTURE_LOG")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/monitor/fake-action")
    .toString().replace("file://", "")
  readonly property string fakeHostname: Qt.resolvedUrl("tests/fixtures/monitor/fake-hostname")
    .toString().replace("file://", "")
  readonly property string fakeWorkspaces: Qt.resolvedUrl("tests/fixtures/monitor/fake-workspaces")
    .toString().replace("file://", "")
  readonly property string fakeOldState: Qt.resolvedUrl("tests/fixtures/monitor/fake-state-old-service")
    .toString().replace("file://", "")
  readonly property string fakeReplacementState: Qt.resolvedUrl("tests/fixtures/monitor/fake-state-replacement")
    .toString().replace("file://", "")
  readonly property string fakeRestartState: Qt.resolvedUrl("tests/fixtures/monitor/fake-state-restart")
    .toString().replace("file://", "")
  readonly property bool windowSmokeEnabled: Quickshell.env("MONITOR_NATIVE_WINDOW_SMOKE") === "1"
  readonly property string releaseTopology: "4c05fc30acaebba57ab4c39415d88198f02eaacc232fc25b6b5e17bd8316ec90"
  readonly property string releaseEdidA: "00ffffffffffff000421111104030201011e0104801009780a0000000000000000000000000000000000000000000000000000000000010101010101010101010101010101010101000000fc004163657220583234335720200a000000ff000403020100000000000000000a3d4e5f708192a3b4c5d6e7f8091a2b3c4d5e00b5"
  readonly property string releaseEdidB: "00ffffffffffff000842222208070605011e0104801009780a0000000000000000000000000000000000000000000000000000000000010101010101010101010101010101010101000000fc00444953504c41592d422020200a000000ff000807060500000000000000000a5f708192a3b4c5d6e7f8091a2b3c4d5e6f800028"
  readonly property string releaseIdentityA: "015ccccd35030ddfd6877a55e25abf43378d3daf4f161a45be1afb1e75374b39"
  readonly property string releaseIdentityB: "13b3c77907272de8206d3701924fa98425edb5769afaf3f01d665592d62e588f"
  property string stateLogText: ""
  property string actionLogText: ""
  property string workspaceLogText: ""
  property int phase: 0
  property bool sharedStateChecked: false
  property bool workspaceStateChecked: false
  property bool workspaceWindowChecked: false
  property bool workspaceIncompleteChecked: false
  property bool replacementStateChecked: false
  property bool replacementCallbackChecked: false
  property bool actionRetainedDemand: false
  property bool actionChecked: false
  property bool brightnessReleaseChecked: false
  property bool brightnessReleaseDeferredChecked: false
  property bool liveSlidersChecked: false
  property int liveSliderPhase: 0
  property bool brightnessConfirmationChecked: false
  property bool nativeRefreshChecked: false
  property bool sameServiceStaleIgnored: false
  property bool sameServiceRestartChecked: false
  property var replacementService: null
  property var replacementStateBeforeCallback: null
  property var stoppedStateWorker: null
  property var workspaceSmokeWidgets: []
  property bool initialLogsReloaded: false

  readonly property var nativeTopology: Model.normalizeMonitors(
    topologyGeneration >= 0 && Hyprland.monitors ? Hyprland.monitors.values : [], Hyprland.focusedMonitor)
  property int topologyGeneration: 0

  function refreshTopology() { topologyGeneration++ }

  function registerWorkspaceSmokeWidget(widget) {
    if (!widget || root.workspaceSmokeWidgets.indexOf(widget) !== -1) return
    root.workspaceSmokeWidgets = root.workspaceSmokeWidgets.concat([widget])
  }

  function unregisterWorkspaceSmokeWidget(widget) {
    root.workspaceSmokeWidgets = root.workspaceSmokeWidgets.filter(function(item) { return item !== widget })
  }

  function workspaceWindowContext() {
    for (var i = 0; i < root.workspaceSmokeWidgets.length; i++) {
      var widget = root.workspaceSmokeWidgets[i]
      var window = widget ? widget.window : null
      if (!window || !window.screen) return { ready: false, error: "" }
      if (widget.screenName !== String(window.screen.name || ""))
        return { ready: false, error: "workspace widget lost its QsWindow screen association" }
      var ids = widget.workspaceIds()
      if (ids.length === 0)
        return { ready: false, error: "real workspace widget has no workspace buttons" }
    }
    return { ready: root.workspaceSmokeWidgets.length > 0, error: "" }
  }

  function lines(text) {
    return String(text || "").split("\n").filter(function(line) { return line !== "" })
  }

  function sameState(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  }

  function releaseRecord(connector, percent, edid, identity, bus) {
    return {
      connector: connector,
      backend: "ddc",
      available: true,
      stale: false,
      error: "",
      current: percent,
      maximum: 100,
      percent: percent,
      identity: identity,
      topology: root.releaseTopology,
      edid: edid,
      selector: { kind: "bus", value: bus }
    }
  }

  function checkBrightnessReleaseOrdering() {
    var displaySlider = releasePanel.displayBrightnessControl
    if (!displaySlider) return false
    releaseService.lastBrightness = -1
    releaseService.operationPending = false
    releasePanel.brightnessPreviewPercent = releasePanel.brightness.percent
    displaySlider.dragging = true
    displaySlider.liveValue = 75
    displaySlider.moved(displaySlider.liveValue)
    displaySlider.releaseCurrentValue()
    return releaseService.lastBrightness === 75
      && releasePanel.brightnessPreviewPercent === 75
  }

  function sameValues(actual, expected) {
    return JSON.stringify(actual) === JSON.stringify(expected)
  }

  function brightnessValues() {
    return releaseService.brightnessActions.map(function(action) { return action.percent })
  }

  function advanceLiveSliderCoverage() {
    var displaySlider = releasePanel.displayBrightnessControl
    var keyboardSlider = releasePanel.keyboardBrightnessControl
    if (!displaySlider || !keyboardSlider) {
      root.fail("merged monitor panel sliders are not accessible")
      return true
    }

    if (root.liveSliderPhase === 0) {
      releaseService.resetLiveActions()
      releaseService.publishState(40, 20, false)
      displaySlider.dragging = true
      displaySlider.liveValue = 60
      displaySlider.moved(displaySlider.liveValue)
      root.liveSliderPhase = 1
      return false
    }

    if (root.liveSliderPhase === 1) {
      if (releaseService.brightnessActions.length < 1) return false
      if (!sameValues(root.brightnessValues(), [60])
          || releaseService.brightnessActions[0].connector !== "DP-1"
          || releaseService.brightnessActions[0].identity !== root.releaseIdentityA
          || releasePanel.brightnessPreviewPercent !== 60
          || !releaseService.operationPending)
        root.fail("display live throttle did not submit the first value")
      releaseService.publishState(40, 20, true)
      if (releasePanel.brightnessPreviewPercent !== 60 || displaySlider.liveValue !== 60)
        root.fail("confirmed display state overwrote the drag preview")
      displaySlider.liveValue = 75
      displaySlider.moved(displaySlider.liveValue)
      displaySlider.releaseCurrentValue()
      root.liveSliderPhase = 2
      return false
    }

    if (root.liveSliderPhase === 2) {
      if (releaseService.brightnessActions.length < 2) return false
      if (!sameValues(root.brightnessValues(), [60, 75])
          || releaseService.brightnessActions[1].connector !== "DP-1"
          || releaseService.brightnessActions[1].identity !== root.releaseIdentityA
          || releasePanel.brightnessPreviewPercent !== 75)
        root.fail("display release did not submit the latest value after the live value")
      releaseService.publishState(40, 20, true)
      if (releasePanel.brightnessPreviewPercent !== 75)
        root.fail("pending display confirmation overwrote the release preview")
      releaseService.publishState(75, 20, false)
      if (releasePanel.brightnessPreviewPercent !== 75)
        root.fail("display preview did not reconcile after confirmation")
      releaseService.resetLiveActions()
      keyboardSlider.dragging = true
      keyboardSlider.liveValue = 30
      keyboardSlider.moved(keyboardSlider.liveValue)
      root.liveSliderPhase = 3
      return false
    }

    if (root.liveSliderPhase === 3) {
      if (releaseService.keyboardActions.length < 1) return false
      if (!sameValues(releaseService.keyboardActions, [30])
          || releasePanel.keyboardBrightnessPercent !== 30
          || !releaseService.operationPending)
        root.fail("keyboard live throttle did not submit the first value")
      releaseService.publishState(75, 20, true)
      if (releasePanel.keyboardBrightnessPercent !== 30 || keyboardSlider.liveValue !== 30)
        root.fail("confirmed keyboard state overwrote the drag preview")
      keyboardSlider.liveValue = 45
      keyboardSlider.moved(keyboardSlider.liveValue)
      keyboardSlider.releaseCurrentValue()
      root.liveSliderPhase = 4
      return false
    }

    if (releaseService.keyboardActions.length < 2) return false
    if (!sameValues(releaseService.keyboardActions, [30, 45])
        || releasePanel.keyboardBrightnessPercent !== 45)
      root.fail("keyboard release did not submit the latest value after the live value")
    releaseService.publishState(75, 45, false)
    if (releasePanel.keyboardBrightnessPercent !== 45)
      root.fail("keyboard preview did not reconcile after confirmation")
    root.liveSlidersChecked = true
    return true
  }

  function fail(message) {
    console.error("Monitor shared fixture failed: " + String(message), root.phase,
      root.stateLogText, root.workspaceLogText, root.actionLogText,
      JSON.stringify(monitorService.hardwareState),
      JSON.stringify(workspaceService.activeWorkspaceIds))
    Qt.exit(1)
  }

  function advance() {
    try {
      if (root.phase === 0) {
        if (!monitorService.hardwareState.available || !workspaceService.activeWorkspaceIds["eDP-1"])
          return
        if (!root.initialLogsReloaded) {
          stateLog.reload()
          workspaceLog.reload()
          root.initialLogsReloaded = true
          return
        }
        stateLog.reload()
        workspaceLog.reload()
        if (root.lines(root.stateLogText).length === 0 || root.lines(root.workspaceLogText).length === 0)
          return
        if (!root.windowSmokeEnabled)
          return root.fail("window-context smoke was not enabled")
        var workspaceContext = root.workspaceWindowContext()
        if (workspaceContext.error !== "") return root.fail(workspaceContext.error)
        if (!workspaceContext.ready) return
        root.workspaceWindowChecked = true
        root.sharedStateChecked = monitorService.consumerCount === 2
          && monitorLeft.service === monitorRight.service
          && monitorService.brightnessFor("DP-1").percent === 40
          && monitorService.hostname === "antoinews-linux"
          && monitorService.reconciliationGeneration === 1
          && root.lines(root.stateLogText).length === 1
        root.workspaceStateChecked = workspaceService.consumerCount === 2 + root.workspaceSmokeWidgets.length
          && workspaceService.activeWorkspaceIds["eDP-1"] === 4
          && workspaceService.activeWorkspaceIds["DP-1"] === 7
          && workspaceService.activeRefreshGeneration === 1
          && workspaceService.activeRefreshFinalizedGeneration === 1
          && root.lines(root.workspaceLogText).length === 1
        if (!root.sharedStateChecked || !root.workspaceStateChecked) return
        root.nativeRefreshChecked = monitorService.refreshNativeMonitors(true) === true
        if (!root.nativeRefreshChecked) {
          root.fail("monitor service did not own native refresh reconciliation")
          return
        }
        if (!root.brightnessReleaseChecked) {
          root.brightnessReleaseChecked = root.checkBrightnessReleaseOrdering()
          if (!root.brightnessReleaseChecked) {
            root.fail("brightness release submitted the confirmed value")
            return
          }
          return
        }
        if (!root.brightnessReleaseDeferredChecked) {
          root.brightnessReleaseDeferredChecked = releaseService.lastBrightness === 75
            && releasePanel.brightnessPreviewPercent === 75
          if (!root.brightnessReleaseDeferredChecked) {
            root.fail("deferred brightness reconciliation overwrote the submitted value")
            return
          }
          return
        }
        if (!root.liveSlidersChecked && !root.advanceLiveSliderCoverage()) return
        var previousMap = JSON.stringify(workspaceService.activeWorkspaceIds)
        root.workspaceIncompleteChecked = !workspaceService.applySnapshot("{}")
          && JSON.stringify(workspaceService.activeWorkspaceIds) === previousMap
        workspaceService.applySnapshot("[{\"name\":\"eDP-1\"}]")
        root.workspaceIncompleteChecked = root.workspaceIncompleteChecked
          && workspaceService.activeWorkspaceIds["eDP-1"] === 4
          && workspaceService.activeWorkspaceIds["DP-1"] === 7
        if (!root.workspaceIncompleteChecked) return
        oldStateHoldFile.setText("hold\n")
        oldConsumer.service = oldService
        root.phase = 1
        return
      }

      if (root.phase === 1) {
        if (!oldService.stateWorker || !oldService.stateWorker.running) return
        oldConsumer.service = null
        root.replacementService = replacementComponent.createObject(root)
        root.replacementService.shell = fakeShell
        root.replacementService.manifest = ({ id: "desktop.monitor" })
        root.replacementService.stateExecutable = root.fakeReplacementState
        root.replacementService.hostnameExecutable = root.fakeHostname
        root.replacementService.processStartGraceInterval = 50
        replacementConsumer.service = root.replacementService
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (!root.replacementService.hardwareState.available) return
        root.replacementStateChecked = root.replacementService.brightnessFor("DP-1").percent === 80
        root.replacementStateBeforeCallback = root.replacementService.hardwareState
        oldStateReleaseFile.setText("release\n")
        replacementConsumer.active = false
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        root.replacementCallbackChecked = sameState(
          root.replacementService.hardwareState, root.replacementStateBeforeCallback)
        if (!root.replacementStateChecked || !root.replacementCallbackChecked) return
        stateModeFile.setText("old\n")
        sameStateOldHoldFile.setText("hold\n")
        monitorService.refresh()
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        if (!monitorService.stateWorker || !monitorService.stateWorker.running) return
        root.stoppedStateWorker = monitorService.stateWorker
        monitorLeft.active = false
        monitorRight.active = false
        root.phase = 41
        return

      }

      if (root.phase === 41) {
        if (monitorService.collecting || monitorService.consumerCount !== 0) return
        if (monitorService.stateWorker) {
          root.fail("last monitor consumer did not cancel the held query")
          return
        }
        sameStateOldReleaseFile.setText("release\n")
        stateModeFile.setText("new\n")
        sameStateNewHoldFile.setText("hold\n")
        monitorLeft.active = true
        monitorRight.active = true
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (!root.sameServiceStaleIgnored) {
          if (!monitorService.stateWorker || !monitorService.stateWorker.running) return
          root.sameServiceStaleIgnored = monitorService.stateWorker !== root.stoppedStateWorker
            && monitorService.brightnessFor("DP-1").percent === 40
            && monitorService.brightnessFor("HDMI-1").percent === 60
          if (!root.sameServiceStaleIgnored) return
          sameStateNewReleaseFile.setText("release\n")
          return
        }
        root.sameServiceRestartChecked = monitorService.brightnessFor("DP-1").available === true
          && monitorService.brightnessFor("DP-1").percent === 90
        if (!root.sameServiceRestartChecked) return
        if (!monitorService.collecting || monitorService.consumerCount !== 2) return
        actionModeFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        if (monitorService.setBrightness("DP-1", 75) !== true)
          return root.fail("targeted brightness action was rejected")
        root.brightnessConfirmationChecked = monitorService.brightnessFor("DP-1").percent === 90
        actionModeFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        monitorService.setScale("DP-1", "1.25")
        monitorService.setLayout("single", "DP-1")
        root.phase = 6
        return
      }

      if (root.phase === 6) {
        if (!monitorService.actionWorker || !monitorService.actionWorker.running) return
        root.actionRetainedDemand = monitorService.operationPending
          && monitorService.consumerCount === 2
        monitorLeft.active = false
        monitorRight.active = false
        root.actionRetainedDemand = root.actionRetainedDemand
          && monitorService.consumerCount === 0 && monitorService.collecting
        actionReleaseFile.setText("release\n")
        root.phase = 7
        return
      }

      if (root.phase === 7) {
        actionLog.reload()
        var actions = root.lines(root.actionLogText)
        root.actionChecked = actions.indexOf("monitor set-scale DP-1 1.25") !== -1
          && actions.indexOf("monitor set-layout single DP-1") !== -1
        if (!root.actionChecked || monitorService.operationPending || monitorService.collecting) return
        var success = root.nativeTopology.monitors.length > 0 && root.sharedStateChecked
           && root.workspaceStateChecked && root.workspaceIncompleteChecked && root.replacementStateChecked
           && root.replacementCallbackChecked && root.sameServiceRestartChecked
           && root.workspaceWindowChecked
           && root.brightnessReleaseChecked && root.brightnessReleaseDeferredChecked
           && root.liveSlidersChecked
           && root.brightnessConfirmationChecked
           && root.actionRetainedDemand && root.actionChecked
        if (!success) root.fail("one or more shared ownership assertions failed")
        else {
          console.log("Monitor native topology fixture passed", root.nativeTopology.monitors.length,
            root.nativeTopology.focusedMonitor, root.topologyChanges)
          Qt.exit(0)
        }
      }
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }

  Connections {
    target: Hyprland.monitors
    function onValuesChanged() {
      root.topologyChanges++
      root.refreshTopology()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() {
      root.topologyChanges++
      root.refreshTopology()
    }
  }

  QtObject {
    id: fakeShell
    property bool previewMode: false
    function widgetSettingsFor(pluginId) { return ({}) }
    function serviceFor(pluginId) {
      if (pluginId === "desktop.monitor") return releaseService
      if (pluginId === "desktop.workspaces") return workspaceService
      return null
    }
  }

  QtObject {
    id: releaseService
    property int keyboardPercent: 0
    property bool operationPending: false
    property int consumerCount: 0
    property int lastBrightness: -1
    property var targetRecords: ({})
    property var pendingTargets: ({})
    property var errorTargets: ({})
    property var brightnessSnapshot: ({ version: 1, topology: root.releaseTopology, monitors: ({}) })
    property var hardwareState: ({ available: true, stale: false, data: ({}) })
    property var brightnessActions: []
    property var keyboardActions: []
    signal invalidated()
    function setConsumer(owner, details) { consumerCount++ }
    function removeConsumer(owner) { consumerCount = Math.max(0, consumerCount - 1) }
    function refresh() { return true }
    function refreshNativeMonitors(delayed) { return true }
    function notify() {
      brightnessSnapshot = { version: 1, topology: root.releaseTopology, monitors: targetRecords }
      var display = targetRecords["DP-1"]
      hardwareState = {
        available: true,
        stale: false,
        data: {
          brightness: display || { available: false, percent: null },
          keyboardBrightness: { available: keyboardPercent !== null, percent: keyboardPercent }
        }
      }
      operationPending = Object.keys(pendingTargets).length > 0
    }
    function resetTargets() {
      targetRecords = ({
        "DP-1": root.releaseRecord("DP-1", 40, root.releaseEdidA, root.releaseIdentityA, "3"),
        "HDMI-1": root.releaseRecord("HDMI-1", 60, root.releaseEdidB, root.releaseIdentityB, "4")
      })
      pendingTargets = ({})
      errorTargets = ({})
      keyboardPercent = 0
      notify()
    }
    function brightnessFor(connector) {
      return targetRecords[connector] || { connector: connector, available: false, stale: false,
        error: "Brightness unavailable", current: null, maximum: null, percent: null }
    }
    function brightnessPending(connector) { return pendingTargets[connector] === true }
    function brightnessError(connector) {
      return errorTargets[connector] || (brightnessFor(connector).error || "Brightness unavailable")
    }
    function resetLiveActions() {
      brightnessActions = []
      keyboardActions = []
      pendingTargets = ({})
      notify()
    }
    function publishState(displayValue, keyboardValue, pending) {
      var nextRecords = Object.assign({}, targetRecords)
      nextRecords["DP-1"] = Object.assign({}, brightnessFor("DP-1"), {
        available: true, stale: false, error: "", current: Math.round(Number(displayValue)),
        percent: Math.round(Number(displayValue))
      })
      targetRecords = nextRecords
      keyboardPercent = Math.round(Number(keyboardValue))
      var nextPending = Object.assign({}, pendingTargets)
      if (pending) nextPending["DP-1"] = true
      else delete nextPending["DP-1"]
      pendingTargets = nextPending
      notify()
      operationPending = pending
    }
    function setBrightness(connector, value) {
      var target = brightnessFor(connector)
      if (typeof connector !== "string" || typeof value !== "number" || !target.available) return false
      lastBrightness = Math.round(Number(value))
      brightnessActions = brightnessActions.concat([{
        connector: connector,
        percent: lastBrightness,
        identity: target.identity
      }])
      var nextPending = Object.assign({}, pendingTargets)
      nextPending[connector] = true
      pendingTargets = nextPending
      notify()
      return true
    }
    function setKeyboardBrightness(action) {
      keyboardActions = keyboardActions.concat([Math.round(Number(action))])
      operationPending = true
    }
    function runAction(args) {}
    Component.onCompleted: resetTargets()
  }

  QtObject {
    id: releaseBar
    property var shell: fakeShell
    property bool vertical: false
    property int barSize: 30
    property string fontFamily: Style.font.family
    property real fontSize: 12
    property int iconFontSize: 16
    property color barForeground: "white"
    property color foreground: "white"
    property color background: "black"
    property color activeColor: "white"
    property string position: "top"
    property int barH: 30
    property int barW: 30
    property bool foregroundAnimationEnabled: false
    property bool tooltipShown: false
    property var tooltipTarget: null
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function switchPanelFrom(panel, direction) { return false }
  }

  Monitor.Panel {
    id: releasePanel
    bar: releaseBar
    testBarMonitor: "DP-1"
    visible: false
  }

  Monitor.Service {
    id: monitorService
    shell: fakeShell
    manifest: ({ id: "desktop.monitor" })
    stateExecutable: root.fakeRestartState
    actionExecutable: root.fakeAction
    hostnameExecutable: root.fakeHostname
    processStartGraceInterval: 50
  }

  Workspace.WorkspaceService {
    id: workspaceService
    shell: fakeShell
    manifest: ({ id: "desktop.workspaces" })
    queryExecutable: root.fakeWorkspaces
    processStartGraceInterval: 50
  }

  Variants {
    model: root.windowSmokeEnabled ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: workspaceSmokeWindow
        required property var modelData

        screen: modelData
        visible: root.windowSmokeEnabled
        color: "transparent"
        implicitWidth: Math.max(1, workspaceSmokeWidget.implicitWidth)
        implicitHeight: Math.max(1, workspaceSmokeWidget.implicitHeight)

        Workspace.Workspaces {
          id: workspaceSmokeWidget
          anchors.fill: parent
          bar: releaseBar
          Component.onCompleted: root.registerWorkspaceSmokeWidget(workspaceSmokeWidget)
          Component.onDestruction: root.unregisterWorkspaceSmokeWidget(workspaceSmokeWidget)
        }
      }
    }
  }

  Monitor.Service {
    id: oldService
    shell: fakeShell
    manifest: ({ id: "desktop.monitor" })
    stateExecutable: root.fakeOldState
    hostnameExecutable: root.fakeHostname
    processStartGraceInterval: 50
  }

  Component {
    id: replacementComponent
    Monitor.Service { }
  }

  ServiceConsumer { id: monitorLeft; service: monitorService }
  ServiceConsumer { id: monitorRight; service: monitorService }
  ServiceConsumer { id: workspaceLeft; service: workspaceService }
  ServiceConsumer { id: workspaceRight; service: workspaceService }
  ServiceConsumer { id: oldConsumer; service: null }
  ServiceConsumer { id: replacementConsumer; service: null }

  FileView {
    id: stateLog
    path: root.stateLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.stateLogText = text()
  }

  FileView {
    id: actionLog
    path: root.actionLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.actionLogText = text()
  }

  FileView {
    id: workspaceLog
    path: root.workspaceLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.workspaceLogText = text()
  }

  FileView { id: oldStateHoldFile; path: root.oldStateHoldPath; printErrors: false }
  FileView { id: oldStateReleaseFile; path: root.oldStateReleasePath; printErrors: false }
  FileView { id: stateModeFile; path: root.stateModePath; printErrors: false }
  FileView { id: sameStateOldHoldFile; path: root.sameStateOldHoldPath; printErrors: false }
  FileView { id: sameStateOldReleaseFile; path: root.sameStateOldReleasePath; printErrors: false }
  FileView { id: sameStateNewHoldFile; path: root.sameStateNewHoldPath; printErrors: false }
  FileView { id: sameStateNewReleaseFile; path: root.sameStateNewReleasePath; printErrors: false }
  FileView { id: actionModeFile; path: root.actionModePath; printErrors: false }
  FileView { id: actionReleaseFile; path: root.actionReleasePath; printErrors: false }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: root.advance()
  }

  Timer {
    interval: 500
    repeat: false
    running: true
    onTriggered: Hyprland.refreshMonitors()
  }

  Timer {
    interval: 30000
    repeat: false
    running: true
    onTriggered: {
      root.fail("watchdog expired")
    }
  }
}
