import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/vm"

Item {
  id: root
  property string fixtureStatePath: Quickshell.env("VM_FIXTURE_STATE_PATH")
    || Qt.resolvedUrl("tests/fixtures/vm/state-mode")
  property string watcherModePath: Quickshell.env("VM_FIXTURE_WATCHER_MODE")
    || Qt.resolvedUrl("tests/fixtures/vm/watcher-mode")
  property string fakeVirsh: Qt.resolvedUrl("tests/fixtures/vm/fake-virsh").toString().replace("file://", "")
  property string fakeState: Qt.resolvedUrl("tests/fixtures/vm/fake-state").toString().replace("file://", "")
  property string fakeStateOldService: Qt.resolvedUrl("tests/fixtures/vm/fake-state-old-service")
    .toString().replace("file://", "")
  property bool sawRunning: false
  property bool sawStopped: false
  property bool sawStale: false
  property bool sawMultiple: false
  property bool installed: false
  property bool sawWatcherStop: false
  property bool forceWatcherStartFailure: false
  property int checks: 0
  property bool sawUtilization: false
  property bool sawReconciliation: false
  property bool sawStartupPhase: false
  property bool sawSteadyPhase: false
  property int watcherStartEvents: 0
  property int reconciliationStartEvents: 0
  property int popupRefreshBaseline: 0
  property bool collectionStopStarted: false
  property bool sawCollectionStop: false
  property bool sawCollectionRestart: false
  property bool collectionRestartReady: false
  property bool sawLateVmIgnored: false
  property var stateBeforeCollectionStop: null
  property int stoppedCollectionGeneration: 0
  property var stoppedStateWorker: null
  property var stoppedWatcherWorker: null
  property bool collectionStopArmed: false
  property bool sharedWatcherStarted: false
  property bool sharedStateObserved: false
  property bool sharedConsumersDetached: false
  property int sharedWatcherStartEvents: 0
  readonly property string actionModePath: Quickshell.env("VM_FIXTURE_ACTION_MODE")
  readonly property string actionReleasePath: Quickshell.env("VM_FIXTURE_ACTION_RELEASE")
  readonly property string stateHoldPath: Quickshell.env("VM_FIXTURE_STATE_HOLD")
  readonly property string oldServiceStatePath: Quickshell.env("VM_FIXTURE_OLD_SERVICE_STATE")
  readonly property string oldServiceStateHoldPath: Quickshell.env("VM_FIXTURE_OLD_SERVICE_STATE_HOLD")
  readonly property string fakeStateReplacement: Qt.resolvedUrl("tests/fixtures/vm/fake-state-replacement")
    .toString().replace("file://", "")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/vm/fake-action").toString().replace("file://", "")
  property int actionPhase: 0
  property bool actionInvalidChecked: false
  property bool actionBusyChecked: false
  property bool actionConsumersRemoved: false
  property bool actionFinalReconciliationSeen: false
  property bool actionSuccessSeen: false
  property bool actionExitRequested: false
  property bool actionExitFailureSeen: false
  property bool actionStartRequested: false
  property bool actionStartFailureSeen: false
  property bool actionRetainedStateRejected: false
  property var replacementService: null
  property bool serviceReplacementReady: false
  property bool oldServiceActionAccepted: false
  property bool oldServiceConsumerDetached: false
  property bool oldServiceDestroyed: false
  property bool serviceInvalidated: false
  property bool oldServiceStateHoldStarted: false
  property var oldServiceObject: null
  property bool obsoleteCallbackDelivered: false
  property var replacementStateBeforeObsoleteCallback: null
  property bool serviceReplacementCallbackChecked: false

  function sameState(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  }

  function startServiceReplacement() {
    if (replacementService) return
    replacementService = replacementComponent.createObject(root)
    replacementService.shell = fakeShell
    replacementService.manifest = ({ id: "desktop.vm" })
    replacementService.virshExecutable = fakeVirsh
    replacementService.stateHelperExecutable = fakeStateReplacement
    replacementService.capabilityProbeInterval = 100
    replacementService.startupReconciliationInterval = 100
    replacementService.steadyReconciliationInterval = 300
    replacementService.stabilityInterval = 200
    replacementService.utilizationInterval = 100
    replacementService.processStartGraceInterval = 50
    replacementService.actionExecutable = fakeAction
    var oldService = vmService
    oldServiceObject = oldService
    vmRight.service = null
    oldServiceConsumerDetached = oldService.consumerCount === 0
    vmRight.service = replacementService
  }

  function prepareServiceReplacement() {
    if (oldServiceActionAccepted) return
    actionModeFile.setText("hold\n")
    actionReleaseFile.setText("wait\n")
    watcherModeFile.setText("stable\n")
    oldServiceActionTimer.start()
  }

  function finish() {
    var success = sawRunning && sawStopped && sawStale && sawMultiple && sawUtilization
      && sawReconciliation && sawStartupPhase && sawSteadyPhase
      && watcherStartEvents >= 1 && reconciliationStartEvents >= 4
      && sawCollectionStop && sawCollectionRestart && sawLateVmIgnored
      && sharedWatcherStarted && sharedStateObserved && sharedConsumersDetached
      && sharedWatcherStartEvents >= 1
      && actionInvalidChecked && actionBusyChecked && actionConsumersRemoved
      && actionFinalReconciliationSeen && actionSuccessSeen
      && actionExitFailureSeen && actionStartFailureSeen && actionRetainedStateRejected
      && serviceReplacementReady && serviceInvalidated && oldServiceDestroyed
      && oldServiceConsumerDetached && oldServiceActionAccepted
      && serviceReplacementCallbackChecked
    modeFile.setText("running-missing\n")
    watcherModeFile.setText("stable\n")
    if (!success) console.error("VmMonitor fixture failed", sawRunning, sawStopped, sawStale, sawMultiple,
      sawUtilization, sawReconciliation, watcherStartEvents, reconciliationStartEvents,
      monitor.capabilityAvailable, monitor.watcherRunning, monitor.reconciliationRunning,
      sawCollectionStop, sawCollectionRestart, sawLateVmIgnored,
      sharedWatcherStarted, sharedStateObserved, sharedConsumersDetached, sharedWatcherStartEvents,
      actionInvalidChecked, actionBusyChecked, actionConsumersRemoved,
      actionFinalReconciliationSeen, actionSuccessSeen, actionExitFailureSeen, actionStartFailureSeen,
      actionRetainedStateRejected,
      serviceReplacementReady,
      actionPhase, oldServiceActionAccepted, oldServiceConsumerDetached, oldServiceDestroyed,
      serviceInvalidated, serviceReplacementCallbackChecked,
      root.replacementService ? root.replacementService.consumerCount : -1,
      root.replacementService ? root.replacementService.watcherRunning : false,
      root.replacementService ? root.replacementService.state.available : false,
      root.replacementService ? root.replacementService.state.confirmedRunning : false,
      root.replacementService ? root.replacementService.state.stale : false,
      root.replacementService ? root.replacementService.state.error : "",
      root.replacementService ? root.replacementService.reconciliationRunning : false,
      root.replacementService ? root.replacementService.collecting : false,
      vmRight.service === root.replacementService,
      root.oldServiceDestroyed ? false : vmService.watcherRunning,
      root.oldServiceDestroyed ? false : vmService.state.available,
      root.oldServiceDestroyed ? false : vmService.state.stale,
      root.oldServiceDestroyed ? false : vmService.state.canResize,
      root.oldServiceDestroyed ? false : vmService.reconciliationRunning,
      root.oldServiceDestroyed ? "" : vmService.actionError)
    else console.log("VmMonitor fake-process fixture passed")
    Qt.exit(success ? 0 : 1)
  }

  VmMonitor {
    id: monitor
    collecting: true
    virshExecutable: installed && !root.forceWatcherStartFailure ? root.fakeVirsh : root.fakeVirsh + ".missing"
    stateHelperExecutable: root.fakeState
    capabilityProbeInterval: 100
    startupReconciliationInterval: 100
    steadyReconciliationInterval: 300
    stabilityInterval: 200
    utilizationInterval: 100
    processStartGraceInterval: 50
    onStateChanged: {
      if (state.confirmedRunning) root.sawRunning = true
      if (!state.available && !state.stale) root.sawStopped = true
      if (state.stale && state.error === "fixture stale") root.sawStale = true
      if (state.error === "more than one running VM was found") root.sawMultiple = true
    }
  }

  QtObject {
    id: fakeShell
    property bool previewMode: false

    function widgetSettingsFor(pluginId) { return ({}) }

    function serviceFor(pluginId) {
      return String(pluginId) === "desktop.host-metrics" ? fakeHostService : null
    }
  }

  SharedService {
    id: fakeHostService
    shell: fakeShell
    manifest: ({ id: "desktop.host-metrics" })
    property var cpuState: ({ available: true, percent: 10 })
    property var memoryState: ({ available: true, percent: 20 })
  }

  Service {
    id: vmService
    shell: fakeShell
    manifest: ({ id: "desktop.vm" })
    virshExecutable: root.fakeVirsh
    stateHelperExecutable: root.fakeStateOldService
    capabilityProbeInterval: 100
    startupReconciliationInterval: 100
    steadyReconciliationInterval: 300
    stabilityInterval: 200
    utilizationInterval: 100
    processStartGraceInterval: 50
    actionExecutable: root.fakeAction
  }

  Component {
    id: replacementComponent

    Service { }
  }

  ServiceConsumer {
    id: vmLeft
    service: vmService
    details: true
  }

  ServiceConsumer {
    id: vmRight
    service: vmService
    details: true
  }

  Connections {
    target: vmService

    function onInvalidated() {
      root.serviceInvalidated = true
    }

    function onResizePendingChanged() {
      if (root.serviceReplacementReady && root.oldServiceActionAccepted && !vmService.resizePending)
        root.obsoleteCallbackDelivered = true
    }

    function onWatcherRunningChanged() {
      if (vmService.watcherRunning) root.sharedWatcherStartEvents++
    }

    function onStateChanged() {
      if (!vmService.state || !vmService.state.available) return
      if (vmLeft.service === vmRight.service)
        root.sharedStateObserved = vmLeft.service.state === vmRight.service.state
      if (root.actionPhase === 4 && !root.actionRetainedStateRejected
          && vmService.watcherRunning && vmService.state.canResize)
        root.actionRetainedStateRejected = !vmService.requestMemory(1)
    }

    function onReconciliationRunningChanged() {
      if (root.actionPhase === 3 && vmService.resizePending && vmService.actionReconciliationStarted)
        root.actionFinalReconciliationSeen = true
    }
  }

  Connections {
    target: monitor
    function onWatcherRunningChanged() {
      if (monitor.watcherRunning) root.watcherStartEvents++
    }
    function onReconciliationRunningChanged() {
      if (monitor.reconciliationRunning) root.reconciliationStartEvents++
    }
  }

  FileView {
    id: modeFile
    path: root.fixtureStatePath
    preload: false
    printErrors: false
    blockWrites: false
  }

  FileView {
    id: watcherModeFile
    path: root.watcherModePath
    preload: false
    printErrors: false
    blockWrites: false
  }

  FileView {
    id: actionModeFile
    path: root.actionModePath
    preload: false
    printErrors: false
    blockWrites: false
  }

  FileView {
    id: actionReleaseFile
    path: root.actionReleasePath
    preload: false
    printErrors: false
    blockWrites: false
  }

  FileView {
    id: stateHoldFile
    path: root.stateHoldPath
    preload: false
    printErrors: false
    blockWrites: false
  }

  FileView {
    id: oldServiceStateHoldFile
    path: root.oldServiceStateHoldPath
    preload: false
    printErrors: false
    blockWrites: false
  }

  Timer {
    id: replacementCallbackCheckTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (root.replacementService)
        root.serviceReplacementCallbackChecked = root.sameState(root.replacementService.state,
          root.replacementStateBeforeObsoleteCallback)
    }
  }

  Timer {
    id: oldServiceActionTimer
    interval: 50
    repeat: true
    onTriggered: {
      if (root.actionPhase !== 7 || root.oldServiceActionAccepted) {
        stop()
        return
      }
      if (!root.oldServiceStateHoldStarted && vmService.watcherRunning && vmService.state.canResize) {
        oldServiceStateHoldFile.setText("hold\n")
        root.oldServiceStateHoldStarted = true
        return
      }
      if (!root.oldServiceStateHoldStarted) return
      root.oldServiceActionAccepted = vmService.requestMemory(1)
      if (root.oldServiceActionAccepted) {
        stop()
        vmService.refreshNow()
      }
    }
  }

  Timer {
    interval: 200
    repeat: false
    running: true
    onTriggered: {
      root.installed = true
      Qt.callLater(function() { monitor.probeNow() })
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      root.sawUtilization = root.sawUtilization || monitor.utilizationRunning
      root.sawReconciliation = root.sawReconciliation || monitor.reconciliationRunning
        || reconciliationStartEvents > 0
      root.sawStartupPhase = root.sawStartupPhase || monitor.monitorState.startupPhase
      root.sawSteadyPhase = root.sawSteadyPhase || !monitor.monitorState.startupPhase
      if (root.checks >= 200) {
        stop()
        root.finish()
        return
      }
      if (root.sawRunning && root.sawUtilization && !root.collectionStopStarted) {
        if (!root.collectionStopArmed) {
          stateHoldFile.setText("hold\n")
          monitor.refreshNow()
          root.collectionStopArmed = true
          return
        }
        if (!monitor.stateProcess || !monitor.stateProcess.running) return
        root.collectionStopStarted = true
        root.stateBeforeCollectionStop = monitor.state
        root.stoppedStateWorker = monitor.stateProcess
        root.stoppedWatcherWorker = monitor.watcherProcess
        root.stoppedCollectionGeneration = monitor.collectionGeneration
        monitor.collecting = false
        var lateState = '{"available":true,"stale":true,"error":"late stopped cycle","data":{"name":"late","vcpus":1,"cpu":{"available":false},"memory":{"allocationAvailable":false,"usageAvailable":false}}}'
        monitor.applyState(lateState, "late stopped cycle", root.stoppedCollectionGeneration)
        root.sawLateVmIgnored = root.sameState(monitor.state, root.stateBeforeCollectionStop)
        root.sawCollectionStop = monitor.monitorState.watcherGeneration === 0 && !monitor.utilizationRunning
        monitor.collecting = true
        stateHoldFile.setText("release\n")
        root.sawCollectionRestart = monitor.monitorState.watcherGeneration === 0
        var stateBeforeLateWorker = monitor.state
        monitor.applyState(lateState, "late restarted worker", monitor.activeCollectionGeneration,
          root.stoppedStateWorker)
        if (root.stoppedWatcherWorker) monitor.handleWatcherExit(root.stoppedWatcherWorker)
        root.sawLateVmIgnored = root.sawLateVmIgnored && root.sameState(monitor.state, stateBeforeLateWorker)
        monitor.applyState('{"available":true,"stale":true,"error":"late restarted cycle","data":{"name":"late","vcpus":1,"cpu":{"available":false},"memory":{"allocationAvailable":false,"usageAvailable":false}}}', "late restarted cycle", root.stoppedCollectionGeneration)
        root.sawLateVmIgnored = root.sawLateVmIgnored && root.sameState(monitor.state, root.stateBeforeCollectionStop)
        if (!root.sawLateVmIgnored)
          console.error("late VM state changed while inactive", JSON.stringify(root.stateBeforeCollectionStop),
            JSON.stringify(monitor.state))
        Qt.callLater(function() { monitor.probeNow() })
        return
      }
      if (root.sawCollectionRestart && !root.collectionRestartReady) {
        if (!monitor.capabilityAvailable || !monitor.watcherRunning || !monitor.state.confirmedRunning) return
        root.collectionRestartReady = true
      }
      if (root.sawRunning && !root.sawUtilization && !root.forceWatcherStartFailure && !root.sawWatcherStop) {
        return
      } else if (root.sawRunning && !root.forceWatcherStartFailure && !root.sawWatcherStop) {
        watcherModeFile.setText("flap\n")
        root.forceWatcherStartFailure = true
      } else if (root.forceWatcherStartFailure && !monitor.watcherRunning
          && monitor.backoffSeconds >= 4) {
        root.sawWatcherStop = true
        watcherModeFile.setText("stable\n")
        root.forceWatcherStartFailure = false
        modeFile.setText("stopped\n")
        monitor.refreshNow()
      } else if (root.sawWatcherStop && root.sawStopped && !root.sawStale) {
        modeFile.setText("stale\n")
        monitor.refreshNow()
      } else if (root.sawStale && !root.sawMultiple) {
        modeFile.setText("multiple\n")
        monitor.refreshNow()
      } else if (root.sawMultiple) {
        if (root.popupRefreshBaseline === 0) {
          root.popupRefreshBaseline = root.reconciliationStartEvents
          monitor.popupOpen = true
          return
        }
        if (root.reconciliationStartEvents <= root.popupRefreshBaseline) {
          console.error("VM popup opening did not request an immediate refresh")
          Qt.exit(1)
          return
        }
        if (root.actionPhase < 7 || !root.serviceReplacementReady || !root.serviceReplacementCallbackChecked) return
        stop()
        root.finish()
      }
    }
  }

  Timer {
    id: sharedConsumerTimer
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      if (!root.sharedWatcherStarted && vmService.watcherRunning) {
        root.sharedWatcherStarted = true
        if (root.sharedWatcherStartEvents !== 1 || !vmService.collecting || !vmService.detailed) {
          console.error("shared VM service did not start one detailed collection", root.sharedWatcherStartEvents,
            vmService.collecting, vmService.detailed)
          Qt.exit(1)
          return
        }
        actionModeFile.setText("fail-exit\n")
        actionReleaseFile.setText("wait\n")
        var nanAccepted = vmService.requestMemory(NaN)
        var tooLargeAccepted = vmService.requestMemory(3)
        root.actionInvalidChecked = !nanAccepted && !tooLargeAccepted
        root.actionPhase = 1
        return
      }
      if (root.actionPhase === 1 && !vmService.resizePending) {
        actionModeFile.setText("hold\n")
        actionReleaseFile.setText("wait\n")
        var accepted = vmService.requestMemory(1)
        if (!accepted) return
        root.actionBusyChecked = !vmService.requestMemory(1)
        vmLeft.active = false
        vmRight.active = false
        root.actionConsumersRemoved = vmService.consumerCount === 0 && vmService.collecting
        root.actionPhase = 2
        return
      }
      if (root.actionPhase === 2 && vmService.resizePending) {
        actionReleaseFile.setText("release\n")
        root.actionPhase = 3
        return
      }
      if (root.actionPhase === 3) {
        if (vmService.resizePending && vmService.reconciliationRunning)
          root.actionFinalReconciliationSeen = true
        if (!vmService.resizePending && root.actionFinalReconciliationSeen) {
          root.actionSuccessSeen = true
          root.sharedConsumersDetached = !vmService.collecting && !vmService.watcherRunning
          vmRight.active = true
          root.actionPhase = 4
        }
        return
      }
      if (root.actionPhase === 4 && root.actionRetainedStateRejected && !root.actionExitRequested
          && vmRight.active && vmService.watcherRunning && vmService.state.canResize) {
        actionModeFile.setText("fail-exit\n")
        root.actionExitRequested = vmService.requestMemory(1)
        root.actionPhase = 5
        return
      }
      if (root.actionPhase === 5 && root.actionExitRequested && !vmService.resizePending
          && vmService.actionError === "fixture action failed") {
        root.actionExitFailureSeen = true
        vmService.actionExecutable = root.fakeAction + ".missing"
        root.actionStartRequested = vmService.requestMemory(1)
        root.actionPhase = 6
        return
      }
      if (root.actionPhase === 6 && root.actionStartRequested && !vmService.resizePending
          && vmService.actionError === "VM memory action failed to start") {
        root.actionStartFailureSeen = true
        vmService.actionExecutable = root.fakeAction
        root.actionPhase = 7
        root.prepareServiceReplacement()
      }
      if (root.actionPhase === 7 && !root.replacementService && root.oldServiceActionAccepted
          && vmService.resizePending && vmService.reconciliationRunning) {
        root.startServiceReplacement()
        return
      }
      if (root.actionPhase === 7 && root.replacementService && !root.serviceReplacementReady
          && root.oldServiceConsumerDetached && root.oldServiceActionAccepted
          && vmRight.service === root.replacementService
          && root.replacementService.consumerCount === 1 && root.replacementService.watcherRunning
          && root.replacementService.state.confirmedRunning)
        root.serviceReplacementReady = true
      if (root.serviceReplacementReady && !root.replacementStateBeforeObsoleteCallback) {
        root.replacementStateBeforeObsoleteCallback = root.replacementService.state
        actionReleaseFile.setText("release\n")
        oldServiceStateHoldFile.setText("release\n")
        return
      }
      if (root.serviceReplacementReady && root.obsoleteCallbackDelivered && !root.oldServiceDestroyed) {
        root.oldServiceObject.destroy()
        root.oldServiceDestroyed = true
        return
      }
      if (root.serviceReplacementReady && !root.serviceReplacementCallbackChecked
          && root.oldServiceDestroyed && root.serviceInvalidated && !replacementCallbackCheckTimer.running) {
        replacementCallbackCheckTimer.start()
      }
    }
  }
}
