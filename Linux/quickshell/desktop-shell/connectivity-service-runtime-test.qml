import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/network" as Network
import "plugins/panels/tailscale" as Tailscale

Item {
  id: root

  readonly property string oldStateModePath: Quickshell.env("CONNECTIVITY_STATE_MODE")
  readonly property string oldStateHoldPath: Quickshell.env("CONNECTIVITY_STATE_HOLD")
  readonly property string replacementStateModePath: Quickshell.env("CONNECTIVITY_REPLACEMENT_STATE_MODE")
  readonly property string replacementStateHoldPath: Quickshell.env("CONNECTIVITY_REPLACEMENT_STATE_HOLD")
  readonly property string actionModePath: Quickshell.env("CONNECTIVITY_ACTION_MODE")
  readonly property string actionReleasePath: Quickshell.env("CONNECTIVITY_ACTION_RELEASE")
  readonly property string stateLogPath: Quickshell.env("CONNECTIVITY_STATE_LOG")
  readonly property string actionLogPath: Quickshell.env("CONNECTIVITY_ACTION_LOG")
  readonly property string stdinLogPath: Quickshell.env("CONNECTIVITY_STDIN_LOG")
  readonly property string tailscaleModePath: Quickshell.env("CONNECTIVITY_TAILSCALE_MODE")
  readonly property string fakeState: Qt.resolvedUrl("tests/fixtures/connectivity/fake-iwd-state")
    .toString().replace("file://", "")
  readonly property string fakeReplacementState: Qt.resolvedUrl("tests/fixtures/connectivity/fake-iwd-state-replacement")
    .toString().replace("file://", "")
  readonly property string fakeTailscaleState: Qt.resolvedUrl("tests/fixtures/connectivity/fake-tailscale-state")
    .toString().replace("file://", "")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/connectivity/fake-connectivity-action")
    .toString().replace("file://", "")

  property int phase: 0
  property bool sawReplacement: false
  property bool sawTwoConsumers: false
  property bool sawActionContention: false
  property bool sawPasswordStdinOnly: false
  property bool sawConsumersRemovedDuringAction: false
  property bool sawPostActionReconcile: false
  property bool sawOnePostActionRead: false
  property bool sawFailedActionStart: false
  property bool sawFailedStateStart: false
  property bool sawNetworkNonzeroReconcile: false
  property bool sawCancelledCredential: false
  property bool sawQueuedCancellation: false
  property bool sawReentrantSingleStart: false
  property bool sawStateWorkerHeldQueue: false
  property bool sawTailscale: false
  property bool sawTailscaleActionContention: false
  property bool sawTailscaleFailedActionStart: false
  property bool sawTailscaleNonzeroReconcile: false
  property var replacementService: null
  property var cancelledActionWorker: null
  property var retainedQueuedStarter: null
  property string stateLogText: ""
  property string actionLogText: ""
  property string stdinLogText: ""
  property int stateReadsBeforeAction: 0
  property int stateReadsBeforeFailedAction: 0
  property int actionLinesBeforeReentrant: 0
  property int actionLinesBeforeHeldQueue: 0
  property bool failedActionHoldReleased: false
  property bool reentrantActionReleased: false
  property bool reentrantTriggered: false
  property bool postActionHoldReleased: false

  QtObject {
    id: fakeShell
    property bool previewMode: false

    function widgetSettingsFor(pluginId) { return ({}) }

    function serviceFor(pluginId) {
      if (String(pluginId) === "desktop.network") return network
      if (String(pluginId) === "desktop.tailscale") return tailscale
      return null
    }
  }

  Network.Service {
    id: network
    shell: fakeShell
    manifest: ({ id: "desktop.network" })
    stateExecutable: root.fakeState
    actionExecutable: root.fakeAction
    processStartGraceInterval: 250
  }

  Component {
    id: replacementComponent

    Network.Service {
      shell: fakeShell
      manifest: ({ id: "desktop.network" })
      stateExecutable: root.fakeReplacementState
      actionExecutable: root.fakeAction
      processStartGraceInterval: 250
    }
  }

  Tailscale.Service {
    id: tailscale
    shell: fakeShell
    manifest: ({ id: "desktop.tailscale" })
    stateExecutable: root.fakeTailscaleState
    actionExecutable: root.fakeAction
    processStartGraceInterval: 250
  }

  ServiceConsumer {
    id: left
    service: network
  }

  ServiceConsumer {
    id: right
    service: network
  }

  ServiceConsumer {
    id: tailscaleConsumer
    service: tailscale
  }

  Connections {
    target: root.replacementService
    function onActionKindChanged() {
      if (root.reentrantTriggered || !root.retainedQueuedStarter) return
      root.reentrantTriggered = true
      root.retainedQueuedStarter()
    }
  }

  FileView {
    id: oldStateMode
    path: root.oldStateModePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: oldStateHold
    path: root.oldStateHoldPath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: replacementStateMode
    path: root.replacementStateModePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: replacementStateHold
    path: root.replacementStateHoldPath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: actionMode
    path: root.actionModePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: actionRelease
    path: root.actionReleasePath
    preload: false
    blockWrites: false
    printErrors: false
  }

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
    id: stdinLog
    path: root.stdinLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.stdinLogText = text()
  }

  FileView {
    id: tailscaleMode
    path: root.tailscaleModePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: root.advance()
  }

  Timer {
    interval: 30000
    running: true
    repeat: false
    onTriggered: root.fail("watchdog expired")
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  function lineCount(value) {
    var lines = String(value || "").split("\n").filter(function(line) { return line !== "" })
    return lines.length
  }

  function queuedActionStateFor(service) {
    var entries = service && service.data ? service.data : []
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && entries[i].objectName === "networkQueuedActionState") return entries[i]
    }
    return null
  }

  function sharedSnapshot(service) {
    return JSON.stringify({
      iwdAvailable: service.iwdAvailable,
      iwdDevice: service.iwdDevice,
      connectionState: service.connectionState,
      connectedSsid: service.connectedSsid,
      actionKind: service.actionKind,
      actionDevice: service.actionDevice,
      actionProfile: service.actionProfile,
      queuedActionKind: service.queuedActionKind,
      queuedActionDevice: service.queuedActionDevice,
      queuedActionProfile: service.queuedActionProfile
    })
  }

  function finish() {
    var success = sawReplacement && sawTwoConsumers && sawActionContention
      && sawPasswordStdinOnly && sawConsumersRemovedDuringAction && sawPostActionReconcile
      && sawOnePostActionRead && sawFailedActionStart && sawFailedStateStart
      && sawNetworkNonzeroReconcile && sawQueuedCancellation && sawCancelledCredential
      && sawReentrantSingleStart && sawStateWorkerHeldQueue
      && sawTailscale && sawTailscaleActionContention && sawTailscaleFailedActionStart
      && sawTailscaleNonzeroReconcile
    if (!success) {
      console.error("connectivity fixture failed", sawReplacement, sawTwoConsumers,
        sawActionContention, sawPasswordStdinOnly, sawConsumersRemovedDuringAction,
        sawPostActionReconcile, sawOnePostActionRead, sawFailedActionStart,
        sawFailedStateStart, sawNetworkNonzeroReconcile, sawCancelledCredential,
        sawQueuedCancellation,
        sawReentrantSingleStart, sawStateWorkerHeldQueue,
        sawTailscale, sawTailscaleActionContention, sawTailscaleFailedActionStart,
        sawTailscaleNonzeroReconcile,
        network.consumerCount, network.collecting, network.busy, network.actionReserved,
        replacementService ? replacementService.consumerCount : -1,
        replacementService ? replacementService.collecting : false,
        replacementService ? replacementService.busy : false,
        replacementService ? replacementService.actionReserved : false,
        actionLogText, stdinLogText)
    } else {
      console.log("connectivity fake-process fixture passed")
    }
    Qt.exit(success ? 0 : 1)
  }

  function fail(message) {
    console.error("connectivity-service-runtime-test: " + String(message))
    Qt.exit(1)
  }

  function advance() {
    try {
      if (phase === 0) {
        if (!network.busy || network.consumerCount !== 2) return
        sawTwoConsumers = true
        replacementService = replacementComponent.createObject(root)
        check(replacementService !== null, "replacement service created")
        replacementStateMode.setText("replacement\n")
        replacementStateHold.setText("hold\n")
        left.service = replacementService
        right.service = replacementService
        check(network.consumerCount === 0, "old service detached")
        oldStateHold.setText("release\n")
        phase = 1
        return
      }

      if (phase === 1) {
        if (!replacementService || !replacementService.busy) return
        if (network.busy) return
        replacementStateHold.setText("release\n")
        phase = 2
        return
      }

      if (phase === 2) {
        if (!replacementService || !replacementService.iwdAvailable || replacementService.busy) return
        sawReplacement = replacementService.connectedSsid === "replacement-network"
        check(sawReplacement, "replacement state won over the old read")
        replacementStateHold.setText("hold\n")
        replacementService.requestRefresh(false)
        phase = 3
        return
      }

      if (phase === 3) {
        if (!replacementService || !replacementService.busy) return
        stateLog.reload()
        phase = 30
        return
      }

      if (phase === 30) {
        if (lineCount(stateLogText) === 0) return
        stateReadsBeforeAction = lineCount(stateLogText)
        actionMode.setText("hold\n")
        actionRelease.setText("wait\n")
        var firstAccepted = replacementService.runConnect("fixture-network", "fixture-password")
        var secondAccepted = replacementService.runConnect("other-network", "other-password")
        sawActionContention = firstAccepted && !secondAccepted
        check(sawActionContention, "one shared network reservation")
        check(replacementService.actionReserved && replacementService.busy, "reservation owns busy")
        check(sharedSnapshot(replacementService).indexOf("fixture-password") === -1,
          "password absent from shared public snapshot")
        check(replacementService.actionPassword === "" && replacementService.queuedActionPassword === "",
          "password fields remain private to the operation worker")
        replacementStateHold.setText("release\n")
        phase = 4
        return
      }

      if (phase === 4) {
        if (replacementService.actionKind !== "connect") return
        stateLog.reload()
        phase = 40
        return
      }

      if (phase === 40) {
        if (lineCount(stateLogText) <= stateReadsBeforeAction) return
        stateReadsBeforeAction = lineCount(stateLogText)
        left.active = false
        right.active = false
        sawConsumersRemovedDuringAction = replacementService.consumerCount === 0
          && replacementService.collecting
        check(sawConsumersRemovedDuringAction, "action retains collection after last consumer")
        replacementStateHold.setText("hold\n")
        actionRelease.setText("release\n")
        phase = 5
        return
      }

      if (phase === 5) {
        if (replacementService.consumerCount === 0 && replacementService.collecting
            && replacementService.busy) {
          sawPostActionReconcile = true
          if (!postActionHoldReleased && replacementService.actionKind === "") {
            postActionHoldReleased = true
            replacementStateHold.setText("release\n")
          }
        }
        if (replacementService.actionReserved || replacementService.busy || replacementService.collecting) return
        stateLog.reload()
        actionLog.reload()
        stdinLog.reload()
        phase = 50
        return
      }

      if (phase === 50) {
        if (lineCount(stateLogText) <= stateReadsBeforeAction || actionLogText === ""
            || stdinLogText.indexOf("fixture-password") === -1) return
        sawPasswordStdinOnly = actionLogText.indexOf("fixture-password") === -1
          && stdinLogText.indexOf("fixture-password") !== -1
        check(sawPasswordStdinOnly, "connect password uses stdin only")
        sawOnePostActionRead = lineCount(stateLogText) === stateReadsBeforeAction + 1
        check(sawOnePostActionRead, "accepted action causes one reconciliation")
        left.active = true
        replacementService.actionExecutable = root.fakeAction + ".missing"
        check(replacementService.runNetworkAction("disconnect", "fixture-network"),
          "failed-start action accepted")
        phase = 6
        return
      }

      if (phase === 6) {
        if (replacementService.busy || replacementService.actionReserved) return
        sawFailedActionStart = replacementService.actionError !== ""
          || replacementService.healthError.indexOf("Network action failed") !== -1
        replacementService.stateExecutable = root.fakeState + ".missing"
        replacementService.requestRefresh(false)
        phase = 7
        return
      }

      if (phase === 7) {
        if (replacementService.busy) return
        sawFailedStateStart = replacementService.healthError.indexOf("state query") !== -1
        replacementService.stateExecutable = root.fakeReplacementState
        replacementService.actionExecutable = root.fakeAction
        stateLog.reload()
        stateReadsBeforeFailedAction = lineCount(stateLogText)
        replacementService.requestRefresh(false)
        phase = 8
        return
      }

      if (phase === 8) {
        if (replacementService.busy) return
        stateLog.reload()
        if (lineCount(stateLogText) <= stateReadsBeforeFailedAction) return
        replacementStateHold.setText("hold\n")
        actionMode.setText("fail-exit\n")
        check(replacementService.runNetworkAction("disconnect", "fixture-network"),
          "nonzero network action accepted")
        stateReadsBeforeFailedAction = lineCount(stateLogText)
        phase = 9
        return
      }

      if (phase === 9) {
        stateLog.reload()
        if (replacementService.actionError === "") return
        if (!failedActionHoldReleased) {
          check(replacementService.operationPending && replacementService.actionReserved,
            "nonzero network action retains reconciliation demand")
          failedActionHoldReleased = true
          replacementStateHold.setText("release\n")
          return
        }
        if (replacementService.busy) return
        if (lineCount(stateLogText) <= stateReadsBeforeFailedAction) return
        sawNetworkNonzeroReconcile = replacementService.connectedSsid === ""
          && replacementService.actionError === "Network action failed"
          && !replacementService.operationPending
          && !replacementService.actionReserved
          && lineCount(stateLogText) === stateReadsBeforeFailedAction + 1
        check(sawNetworkNonzeroReconcile, "network failure reconciles mutated state")
        replacementStateHold.setText("hold\n")
        replacementService.requestRefresh(false)
        phase = 10
        return
      }

      if (phase === 10) {
        if (!replacementService.stateWorker) return
        actionMode.setText("hold\n")
        actionRelease.setText("wait\n")
        actionLog.reload()
        actionLinesBeforeReentrant = lineCount(actionLogText)
        check(replacementService.runConnect("reentrant-network", "reentrant-password"),
          "reentrant network action accepted")
        var queuedActionState = queuedActionStateFor(replacementService)
        check(queuedActionState !== null, "queued action state exists")
        retainedQueuedStarter = queuedActionState.starter
        check(typeof retainedQueuedStarter === "function", "queued starter retained")
        reentrantTriggered = false
        replacementStateHold.setText("release\n")
        phase = 11
        return
      }

      if (phase === 11) {
        if (!reentrantActionReleased) {
          if (replacementService.actionKind === "") return
          reentrantActionReleased = true
          actionRelease.setText("release\n")
          return
        }
        if (replacementService.busy || replacementService.actionReserved) return
        actionLog.reload()
        if (lineCount(actionLogText) <= actionLinesBeforeReentrant) return
        sawReentrantSingleStart = lineCount(actionLogText) === actionLinesBeforeReentrant + 1
        check(sawReentrantSingleStart, "queued starter is single-use during reentry")
        replacementStateHold.setText("hold\n")
        replacementService.requestRefresh(false)
        phase = 12
        return
      }

      if (phase === 12) {
        if (!replacementService.stateWorker) return
        actionMode.setText("require-stdin\n")
        actionRelease.setText("release\n")
        actionLog.reload()
        actionLinesBeforeHeldQueue = lineCount(actionLogText)
        check(replacementService.runConnect("held-network", "held-password"),
          "state-held network action accepted")
        var heldActionState = queuedActionStateFor(replacementService)
        check(heldActionState !== null, "state-held action state exists")
        retainedQueuedStarter = heldActionState.starter
        check(typeof retainedQueuedStarter === "function", "state-held starter retained")
        retainedQueuedStarter()
        check(replacementService.queuedActionKind === "connect"
          && replacementService.actionReserved && replacementService.actionWorker === null,
          "state-held starter leaves request reserved")
        replacementStateHold.setText("release\n")
        phase = 13
        return
      }

      if (phase === 13) {
        if (replacementService.busy || replacementService.actionReserved) return
        actionLog.reload()
        if (lineCount(actionLogText) <= actionLinesBeforeHeldQueue) return
        sawStateWorkerHeldQueue = replacementService.actionError === ""
          && lineCount(actionLogText) === actionLinesBeforeHeldQueue + 1
        check(sawStateWorkerHeldQueue, "state-held invocation preserves queued request")
        replacementStateHold.setText("hold\n")
        replacementService.requestRefresh(false)
        phase = 14
        return
      }

      if (phase === 14) {
        if (!replacementService.stateWorker) return
        actionMode.setText("hold\n")
        actionRelease.setText("wait\n")
        check(replacementService.runConnect("queued-cancel", "queued-cancel-password"),
          "queued cancellation action accepted")
        var cancelledActionState = queuedActionStateFor(replacementService)
        check(cancelledActionState !== null, "queued cancellation state exists")
        retainedQueuedStarter = cancelledActionState.starter
        check(typeof retainedQueuedStarter === "function", "queued cancellation starter retained")
        replacementService.stopCollection()
        retainedQueuedStarter()
        sawQueuedCancellation = replacementService.actionWorker === null
          && replacementService.actionKind === ""
          && !replacementService.actionReserved
        check(sawQueuedCancellation, "retained queued starter cannot bypass cancellation")
        actionRelease.setText("release\n")
        phase = 15
        return
      }

      if (phase === 15) {
        actionMode.setText("hold\n")
        actionRelease.setText("wait\n")
        check(replacementService.runConnect("cancelled-network", "cancelled-password"),
          "cancellable network action accepted")
        cancelledActionWorker = replacementService.actionWorker
        check(cancelledActionWorker !== null, "cancellable action worker created")
        left.active = false
        replacementService.stopCollection()
        check(!replacementService.collecting, "cancellation stops collection")
        sawCancelledCredential = typeof cancelledActionWorker.password === "undefined"
        check(sawCancelledCredential, "cancelled worker does not expose password")
        actionRelease.setText("release\n")
        phase = 16
        return
      }

      if (phase === 16) {
        if (replacementService.collecting) return
        actionMode.setText("wait\n")
        actionRelease.setText("release\n")
        phase = 17
        return
      }

      if (phase === 17) {
        if (!tailscale.available || tailscale.busy) return
        tailscaleConsumer.details = true
        var firstTailscaleAction = tailscale.up()
        var secondTailscaleAction = tailscale.down()
        sawTailscale = tailscale.selfName === "fixture-tail" && tailscale.detailed
        sawTailscaleActionContention = firstTailscaleAction && !secondTailscaleAction
        check(sawTailscale && sawTailscaleActionContention, "Tailscale action serialization")
        actionRelease.setText("release\n")
        phase = 18
        return
      }

      if (phase === 18) {
        if (tailscale.busy) return
        tailscale.actionExecutable = root.fakeAction + ".missing"
        check(tailscale.up(), "failed-start Tailscale action accepted")
        phase = 19
        return
      }

      if (phase === 19) {
        if (tailscale.busy || tailscale.actionReserved) return
        sawTailscaleFailedActionStart = tailscale.actionStatus === ""
          && tailscale.lastError.indexOf("action failed to start") !== -1
        check(sawTailscaleFailedActionStart, "Tailscale failed action releases guards and status")
        tailscale.actionExecutable = root.fakeAction
        actionMode.setText("fail-exit\n")
        check(tailscale.up(), "nonzero Tailscale action accepted")
        phase = 20
        return
      }

      if (phase === 20) {
        if (tailscale.busy || tailscale.actionReserved) return
        sawTailscaleNonzeroReconcile = !tailscale.running
          && tailscale.backendState === "Stopped"
          && tailscale.lastError === "Tailscale action failed"
          && tailscale.actionStatus === ""
        check(sawTailscaleNonzeroReconcile, "Tailscale failure reconciles mutated state")
        finish()
      }
    } catch (error) {
      fail(error && error.message ? error.message : error)
    }
  }
}
