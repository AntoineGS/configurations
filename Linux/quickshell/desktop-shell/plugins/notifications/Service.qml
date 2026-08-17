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
  readonly property string routePath: runtimeDir + "/desktop-shell/notification-route.json"
  readonly property int cornerRadius: Style.cornerRadius

  property bool ownershipEnabled: Quickshell.env("DESKTOP_SHELL_NOTIFICATIONS_REGISTER") !== "0"
  property bool notificationsOwned: false
  property string ownershipError: "notification owner probe pending"
  property bool routeValid: false
  property string routeError: "notification route unavailable"
  property string routeRaw: ""
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
  property alias popupModel: popupModel
  ListModel { id: popupModel }

  property int persistenceRetryLimit: 2
  property string persistenceError: ""
  readonly property int historyLimit: 10
  property int historyCount: 0
  property bool historyCountQueued: false
  readonly property int lowPopupDuration: 5000
  readonly property int normalPopupDuration: 8000
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

  function durationFor(urgency, expireTimeout) {
    switch (urgency) {
    case NotificationUrgency.Critical:
      return 0
    case NotificationUrgency.Low:
      return Math.min(maxPopupDuration, Math.max(lowPopupDuration, requestedDuration(expireTimeout)))
    default:
      return Math.min(maxPopupDuration, Math.max(normalPopupDuration, requestedDuration(expireTimeout)))
    }
  }

  function requestedDuration(expireTimeout) {
    var ms = Number(expireTimeout || 0)
    if (!isFinite(ms) || ms <= 0) return 0
    return Math.round(ms)
  }

  function shouldBypassDnd(notification) {
    return NotificationLogic.shouldBypassDnd(notification, NotificationUrgency.Critical)
  }

  function isEphemeral(notification) {
    return NotificationLogic.isEphemeral(notification)
  }

  function snapshotOf(notification) {
    return NotificationLogic.snapshotOf(notification, Date.now())
  }

  function isSpotify(notification) {
    if (!notification) return false
    var source = String(notification.appName || "") + "\n" + String(notification.appIcon || "")
    return source.toLowerCase().indexOf("spotify") >= 0
  }

  function handleNotification(notification) {
    // This sender is intentionally excluded before it can enter a popup or history.
    if (isSpotify(notification)) return

    notification.tracked = true
    var snapshot = snapshotOf(notification)
    liveRefs[snapshot.originalId] = notification
    notification.closed.connect(function() {
      if (service.liveRefs[snapshot.originalId] === notification)
        delete service.liveRefs[snapshot.originalId]
    })

    if (service.doNotDisturb && !shouldBypassDnd(notification)) {
      if (!isEphemeral(notification)) {
        writeSilenced(notification, snapshot)
        return
      }
      delete liveRefs[snapshot.originalId]
      notification.tracked = false
      return
    }

    persistPopupFile(snapshot)
    watchForUpdates(notification, snapshot)
    Qt.callLater(function() {
      removePopupsByOriginalId(snapshot.originalId, NotificationLogic.popupFileName(snapshot))
      popupModel.insert(0, snapshot)
      service.refreshPopup(notification, snapshot.originalId, snapshot.timestamp)
    })
  }

  function writeSilenced(notification, written) {
    writeHistoryFile(written, function(success, exitCode) {
      if (!success) {
        service.persistenceError = "notification history persistence failed (exit " + String(exitCode) + ")"
        service.releaseSilenced(notification, written.originalId)
        return
      }
      var updated = null
      try {
        updated = NotificationLogic.replacementSnapshot(notification, written.originalId, written.timestamp)
      } catch (error) {
        // The sender can disappear while the queued history write is running.
      }
      if (updated && NotificationLogic.popupRowChanged(written, updated)) {
        service.writeSilenced(notification, updated)
        return
      }
      service.releaseSilenced(notification, written.originalId)
    })
  }

  function releaseSilenced(notification, originalId) {
    if (liveRefs[originalId] === notification) delete liveRefs[originalId]
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

  readonly property var updateSignals: [
    "summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged",
    "imageChanged", "urgencyChanged", "expireTimeoutChanged", "hintsChanged"
  ]

  function watchForUpdates(notification, snapshot) {
    function refresh() {
      service.refreshPopup(notification, snapshot.originalId, snapshot.timestamp)
    }

    for (var i = 0; i < updateSignals.length; i++) {
      var signal = notification[updateSignals[i]]
      if (signal && typeof signal.connect === "function") signal.connect(refresh)
    }
  }

  function refreshPopup(notification, originalId, timestamp) {
    if (service.liveRefs[originalId] !== notification) return

    var updated
    try {
      updated = NotificationLogic.replacementSnapshot(notification, originalId, timestamp)
    } catch (error) {
      return
    }

    var roles = NotificationLogic.popupRoles()
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId || row.timestamp !== timestamp) continue
      if (!NotificationLogic.popupRowChanged(row, updated)) return
      for (var r = 0; r < roles.length; r++) popupModel.setProperty(i, roles[r], updated[roles[r]])
      persistPopupFile(updated)
      return
    }
  }

  property var restoredPopups: ({})

  function isRestoredRow(row) {
    return !!row && !!restoredPopups[NotificationLogic.popupFileName(row)]
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
    var ref = !internal && !restored && originalId >= 0 ? liveRefs[originalId] : null

    if (entry && !internal) {
      archivePopupFileFor(entry)
      if (restored) delete restoredPopups[NotificationLogic.popupFileName(entry)]
    }
    popupModel.remove(index)

    if (ref) {
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

  function invokePopupDefault(index) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var ref = entry && !isRestoredRow(entry) ? liveRefs[entry.originalId] : null
    try {
      if (ref && ref.actions) {
        for (var i = 0; i < ref.actions.length; i++) {
          var action = ref.actions[i]
          if (action && action.identifier === "default") {
            action.invoke()
            break
          }
        }
      }
    } catch (error) {
      console.warn("notifications: default action failed", error)
    }
    dismissPopup(index)
  }

  function showDndConfirmation() {
    for (var i = popupModel.count - 1; i >= 0; i--) {
      var old = popupModel.get(i)
      if (old && Number(old.originalId) < 0) popupModel.remove(i)
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

  function enqueuePopupFileJob(command, done, attempt) {
    popupFileQueue = popupFileQueue.concat([{
      command: command,
      done: done || null,
      attempt: Number(attempt || 0)
    }])
    runNextPopupFileJob()
  }

  function enqueueHistoryRead() {
    popupFileQueue = popupFileQueue.concat([{ read: true }])
    runNextPopupFileJob()
  }

  function runNextPopupFileJob() {
    if (readHistoryProc.running || popupFileProc.running) return
    if (popupFileQueue.length === 0) return

    var job = popupFileQueue[0]
    popupFileQueue = popupFileQueue.slice(1)
    if (job.read) {
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
      if (!success) {
        service.persistenceError = "notification persistence job failed (exit " + String(exitCode) + ")"
        if (job && job.attempt < service.persistenceRetryLimit) {
          service.popupFileQueue = [{
            command: job.command,
            done: job.done,
            attempt: job.attempt + 1
          }].concat(service.popupFileQueue)
          service.runNextPopupFileJob()
          return
        }
      }
      if (job && job.done) {
        try { job.done(success, exitCode) } catch (error) {
          console.warn("notifications: file callback failed", error)
        }
      }
      service.runNextPopupFileJob()
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
      copyImagesScript +
      "printf '%s\\n' \"$json\" > \"$dir/$name\" && chmod 600 -- \"$dir/$name\" || exit 1", "--",
      popupStateDir,
      imagesDir,
      NotificationLogic.serializePopup(persistable.entry, NotificationUrgency.Normal),
      NotificationLogic.popupFileName(snapshot)]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueuePopupFileJob(command)
  }

  function deletePopupFileFor(row) {
    if (!row) return
    enqueuePopupFileJob(["bash", "-c",
      "umask 077\nrm -f -- \"$1/$2.json\" \"$3/$2\"-*", "--",
      popupStateDir, NotificationLogic.imageStem(row), imagesDir])
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
      imagesDir], service.updateHistoryCount)
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
      "shift 5\n" +
      copyImagesScript +
      "printf '%s\\n' \"$json\" > \"$hist/$name\" && chmod 600 -- \"$hist/$name\" || exit 1\n" +
      trimHistoryScript, "--",
      historyDir,
      String(historyLimit),
      NotificationLogic.popupFileName(entry),
      NotificationLogic.serializePopup(persistable.entry, NotificationUrgency.Normal),
      imagesDir]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueuePopupFileJob(command, function(success, exitCode) {
      if (!success) {
        if (done) done(false, exitCode)
        return
      }
      service.updateHistoryCount()
      if (done) done(true, exitCode)
    })
  }

  function clearHistory() {
    enqueuePopupFileJob(["bash", "-c",
      "umask 077\n" +
      "for f in \"$1\"/*.json; do\n" +
      "  [[ -e $f ]] || continue\n" +
      "  stale=\"${f##*/}\"\n" +
      "  rm -f \"$f\" \"$2/${stale%.json}\"-*\n" +
      "done", "--", historyDir, imagesDir], service.updateHistoryCount)
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
      "done", "--", popupStateDir, historyDir, imagesDir])
  }

  Process {
    id: readHistoryProc
    running: false
    onExited: service.runNextPopupFileJob()
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
      service.restoredPopups[NotificationLogic.popupFileName(rows[i])] = true
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
    service.restoredPopups[fileName] = true
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
    var entries = NotificationLogic.parsePopupFiles(raw, NotificationUrgency.Normal)
    var now = Date.now()
    var live = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var duration = durationFor(entry.urgency, entry.expireTimeout)
      if (NotificationLogic.popupExpired(entry, duration, now)) {
        archivePopupFileFor(entry)
        continue
      }
      if (duration > 0) {
        entry.deadline = now + duration
        persistPopupFile(entry)
        delete entry.deadline
      }
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
        service.restoredPopups[NotificationLogic.popupFileName(restored)] = true
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
    }
  }

  property bool settingsLoaded: false

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
    if (settingsWriteProc.running) return
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
    onLoaded: service.applyRoute(text())
    onLoadFailed: service.invalidateRoute("notification route unavailable")
    onFileChanged: reload()
  }

  Timer {
    id: routeExpiryTimer
    interval: 1000
    repeat: true
    running: service.routeRaw.length > 0
    onTriggered: service.refreshRoute()
  }

  function invalidateRoute(error) {
    var message = String(error || "invalid route")
    service.routeRaw = ""
    service.route = {
      valid: false,
      visible: false,
      output: null,
      cueOutput: null,
      direction: null,
      error: message
    }
    service.routeValid = false
    service.routeError = message
  }

  function applyRoute(raw) {
    service.routeRaw = String(raw || "")
    service.refreshRoute()
  }

  function refreshRoute() {
    var next = NotificationLogic.normalizeRoute(service.routeRaw, Date.now())
    service.route = next
    service.routeValid = next.valid === true
    service.routeError = next.error || ""
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
    return service.routeValid && service.route.cueOutput !== null
      && String(service.route.cueOutput) === screenName(screen)
      && service.route.direction !== null
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
      popupCount: popupModel.count,
      historyCount: service.historyCount,
      routeValid: service.routeValid,
      routeVisible: service.routeVisible,
      routeError: service.routeError
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

  IpcHandler {
    target: "desktop.notifications"

    function ping(): string { return service.ping() }
    function status(): string { return service.status() }
    function dismissAll(): string { return service.dismissAll() }
    function dismissLast(): string { return service.dismissLast() }
    function restoreLast(): string { return service.restoreLast() }
    function invokeLast(): string { return service.invokeLast() }
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
      bodyHyperlinksSupported: true
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
      visible: service.cardsVisibleOn(modelData) || service.cueVisibleOn(modelData)

      WlrLayershell.namespace: "desktop-shell-notifications"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      readonly property var popupPlacement: NotificationLogic.popupPlacement(
        service.barPosition, service.barClearance, Style.gapsOut)

      anchors { top: true; bottom: true; left: true; right: true }

      mask: Region { item: popupColumn }

      ColumnLayout {
        id: popupColumn
        visible: service.cardsVisibleOn(popupWindow.modelData)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: popupWindow.popupPlacement.margins.top
        anchors.rightMargin: popupWindow.popupPlacement.margins.right
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

            Layout.preferredWidth: card.implicitWidth
            Layout.alignment: Qt.AlignRight
            implicitHeight: card.implicitHeight

            readonly property real lifetime: service.durationFor(cardSlot.urgency, cardSlot.expireTimeout)
            property real remainingLifetime: 1.0
            readonly property bool ticking: cardSlot.lifetime > 0 && !card.hovered

            onSummaryChanged: cardSlot.remainingLifetime = 1.0
            onBodyChanged: cardSlot.remainingLifetime = 1.0
            onImageChanged: cardSlot.remainingLifetime = 1.0

            Timer {
              interval: 50
              repeat: true
              running: cardSlot.ticking
              onTriggered: {
                if (cardSlot.lifetime <= 0) return
                cardSlot.remainingLifetime -= 50.0 / cardSlot.lifetime
                if (cardSlot.remainingLifetime <= 0) {
                  cardSlot.remainingLifetime = 0
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
              cornerRadius: service.cornerRadius
              fontFamily: service.shell && service.shell.bar
                ? String(service.shell.bar.fontFamily || Style.font.family) : Style.font.family

              onCloseRequested: service.dismissPopup(cardSlot.index)
              onCardClicked: service.invokePopupDefault(cardSlot.index)
            }
          }
        }
      }

      BorderSurface {
        id: cueSurface
        visible: service.cueVisibleOn(popupWindow.modelData)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: popupWindow.popupPlacement.margins.top
        anchors.rightMargin: popupWindow.popupPlacement.margins.right
        implicitWidth: cueLabel.implicitWidth + Style.space(20)
        implicitHeight: cueLabel.implicitHeight + Style.space(12)
        radius: service.cornerRadius
        color: Color.notifications.background
        borderSpec: Border.surfaceSpec("notifications", "border", Color.notifications.border, Math.max(1, Style.space(2)))

        Text {
          id: cueLabel
          anchors.centerIn: parent
          text: "Notifications " + String(service.route.direction || "")
          color: Color.notifications.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }
  }

  Component.onCompleted: {
    ensureDirsProc.running = true
    if (service.ownershipEnabled) service.probeNotificationOwner()
    else service.setOwnershipState(false, "notification registration disabled")
    service.updateHistoryCount()
    Qt.callLater(function() {
      settingsFile.reload()
      routeFile.reload()
      restorePopupsProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", service.popupStateDir]
      restorePopupsProc.running = true
      service.sweepOrphanImages()
    })
  }
}
