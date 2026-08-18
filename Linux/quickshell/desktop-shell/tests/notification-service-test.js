const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.resolve(__dirname, "..")
const servicePath = path.join(root, "plugins/notifications/Service.qml")
const cardPath = path.join(root, "plugins/notifications/components/NotificationCard.qml")
const logicPath = path.join(root, "plugins/notifications/NotificationLogic.js")
const runtimeTestPath = path.join(root, "tests/notification-runtime-test.sh")
const manifestPath = path.join(root, "plugins/notifications/manifest.json")
const sourcePath = path.join(root, "SOURCE")
const selectedPluginsPath = path.join(root, "SELECTED_PLUGINS")

function readRequired(file) {
  assert.ok(fs.existsSync(file), `required notification artifact is missing: ${file}`)
  return fs.readFileSync(file, "utf8")
}

const service = readRequired(servicePath)
const card = readRequired(cardPath)
const logic = readRequired(logicPath)
const runtimeTest = readRequired(runtimeTestPath)
const manifest = JSON.parse(readRequired(manifestPath))
const source = readRequired(sourcePath)
const selected = readRequired(selectedPluginsPath)

assert.equal(manifest.id, "desktop.notifications")
assert.deepEqual(manifest.kinds, ["service"])
assert.equal(manifest.entryPoints.service, "Service.qml")

