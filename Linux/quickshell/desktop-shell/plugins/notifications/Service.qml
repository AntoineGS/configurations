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
  property var livePersistenceSources: ({})
  property var actionClosingGenerations: ({})
  property var pendingRefreshes: ({})
  property var pendingSilencedRefreshes: ({})
  property var silencedDirty: ({})
  property alias popupModel: popupModel
  ListModel { id: popupModel }

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

  function deadlineFor(urgency, expireTimeout, startedAt) {
    return NotificationLogic.deadlineFor(
      urgency, expireTimeout, startedAt, NotificationUrgency.Critical, NotificationUrgency.Low,
      lowPopupDuration, normalPopupDuration, maxPopupDuration)
  }

  function snapshotOf(notification, timestamp) {
    var startedAt = timestamp === undefined ? Date.now() : Number(timestamp)
    var snapshot = NotificationLogic.snapshotOf(notification, startedAt)
    var deadline = deadlineFor(snapshot.urgency, snapshot.expireTimeout, startedAt)
    snapshot.deadline = deadline === null ? 0 : deadline
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

  function popupIndexForOriginalId(originalId) {
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (row && row.originalId === originalId) return i
    }
    return -1
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
      delete liveRefs[originalId]
      delete liveGenerations[originalId]
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
    if (previous && previous !== notification) {
      delete pendingSilencedRefreshes[String(snapshot.originalId)]
      delete silencedDirty[snapshot.originalId]
      try { previous.tracked = false } catch (error) {}
    }
    liveRefs[snapshot.originalId] = notification
    liveGenerations[snapshot.originalId] = snapshot.timestamp
    livePersistenceSources[snapshot.originalId] = snapshot.transient ? "none"
      : (service.doNotDisturb && !shouldBypassDnd(notification) ? "history" : "popup")
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

    if (!reservePopupSlot(snapshot.originalId)) {
      service.persistenceError = "notification active popup limit reached"
      releaseLiveNotification(notification, snapshot.originalId, true)
      return
    }

    if (!snapshot.transient) service.persistPopupFile(snapshot)
    watchForUpdates(notification, snapshot)
    Qt.callLater(function() {
      delete service.pendingPopups[String(snapshot.originalId)]
      if (service.liveRefs[snapshot.originalId] !== notification) return
      removePopupsByOriginalId(snapshot.originalId, NotificationLogic.popupFileName(snapshot))
      if (popupModel.count >= service.maxActivePopups) {
        service.persistenceError = "notification active popup limit reached"
        service.releaseLiveNotification(notification, snapshot.originalId, true)
        return
      }
      popupModel.insert(0, snapshot)
    })
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
        latest.deadline = request.persisted.deadline === undefined ? 0 : request.persisted.deadline
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
      delete liveRefs[originalId]
      delete liveGenerations[originalId]
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
    if (Number(service.actionClosingGenerations[originalId]) === generation) return
    var source = service.livePersistenceSources[originalId] || "popup"
    var found = false
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (row && row.originalId === originalId && Number(row.timestamp) === generation && !isRestoredRow(row)) {
        service.removePopup(i, "closed")
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
    } catch (error) {
      return
    }

    var roles = NotificationLogic.popupRoles()
    var row = popupModel.get(rowIndex)
    if (!row) return
    var oldFileName = NotificationLogic.popupFileName(row)
    var newFileName = NotificationLogic.popupFileName(updated)
    if (oldFileName !== newFileName || (!row.transient && updated.transient)) deletePopupFileFor(row)
    service.liveGenerations[originalId] = updated.timestamp
    service.livePersistenceSources[originalId] = updated.transient ? "none" : "popup"
    popupModel.setProperty(rowIndex, "timestamp", updated.timestamp)
    for (var r = 0; r < roles.length; r++) popupModel.setProperty(rowIndex, roles[r], updated[roles[r]])
    if (!updated.transient) service.persistPopupFile(updated)
    return
  }

  property var restoredPopups: ({})

  function isRestoredRow(row) {
    return !!row && !!restoredPopups[NotificationLogic.popupFileName(row)]
  }

  function restoredSource(row) {
    return row ? restoredPopups[NotificationLogic.popupFileName(row)] : ""
  }

  function removePopupsByOriginalId(originalId, keepFileName) {
    for (var i = popupModel.count - 1; i >= 0; i--) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId) continue
      if (isRestoredRow(row)) continue
      if (NotificationLogic.popupFileName(row) !== keepFileName) deletePopupFileFor(row)
      popupModel.remove(i)
    }
  }

  function dismissPopup(index) {
    removePopup(index, "dismiss")
  }

  function expirePopup(index) {
    removePopup(index, "expire")
  }

  function removePopup(index, reason) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var originalId = entry ? entry.originalId : -1
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

    if (ref && reason !== "closed") {
      delete liveRefs[originalId]
      delete liveGenerations[originalId]
      delete livePersistenceSources[originalId]
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

  function clearPopups() {
    while (popupModel.count > 0) dismissPopup(0)
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

  function invokePopupAction(index, identifier, forceDismiss) {
    if (index < 0 || index >= popupModel.count) return false
    var entry = popupModel.get(index)
    var ref = entry && !isRestoredRow(entry) ? liveRefs[entry.originalId] : null
    var action = liveAction(ref, String(identifier || ""))
    if (!action) return false

    var shouldDismiss = forceDismiss === true || ref.resident !== true
    if (shouldDismiss) actionClosingGenerations[entry.originalId] = entry.timestamp
    try {
      action.invoke()
    } catch (error) {
      if (shouldDismiss) delete actionClosingGenerations[entry.originalId]
      console.warn("notifications: action failed", error)
      return false
    }

    if (shouldDismiss) {
      dismissPopup(index)
      delete actionClosingGenerations[entry.originalId]
    }
    return true
  }

  function clickPopup(index) {
    if (!invokePopupAction(index, "default", true)) dismissPopup(index)
  }

  function invokePopupDefault(index) {
    return invokePopupAction(index, "default")
  }

  function showDndConfirmation() {
    for (var i = popupModel.count - 1; i >= 0; i--) {
      var old = popupModel.get(i)
      if (old && Number(old.originalId) < 0) popupModel.remove(i)
    }
    if (popupModel.count >= maxActivePopups) {
      service.persistenceError = "notification active popup limit reached"
      return
    }
    var id = -Date.now()
    popupModel.insert(0, {
      id: id,
      originalId: id,
      app: "desktop-shell",
      appIcon: "",
      summary: service.doNotDisturb ? "Do not disturb enabled" : "Do not disturb disabled",
      body: "",
      image: "",
      urgency: NotificationUrgency.Low,
      expireTimeout: 2500,
      deadline: 0,
      transient: false,
      actions: [],
      timestamp: Date.now()
    })
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

  function enqueueHistoryRead() {
    enqueuePersistenceJob({ read: true, key: "history-read" }, false)
  }

  function runNextPopupFileJob() {
    if (readHistoryProc.running || popupFileProc.running) return
    if (popupFileQueue.length === 0) return

    var job = popupFileQueue[0]
    popupFileQueue = popupFileQueue.slice(1)
    if (job.read) {
      service.runningHistoryReadGeneration = job.generation
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
    onExited: {
      var completed = {
        key: "history-read", generation: service.runningHistoryReadGeneration
      }
      service.runningHistoryReadGeneration = null
      service.runNextPopupFileJob()
      service.releasePersistenceGeneration(completed)
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.replayHistory(text)
    }
  }

  property var replayCarryOver: []
  property bool historyReadQueued: false

  function showRecentHistory() {
    if (readHistoryProc.running || service.historyReadQueued) return "ok"
    service.replayCarryOver = liveRowsForReplay()
    service.historyReadQueued = true
    enqueueHistoryRead()
    return "ok"
  }

  function startHistoryRead() {
    service.historyReadQueued = false
    readHistoryProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", historyDir]
    readHistoryProc.running = true
  }

  function liveRowsForReplay() {
    var rows = []
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (!row || Number(row.originalId) < 0) continue
      if (row.transient === true) continue
      rows.push(NotificationLogic.persistablePopup({
        id: row.id,
        originalId: row.originalId,
        app: row.app,
        appIcon: row.appIcon,
        summary: row.summary,
        body: row.body,
        image: row.image,
        urgency: row.urgency,
        timestamp: row.timestamp
      }, imagesDir).entry)
    }
    return rows
  }

  function replayHistory(raw) {
    var rows = NotificationLogic.historyRows(
      raw, service.replayCarryOver, NotificationUrgency.Normal, service.historyLimit)
    service.replayCarryOver = []
    service.updateHistoryCount()
    if (rows.length === 0) return

    clearPopups()
    for (var i = 0; i < rows.length; i++) {
      rows[i].deadline = 0
      rows[i].transient = false
      service.restoredPopups[NotificationLogic.popupFileName(rows[i])] = "history"
      popupModel.append(rows[i])
    }
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
    row.deadline = 0
    row.transient = false
    service.restoredPopups[fileName] = "history"
    popupModel.append(row)
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
    var now = Date.now()
    var live = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      entry.transient = entry.transient === true
      if (entry.transient) {
        deletePopupFileFor(entry)
        continue
      }
      var duration = durationFor(entry.urgency, entry.expireTimeout)
      var deadline = Number(entry.deadline)
      var needsDeadlineWrite = false
      if (duration > 0 && (!isFinite(deadline) || deadline <= 0)) {
        entry.deadline = Number(entry.timestamp) + duration
        deadline = entry.deadline
        needsDeadlineWrite = true
      }
      if (NotificationLogic.popupExpired(entry, duration, now)) {
        archivePopupFileFor(entry)
        continue
      }
      if (duration <= 0) entry.deadline = 0
      else if (needsDeadlineWrite) persistPopupFile(entry)
      live.push(entry)
    }
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
        if (restored.deadline === undefined) restored.deadline = 0
        if (restored.transient === undefined) restored.transient = false
        service.restoredPopups[NotificationLogic.popupFileName(restored)] = "popup"
        popupModel.append(restored)
      }
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
    return service.routeVisible
      && service.route.output !== null
      && String(service.route.output) === screenName(screen)
      && popupModel.count > 0
  }

  function cueVisibleOn(screen) {
    return service.routeVisible && service.route.cueOutput !== null
      && String(service.route.cueOutput) === screenName(screen)
      && popupModel.count > 0
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
    if (popupModel.count > 0) service.dismissPopup(0)
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
    if (popupModel.count > 0) service.invokePopupDefault(0)
    return "ok"
  }

  function invokeAction(identifier) {
    if (popupModel.count > 0) service.invokePopupAction(0, identifier)
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

    PanelWindow {
      id: popupWindow
      required property var modelData
      screen: modelData
      visible: !service.testSurfaceSuppressed && (service.cardsVisibleOn(modelData)
        || service.cueVisibleOn(modelData))

      WlrLayershell.namespace: "desktop-shell-notifications"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      readonly property var popupPlacement: NotificationLogic.popupPlacement(
        service.barPosition, service.barClearance, Style.gapsOut)
      readonly property int placementInset: Style.space(24)

      anchors { top: true; bottom: true; left: true; right: true }

      mask: Region { item: popupColumn }

      ColumnLayout {
        id: popupColumn
        visible: service.cardsVisibleOn(popupWindow.modelData)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: popupWindow.popupPlacement.margins.top + popupWindow.placementInset
        anchors.rightMargin: popupWindow.popupPlacement.margins.right + popupWindow.placementInset
        spacing: Style.space(8)

        Repeater {
          model: popupModel

          delegate: Item {
            id: cardSlot
            required property int index
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property int urgency
            required property double expireTimeout
            required property double timestamp
            required property var deadline
            required property var actions

            Layout.preferredWidth: card.implicitWidth
            Layout.alignment: Qt.AlignRight
            implicitHeight: card.implicitHeight

            readonly property real lifetime: service.durationFor(cardSlot.urgency, cardSlot.expireTimeout)
            readonly property real deadlineLifetime:
              NotificationLogic.remainingLifetime(cardSlot, Date.now(), cardSlot.lifetime)
            property real remainingLifetime: cardSlot.deadlineLifetime
            readonly property bool ticking: cardSlot.lifetime > 0 && !card.hovered

            function resetLifetime() {
              cardSlot.remainingLifetime = NotificationLogic.remainingLifetime(
                cardSlot, Date.now(), cardSlot.lifetime)
            }

            onSummaryChanged: cardSlot.resetLifetime()
            onBodyChanged: cardSlot.resetLifetime()
            onImageChanged: cardSlot.resetLifetime()
            onUrgencyChanged: cardSlot.resetLifetime()
            onExpireTimeoutChanged: cardSlot.resetLifetime()
            onDeadlineChanged: cardSlot.resetLifetime()
            onActionsChanged: cardSlot.resetLifetime()

            Timer {
              interval: 50
              repeat: true
              running: cardSlot.ticking
              onTriggered: {
                var remaining = NotificationLogic.remainingLifetime(
                  cardSlot, Date.now(), cardSlot.lifetime)
                cardSlot.remainingLifetime = remaining
                if (remaining <= 0) {
                  service.expirePopup(cardSlot.index)
                }
              }
            }

            NotificationCard {
              id: card
              anchors.right: parent.right
              app: cardSlot.app
              appIcon: cardSlot.appIcon
              summary: cardSlot.summary
              body: cardSlot.body
              image: cardSlot.image
              urgency: cardSlot.urgency
              timestamp: cardSlot.timestamp
              actions: cardSlot.actions
              fontFamily: service.shell && service.shell.bar
                ? String(service.shell.bar.fontFamily || Style.font.family) : Style.font.family

              onCloseRequested: service.dismissPopup(cardSlot.index)
              onActionClicked: function(identifier) {
                service.invokePopupAction(cardSlot.index, identifier)
              }
              onCardClicked: service.clickPopup(cardSlot.index)
            }
          }
        }
      }

      ElevatedSurface {
        id: cueSurface
        visible: service.cueVisibleOn(popupWindow.modelData)
        revealed: visible
        entranceX: Style.space(12)
        concealedScale: 1.0
        motionDuration: 160
        shadowBlurMax: 48
        shadowBlurAmount: 1.0
        shadowOpacityAmount: 0.78
        shadowOffsetY: 14
        shadowScaleAmount: 1.03
        effectPaddingRect: Qt.rect(-8, -8, 16, 30)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: popupWindow.popupPlacement.margins.top + popupWindow.placementInset
        anchors.rightMargin: popupWindow.popupPlacement.margins.right + popupWindow.placementInset
        implicitWidth: Style.space(250)
        implicitHeight: Style.space(48)
        radius: 0
        color: Color.notifications.background
        borderSpec: Border.none()

        Text {
          id: cueLabel
          anchors.centerIn: parent
          text: NotificationLogic.cueGlyph(service.route.direction)
          color: Color.notifications.text
          font.family: Style.font.family
          font.pixelSize: Style.font.display
        }
      }
    }
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
