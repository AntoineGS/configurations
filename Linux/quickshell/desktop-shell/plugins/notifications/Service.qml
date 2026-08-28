import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons
import qs.Ui

import "components"
import "NotificationLogic.js" as NotificationLogic
import "NotificationPresentation.js" as Presentation

Item {
  id: service

  property var shell: null
  property var pluginRegistry: null

  readonly property string home: String(Quickshell.env("HOME") || "")
  readonly property string stateHome: String(Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state"))
  readonly property string stateDir: stateHome + "/desktop-shell/"
  readonly property string settingsPath: stateDir + "notifications.json"
  readonly property string notificationStateDir: stateHome + "/desktop-shell/notifications/"
  readonly property string popupStateDir: notificationStateDir
  readonly property string historyDir: popupStateDir + "history/"
  readonly property string imagesDir: popupStateDir + "images/"
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string routeDir: runtimeDir + "/desktop-shell"
  readonly property string routePath: routeDir + "/notification-route.json"
  readonly property string leasePath: routeDir + "/notification-route-lease.json"
  readonly property bool testSurfaceSuppressed: Quickshell.env("DESKTOP_SHELL_TEST_NO_SURFACES") === "1"
  property bool ownershipEnabled: Quickshell.env("DESKTOP_SHELL_NOTIFICATIONS_REGISTER") === "1"
  property bool notificationsOwned: false
  property string ownershipError: "notification owner probe pending"
  property bool routeValid: false
  property string routeError: "notification route unavailable"
  property string routeRaw: ""
  property string leaseRaw: ""
  property bool leaseValid: false
  property string leaseError: "notification route lease unavailable"
  property bool routeMetadataValid: false
  property string routeMetadataError: "notification route metadata unavailable"
  property int routeMetadataGeneration: 0
  property int routeMetadataCheckGeneration: -1
  property int routeMetadataAttemptCount: 0
  property int routeMetadataSnapshotRevision: -1
  property var routeMetadataSnapshot: null
  property bool routeMetadataCheckScheduled: false
  property int routeAcceptedGeneration: -1
  property real routeAcceptedRefreshedAtMs: -1
  property real routeAcceptedExpiresAtMs: -1
  property string routeLastTransitionReason: ""
  property bool routeCandidatePending: false
  property bool routeCandidateMetadataPending: false
  property string routeCandidateError: "notification route candidate unavailable"
  property var acceptedRoute: null
  property var acceptedLease: null
  property int routeTransitionCount: 0
  property int routeInvalidationCount: 0
  property var routeTransitionLog: []
  property var route: ({
    valid: false,
    visible: false,
    output: null,
    cueOutput: null,
    direction: null,
    error: "notification route unavailable"
  })
  readonly property bool routeVisible: routeValid && route.visible === true

  property var presentationState: Presentation.createInitialState({
    routeVisible: service.routeVisible,
    output: service.route.output || ""
  })
  property var presentationFrame: Presentation.presentationFrame(service.presentationState)
  property real presentationWatchdogToken: 0
  property string presentationWatchdogKind: ""
  property string presentationWatchdogOutput: ""

  readonly property string barPosition: shell && shell.barConfig
    ? String(shell.barConfig.position || "top") : "top"
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  readonly property int defaultBarSize: barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int liveBarSize: shell && shell.bar && Number(shell.bar.barSize) > 0
    ? Math.max(0, Number(shell.bar.barSize)) : defaultBarSize
  readonly property int barClearance: shell && shell.barVisible === false
    ? Style.gapsOut : liveBarSize + Style.gapsOut

  property var liveRefs: ({})
  property var liveGenerations: ({})
  property real latestLiveGeneration: -1
  property real latestPopupQueueOrder: -1
  property var livePersistenceSources: ({})
  property var actionClosingGenerations: ({})
  property var failedHistoryActions: ({})
  property var pendingRefreshes: ({})
  property var pendingSilencedRefreshes: ({})
  property var silencedDirty: ({})
  property alias popupModel: popupModel
  ListModel { id: popupModel }
  property bool popupSurfaceOpened: false
  property string popupMotionState: "closed"
  property int popupTransitionGeneration: 0
  property string pendingRemovalIdentity: ""
  property string pendingRemovalReason: ""
  property string pendingPreemptionIdentity: ""
  property bool activePopupHovered: false
  property string popupTransitionOutput: ""
  property string popupTransitionIdentity: ""
  property string popupTransitionKind: ""
  property string popupRenderedOutput: ""
  property string popupRenderedIdentity: ""
  property string tickingIdentity: ""
  property real activeDuration: 0
  property real activeRemainingLifetime: 0
  property real activeTickStartedAt: 0
  property real activeTickStartRemaining: 0
  readonly property real remainingFraction: presentationFrame.countdown.duration > 0
    ? Math.max(0, Math.min(1, presentationFrame.countdown.remaining / presentationFrame.countdown.duration)) : 1
  readonly property bool countdownVisible: presentationFrame.countdown.visible === true
  property alias historyModel: historyModel
  ListModel { id: historyModel }
  property bool historyOpen: false
  property int historyRequestGeneration: 0
  property int runningHistoryViewGeneration: -1
  property string historyReadRaw: ""
  property var historyLiveSnapshot: []

  property int persistenceRetryLimit: 2
  property string persistenceError: ""
  readonly property int historyLimit: 10
  readonly property int maxActivePopups: 50
  readonly property int maxPersistenceJobs: 100
  readonly property int admissionLimit: 120
  readonly property int admissionWindowMs: 60000
  property var admissionTimestamps: []
  property int admissionDropped: 0
  property int historyCount: 0
  property bool historyCountQueued: false
  readonly property int lowPopupDuration: 10000
  readonly property int normalPopupDuration: 15000
  readonly property int maxPopupDuration: 30000

  PersistentProperties {
    id: persisted
    reloadableId: "desktop-shell-notifications"
    property bool doNotDisturb: false

    onDoNotDisturbChanged: {
      if (!service._hydrating) service.scheduleSettingsSave()
    }
  }

  property bool _hydrating: false
  property alias doNotDisturb: persisted.doNotDisturb
  property var pendingPopups: ({})
  property string dndConfirmationIdentity: ""

  function durationFor(urgency, expireTimeout) {
    return NotificationLogic.durationFor(
      urgency, expireTimeout, NotificationUrgency.Critical, NotificationUrgency.Low,
      lowPopupDuration, normalPopupDuration, maxPopupDuration)
  }

  function shouldBypassDnd(notification) {
    return NotificationLogic.shouldBypassDnd(notification, NotificationUrgency.Critical)
  }

  function isEphemeral(notification) {
    return NotificationLogic.isEphemeral(notification)
  }

  function snapshotOf(notification, timestamp) {
    var requestedAt = timestamp === undefined ? Date.now() : Number(timestamp)
    var startedAt = NotificationLogic.nextMonotonicTimestamp(service.latestLiveGeneration, requestedAt)
    service.latestLiveGeneration = startedAt
    var snapshot = NotificationLogic.snapshotOf(notification, startedAt)
    snapshot.duration = durationFor(snapshot.urgency, snapshot.expireTimeout)
    snapshot.remainingLifetime = durationFor(snapshot.urgency, snapshot.expireTimeout)
    snapshot.queuePriority = NotificationLogic.popupQueuePriority(snapshot, NotificationUrgency.Critical)
    ensurePopupQueueOrder(snapshot)
    snapshot.transient = isEphemeral(notification)
    return snapshot
  }

  function isSpotify(notification) {
    if (!notification) return false
    var source = NotificationLogic.boundedText(notification.appName, 128) + "\n"
      + NotificationLogic.boundedText(notification.appIcon, 128)
    return source.toLowerCase().indexOf("spotify") >= 0
  }

  function consumeAdmission() {
    var updated = NotificationLogic.admissionUpdate(
      admissionTimestamps, Date.now(), admissionLimit, admissionWindowMs)
    admissionTimestamps = updated.timestamps
    if (updated.accepted) return true

    admissionDropped += updated.dropped
    persistenceError = "notification admission limit reached"
    return false
  }

  function admitNotification(notification) {
    if (service.consumeAdmission()) return true

    try {
      notification.tracked = false
      if (notification && typeof notification.dismiss === "function") notification.dismiss()
    } catch (error) {
      // The rejected sender may already be closed.
    }
    return false
  }

  function admitRefresh() {
    return service.consumeAdmission()
  }

  function pendingPopupCount() {
    var count = 0
    for (var key in pendingPopups) {
      if (Object.prototype.hasOwnProperty.call(pendingPopups, key)) count++
    }
    return count
  }

  function identityForSnapshot(snapshot) {
    return snapshot && snapshot.identity
      ? String(snapshot.identity)
      : NotificationLogic.popupIdentity(snapshot)
  }

  function presentationIdentityForOriginalId(originalId) {
    var state = service.presentationState
    var rows = state.active ? [state.active].concat(state.pending) : state.pending
    for (var i = 0; i < rows.length; i++)
      if (Number(rows[i].originalId) === Number(originalId)) return identityForSnapshot(rows[i])
    return ""
  }

  function syncPresentationModel() {
    var rows = []
    var state = service.presentationState
    if (state.active) rows.push(state.active)
    rows = rows.concat(state.pending)
    popupModel.clear()
    for (var i = 0; i < rows.length; i++) popupModel.append(rows[i])
  }

  function syncLegacyPresentation() {
    var state = service.presentationState
    var visual = state.visual || {}
    var countdown = state.countdown || {}
    popupMotionState = service.testSurfaceSuppressed ? "closed" : state.phase
    popupTransitionGeneration = Number(visual.token) || 0
    popupTransitionKind = String(visual.kind || "")
    popupTransitionOutput = String(visual.output || state.route.output || "")
    popupTransitionIdentity = visual.incoming
      ? identityForSnapshot(visual.incoming) : (visual.outgoing ? identityForSnapshot(visual.outgoing) : "")
    popupSurfaceOpened = !service.testSurfaceSuppressed
      && (state.phase === "opening" || state.phase === "open" || state.phase === "switching")
    tickingIdentity = String(countdown.identity || "")
    activeDuration = Number(countdown.duration) || 0
    activeRemainingLifetime = Number(countdown.remaining) || 0
    activeTickStartedAt = Number(countdown.lastNow) || 0
    activeTickStartRemaining = activeRemainingLifetime
    activePopupHovered = state.hovered === true
  }

  function dispatchPresentation(event) {
    var result = Presentation.reduce(service.presentationState, event)
    service.presentationState = result.state
    service.presentationFrame = Presentation.presentationFrame(result.state)
    syncPresentationModel()
    syncLegacyPresentation()
    applyPresentationEffects(result.effects)
  }

  function findLiveReference(identity, snapshot) {
    var originalId = snapshot ? snapshot.originalId : null
    var generation = snapshot ? Number(snapshot.timestamp) : NaN
    if (originalId !== null && liveRefs[originalId]
        && Number(liveGenerations[originalId]) === generation
        && identityForSnapshot({ originalId: originalId, timestamp: generation }) === identity)
      return liveRefs[originalId]
    for (var key in liveRefs) {
      if (!Object.prototype.hasOwnProperty.call(liveRefs, key)) continue
      if (identityForSnapshot({ originalId: key, timestamp: liveGenerations[key] }) === identity)
        return liveRefs[key]
    }
    return null
  }

  function applyPresentationEffects(effects) {
    var effect
    for (var i = 0; i < effects.length; i++) {
      effect = effects[i]
      if (!effect) continue
      if (effect.type === "persist") persistPopupFile(effect.snapshot)
      else if (effect.type === "archive") {
        if (effect.snapshot.presentationSource === "history") deleteHistoryFileFor(effect.snapshot)
        else archivePopupFileFor(effect.snapshot)
      }
      else if (effect.type === "cleanup") {
        var snapshot = effect.snapshot
        var source = String(snapshot.presentationSource || "")
        var key = snapshot && snapshot.originalId
        markHistoryUnavailable(key, snapshot.timestamp)
        if (!source) source = restoredSource(snapshot) || livePersistenceSources[key] || ""
        if (effect.reason === "closed" || effect.reason === "replace") {
          if (source === "history") deleteHistoryFileFor(snapshot)
          else if (source === "popup") deletePopupFileFor(snapshot)
        }
        if (restoredPopups[NotificationLogic.popupFileName(snapshot)])
          delete restoredPopups[NotificationLogic.popupFileName(snapshot)]
        if (Number(liveGenerations[key]) === Number(snapshot.timestamp)) {
          delete liveRefs[key]
          delete liveGenerations[key]
          delete livePersistenceSources[key]
        }
        clearFailedHistoryAction(key, snapshot.timestamp)
      }
      else if (effect.type === "senderDismiss" || effect.type === "senderExpire") {
        var ref = findLiveReference(effect.identity, effect.snapshot)
        if (!ref) continue
        actionClosingGenerations[effect.snapshot.originalId] = effect.snapshot.timestamp
        try {
          if (effect.type === "senderExpire" && typeof ref.expire === "function") ref.expire()
          else if (typeof ref.dismiss === "function") ref.dismiss()
        } catch (error) {
          // The sender may have been destroyed before the reducer effect ran.
        }
        delete actionClosingGenerations[effect.snapshot.originalId]
      } else if (effect.type === "startWatchdog") {
        presentationWatchdogToken = effect.token
        presentationWatchdogKind = effect.kind
        presentationWatchdogOutput = effect.output
        presentationWatchdog.interval = effect.timeout
        presentationWatchdog.restart()
      } else if (effect.type === "cancelWatchdog"
          && presentationWatchdogToken === effect.token
          && presentationWatchdogKind === effect.kind
          && presentationWatchdogOutput === effect.output) {
        presentationWatchdog.stop()
        presentationWatchdogToken = 0
        presentationWatchdogKind = ""
        presentationWatchdogOutput = ""
      }
    }
  }

  function popupIndexForOriginalId(originalId) {
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (row && row.originalId === originalId) return i
    }
    return -1
  }

  function popupRows() {
    var rows = []
    for (var i = 0; i < popupModel.count; i++) rows.push(popupModel.get(i))
    return rows
  }

  function ensurePopupQueueOrder(row) {
    var current = Number(row.queueOrder)
    if (isFinite(current) && current >= 0) {
      service.latestPopupQueueOrder = Math.max(service.latestPopupQueueOrder, current)
      row.queueOrder = current
      return current
    }
    var candidate = Number(row.timestamp)
    if (!isFinite(candidate) || candidate < 0) candidate = Date.now()
    var next = candidate > service.latestPopupQueueOrder
      ? candidate : NotificationLogic.nextMonotonicTimestamp(service.latestPopupQueueOrder, candidate)
    service.latestPopupQueueOrder = next
    row.queueOrder = next
    return next
  }

  function popupIndexForIdentity(identity) {
    var wanted = String(identity || "")
    if (!wanted) return -1
    for (var i = 0; i < popupModel.count; i++) {
      if (NotificationLogic.popupIdentity(popupModel.get(i)) === wanted) return i
    }
    return -1
  }

  function enqueuePopup(snapshot) {
    if (typeof snapshot.queuePriority !== "boolean")
      snapshot.queuePriority = NotificationLogic.popupQueuePriority(snapshot, NotificationUrgency.Critical)
    ensurePopupQueueOrder(snapshot)
    var wasEmpty = popupModel.count === 0
    var plan = NotificationLogic.popupArrivalPlan(
      popupRows(), snapshot.urgency, NotificationUrgency.Critical, activePopupHovered)
    popupModel.insert(plan.insertIndex, snapshot)
    if (wasEmpty) requestPopupOpen()
    else if (plan.preempt || plan.deferred) {
      if (pendingPreemptionIdentity === "")
        pendingPreemptionIdentity = NotificationLogic.popupIdentity(snapshot)
      if (plan.preempt) requestPopupClose("preempt")
    }
    if (popupMotionState === "closed" && routeVisible) requestPopupOpen()
  }

  function startActiveLifetime() {
    if (popupModel.count === 0 || popupMotionState !== "open"
        || activePopupHovered || !routeVisible) return
    var row = popupModel.get(0)
    activeDuration = durationFor(row.urgency, row.expireTimeout)
    activeRemainingLifetime = Number(row.remainingLifetime) || 0
    if (activeDuration <= 0) return
    tickingIdentity = NotificationLogic.popupIdentity(row)
    activeTickStartedAt = Date.now()
    activeTickStartRemaining = activeRemainingLifetime
  }

  function prepareActiveLifetimeDisplay() {
    if (popupModel.count === 0) {
      activeDuration = 0
      activeRemainingLifetime = 0
      return
    }
    var row = popupModel.get(0)
    activeDuration = durationFor(row.urgency, row.expireTimeout)
    activeRemainingLifetime = Number(row.remainingLifetime) || 0
  }

  function updateActiveLifetime(now, requestExpiry) {
    if (tickingIdentity === "") return
    activeRemainingLifetime = NotificationLogic.consumeRemainingLifetime(
      activeTickStartRemaining, Number(now) - activeTickStartedAt)
    if (requestExpiry === true && activeRemainingLifetime <= 0)
      requestPopupRemoval(tickingIdentity, "expire")
  }

  function pauseActiveLifetime() {
    if (tickingIdentity === "") return
    updateActiveLifetime(Date.now(), false)
    var index = popupIndexForIdentity(tickingIdentity)
    if (index >= 0) popupModel.setProperty(index, "remainingLifetime", activeRemainingLifetime)
    checkpointPopupIdentity(tickingIdentity)
    tickingIdentity = ""
  }

  function checkpointPopupIdentity(identity) {
    var index = popupIndexForIdentity(identity)
    if (index < 0) return
    popupModel.setProperty(index, "remainingLifetime", activeRemainingLifetime)
    var row = popupModel.get(index)
    if (row && NotificationLogic.shouldPersistPopup(row)) persistPopupFile(row)
  }

  function setActivePopupHovered(hovered) {
    dispatchPresentation({ type: "HOVER_CHANGED", hovered: hovered === true })
  }

  function requestPopupOpen() {
    if (testSurfaceSuppressed) {
      popupSurfaceOpened = false
      popupMotionState = "closed"
      return
    }
    if (popupModel.count === 0 || !routeVisible || popupMotionState !== "closed") return
    promoteCriticalRun()
    if (pendingPreemptionIdentity !== ""
        && pendingPreemptionIdentity === NotificationLogic.popupIdentity(popupModel.get(0)))
      pendingPreemptionIdentity = ""
    popupTransitionGeneration++
    popupTransitionKind = "open"
    popupTransitionOutput = String(route.output || "")
    popupTransitionIdentity = NotificationLogic.popupIdentity(popupModel.get(0))
    popupRenderedOutput = ""
    popupRenderedIdentity = ""
    prepareActiveLifetimeDisplay()
    popupMotionState = "opening"
    popupSurfaceOpened = true
  }

  function requestPopupClose(reason) {
    if (popupMotionState === "closed" || popupMotionState === "closing") return
    pauseActiveLifetime()
    popupTransitionGeneration++
    popupTransitionOutput = popupRenderedOutput || popupTransitionOutput
    popupTransitionIdentity = popupRenderedIdentity || popupTransitionIdentity
    popupMotionState = "closing"
    popupTransitionKind = "close"
    popupSurfaceOpened = false
  }

  function handlePopupOpenFinished(identity, generation, outputName) {
    if (Number(generation) !== service.presentationState.visual.token
        || String(outputName) !== service.presentationState.visual.output) return
    dispatchPresentation({
      type: "TRANSITION_FINISHED", token: service.presentationState.visual.token,
      kind: service.presentationState.visual.kind, output: service.presentationState.visual.output
    })
  }

  function handlePopupCloseFinished(identity, generation, outputName) {
    if (Number(generation) !== service.presentationState.visual.token
        || String(outputName) !== service.presentationState.visual.output) return
    dispatchPresentation({
      type: "TRANSITION_FINISHED", token: service.presentationState.visual.token,
      kind: service.presentationState.visual.kind, output: service.presentationState.visual.output
    })
  }

  function promoteCriticalRun() {
    var target = 0
    for (var i = 0; i < popupModel.count; i++) {
      if (!NotificationLogic.popupQueuePriority(popupModel.get(i), NotificationUrgency.Critical)) continue
      if (i !== target) popupModel.move(i, target, 1)
      target++
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: service.presentationState.phase === "open" && service.presentationState.countdown.visible
    onTriggered: service.dispatchPresentation({
      type: "TICK",
      identity: service.presentationState.countdown.identity,
      now: Date.now()
    })
  }

  Timer {
    interval: 5000
    repeat: true
    running: service.presentationState.phase === "open" && service.presentationState.countdown.visible
    onTriggered: {
      service.dispatchPresentation({
        type: "TICK",
        identity: service.presentationState.countdown.identity,
        now: Date.now()
      })
      var active = service.presentationState.active
      if (active && service.presentationState.countdown.identity === identityForSnapshot(active))
        service.persistPopupFile(active)
    }
  }

  Timer {
    id: presentationWatchdog
    repeat: false
    onTriggered: {
      if (service.presentationWatchdogToken === service.presentationState.visual.token
          && service.presentationWatchdogKind === service.presentationState.visual.kind
          && service.presentationWatchdogOutput === service.presentationState.visual.output) {
        service.dispatchPresentation({
          type: "TRANSITION_TIMED_OUT",
          token: service.presentationWatchdogToken,
          kind: service.presentationWatchdogKind,
          output: service.presentationWatchdogOutput
        })
      }
    }
  }

  function reservePopupSlot(originalId) {
    var key = String(originalId)
    if (popupIndexForOriginalId(originalId) >= 0 || pendingPopups[key] === true) return true
    if (popupModel.count + pendingPopupCount() >= maxActivePopups) return false
    pendingPopups[key] = true
    return true
  }

  function releaseLiveNotification(notification, originalId, dismiss) {
    if (liveRefs[originalId] === notification) {
      var generation = liveGenerations[originalId]
      service.markHistoryUnavailable(originalId, liveGenerations[originalId])
      delete liveRefs[originalId]
      delete liveGenerations[originalId]
      service.clearFailedHistoryAction(originalId, generation)
      delete livePersistenceSources[originalId]
      delete pendingRefreshes[String(originalId)]
      delete pendingSilencedRefreshes[String(originalId)]
      delete silencedDirty[originalId]
    }
    try {
      if (dismiss && notification.tracked && typeof notification.dismiss === "function") notification.dismiss()
      notification.tracked = false
    } catch (error) {
      // The notification object was already destroyed.
    }
  }

  function handleNotification(notification) {
    // This sender is intentionally excluded before it can enter a popup or history.
    if (isSpotify(notification)) return
    if (!service.admitNotification(notification)) return

    notification.tracked = true
    var snapshot = snapshotOf(notification)
    var previous = liveRefs[snapshot.originalId]
    var previousIdentity = previous && previous !== notification
      ? String(liveGenerations[snapshot.originalId]) + ":" + String(snapshot.originalId) : ""
    if (previousIdentity === "") previousIdentity = presentationIdentityForOriginalId(snapshot.originalId)
    if (previous && previous !== notification) {
      service.markHistoryUnavailable(snapshot.originalId, liveGenerations[snapshot.originalId])
      delete pendingSilencedRefreshes[String(snapshot.originalId)]
      delete silencedDirty[snapshot.originalId]
      try { previous.tracked = false } catch (error) {}
    }
    liveRefs[snapshot.originalId] = notification
    liveGenerations[snapshot.originalId] = snapshot.timestamp
    livePersistenceSources[snapshot.originalId] = snapshot.transient ? "none"
      : (service.doNotDisturb && !shouldBypassDnd(notification) ? "history" : "popup")
    snapshot.presentationSource = livePersistenceSources[snapshot.originalId]
    notification.closed.connect(function() {
      service.handleClosedNotification(notification, snapshot.originalId)
    })

    if (service.doNotDisturb && !shouldBypassDnd(notification)) {
      if (!isEphemeral(notification)) {
        silencedDirty[snapshot.originalId] = false
        watchForSilencedUpdates(notification, snapshot.originalId)
        writeSilenced(notification, snapshot)
        return
      }
      releaseLiveNotification(notification, snapshot.originalId, false)
      return
    }

    if (previousIdentity === "" && !reservePopupSlot(snapshot.originalId)) {
      service.persistenceError = "notification active popup limit reached"
      releaseLiveNotification(notification, snapshot.originalId, true)
      return
    }

    watchForUpdates(notification, snapshot)
    delete service.pendingPopups[String(snapshot.originalId)]
    service.dispatchPresentation(previousIdentity === ""
      ? { type: "ARRIVE", snapshot: snapshot }
      : { type: "REPLACE", identity: previousIdentity, snapshot: snapshot })
  }

  function writeSilenced(notification, written) {
    writeHistoryFile(written, function(success, exitCode, outcome) {
      if (outcome === "superseded") return
      service.finishSilencedWrite(notification, written, success, exitCode, outcome)
    })
  }

  function markSilencedDirty(notification, originalId) {
    if (liveRefs[originalId] === notification) silencedDirty[originalId] = true
  }

  function watchForSilencedUpdates(notification, originalId) {
    function markDirty() {
      service.markSilencedDirty(notification, originalId)
    }

    for (var i = 0; i < updateSignals.length; i++) {
      var signal = notification[updateSignals[i]]
      if (signal && typeof signal.connect === "function") signal.connect(markDirty)
    }

    var actions = notification.actions || []
    var actionLimit = Math.min(actions.length, 8)
    for (var a = 0; a < actionLimit; a++) {
      var actionSignal = actions[a] && actions[a].textChanged
      if (actionSignal && typeof actionSignal.connect === "function") actionSignal.connect(markDirty)
    }
  }

  function scheduleSilencedRefresh(notification, originalId, persisted) {
    if (liveRefs[originalId] !== notification) return
    var key = String(originalId)
    var updated = NotificationLogic.refreshScheduleUpdate(
      pendingSilencedRefreshes, key, {
        notification: notification,
        originalId: originalId,
        persisted: persisted,
      })
    pendingSilencedRefreshes = updated.pending
    if (!updated.scheduled) return

    Qt.callLater(function() {
      var request = service.pendingSilencedRefreshes[key]
      if (!request) return
      delete service.pendingSilencedRefreshes[key]
      if (service.liveRefs[request.originalId] !== request.notification) return
      if (service.livePersistenceSources[request.originalId] !== "history") {
        service.releaseSilenced(request.notification, request.originalId)
        return
      }
      if (!service.admitRefresh()) {
        service.releaseSilenced(request.notification, request.originalId)
        return
      }

      var latest
      try {
        latest = NotificationLogic.replacementSnapshot(
          request.notification, request.originalId, request.persisted.timestamp)
        latest.remainingLifetime = 0
        latest.duration = durationFor(latest.urgency, latest.expireTimeout)
        delete latest.deadline
      } catch (error) {
        service.releaseSilenced(request.notification, request.originalId)
        return
      }
      if (latest.transient === true) {
        service.deleteHistoryFileFor(request.persisted)
        service.livePersistenceSources[request.originalId] = "none"
        service.releaseSilenced(request.notification, request.originalId)
        return
      }
      service.silencedDirty[request.originalId] = false
      if (!NotificationLogic.popupRowChanged(request.persisted, latest)) {
        service.releaseSilenced(request.notification, request.originalId)
        return
      }
      service.writeSilenced(request.notification, latest)
    })
  }

  function finishSilencedWrite(notification, written, success, exitCode, outcome) {
    if (outcome === "superseded") return
    if (!success) {
      service.persistenceError = "notification history persistence failed (exit " + String(exitCode) + ")"
      service.releaseSilenced(notification, written.originalId)
      return
    }
    if (service.liveRefs[written.originalId] !== notification) return
    if (service.silencedDirty[written.originalId] !== true) {
      service.releaseSilenced(notification, written.originalId)
      return
    }
    service.scheduleSilencedRefresh(notification, written.originalId, written)
  }

  function releaseSilenced(notification, originalId) {
    if (liveRefs[originalId] === notification) {
      var generation = liveGenerations[originalId]
      service.markHistoryUnavailable(originalId, liveGenerations[originalId])
      delete liveRefs[originalId]
      delete liveGenerations[originalId]
      service.clearFailedHistoryAction(originalId, generation)
      delete livePersistenceSources[originalId]
      delete pendingRefreshes[String(originalId)]
      delete pendingSilencedRefreshes[String(originalId)]
      delete silencedDirty[originalId]
    }
    try {
      notification.tracked = false
    } catch (error) {
      // The notification object was already destroyed.
    }
  }

  function liveReferenceCount() {
    var count = 0
    for (var key in liveRefs) {
      if (Object.prototype.hasOwnProperty.call(liveRefs, key)) count++
    }
    return count
  }

  function handleClosedNotification(notification, originalId) {
    if (service.liveRefs[originalId] !== notification) return
    delete service.pendingRefreshes[String(originalId)]
    delete service.pendingSilencedRefreshes[String(originalId)]
    delete service.silencedDirty[originalId]
    var generation = Number(service.liveGenerations[originalId])
    service.markHistoryUnavailable(originalId, generation)
    if (Number(service.actionClosingGenerations[originalId]) === generation) return
    var source = service.livePersistenceSources[originalId] || "popup"
    var found = false
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (row && row.originalId === originalId && Number(row.timestamp) === generation && !isRestoredRow(row)) {
        service.dispatchPresentation({
          type: "SENDER_CLOSED",
          identity: NotificationLogic.popupIdentity(row)
        })
        found = true
        break
      }
    }
    if (!found) {
      var row = { originalId: originalId, timestamp: generation }
      if (source === "history") service.deleteHistoryFileFor(row)
      else if (source === "popup") service.deletePopupFileFor(row)
    }
    delete service.liveRefs[originalId]
    delete service.liveGenerations[originalId]
    service.clearFailedHistoryAction(originalId, generation)
    delete service.livePersistenceSources[originalId]
    try { notification.tracked = false } catch (error) {}
  }

  readonly property var updateSignals: [
    "summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged",
    "imageChanged", "urgencyChanged", "expireTimeoutChanged", "hintsChanged", "actionsChanged"
  ]

  function watchForUpdates(notification, snapshot) {
    function refresh() {
      service.scheduleRefresh(notification, snapshot.originalId)
    }

    for (var i = 0; i < updateSignals.length; i++) {
      var signal = notification[updateSignals[i]]
      if (signal && typeof signal.connect === "function") signal.connect(refresh)
    }

    var actions = notification.actions || []
    var actionLimit = Math.min(actions.length, 8)
    for (var a = 0; a < actionLimit; a++) {
      var actionSignal = actions[a] && actions[a].textChanged
      if (actionSignal && typeof actionSignal.connect === "function") actionSignal.connect(refresh)
    }
  }

  function scheduleRefresh(notification, originalId) {
    var key = String(originalId)
    var updated = NotificationLogic.refreshScheduleUpdate(
      pendingRefreshes, key, { notification: notification, originalId: originalId })
    pendingRefreshes = updated.pending
    if (!updated.scheduled) return

    Qt.callLater(function() {
      var request = service.pendingRefreshes[key]
      if (!request) return
      delete service.pendingRefreshes[key]
      if (service.liveRefs[request.originalId] !== request.notification) return
      service.refreshPopup(request.notification, request.originalId)
    })
  }

  function refreshPopup(notification, originalId) {
    if (service.liveRefs[originalId] !== notification) return

    var rowIndex = -1
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (row && row.originalId === originalId && !isRestoredRow(row)) {
        rowIndex = i
        break
      }
    }
    if (rowIndex < 0 || !service.admitRefresh()) return

    var updated
    try {
      updated = snapshotOf(notification, Date.now())
      updated.id = originalId
      updated.originalId = originalId
      updated.presentationSource = livePersistenceSources[originalId] || "popup"
    } catch (error) {
      return
    }

    var row = popupModel.get(rowIndex)
    if (!row) return
    service.dispatchPresentation({
      type: "REPLACE",
      identity: NotificationLogic.popupIdentity(row),
      snapshot: updated
    })
  }

  property var restoredPopups: ({})

  function isRestoredRow(row) {
    return !!row && !!restoredPopups[NotificationLogic.popupFileName(row)]
  }

  function restoredSource(row) {
    return row ? restoredPopups[NotificationLogic.popupFileName(row)] : ""
  }

  function replacePopupRow(rowIndex, updated) {
    var row = popupModel.get(rowIndex)
    if (!row || !updated) return
    var oldIdentity = NotificationLogic.popupIdentity(row)
    var newIdentity = NotificationLogic.popupIdentity(updated)
    if (pendingRemovalIdentity === oldIdentity) {
      pendingRemovalIdentity = ""
      pendingRemovalReason = ""
    }
    if (pendingPreemptionIdentity === oldIdentity) pendingPreemptionIdentity = newIdentity
    var active = rowIndex === 0
    if (active) pauseActiveLifetime()
    service.markHistoryUnavailable(row.originalId, row.timestamp)
    service.deletePopupFileFor(row)
    updated.remainingLifetime = durationFor(updated.urgency, updated.expireTimeout)
    updated.queuePriority = typeof row.queuePriority === "boolean"
      ? row.queuePriority : NotificationLogic.popupQueuePriority(row, NotificationUrgency.Critical)
    updated.queueOrder = ensurePopupQueueOrder(row)
    var roles = NotificationLogic.popupRoles()
    popupModel.setProperty(rowIndex, "timestamp", updated.timestamp)
    for (var r = 0; r < roles.length; r++) popupModel.setProperty(rowIndex, roles[r], updated[roles[r]])
    service.liveGenerations[updated.originalId] = updated.timestamp
    service.livePersistenceSources[updated.originalId] = updated.transient ? "none" : "popup"
    if (NotificationLogic.shouldPersistPopup(updated)) service.persistPopupFile(updated)
    if (active) {
      if (popupMotionState === "open") popupRenderedIdentity = newIdentity
      prepareActiveLifetimeDisplay()
      if (popupMotionState === "open" && !activePopupHovered) startActiveLifetime()
    }
  }

  function dismissPopup(index) {
    if (index < 0 || index >= popupModel.count) return
    dispatchPresentation({ type: "DISMISS", identity: identityForSnapshot(popupModel.get(index)) })
  }

  function expirePopup(index) {
    if (index < 0 || index >= popupModel.count) return
    dispatchPresentation({ type: "DISMISS", identity: identityForSnapshot(popupModel.get(index)) })
  }

  function finalizePopupRemoval(index, reason) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var originalId = entry ? entry.originalId : -1
    if (entry) service.markHistoryUnavailable(originalId, entry.timestamp)
    var internal = Number(originalId) < 0
    var restored = isRestoredRow(entry)
    var source = restoredSource(entry) || livePersistenceSources[originalId] || ""
    var ref = !internal && !restored && originalId >= 0 ? liveRefs[originalId] : null

    if (entry && !internal && reason === "closed") {
      if (source === "history") deleteHistoryFileFor(entry)
      else if (source === "popup") deletePopupFileFor(entry)
    } else if (entry && !internal && source !== "history" && entry.transient !== true) {
      archivePopupFileFor(entry)
    }
    if (restored) delete restoredPopups[NotificationLogic.popupFileName(entry)]
    popupModel.remove(index)
    if (pendingPreemptionIdentity !== ""
        && popupIndexForIdentity(pendingPreemptionIdentity) < 0)
      pendingPreemptionIdentity = ""

    if (ref && reason !== "closed") {
      delete liveRefs[originalId]
      delete liveGenerations[originalId]
      delete livePersistenceSources[originalId]
      service.clearFailedHistoryAction(originalId, entry.timestamp)
      try {
        if (ref.tracked) {
          if (reason === "expire" && typeof ref.expire === "function") ref.expire()
          else ref.dismiss()
        }
      } catch (error) {
        // The sender can tear down a reference before the card disappears.
      }
    }
  }

  function requestPopupRemoval(identity, reason) {
    dispatchPresentation({
      type: reason === "closed" ? "SENDER_CLOSED" : "DISMISS", identity: String(identity || "")
    })
  }

  function clearPopups() {
    dispatchPresentation({ type: "DISMISS_ALL" })
  }

  function liveAction(ref, identifier) {
    if (!ref || !ref.actions) return null
    var wanted = String(identifier || "")
    var limit = Math.min(ref.actions.length, 8)
    for (var i = 0; i < limit; i++) {
      var action = ref.actions[i]
      if (action && action.identifier === wanted) return action
    }
    return null
  }

  function invokePopupAction(index, identifier, forceDismiss, historyEntry) {
    if (index < 0 || index >= popupModel.count) return false
    var entry = popupModel.get(index)
    var ref = entry && !isRestoredRow(entry) ? liveRefs[entry.originalId] : null
    var action = liveAction(ref, String(identifier || ""))
    if (!action) return false

    var identity = NotificationLogic.popupIdentity(entry)
    var shouldDismiss = forceDismiss === true || ref.resident !== true
    if (shouldDismiss) actionClosingGenerations[entry.originalId] = entry.timestamp
    try {
      action.invoke()
    } catch (error) {
      if (shouldDismiss) delete actionClosingGenerations[entry.originalId]
      if (historyEntry) service.rememberFailedHistoryAction(historyEntry)
      console.warn("notifications: action failed", error)
      return false
    }

    if (shouldDismiss) {
      requestPopupRemoval(identity, "dismiss")
      delete actionClosingGenerations[entry.originalId]
    }
    return true
  }

  function clickPopup(index) {
    if (index < 0 || index >= popupModel.count) return
    clickPopupIdentity(NotificationLogic.popupIdentity(popupModel.get(index)))
  }

  function invokePopupActionIdentity(identity, identifier, forceDismiss, historyEntry) {
    var index = popupIndexForIdentity(identity)
    if (index < 0) return false
    return invokePopupAction(index, identifier, forceDismiss, historyEntry)
  }

  function clickPopupIdentity(identity) {
    if (!invokePopupActionIdentity(identity, "default", true)) requestPopupRemoval(identity, "dismiss")
  }

  function invokePopupDefault(index, historyEntry) {
    return invokePopupAction(index, "default", false, historyEntry)
  }

  function showDndConfirmation() {
    var timestamp = NotificationLogic.nextMonotonicTimestamp(service.latestLiveGeneration, Date.now())
    service.latestLiveGeneration = timestamp
    var id = -timestamp
    var next = {
      id: id, originalId: id, app: "desktop-shell", appIcon: "",
      summary: service.doNotDisturb ? "Do not disturb enabled" : "Do not disturb disabled",
      body: "", image: "", urgency: NotificationUrgency.Low, expireTimeout: 2500,
      remainingLifetime: durationFor(NotificationUrgency.Low, 2500),
      duration: durationFor(NotificationUrgency.Low, 2500), transient: false,
      presentationSource: "none", actions: [], timestamp: timestamp
    }
    var state = service.presentationState
    var oldIdentity = service.dndConfirmationIdentity
    var known = state.active && identityForSnapshot(state.active) === oldIdentity
    if (!known) for (var i = 0; i < state.pending.length; i++)
      if (identityForSnapshot(state.pending[i]) === oldIdentity) known = true
    if (!known && (state.active ? state.pending.length + 1 : state.pending.length) >= service.maxActivePopups) {
      service.persistenceError = "notification active popup limit reached"
      return
    }
    dispatchPresentation(known
      ? { type: "REPLACE", identity: oldIdentity, snapshot: next }
      : { type: "ARRIVE", snapshot: next })
    dndConfirmationIdentity = identityForSnapshot(next)
  }

  Process {
    id: ensureDirsProc
    command: ["bash", "-c",
      "umask 077\n" +
      "mkdir -p -- \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" || exit 1\n" +
      "chmod 700 -- \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" || exit 1\n" +
      "for file in \"$3\"/*.json \"$4\"/*.json \"$5\"/*; do\n" +
      "  [[ -e $file ]] || continue\n" +
      "  [[ -f $file && ! -L $file ]] || exit 1\n" +
      "  chmod 600 -- \"$file\" || exit 1\n" +
      "done\n" +
      "if [[ -L $6 || ( -e $6 && ! -f $6 ) ]]; then exit 1; fi\n" +
      "if [[ -e $6 ]]; then chmod 600 -- \"$6\" || exit 1; fi", "--",
      service.stateDir, service.notificationStateDir, service.popupStateDir,
      service.historyDir, service.imagesDir, service.settingsPath]
    running: false
    onExited: function(exitCode) {
      if (Number(exitCode) !== 0)
        service.persistenceError = "notification state directory creation failed (exit " + String(exitCode) + ")"
    }
  }

  property var popupFileQueue: []
  property var runningPopupFileJob: null
  property var runningHistoryReadGeneration: null
  property int persistenceGeneration: 0
  property var latestPersistenceGenerations: ({})

  function pendingPersistenceCount() {
    return popupFileQueue.length
  }

  function hasPersistenceIntentForKey(key) {
    if (!key) return false
    if (runningPopupFileJob && runningPopupFileJob.key === key) return true
    if (key === "history-read" && runningHistoryReadGeneration !== null) return true
    for (var i = 0; i < popupFileQueue.length; i++) {
      if (popupFileQueue[i] && popupFileQueue[i].key === key) return true
    }
    return false
  }

  function protectedPersistenceKeys() {
    var protectedKeys = {}
    if (runningPopupFileJob && runningPopupFileJob.key)
      protectedKeys[runningPopupFileJob.key] = true
    if (runningHistoryReadGeneration !== null) protectedKeys["history-read"] = true
    return protectedKeys
  }

  function notifyDroppedPersistenceJob(job) {
    service.persistenceError = "notification persistence queue full; dropped oldest job"
    if (job && job.done) {
      try { job.done(false, 75, "capacity-dropped") } catch (error) {
        console.warn("notifications: dropped file callback failed", error)
      }
    }
    service.releasePersistenceGeneration(job)
  }

  function isCurrentPersistenceJob(job) {
    if (!job || !job.key) return true
    return Number(latestPersistenceGenerations[job.key]) === Number(job.generation)
  }

  function releasePersistenceGeneration(job, releaseAny) {
    if (!job || !job.key || service.hasPersistenceIntentForKey(job.key)) return
    if (!releaseAny && !service.isCurrentPersistenceJob(job)) return
    delete latestPersistenceGenerations[job.key]
  }

  function notifyStalePersistenceJob(job) {
    service.persistenceError = "stale persistence job discarded"
    if (job && job.done) {
      try { job.done(false, 75, "superseded") } catch (error) {
        console.warn("notifications: stale file callback failed", error)
      }
    }
    service.releasePersistenceGeneration(job, true)
  }

  function enqueuePersistenceJob(job, front) {
    if (job.generation === undefined || job.generation === null) {
      service.persistenceGeneration++
      job.generation = service.persistenceGeneration
      if (job.key) service.latestPersistenceGenerations[job.key] = job.generation
    }
    var updated = NotificationLogic.persistenceQueueUpdate(
      popupFileQueue, job, maxPersistenceJobs, front === true, service.protectedPersistenceKeys())
    if (updated.stale) {
      service.notifyStalePersistenceJob(job)
      return
    }
    popupFileQueue = updated.queue
    if (updated.dropped) {
      if (updated.droppedOutcome === "superseded") service.notifyStalePersistenceJob(updated.dropped)
      else service.notifyDroppedPersistenceJob(updated.dropped)
    }
    runNextPopupFileJob()
  }

  function enqueuePopupFileJob(command, done, attempt, key, front) {
    enqueuePersistenceJob({
      command: command,
      done: done || null,
      attempt: Number(attempt || 0),
      key: key || "",
    }, front === true)
  }

  function enqueueHistoryRead(requestGeneration) {
    enqueuePersistenceJob({
      read: true,
      key: "history-read",
      requestGeneration: requestGeneration,
    }, false)
  }

  function runNextPopupFileJob() {
    if (readHistoryProc.running || popupFileProc.running) return
    if (popupFileQueue.length === 0) return

    var job = popupFileQueue[0]
    popupFileQueue = popupFileQueue.slice(1)
    if (job.read) {
      service.runningHistoryReadGeneration = job.generation
      service.runningHistoryViewGeneration = Number(job.requestGeneration)
      startHistoryRead()
      return
    }

    popupFileProc.command = job.command
    service.runningPopupFileJob = job
    popupFileProc.running = true
  }

  Process {
    id: popupFileProc
    running: false
    onExited: function(exitCode) {
      var job = service.runningPopupFileJob
      service.runningPopupFileJob = null
      var success = Number(exitCode) === 0
      if (job && !service.isCurrentPersistenceJob(job)) {
        service.notifyStalePersistenceJob(job)
        service.runNextPopupFileJob()
        service.releasePersistenceGeneration(job, true)
        return
      }
      if (!success) {
        service.persistenceError = "notification persistence job failed (exit " + String(exitCode) + ")"
        if (job && job.attempt < service.persistenceRetryLimit) {
          service.enqueuePersistenceJob({
            command: job.command,
            done: job.done,
            attempt: job.attempt + 1,
            key: job.key || "",
            generation: job.generation,
          }, true)
          return
        }
      }
      if (job && job.done) {
        try { job.done(success, exitCode) } catch (error) {
          console.warn("notifications: file callback failed", error)
        }
      }
      service.runNextPopupFileJob()
      service.releasePersistenceGeneration(job)
    }
  }

  readonly property string copyImagesScript:
    "umask 077\n" +
    "while (( $# >= 2 )); do\n" +
    "  if [[ -f $1 ]] && timeout 5 head -c 5242881 -- \"$1\" > \"$2.tmp\" 2>/dev/null &&\n" +
    "     (( $(stat -c%s -- \"$2.tmp\") <= 5242880 )) && chmod 600 -- \"$2.tmp\"; then mv -f -- \"$2.tmp\" \"$2\"; else rm -f -- \"$2.tmp\"; fi\n" +
    "  shift 2\n" +
    "done\n"

  function persistPopupFile(snapshot) {
    if (!NotificationLogic.shouldPersistPopup(snapshot)) return
    var persistable = NotificationLogic.persistablePopup(snapshot, imagesDir)
    var command = ["bash", "-c",
      "umask 077\n" +
      "mkdir -p -- \"$1\" \"$2\" || exit 1\n" +
      "chmod 700 -- \"$1\" \"$2\" || exit 1\n" +
      "dir=\"$1\" json=\"$3\" name=\"$4\"\n" +
      "temporary=$(mktemp \"$dir/$name.XXXXXX\") || exit 1\n" +
      "trap 'rm -f -- \"$temporary\"' EXIT HUP INT TERM\n" +
      copyImagesScript +
      "printf '%s\\n' \"$json\" > \"$temporary\" && chmod 600 -- \"$temporary\" && " +
      "mv -f -- \"$temporary\" \"$dir/$name\" || exit 1\n" +
      "trap - EXIT HUP INT TERM", "--",
      popupStateDir,
      imagesDir,
      NotificationLogic.serializePopup(persistable.entry, NotificationUrgency.Normal),
      NotificationLogic.popupFileName(snapshot)]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueuePopupFileJob(command, null, 0, "popup:" + NotificationLogic.popupFileName(snapshot))
  }

  function deletePopupFileFor(row) {
    if (!row) return
    enqueuePopupFileJob(["bash", "-c",
      "umask 077\nrm -f -- \"$1/$2.json\" \"$3/$2\"-*", "--",
      popupStateDir, NotificationLogic.imageStem(row), imagesDir], null, 0,
      "popup:" + NotificationLogic.popupFileName(row))
  }

  function deleteHistoryFileFor(row) {
    if (!row) return
    enqueuePopupFileJob(["bash", "-c",
      "umask 077\nrm -f -- \"$1/$2.json\" \"$3/$2\"-*", "--",
      historyDir, NotificationLogic.imageStem(row), imagesDir], null, 0,
      "history:" + NotificationLogic.popupFileName(row))
  }

  readonly property string trimHistoryScript:
    "ls -1 \"$hist\" 2>/dev/null | sort -n | head -n \"-$limit\" | while IFS= read -r stale; do rm -f \"$hist/$stale\" \"$imgs/${stale%.json}\"-*; done"

  function archivePopupFileFor(row) {
    if (!row) return
    enqueuePopupFileJob(["bash", "-c",
      "umask 077\n" +
      "mkdir -p -- \"$1\" || exit 1\n" +
      "chmod 700 -- \"$1\" || exit 1\n" +
      "hist=\"$1\" limit=\"$2\" imgs=\"$5\"\n" +
      "mv -f -- \"$4/$3\" \"$1/$3\" 2>/dev/null || exit 1\n" +
      "chmod 600 -- \"$1/$3\" || exit 1\n" +
      trimHistoryScript, "--",
      historyDir,
      String(historyLimit),
      NotificationLogic.popupFileName(row),
      popupStateDir,
       imagesDir], service.updateHistoryCount, 0, "popup:" + NotificationLogic.popupFileName(row))
  }

  function writeHistoryFile(entry, done) {
    if (!entry) {
      if (done) done(true, 0)
      return
    }
    var persistable = NotificationLogic.persistablePopup(entry, imagesDir)
    var command = ["bash", "-c",
      "umask 077\n" +
      "mkdir -p -- \"$1\" \"$5\" || exit 1\n" +
      "chmod 700 -- \"$1\" \"$5\" || exit 1\n" +
      "hist=\"$1\" limit=\"$2\" name=\"$3\" json=\"$4\" imgs=\"$5\"\n" +
      "temporary=$(mktemp \"$hist/$name.XXXXXX\") || exit 1\n" +
      "trap 'rm -f -- \"$temporary\"' EXIT HUP INT TERM\n" +
      "shift 5\n" +
      copyImagesScript +
      "printf '%s\\n' \"$json\" > \"$temporary\" && chmod 600 -- \"$temporary\" && " +
      "mv -f -- \"$temporary\" \"$hist/$name\" || exit 1\n" +
      trimHistoryScript, "--",
      historyDir,
      String(historyLimit),
      NotificationLogic.popupFileName(entry),
      NotificationLogic.serializePopup(persistable.entry, NotificationUrgency.Normal),
      imagesDir]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueuePopupFileJob(command, function(success, exitCode, outcome) {
      if (outcome === "superseded") return
      if (!success) {
        if (done) done(false, exitCode, false)
        return
      }
      service.updateHistoryCount()
      if (done) done(true, exitCode, false)
    }, 0, "history:" + NotificationLogic.popupFileName(entry))
  }

  function clearHistory() {
    enqueuePopupFileJob(["bash", "-c",
      "umask 077\n" +
      "for f in \"$1\"/*.json; do\n" +
      "  [[ -e $f ]] || continue\n" +
      "  stale=\"${f##*/}\"\n" +
      "  rm -f \"$f\" \"$2/${stale%.json}\"-*\n" +
       "done", "--", historyDir, imagesDir], service.updateHistoryCount, 0, "history-clear")
  }

  function sweepOrphanImages() {
    enqueuePopupFileJob(["bash", "-c",
      "umask 077\n" +
      "for img in \"$3\"/*; do\n" +
      "  [[ -e $img ]] || continue\n" +
      "  [[ $img == *.tmp ]] && { rm -f -- \"$img\"; continue; }\n" +
      "  stem=\"${img##*/}\"\n" +
      "  stem=\"${stem%-*}\"\n" +
      "  [[ -e $1/$stem.json || -e $2/$stem.json ]] || rm -f \"$img\"\n" +
       "done", "--", popupStateDir, historyDir, imagesDir], null, 0, "image-sweep")
  }

  Process {
    id: readHistoryProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.historyReadRaw = text
    }
    onExited: function(exitCode) {
      var viewGeneration = service.runningHistoryViewGeneration
      var completed = {
        key: "history-read",
        generation: service.runningHistoryReadGeneration,
      }
      service.runningHistoryReadGeneration = null
      service.runningHistoryViewGeneration = -1
      if (Number(exitCode) === 0) {
        service.loadHistoryModel(service.historyReadRaw, viewGeneration)
      } else {
        service.persistenceError = "notification history read failed (exit " + String(exitCode) + ")"
        service.loadHistoryModel("", viewGeneration)
      }
      service.historyReadRaw = ""
      service.runNextPopupFileJob()
      service.releasePersistenceGeneration(completed)
    }
  }

  function startHistoryRead() {
    readHistoryProc.command = ["bash", "-c",
      "shopt -s nullglob\nfiles=(\"$1\"/*.json)\n((${#files[@]} == 0)) || awk 1 \"${files[@]}\"",
      "--", historyDir]
    readHistoryProc.running = true
  }

  function liveRowsForHistory() {
    var rows = []
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (!row || Number(row.originalId) < 0 || row.transient === true) continue
      rows.push({
        id: row.id,
        originalId: row.originalId,
        app: row.app,
        appIcon: row.appIcon,
        summary: row.summary,
        body: row.body,
        image: row.image,
        urgency: row.urgency,
        timestamp: row.timestamp,
        actionAvailable: NotificationLogic.historyActionAvailable(
          row, liveRefs[row.originalId], liveGenerations[row.originalId])
      })
    }
    return rows
  }

  function revalidatedHistoryRows() {
    var rows = []
    for (var i = 0; i < service.historyLiveSnapshot.length; i++) {
      var captured = service.historyLiveSnapshot[i]
      if (!captured) continue
      rows.push({
        id: captured.id,
        originalId: captured.originalId,
        app: captured.app,
        appIcon: captured.appIcon,
        summary: captured.summary,
        body: captured.body,
        image: captured.image,
        urgency: captured.urgency,
        timestamp: captured.timestamp,
        actionAvailable: NotificationLogic.historyActionAvailable(
          captured, liveRefs[captured.originalId], liveGenerations[captured.originalId])
      })
    }
    return rows
  }

  function loadHistoryModel(raw, requestGeneration) {
    var result = NotificationLogic.historyReadTransition(
      raw, service.revalidatedHistoryRows(), NotificationUrgency.Normal, service.historyLimit,
      service.historyOpen, requestGeneration, service.historyRequestGeneration)
    if (!result.accepted) return
    historyModel.clear()
    for (var i = 0; i < result.rows.length; i++) historyModel.append(result.rows[i])
    service.updateHistoryCount()
  }

  function openHistory() {
    service.historyRequestGeneration++
    service.historyOpen = true
    service.historyLiveSnapshot = service.liveRowsForHistory()
    historyModel.clear()
    service.enqueueHistoryRead(service.historyRequestGeneration)
    return "ok"
  }

  function closeHistory() {
    service.historyRequestGeneration++
    service.historyOpen = false
    return "ok"
  }

  function toggleHistory() {
    return service.historyOpen ? service.closeHistory() : service.openHistory()
  }

  function popupIndexForHistoryIdentity(originalId, timestamp) {
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (row && row.originalId === originalId && Number(row.timestamp) === Number(timestamp)) return i
    }
    return -1
  }

  function invokeHistoryDefault(index) {
    if (index < 0 || index >= historyModel.count) return false
    var entry = historyModel.get(index)
    var actionState = NotificationLogic.historyActionTransition(
      entry, service.failedHistoryActions, "check")
    if (!actionState.allowed) {
      historyModel.setProperty(index, "actionAvailable", false)
      return false
    }
    var ref = entry ? liveRefs[entry.originalId] : null
    var generation = entry ? liveGenerations[entry.originalId] : null
    if (!NotificationLogic.historyActionAvailable(entry, ref, generation)) {
      historyModel.setProperty(index, "actionAvailable", false)
      return false
    }

    var popupIndex = popupIndexForHistoryIdentity(entry.originalId, entry.timestamp)
    if (popupIndex < 0 || !service.invokePopupDefault(popupIndex, entry)) {
      historyModel.setProperty(index, "actionAvailable", false)
      return false
    }
    service.closeHistory()
    return true
  }

  function markHistoryUnavailable(originalId, timestamp) {
    service.clearFailedHistoryAction(originalId, timestamp)
    for (var i = 0; i < historyModel.count; i++) {
      var row = historyModel.get(i)
      if (row && row.originalId === originalId && Number(row.timestamp) === Number(timestamp)) {
        historyModel.setProperty(i, "actionAvailable", false)
        return
      }
    }
  }

  function clearFailedHistoryAction(originalId, timestamp) {
    var result = NotificationLogic.historyActionTransition({
      originalId: originalId,
      timestamp: timestamp,
    }, service.failedHistoryActions, "ended")
    service.failedHistoryActions = result.failedIdentities
  }

  function rememberFailedHistoryAction(entry) {
    var result = NotificationLogic.historyActionTransition(
      entry, service.failedHistoryActions, "failed")
    var failed = result.failedIdentities
    var keys = Object.keys(failed)
    if (keys.length > service.maxActivePopups) delete failed[keys[0]]
    service.failedHistoryActions = failed
  }

  Process {
    id: restoreLastProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.restoreLastFromRaw(text)
    }
  }

  function restoreLastFromRaw(raw) {
    var row = NotificationLogic.latestHistoryRow(raw, NotificationUrgency.Normal)
    if (!row) return
    var fileName = NotificationLogic.popupFileName(row)
    if (service.restoredPopups[fileName]) return
    for (var i = 0; i < popupModel.count; i++) {
      var current = popupModel.get(i)
      if (current && NotificationLogic.popupFileName(current) === fileName) return
    }
    row.remainingLifetime = 0
    row.duration = durationFor(row.urgency, row.expireTimeout)
    row.queuePriority = NotificationLogic.popupQueuePriority(row, NotificationUrgency.Critical)
    ensurePopupQueueOrder(row)
    delete row.deadline
    row.transient = false
    row.presentationSource = "history"
    service.restoredPopups[fileName] = "history"
    service.dispatchPresentation({ type: "ARRIVE", snapshot: row })
  }

  Process {
    id: restorePopupsProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.restorePopups(text)
    }
  }

  function restorePopups(raw) {
    var entries = NotificationLogic.parsePopupFiles(raw, NotificationUrgency.Normal, service.maxActivePopups)
    service.latestPopupQueueOrder = Math.max(
      service.latestPopupQueueOrder, NotificationLogic.popupQueueOrderSeed(entries))
    var now = Date.now()
    var live = []
    var migrationEntries = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (Number(entry.originalId) < 0) {
        deletePopupFileFor(entry)
        continue
      }
      entry.transient = entry.transient === true
      if (entry.transient) {
        deletePopupFileFor(entry)
        continue
      }
      var duration = durationFor(entry.urgency, entry.expireTimeout)
      entry.duration = duration
      var needsMigration = entry.queuePriority === undefined
        || entry.queueOrder === undefined
        || (entry.remainingLifetime === undefined && entry.deadline !== undefined)
      if (entry.queuePriority === undefined)
        entry.queuePriority = NotificationLogic.popupQueuePriority(entry, NotificationUrgency.Critical)
      entry.remainingLifetime = NotificationLogic.restoredRemainingLifetime(entry, duration, now)
      delete entry.deadline
      if (duration > 0 && entry.remainingLifetime <= 0) {
        archivePopupFileFor(entry)
        continue
      }
      if (needsMigration) migrationEntries.push(entry)
      live.push(entry)
    }
    live = NotificationLogic.migratePopupQueue(live)
    for (var migrated = 0; migrated < migrationEntries.length; migrated++)
      persistPopupFile(migrationEntries[migrated])
    live = NotificationLogic.sortPopupQueue(live, NotificationUrgency.Critical)
    if (live.length === 0) return

    Qt.callLater(function() {
      for (var j = 0; j < live.length; j++) {
        var restored = live[j]
        var duplicate = false
        for (var k = 0; k < popupModel.count; k++) {
          var row = popupModel.get(k)
          if (row && row.originalId === restored.originalId && row.timestamp === restored.timestamp) {
            duplicate = true
            break
          }
        }
        if (duplicate) continue
        if (restored.remainingLifetime === undefined) restored.remainingLifetime = 0
        if (restored.transient === undefined) restored.transient = false
        restored.presentationSource = "popup"
        service.restoredPopups[NotificationLogic.popupFileName(restored)] = "popup"
        service.dispatchPresentation({ type: "ARRIVE", snapshot: restored })
      }
      service.syncPresentationModel()
    })
  }

  Process {
    id: settingsWriteProc
    running: false
    onExited: function(exitCode) {
      if (Number(exitCode) !== 0)
        service.persistenceError = "notification settings persistence failed (exit " + String(exitCode) + ")"
      if (service.settingsSavePending) {
        service.settingsSavePending = false
        service.scheduleSettingsSave()
      }
    }
  }

  property bool settingsLoaded: false
  property bool settingsSavePending: false

  FileView {
    id: settingsFile
    path: service.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadSettings(text())
    onLoadFailed: service.loadSettings("")
  }

  Timer {
    id: settingsSaveTimer
    interval: 200
    repeat: false
    onTriggered: service.flushSettings()
  }

  function scheduleSettingsSave() {
    if (!service.settingsLoaded) return
    settingsSaveTimer.restart()
  }

  function loadSettings(raw) {
    if (service.settingsLoaded) return
    var parsed = NotificationLogic.parseSettings(raw)
    if (parsed.error) console.warn("notifications: settings parse failed", parsed.errorMessage || "")

    if (parsed.dnd !== null) {
      service._hydrating = true
      persisted.doNotDisturb = parsed.dnd
      service._hydrating = false
    }
    service.settingsLoaded = true
    if (parsed.legacy) service.scheduleSettingsSave()
  }

  function flushSettings() {
    if (settingsWriteProc.running) {
      service.settingsSavePending = true
      return
    }
    service.settingsSavePending = false
    settingsWriteProc.command = ["bash", "-c",
      "umask 077\n" +
      "dir=${1%/*}\n" +
      "mkdir -p -- \"$dir\" || exit 1\n" +
      "chmod 700 -- \"$dir\" || exit 1\n" +
      "temporary=$(mktemp \"$1.XXXXXX\") || exit 1\n" +
      "trap 'rm -f -- \"$temporary\"' EXIT HUP INT TERM\n" +
      "printf '%s\\n' \"$2\" >\"$temporary\" || exit 1\n" +
      "chmod 600 -- \"$temporary\" || exit 1\n" +
      "mv -f -- \"$temporary\" \"$1\" || exit 1\n" +
      "trap - EXIT HUP INT TERM", "--", service.settingsPath,
      JSON.stringify({ version: 3, dnd: persisted.doNotDisturb }, null, 2)]
    settingsWriteProc.running = true
  }

  FileView {
    id: routeFile
    path: service.routePath
    watchChanges: true
    printErrors: false
    onFileChanged: {
      service.noteRouteCandidateChange()
      service.scheduleRouteMetadataCheck()
    }
  }

  FileView {
    id: leaseFile
    path: service.leasePath
    watchChanges: true
    printErrors: false
    onFileChanged: {
      service.noteRouteCandidateChange()
      service.scheduleRouteMetadataCheck()
    }
  }

  Process {
    id: routeMetadata
    running: false
    command: []
    stdout: SplitParser {
      id: routeMetadataStdout
      splitMarker: "\n"
      onRead: function(data) {
        service.captureRouteMetadata(data)
      }
    }
    onExited: function(exitCode) {
      service.finishRouteMetadata(exitCode)
    }
  }

  Timer {
    id: routeExpiryTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      service.scheduleRouteMetadataCheck()
    }
  }

  Timer {
    id: routeCandidateSettleTimer
    interval: 100
    repeat: false
    running: false
    onTriggered: {
      service.routeMetadataCheckScheduled = false
      service.checkRouteMetadata()
    }
  }

  Timer {
    id: routeLeaseExpiryTimer
    interval: 1
    repeat: false
    running: false
    onTriggered: {
      service.failClosedRoute("notification route lease expired")
      service.scheduleRouteMetadataCheck()
    }
  }

  function recordRouteTransition(nextValid, reason) {
    var next = nextValid === true
    var previous = service.routeValid
    if (previous === next) return

    var log = Array.isArray(service.routeTransitionLog) ? service.routeTransitionLog.slice() : []
    log.push({
      from: previous,
      to: next,
      generation: service.routeAcceptedGeneration,
      atMs: Date.now(),
      reason: String(reason || "")
    })
    while (log.length > 32) log.shift()
    service.routeTransitionLog = log
    service.routeTransitionCount++
    if (previous && !next) service.routeInvalidationCount++
    service.routeLastTransitionReason = String(reason || "")
    service.routeValid = next
  }

  function failClosedRoute(error) {
    var message = String(error || "invalid route")
    routeLeaseExpiryTimer.stop()
    service.routeMetadataValid = false
    service.routeMetadataError = message
    service.leaseValid = false
    service.leaseError = message
    service.routeMetadataSnapshot = null
    service.routeMetadataSnapshotRevision = -1
    service.acceptedRoute = null
    service.acceptedLease = null
    service.routeAcceptedRefreshedAtMs = -1
    service.routeAcceptedExpiresAtMs = -1
    service.routeRaw = ""
    service.leaseRaw = ""
    service.route = {
      valid: false,
      visible: false,
      output: null,
      cueOutput: null,
      direction: null,
      error: message
    }
    service.routeError = message
    service.routeCandidateError = message
    service.routeCandidatePending = false
    service.routeCandidateMetadataPending = false
    service.recordRouteTransition(false, message)
    service.routeAcceptedGeneration = -1
  }

  function routeMetadataScript() {
    return "set -Eeuo pipefail\n" +
      "export LC_ALL=C\n" +
      "uid=$(id -u)\n" +
      "max_payload_bytes=8192\n" +
      "max_result_bytes=32768\n" +
      "route_dir=$1\nroute_file=$2\nlease_file=$3\nrevision=$4\n" +
      "[[ $revision =~ ^[0-9]+$ ]] || exit 2\n" +
      "secure_identity() {\n" +
      "  local path=$1 identity owner mode type\n" +
      "  [[ -e $path && ! -L $path ]] || exit 10\n" +
      "  identity=$(stat -c '%d %i %u %a %F' -- \"$path\") || exit 10\n" +
      "  read -r _device _inode owner mode type <<<\"$identity\"\n" +
      "  [[ $owner == $uid && $mode == $2 && $type == $3 ]] || exit 10\n" +
      "  printf '%s\\n' \"$identity\"\n" +
      "}\n" +
      "bounded_base64() {\n" +
      "  local path=$1 size encoded decoded_size\n" +
      "  size=$(stat -c '%s' -- \"$path\") || exit 11\n" +
      "  [[ $size =~ ^[0-9]+$ ]] && ((size <= max_payload_bytes)) || exit 11\n" +
      "  encoded=$(head -c \"$((max_payload_bytes + 1))\" -- \"$path\" | base64 -w0) || exit 11\n" +
      "  decoded_size=$(printf '%s' \"$encoded\" | base64 -d | wc -c) || exit 11\n" +
      "  decoded_size=\"${decoded_size//[[:space:]]/}\"\n" +
      "  [[ $decoded_size == \"$size\" ]] || exit 11\n" +
      "  printf '%s' \"$encoded\"\n" +
      "}\n" +
      "directory_before=$(secure_identity \"$route_dir\" 700 directory)\n" +
      "route_before=$(secure_identity \"$route_file\" 600 'regular file')\n" +
      "lease_before=$(secure_identity \"$lease_file\" 600 'regular file')\n" +
      "route_b64=$(bounded_base64 \"$route_file\")\n" +
      "lease_b64=$(bounded_base64 \"$lease_file\")\n" +
      "route_after=$(secure_identity \"$route_file\" 600 'regular file')\n" +
      "lease_after=$(secure_identity \"$lease_file\" 600 'regular file')\n" +
      "directory_after=$(secure_identity \"$route_dir\" 700 directory)\n" +
      "[[ $directory_before == \"$directory_after\" ]] || exit 12\n" +
      "[[ $route_before == \"$route_after\" && $lease_before == \"$lease_after\" ]] || exit 12\n" +
      "route_b64_after=$(bounded_base64 \"$route_file\")\n" +
      "lease_b64_after=$(bounded_base64 \"$lease_file\")\n" +
      "[[ $route_b64 == \"$route_b64_after\" && $lease_b64 == \"$lease_b64_after\" ]] || exit 12\n" +
      "result=$(jq -cn --arg revision \"$revision\" --arg routeB64 \"$route_b64\" --arg leaseB64 \"$lease_b64\" '{revision: ($revision | tonumber), routeB64: $routeB64, leaseB64: $leaseB64}')\n" +
      "((\${#result} <= max_result_bytes)) || exit 13\n" +
      "printf '%s\\n' \"$result\""
  }

  function startRouteMetadataCheck() {
    var revision = service.routeMetadataGeneration
    service.routeMetadataAttemptCount++
    service.routeMetadataCheckGeneration = revision
    service.routeMetadataSnapshot = null
    service.routeMetadataSnapshotRevision = -1
    service.routeCandidateMetadataPending = true
    routeMetadata.command = ["bash", "-c", service.routeMetadataScript(), "--",
      service.routeDir, service.routePath, service.leasePath, String(revision)]
    routeMetadata.running = true
  }

  function captureRouteMetadata(raw) {
    var parsed
    var text = String(raw || "").trim()
    if (!text || text.length > 32768) return
    try {
      parsed = JSON.parse(text)
    } catch (error) {
      return
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) ||
        typeof parsed.routeB64 !== "string" || typeof parsed.leaseB64 !== "string") return
    var revision = Number(parsed.revision)
    if (!isFinite(revision) || Math.floor(revision) !== revision || revision < 0) return
    var routeRaw = Util.decodeBase64(parsed.routeB64)
    var leaseRaw = Util.decodeBase64(parsed.leaseB64)
    service.routeMetadataSnapshotRevision = revision
    service.routeMetadataSnapshot = Object.freeze({
      revision: revision,
      routeB64: parsed.routeB64,
      leaseB64: parsed.leaseB64,
      routeRaw: routeRaw,
      leaseRaw: leaseRaw
    })
  }

  function finishRouteMetadata(exitCode) {
    var revision = service.routeMetadataCheckGeneration
    var snapshot = service.routeMetadataSnapshot
    var currentRevision = revision === service.routeMetadataGeneration
    var matchingSnapshot = !!snapshot && snapshot.revision === revision
    service.routeMetadataSnapshot = null
    service.routeMetadataSnapshotRevision = -1
    if (!currentRevision) {
      service.scheduleRouteMetadataCheck()
      return
    }
    if (!matchingSnapshot || Number(exitCode) !== 0) {
      service.routeCandidatePending = true
      service.routeCandidateMetadataPending = true
      return
    }
    service.promoteRouteCandidate(snapshot)
  }

  function normalizedRouteCandidate(routeRaw, leaseRaw) {
    var now = Date.now()
    var next = NotificationLogic.normalizeRoute(routeRaw, now)
    var nextLease = NotificationLogic.normalizeLease(leaseRaw, now, next.updatedAt)
    return {
      route: next,
      lease: nextLease,
      valid: next.valid === true && nextLease.valid === true
    }
  }

  function candidateWaitsForLease(candidate) {
    return candidate.route.valid === true && candidate.lease.valid !== true
      && /route timestamp/.test(candidate.lease.error || "")
  }

  function checkRouteMetadata() {
    if (routeMetadata.running) return
    service.routeCandidatePending = false
    service.routeCandidateMetadataPending = true
    service.startRouteMetadataCheck()
  }

  function promoteRouteCandidate(snapshot) {
    if (!snapshot || snapshot.revision !== service.routeMetadataGeneration ||
        snapshot.revision !== service.routeMetadataCheckGeneration) {
      service.scheduleRouteMetadataCheck()
      return
    }
    var candidate = service.normalizedRouteCandidate(snapshot.routeRaw, snapshot.leaseRaw)
    if (!candidate.valid) {
      if (service.routeAcceptedGeneration >= 0 && service.candidateWaitsForLease(candidate)) {
        service.routeCandidatePending = true
        service.routeCandidateMetadataPending = false
        return
      }
      service.failClosedRoute(candidate.route.valid ? candidate.lease.error : candidate.route.error)
      return
    }
    if (candidate.lease.expiresAtMs <= Date.now()) {
      service.failClosedRoute("notification route lease expired")
      return
    }

    if (service.routeMetadataValid && service.routeRaw === snapshot.routeRaw && service.leaseRaw === snapshot.leaseRaw) {
      service.routeAcceptedGeneration = snapshot.revision
      service.routeCandidatePending = false
      service.routeCandidateMetadataPending = false
      return
    }

    service.routeRaw = snapshot.routeRaw
    service.leaseRaw = snapshot.leaseRaw
    service.route = candidate.route
    service.acceptedRoute = candidate.route
    service.acceptedLease = candidate.lease
    service.leaseValid = true
    service.leaseError = ""
    service.routeMetadataValid = true
    service.routeMetadataError = ""
    service.routeCandidateError = ""
    service.routeCandidatePending = false
    service.routeCandidateMetadataPending = false
    service.routeAcceptedGeneration = snapshot.revision
    service.routeAcceptedRefreshedAtMs = Number(candidate.lease.refreshedAtMs)
    service.routeAcceptedExpiresAtMs = Number(candidate.lease.expiresAtMs)
    service.routeError = ""
    service.recordRouteTransition(true, "accepted route generation")

    var expiresAtMs = Number(candidate.lease.expiresAtMs)
    var remaining = expiresAtMs - Date.now()
    routeLeaseExpiryTimer.interval = Math.max(1, Math.ceil(remaining))
    routeLeaseExpiryTimer.restart()
  }

  function scheduleRouteMetadataCheck() {
    service.routeMetadataCheckScheduled = true
    routeCandidateSettleTimer.restart()
  }

  function invalidateRouteMetadata(incrementGeneration) {
    if (incrementGeneration !== false) service.routeMetadataGeneration++
    service.routeCandidatePending = true
    service.routeCandidateMetadataPending = true
    if (!service.routeValid) service.routeMetadataError = "notification route metadata check pending"
  }

  function noteRouteCandidateChange() {
    service.invalidateRouteMetadata()
  }

  function refreshRoute() {
    service.scheduleRouteMetadataCheck()
  }

  function screenName(screen) {
    return screen ? String(screen.name || "") : ""
  }

  function cardsVisibleOn(screen) {
    return !service.testSurfaceSuppressed && service.routeVisible
      && service.route.output !== null
      && String(service.route.output) === screenName(screen)
      && popupModel.count > 0
  }

  function cueVisibleOn(screen) {
    return !service.testSurfaceSuppressed && service.routeVisible && service.route.cueOutput !== null
      && String(service.route.cueOutput) === screenName(screen)
      && popupModel.count > 0
  }

  onRouteChanged: {
    dispatchPresentation({
      type: "ROUTE_CHANGED",
      visible: service.routeVisible,
      output: service.routeVisible ? String(service.route.output || "") : null
    })
  }

  onRouteVisibleChanged: {
    dispatchPresentation({
      type: "ROUTE_CHANGED",
      visible: service.routeVisible,
      output: service.routeVisible ? String(service.route.output || "") : null
    })
  }

  Process {
    id: historyCountProc
    running: false
    onExited: {
      if (!service.historyCountQueued) return
      service.historyCountQueued = false
      service.updateHistoryCount()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.setHistoryCount(text)
    }
  }

  function setHistoryCount(raw) {
    var count = Number(String(raw || "").trim())
    service.historyCount = isFinite(count) ? Math.max(0, Math.round(count)) : 0
  }

  function updateHistoryCount() {
    if (historyCountProc.running) {
      service.historyCountQueued = true
      return
    }
    service.historyCountQueued = false
    historyCountProc.command = ["bash", "-c",
      "count=0; for file in \"$1\"/*.json; do [[ -f $file ]] && count=$((count + 1)); done; printf '%s\\n' \"$count\"",
      "--", historyDir]
    historyCountProc.running = true
  }

  function setOwnershipState(owned, error) {
    service.notificationsOwned = owned === true
    service.ownershipError = service.notificationsOwned ? "" : String(error || "notification ownership unavailable")
  }

  function probeNotificationOwner() {
    if (!service.ownershipEnabled) {
      setOwnershipState(false, "notification registration disabled")
      return
    }
    if (!ownershipProbe.running) ownershipProbe.running = true
  }

  function updateNotificationOwner(exitCode, raw) {
    if (!service.ownershipEnabled) {
      setOwnershipState(false, "notification registration disabled")
      return
    }
    if (Number(exitCode) !== 0) {
      setOwnershipState(false, "busctl status failed (exit " + String(exitCode) + ")")
      return
    }
    var match = String(raw || "").match(/\bPID=(\d+)\b/)
    if (!match) {
      setOwnershipState(false, "notification owner is missing")
      return
    }
    if (Number(match[1]) !== Number(Quickshell.processId)) {
      setOwnershipState(false, "notification owner is PID " + String(match[1]))
      return
    }
    setOwnershipState(true, "")
  }

  Process {
    id: ownershipProbe
    // Run through bash so a missing busctl becomes a nonzero exit handled below.
    command: ["bash", "-c", "exec busctl --user status org.freedesktop.Notifications"]
    stdout: StdioCollector {
      id: ownershipStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      service.updateNotificationOwner(exitCode, ownershipStdout.text)
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: service.ownershipEnabled
    onTriggered: service.probeNotificationOwner()
  }

  onOwnershipEnabledChanged: {
    if (service.ownershipEnabled) service.probeNotificationOwner()
    else service.setOwnershipState(false, "notification registration disabled")
  }

  function dndState() {
    return service.doNotDisturb ? "enabled" : "disabled"
  }

  function setDnd(value) {
    var on
    if (typeof value === "boolean") on = value
    else {
      var normalized = String(value || "").toLowerCase()
      on = normalized === "true" || normalized === "1" || normalized === "on" || normalized === "yes"
    }
    service.setDoNotDisturb(on)
    service.showDndConfirmation()
    return dndState()
  }

  function setDoNotDisturb(value) {
    persisted.doNotDisturb = !!value
  }

  function toggleDnd() {
    return service.setDnd(!service.doNotDisturb)
  }

  function ping() {
    return "pong"
  }

  function status() {
    var frame = service.presentationFrame
    var canonicalClosed = service.testSurfaceSuppressed
    return JSON.stringify({
      notificationsOwned: service.notificationsOwned,
      ownershipError: service.ownershipError,
      persistenceError: service.persistenceError,
      dnd: service.doNotDisturb,
      liveCount: service.liveReferenceCount(),
      pendingPersistenceCount: service.pendingPersistenceCount(),
      persistenceGenerationCount: Object.keys(service.latestPersistenceGenerations).length,
      silencedRefreshCount: Object.keys(service.pendingSilencedRefreshes).length,
      silencedDirtyCount: Object.keys(service.silencedDirty).length,
      admissionDropped: service.admissionDropped,
      admissionWindowCount: service.admissionTimestamps.length,
      popupCount: popupModel.count,
      snapshotDuration: service.durationFor(NotificationUrgency.Normal, -1),
      snapshotRemainingLifetime: service.durationFor(NotificationUrgency.Normal, -1),
      phase: canonicalClosed ? "closed" : frame.phase,
      activeIdentity: canonicalClosed ? "" : (frame.active ? identityForSnapshot(frame.active) : ""),
      visualOutgoingIdentity: canonicalClosed ? "" : (frame.visual.outgoing
        ? identityForSnapshot(frame.visual.outgoing) : ""),
      visualIncomingIdentity: canonicalClosed ? "" : (frame.visual.incoming
        ? identityForSnapshot(frame.visual.incoming) : ""),
      transitionToken: canonicalClosed ? 0 : frame.visual.token,
      transitionKind: canonicalClosed ? "" : frame.visual.kind,
      countdownIdentity: canonicalClosed ? "" : frame.countdown.identity,
      pendingCount: canonicalClosed ? 0 : frame.pending.length,
      historyOpen: service.historyOpen,
      historyModelCount: historyModel.count,
      historyCount: service.historyCount,
      routeValid: service.routeValid,
      routeVisible: service.routeVisible,
      routeCueOutput: service.route.cueOutput,
      routeDirection: service.route.direction,
      routeCueGlyph: service.routeValid && service.route.cueOutput !== null
        ? NotificationLogic.cueGlyph(service.route.direction) : null,
      routeError: service.routeError,
      routeAcceptedGeneration: service.routeAcceptedGeneration,
      routeCandidateRevision: service.routeMetadataGeneration,
      routeValidationRevision: service.routeMetadataCheckGeneration,
      routeMetadataAttemptCount: service.routeMetadataAttemptCount,
      routeAcceptedRevision: service.routeAcceptedGeneration,
      routeAcceptedRefreshedAtMs: service.routeAcceptedRefreshedAtMs,
      routeAcceptedExpiresAtMs: service.routeAcceptedExpiresAtMs,
      routeLastTransitionReason: service.routeLastTransitionReason,
      routeCandidatePending: service.routeCandidatePending,
      routeCandidateMetadataPending: service.routeCandidateMetadataPending,
      routeMetadataSnapshotRevision: service.routeMetadataSnapshotRevision,
      routeMetadataRunning: routeMetadata.running,
      routeCandidateGeneration: service.routeMetadataGeneration,
      routeTransitionCount: service.routeTransitionCount,
      routeInvalidationCount: service.routeInvalidationCount,
      routeTransitionLog: service.routeTransitionLog
    })
  }

  function dismissAll() {
    service.clearPopups()
    return "ok"
  }

  function dismissLast() {
    if (popupModel.count > 0) service.requestPopupRemoval(
      NotificationLogic.popupIdentity(popupModel.get(0)), "dismiss")
    return "ok"
  }

  function restoreLast() {
    if (restoreLastProc.running) return "ok"
    restoreLastProc.command = ["bash", "-c",
      "latest=$(ls -1 \"$1\"/*.json 2>/dev/null | sort -n | tail -n 1); " +
      "if [[ -n $latest ]]; then awk 1 \"$latest\"; fi", "--", historyDir]
    restoreLastProc.running = true
    return "ok"
  }

  function invokeLast() {
    if (popupModel.count > 0) service.invokePopupActionIdentity(
      NotificationLogic.popupIdentity(popupModel.get(0)), "default", false)
    return "ok"
  }

  function invokeAction(identifier) {
    if (popupModel.count > 0) service.invokePopupActionIdentity(
      NotificationLogic.popupIdentity(popupModel.get(0)), identifier)
    return "ok"
  }

  IpcHandler {
    target: "desktop.notifications"

    function ping(): string { return service.ping() }
    function status(): string { return service.status() }
    function dismissAll(): string { return service.dismissAll() }
    function dismissLast(): string { return service.dismissLast() }
    function restoreLast(): string { return service.restoreLast() }
    function invokeLast(): string { return service.invokeLast() }
    function invokeAction(identifier: string): string { return service.invokeAction(identifier) }
    function toggleHistory(): string { return service.toggleHistory() }
    function toggleDnd(): string { return service.toggleDnd() }
    function setDnd(value: string): string { return service.setDnd(value) }
  }

  Component {
    id: notificationServerComponent

    NotificationServer {
      keepOnReload: false
      imageSupported: true
      actionsSupported: true
      bodyMarkupSupported: true
      bodyHyperlinksSupported: false
      persistenceSupported: true

      onNotification: function(notification) {
        service.handleNotification(notification)
      }
    }
  }

  Loader {
    id: notificationServerLoader
    active: service.ownershipEnabled
    sourceComponent: notificationServerComponent
  }

  Variants {
    model: Quickshell.screens

    NotificationPopupRail {
      id: popupWindow
      required property var modelData
      output: modelData
      popupModel: service.popupModel
      shell: service.shell
      cardsVisible: service.cardsVisibleOn(modelData)
      cueVisible: service.cueVisibleOn(modelData)
      opened: service.popupSurfaceOpened && service.cardsVisibleOn(modelData)
      transitionGeneration: service.popupTransitionGeneration
      remainingFraction: service.remainingFraction
      countdownVisible: service.countdownVisible
       criticalPending: service.presentationFrame.visual.incomingDeck.criticalPending
         && service.presentationFrame.hovered
      fontFamily: service.shell && service.shell.bar
        ? String(service.shell.bar.fontFamily || Style.font.family) : Style.font.family
      barPosition: service.barPosition
      barSize: service.liveBarSize
      cueGlyph: NotificationLogic.cueGlyph(service.route.direction)
      onDismissRequested: function(identity) { service.requestPopupRemoval(identity, "dismiss") }
      onCardClicked: function(identity) { service.clickPopupIdentity(identity) }
      onActionClicked: function(identity, identifier) {
        service.invokePopupActionIdentity(identity, identifier)
      }
      onActiveHoverChanged: function(hovered) { service.setActivePopupHovered(hovered) }
      onOpenFinished: function(identity, generation, outputName) {
        service.handlePopupOpenFinished(identity, generation, outputName)
      }
      onCloseFinished: function(identity, generation, outputName) {
        service.handlePopupCloseFinished(identity, generation, outputName)
      }
    }
  }

  NotificationHistory {
    shell: service.shell
    opened: service.historyOpen
    model: service.historyModel
    fontFamily: service.shell && service.shell.bar
      ? String(service.shell.bar.fontFamily || Style.font.family) : Style.font.family
    onCloseRequested: service.closeHistory()
    onActivationRequested: function(index) { service.invokeHistoryDefault(index) }
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    if (service.ownershipEnabled) service.probeNotificationOwner()
    else service.setOwnershipState(false, "notification registration disabled")
    service.updateHistoryCount()
    service.scheduleRouteMetadataCheck()
    Qt.callLater(function() {
      settingsFile.reload()
      restorePopupsProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", service.popupStateDir]
      restorePopupsProc.running = true
      service.sweepOrphanImages()
    })
  }
}
