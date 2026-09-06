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
  property string stateLogText: ""
  property string actionLogText: ""
  property string workspaceLogText: ""
  property int phase: 0
  property bool sharedStateChecked: false
  property bool workspaceStateChecked: false
  property bool workspaceIncompleteChecked: false
  property bool replacementStateChecked: false
  property bool replacementCallbackChecked: false
  property bool actionRetainedDemand: false
  property bool actionChecked: false
  property bool brightnessReleaseChecked: false
  property bool brightnessReleaseDeferredChecked: false
  property bool brightnessConfirmationChecked: false
  property bool nativeRefreshChecked: false
  property bool sameServiceStaleIgnored: false
  property bool sameServiceRestartChecked: false
  property var replacementService: null
  property var replacementStateBeforeCallback: null
  property var stoppedStateWorker: null
  property bool initialLogsReloaded: false

  readonly property var nativeTopology: Model.normalizeMonitors(
    topologyGeneration >= 0 && Hyprland.monitors ? Hyprland.monitors.values : [], Hyprland.focusedMonitor)
  property int topologyGeneration: 0

  function refreshTopology() { topologyGeneration++ }

  function lines(text) {
    return String(text || "").split("\n").filter(function(line) { return line !== "" })
  }

  function sameState(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  }

  function checkBrightnessReleaseOrdering() {
    releaseService.lastBrightness = -1
    releaseService.operationPending = false
    releasePanel.brightnessPreviewPercent = releasePanel.brightnessPercent
    releaseSlider.dragging = true
    releaseSlider.liveValue = 75
    releaseSlider.moved(releaseSlider.liveValue)
    releaseSlider.releaseCurrentValue()
    return releaseService.lastBrightness === 75
      && releasePanel.brightnessPreviewPercent === 75
  }

  function fail(message) {
    console.error("Monitor shared fixture failed: " + String(message), root.phase,
      root.stateLogText, root.workspaceLogText, root.actionLogText)
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
        root.sharedStateChecked = monitorService.consumerCount === 2
          && monitorLeft.service === monitorRight.service
          && monitorService.brightnessPercent === 40
          && monitorService.hostname === "antoinews-linux"
          && monitorService.reconciliationGeneration === 1
          && root.lines(root.stateLogText).length === 1
        root.workspaceStateChecked = workspaceService.consumerCount === 2
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
        root.replacementStateChecked = root.replacementService.brightnessPercent === 80
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
            && monitorService.brightnessPercent === 40
            && monitorService.hardwareState.data.brightness.percent === 40
          if (!root.sameServiceStaleIgnored) return
          sameStateNewReleaseFile.setText("release\n")
          return
        }
        root.sameServiceRestartChecked = monitorService.hardwareState.data.brightness
          && monitorService.hardwareState.data.brightness.percent === 90
        if (!root.sameServiceRestartChecked) return
        if (!monitorService.collecting || monitorService.consumerCount !== 2) return
        actionModeFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        monitorService.setBrightness(75)
        root.brightnessConfirmationChecked = monitorService.brightnessPercent === 90
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
          && root.brightnessReleaseChecked && root.brightnessReleaseDeferredChecked
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
    function serviceFor(pluginId) { return pluginId === "desktop.monitor" ? releaseService : null }
  }

  QtObject {
    id: releaseService
    property int brightnessPercent: 40
    property var hardwareState: ({
      available: true,
      stale: false,
      data: {
        brightness: { available: true, percent: 40, device: "release-fixture" },
        keyboardBrightness: { available: false, percent: 0 }
      }
    })
    property bool operationPending: false
    property int consumerCount: 0
    property int lastBrightness: -1
    signal invalidated()
    function setConsumer(owner, details) { consumerCount++ }
    function removeConsumer(owner) { consumerCount = Math.max(0, consumerCount - 1) }
    function refresh() { return true }
    function refreshNativeMonitors(delayed) { return true }
    function setBrightness(value) {
      lastBrightness = Math.round(Number(value))
      operationPending = true
    }
    function setKeyboardBrightness(action) {}
    function runAction(args) {}
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

  PanelSlider {
    id: releaseSlider
    bar: releaseBar
    visible: false
    minimum: 1
    maximum: 100
    step: 1
    integer: true
    value: releasePanel.brightnessPreviewPercent
    onMoved: releasePanel.brightnessPreviewPercent = Math.round(liveValue)
    onDraggingChanged: releasePanel.handleBrightnessDraggingChanged(dragging)
    onReleased: function(value) { releasePanel.releaseBrightness(value) }
  }

  Monitor.Panel {
    id: releasePanel
    bar: releaseBar
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