assert.match(service, /target:\s*"desktop\.notifications"/)
assert.match(service, /NotificationServer/)
assert.match(service, /notification-route\.json/)
assert.match(service, /notification-route-lease\.json/)
assert.match(service, /normalizeLease\(/)
assert.match(service, /stat -c/)
assert.match(service, /routeMetadata/)
assert.match(service, /leaseFile/)
assert.match(service, /routeValid[\s\S]*leaseValid/)
assert.match(service, /service\.routeDir,\s*service\.routePath,\s*service\.leasePath/,
  "route metadata paths are positional process arguments")
assert.doesNotMatch(service, /stat -c[^\n]*\$\{service\.(?:routeDir|routePath|leasePath)\}/,
  "route metadata command does not interpolate paths into shell source")
assert.match(service, /function invalidateRouteMetadata\(/,
  "watched route state has one fail-closed metadata invalidation path")
assert.match(service, /property int routeMetadataGeneration/,
  "metadata checks have a generation that identifies the watched file state")
assert.match(service, /property int routeMetadataCheckGeneration/,
  "metadata process records the generation it checks")
assert.match(service, /routeMetadataCheckGeneration !== service\.routeMetadataGeneration/,
  "stale metadata checks cannot validate a replacement file state")
assert.match(service, /function scheduleRouteMetadataCheck\(\)/,
  "watched replacements have a coalesced metadata scheduling path")
assert.match(service, /onFileChanged:\s*\{[\s\S]*invalidateRouteMetadata\(\)[\s\S]*scheduleRouteMetadataCheck\(\)[\s\S]*reload\(\)/,
  "watched replacements invalidate route validity and schedule metadata revalidation immediately")
assert.match(service, /if \(service\.routeMetadataCheckGeneration !== service\.routeMetadataGeneration\)[\s\S]*return[\s\S]*routeMetadataValid = Number\(exitCode\) === 0/,
  "stale metadata process results are discarded before they can validate a newer generation")
assert.match(service, /LC_ALL=C[\s\S]*stat -c/,
  "metadata type comparisons run in the C locale")
for (const fileViewId of ["routeFile", "leaseFile"]) {
  const start = service.indexOf(`id: ${fileViewId}`)
  const end = service.indexOf("\n  }", start)
  assert.ok(start >= 0 && end > start, `${fileViewId} exists`)
  assert.match(service.slice(start, end), /onFileChanged:\s*\{[\s\S]*invalidateRouteMetadata\(\)[\s\S]*reload\(\)/,
    `${fileViewId} invalidates metadata before reloading a replacement`)
}
assert.match(runtimeTest,
  /refreshed_at=\$\(date \+%s\)\n\s*write_lease_payload "\$refreshed_at" "\$\(\(refreshed_at \+ 2\)\)"/,
  "route-pair fixtures derive both lease endpoints from one timestamp")
assert.doesNotMatch(runtimeTest, /write_lease_payload "\$\(date \+%s\)"/,
  "route-pair fixtures do not sample the lease endpoints independently")
assert.match(service, /desktop-shell\/notifications/)
assert.match(service, /property bool notificationsOwned/)
assert.match(service, /property string ownershipError/)
assert.match(service, /property bool routeValid/)
assert.match(service, /property string routeError/)
assert.doesNotMatch(service + card, /omarchy|OMARCHY|omarchy-glyph|omarchy-exec/)
assert.match(service, /bodyHyperlinksSupported:\s*false/)
assert.doesNotMatch(service, /bodyHyperlinksSupported:\s*true/)
assert.match(service, /boundedText\(notification\.appName,\s*128\)/)

assert.match(logic, /function actionMetadata\(notification\)/)
assert.match(logic, /maxActions:\s*8/)
assert.match(logic, /maxActionLabelLength:\s*256/)
assert.match(logic, /function actionOutcome\(actions, identifier, resident\)/)
assert.match(logic, /function durationFor\(urgency, expireTimeout/)
assert.match(logic, /function deadlineFor\(urgency, expireTimeout/)
assert.match(logic, /function remainingLifetime\(entry, now, fallbackDuration\)/)
assert.match(logic, /function refreshScheduleUpdate\(pending, key, request\)/)
assert.match(logic, /function cueGlyph\(direction\)/)
assert.match(logic, /if \(isEphemeral\(n\)\) result\.transient = true/)
assert.doesNotMatch(logic, /appName[\s\S]*notify-send|notify-send[\s\S]*appName/)

assert.match(service, /function invokePopupAction\(index, identifier\)/)
assert.match(service, /function invokePopupDefault\(index\)/)
assert.match(service, /function invokeAction\(identifier\)/)
assert.match(service, /Math\.min\(ref\.actions\.length,\s*8\)/)
assert.doesNotMatch(service, /for \(var fallback = limit;/)
assert.match(service, /action\.invoke\(\)/)
assert.match(service, /ref\.resident/)
assert.match(service, /actionsChanged/)
assert.match(card, /property var actions/)
assert.match(card, /signal actionClicked\(string identifier\)/)
assert.match(card, /Repeater[\s\S]*root\.actionClicked/)
assert.match(service, /onActionClicked:\s*function\(identifier\)/)
assert.match(service, /defaultActionAvailable/)
assert.match(service, /onExpireTimeoutChanged:/)
assert.match(service, /onUrgencyChanged:/)
assert.match(service, /required property var deadline/)
assert.match(service, /NotificationLogic\.deadlineFor/)
assert.match(service, /NotificationLogic\.remainingLifetime/)
assert.match(service, /entry\.deadline/)

assert.match(service, /function cueVisibleOn\(screen\)[\s\S]*cueOutput !== null[\s\S]*screenName\(screen\)/)
assert.doesNotMatch(service.slice(service.indexOf("function cueVisibleOn"), service.indexOf("Process {", service.indexOf("function cueVisibleOn"))),
  /direction !== null/)
assert.match(service, /text:\s*NotificationLogic\.cueGlyph\(service\.route\.direction\)/)

assert.match(service, /maxActivePopups:\s*50/)
assert.match(service, /maxPersistenceJobs:\s*100/)
assert.match(logic, /maxImageLength:\s*2048/)
assert.match(logic, /maxSerializedPayload:\s*16384/)
assert.match(logic, /function admissionUpdate\(timestamps, now, maxAccepted, windowMs\)/)
assert.match(service, /admissionLimit:\s*120/)
assert.match(service, /admissionWindowMs:\s*60000/)
assert.match(service, /property int admissionDropped/)
assert.match(service, /function admitNotification\(notification\)/)
assert.match(service, /function admitRefresh\(\)/)
assert.match(service, /property var pendingSilencedRefreshes/)
assert.match(service, /function scheduleSilencedRefresh\(/)
assert.match(service, /function finishSilencedWrite\(/)
assert.match(service, /admissionUpdate\(/)
assert.match(service, /admissionDropped:/)
assert.match(service, /persistenceGenerationCount:/)
assert.match(service, /function showDndConfirmation\(\)[\s\S]*popupModel\.count >= maxActivePopups/)
assert.match(service, /pendingPersistenceCount|popupFileQueue\.length/)
assert.match(service, /persistenceQueueUpdate/)
assert.match(service, /droppedOutcome/)
assert.match(service, /capacity-dropped/)
assert.match(service, /outcome === "superseded"/)
assert.match(service, /releasePersistenceGeneration\(job, true\)/)
assert.match(service, /function scheduleRefresh\(notification, originalId\)/)
const watchForUpdatesStart = service.indexOf("function watchForUpdates(")
const scheduleRefreshStart = service.indexOf("function scheduleRefresh(", watchForUpdatesStart)
assert.ok(watchForUpdatesStart >= 0 && scheduleRefreshStart > watchForUpdatesStart)
assert.doesNotMatch(service.slice(watchForUpdatesStart, scheduleRefreshStart), /refreshPopup\(/)
const refreshPopupStart = service.indexOf("function refreshPopup(")
const refreshPopupEnd = service.indexOf("property var restoredPopups", refreshPopupStart)
const refreshPopupBody = service.slice(refreshPopupStart, refreshPopupEnd)
assert.match(refreshPopupBody, /rowIndex < 0 \|\| !service\.admitRefresh\(\)\) return/)
assert.ok(refreshPopupBody.indexOf("admitRefresh()") < refreshPopupBody.indexOf("snapshotOf("))
assert.match(service, /dropped oldest/)
assert.match(service, /parsePopupFiles\(raw, NotificationUrgency\.Normal, service\.maxActivePopups\)/)

assert.match(service, /property string routeRaw/)
assert.match(service, /readonly property bool routeVisible/)
assert.match(service, /function refreshRoute\(\)/)
assert.match(service, /normalizeRoute\(service\.routeRaw,\s*Date\.now\(\)\)/)
assert.match(service, /routeExpiryTimer/)
assert.match(service, /return service\.routeVisible[\s\S]*service\.route\.output !== null/)
assert.match(service, /routeVisible:\s*service\.routeVisible/)

const restoreLastStart = service.indexOf("function restoreLast()")
const invokeLastStart = service.indexOf("function invokeLast()")
assert.ok(restoreLastStart >= 0 && invokeLastStart > restoreLastStart, "restoreLast root method exists")
const restoreLastBody = service.slice(restoreLastStart, invokeLastStart)
assert.match(restoreLastBody, /restoreLastProc/)
assert.doesNotMatch(restoreLastBody, /showRecentHistory|clearPopups/)
assert.match(service, /function restoreLastFromRaw\(raw\)[\s\S]*latestHistoryRow/)

assert.match(service, /property string persistenceError/)
assert.match(service, /property int persistenceRetryLimit/)
assert.match(service, /property int persistenceGeneration/)
assert.match(service, /property var latestPersistenceGenerations/)
assert.match(service, /function isCurrentPersistenceJob\(job\)/)
assert.match(service, /function releasePersistenceGeneration\(job(?:,\s*releaseAny)?\)/)
assert.match(service, /job\.generation/)
assert.match(service, /stale persistence job/)
assert.match(service, /function handleClosedNotification\(notification, originalId\)/)
assert.match(service, /liveGenerations\[originalId\]/)
const handleClosedStart = service.indexOf("function handleClosedNotification(")
const updateSignalsStart = service.indexOf("readonly property var updateSignals", handleClosedStart)
const handleClosedBody = service.slice(handleClosedStart, updateSignalsStart)
assert.match(handleClosedBody, /delete service\.pendingSilencedRefreshes\[String\(originalId\)\]/)
assert.match(handleClosedBody, /delete service\.silencedDirty\[originalId\]/)
assert.match(service, /reason !== "closed"/)
assert.match(service, /snapshot\.transient/)
assert.match(service, /livePersistenceSources\[originalId\] = updated\.transient/)
assert.match(service, /if \(!snapshot\.transient\) service\.persistPopupFile\(snapshot\)/)
assert.match(service, /entry\.transient !== true/)
assert.match(service, /done\(success/)
assert.match(service, /onExited:\s*function\(exitCode/)
assert.doesNotMatch(service, /mkdir -p[^\n]*\|\| exit 0/)
assert.match(service, /umask 077/, "notification persistence uses a restrictive umask")
assert.match(service, /chmod 700/, "notification state directories repair their mode")
assert.match(service, /chmod 600/, "notification state files repair their mode")
assert.match(service, /temporary=\$\(mktemp/, "popup and history JSON use same-directory temporary files")
assert.ok(service.includes('mv -f -- \\"$temporary\\"'), "popup and history JSON use atomic replacement")
assert.match(service, /settingsWriteProc/, "settings persistence has an explicit mode-controlled writer")
assert.match(service, /property bool settingsSavePending/,
  "settings persistence tracks an overlapping save")
assert.match(service,
  /if \(settingsWriteProc\.running\)\s*\{[\s\S]*settingsSavePending = true[\s\S]*return/,
  "an overlapping settings save is recorded instead of dropped")
assert.match(service,
  /onExited:[\s\S]*settingsSavePending[\s\S]*scheduleSettingsSave\(\)/,
  "settings exit schedules one pending follow-up save")
const writeSilencedStart = service.indexOf("function writeSilenced(")
const releaseSilencedStart = service.indexOf("function releaseSilenced(")
assert.ok(writeSilencedStart >= 0 && releaseSilencedStart > writeSilencedStart, "writeSilenced root method exists")
const writeSilencedBody = service.slice(writeSilencedStart, releaseSilencedStart)
assert.match(writeSilencedBody,
  /function\(success,\s*exitCode(?:,\s*(?:stale|outcome))?\)[\s\S]*if\s*\(!success\)\s*\{[\s\S]*releaseSilenced\(notification,\s*written\.originalId\)[\s\S]*return/,
  "failed DND persistence releases the live notification")
assert.match(writeSilencedBody, /finishSilencedWrite\(notification, written, success, exitCode, outcome\)/)
assert.doesNotMatch(writeSilencedBody, /service\.writeSilenced\(notification, updated\)/)
const scheduleSilencedStart = service.indexOf("function scheduleSilencedRefresh(")
const finishSilencedStart = service.indexOf("function finishSilencedWrite(")
assert.ok(scheduleSilencedStart >= 0 && finishSilencedStart > scheduleSilencedStart)
const scheduleSilencedBody = service.slice(scheduleSilencedStart, finishSilencedStart)
assert.ok(scheduleSilencedBody.indexOf("admitRefresh()") < scheduleSilencedBody.indexOf("replacementSnapshot("))
assert.match(service, /persistenceError:\s*service\.persistenceError/,
  "persistence failures are exposed through status")
assert.match(service, /liveCount:\s*service\.liveReferenceCount\(\)/,
  "status reports live notification references")
assert.match(service, /silencedRefreshCount:/)
assert.match(service, /silencedDirtyCount:/)

assert.match(card, /^BorderSurface\s*\{/m)
assert.match(card, /Color\.notifications\.[A-Za-z]+/)
assert.match(card, /Style\.(?:space|font)\b/)
assert.match(card, /\bradius\s*:/)
assert.match(card, /\bimplicitWidth\s*:/)
assert.doesNotMatch(card, /#[0-9A-Fa-f]{3,8}\b/)
assert.doesNotMatch(card, /\b(?:color|border\.color)\s*:\s*["']/)

for (const notificationPath of [
  "shell/plugins/notifications/manifest.json",
  "shell/plugins/notifications/Service.qml",
  "shell/plugins/notifications/NotificationLogic.js",
  "shell/plugins/notifications/components/NotificationCard.qml",
]) {
  assert.ok(source.includes(notificationPath), `SOURCE omits ${notificationPath}`)
}

assert.match(selected, /desktop\.notifications\|omarchy\.notifications\|shell\/plugins\/notifications\/manifest\.json shell\/plugins\/notifications\/Service\.qml shell\/plugins\/notifications\/NotificationLogic\.js shell\/plugins\/notifications\/components\/NotificationCard\.qml/)

console.log("notification-service-test: source, manifest, neutral card, and provenance contract verified")
