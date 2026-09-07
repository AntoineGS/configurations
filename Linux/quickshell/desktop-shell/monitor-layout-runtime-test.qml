import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugins/panels/monitor" as Monitor

Item {
  id: root

  readonly property string stateExecutable: Quickshell.env("MONITOR_RUNTIME_STATE")
  readonly property string actionExecutable: Quickshell.env("MONITOR_RUNTIME_ACTION")
  readonly property string hostnameExecutable: Quickshell.env("MONITOR_RUNTIME_HOSTNAME")
  readonly property string stateModePath: Quickshell.env("MONITOR_RUNTIME_STATE_MODE")
  readonly property string stateReleasePath: Quickshell.env("MONITOR_RUNTIME_STATE_RELEASE")
  readonly property string stateEnteredPath: Quickshell.env("MONITOR_RUNTIME_STATE_ENTERED")
  readonly property string newStatePath: Quickshell.env("MONITOR_RUNTIME_NEW_STATE")
  readonly property string actionModePath: Quickshell.env("MONITOR_RUNTIME_ACTION_MODE")
  readonly property string actionReleasePath: Quickshell.env("MONITOR_RUNTIME_ACTION_RELEASE")
  readonly property string actionEnteredPath: Quickshell.env("MONITOR_RUNTIME_ACTION_ENTERED")
  readonly property string actionLogPath: Quickshell.env("MONITOR_RUNTIME_ACTION_LOG")
  property int phase: 0
  property int ticks: 0
  property int hotplugGeneration: -1
  property string actionLog: ""

  function fail(message) {
    console.error("Monitor layout runtime fixture failed:", message, "phase", phase,
      "fresh", service.monitorInventoryFresh, "pending", service.operationPending,
      "actionAvailable", service.monitorActionAvailable,
      "reconciling", service.operationState.reconciliationRunning,
      "reconcileQueued", service.operationState.reconciliationQueued,
      "generation", service.monitorInventoryAppliedGeneration, service.monitorInventoryGeneration,
      "error", service.actionError, "actions", actionLog)
    Qt.exit(1)
  }

  function logLines() {
    return actionLog.split("\n").filter(function(line) { return line !== "" })
  }

  QtObject {
    id: fakeShell
    property bool previewMode: false
    function widgetSettingsFor(pluginId) { return ({}) }
    function serviceFor(pluginId) { return pluginId === "desktop.monitor" ? service : null }
  }

  QtObject {
    id: fakeBar
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
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function switchPanelFrom(panel, direction) { return false }
  }

  Monitor.Service {
    id: service
    shell: fakeShell
    manifest: ({ id: "desktop.monitor" })
    stateExecutable: root.stateExecutable
    actionExecutable: root.actionExecutable
    hostnameExecutable: root.hostnameExecutable
    processStartGraceInterval: 50
  }

  Monitor.Panel {
    id: panel
    bar: fakeBar
    visible: false
  }

  ServiceConsumer { service: service }
  FileView { id: stateMode; path: root.stateModePath; printErrors: false }
  FileView { id: stateRelease; path: root.stateReleasePath; printErrors: false }
  FileView { id: newState; path: root.newStatePath; printErrors: false }
  FileView { id: actionMode; path: root.actionModePath; printErrors: false }
  FileView { id: actionRelease; path: root.actionReleasePath; printErrors: false }
  FileView {
    id: actionLogFile
    path: root.actionLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.actionLog = text()
    onFileChanged: reload()
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      root.advance()
      if (root.ticks > 700) root.fail("timed out")
    }
  }

  function advance() {
    try {
      if (phase === 0) {
        if (!service.monitorActionAvailable || panel.displayRows.length !== 2) return
        var disabled = panel.displayForMonitor("HDMI-A-1")
        if (!disabled || disabled.enabled || disabled.active) return fail("disabled inventory row was not retained")
        actionMode.setText("hold\n")
        actionRelease.setText("wait\n")
        if (!panel.toggleMonitor(disabled)) return fail("disabled inventory toggle was rejected")
        if (panel.toggleMonitor(disabled)) return fail("busy toggle was queued")
        phase = 1
        return
      }

      if (phase === 1) {
        if (!service.actionWorker || !service.operationPending) return
        if (!actionEnteredPath || !actionLogFile) return fail("action fixture unavailable")
        actionRelease.setText("release\n")
        phase = 2
        return
      }

      if (phase === 2) {
        if (service.operationPending || !service.monitorActionAvailable) return
        actionLogFile.reload()
        if (logLines().indexOf("monitor set-enabled HDMI-A-1 true") === -1) return
        actionMode.setText("fail\n")
        if (!service.setMonitorEnabled("HDMI-A-1", true, "")) return fail("fresh action unexpectedly rejected")
        phase = 3
        return
      }

      if (phase === 3) {
        if (service.operationPending) return
        if (service.actionError === "" || service.actionError.length > 240
            || service.actionError.indexOf("fixture failure") === -1)
          return fail("action failure was not bounded and reported")
        service.applyState('{"available":true,"stale":true,"data":{"monitors":[{"name":"eDP-1","enabled":true}]}}')
        if (service.monitorInventoryFresh || service.setLayout("all")) return fail("stale inventory allowed an action")
        actionMode.setText("ready\n")
        stateMode.setText("hold-old\n")
        stateRelease.setText("wait\n")
        service.refresh()
        phase = 4
        return
      }

      if (phase === 4) {
        if (!service.stateWorker || !service.stateWorker.running) return
        hotplugGeneration = service.monitorInventoryGeneration
        service.handleRawEvent({ name: "monitoradded" })
        if (service.monitorInventoryGeneration <= hotplugGeneration) return fail("hotplug did not invalidate inventory")
        stateMode.setText("ready\n")
        stateRelease.setText("release\n")
        phase = 5
        return
      }

      if (phase === 5) {
        if (service.operationPending || !service.monitorInventoryFresh
            || service.monitorInventoryAppliedGeneration !== service.monitorInventoryGeneration) return
        newState.setText('{"available":true,"stale":false,"data":{"monitors":[{"name":"eDP-1","enabled":true}]}}\n')
        service.refresh()
        phase = 6
        return
      }

      if (phase === 6) {
        if (service.operationPending || !service.monitorActionAvailable || service.monitorInventory.length !== 1) return
        if (!service.setLayout("only", "eDP-1")) return fail("Only action rejected after single inventory")
        phase = 7
        return
      }

      if (phase === 7) {
        if (service.operationPending || !service.monitorActionAvailable) return
        if (!service.setLayout("all")) return fail("Enable all action rejected after single inventory")
        phase = 8
        return
      }

      if (service.operationPending || !service.monitorInventoryFresh) return
      actionLogFile.reload()
      var actions = logLines()
      if (actions.indexOf("monitor set-layout only eDP-1") === -1
          || actions.indexOf("monitor set-layout all") === -1)
        return fail("generic actions were not executed")
      console.log("Monitor layout runtime fixture passed")
      Qt.exit(0)
    } catch (error) {
      fail(error && error.message ? error.message : error)
    }
  }
}
