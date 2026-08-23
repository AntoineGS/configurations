const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.resolve(__dirname, "..")
const servicePath = path.join(root, "plugins/notifications/Service.qml")
const shellPath = path.join(root, "shell.qml")
const cardPath = path.join(root, "plugins/notifications/components/NotificationCard.qml")
const logicPath = path.join(root, "plugins/notifications/NotificationLogic.js")
const runtimeTestPath = path.join(root, "tests/notification-runtime-test.sh")
const publisherHelperPath = path.join(root, "tests/notification-route-publisher.sh")
const manifestPath = path.join(root, "plugins/notifications/manifest.json")
const sourcePath = path.join(root, "SOURCE")
const selectedPluginsPath = path.join(root, "SELECTED_PLUGINS")

function readRequired(file) {
  assert.ok(fs.existsSync(file), `required notification artifact is missing: ${file}`)
  return fs.readFileSync(file, "utf8")
}

const service = readRequired(servicePath)
const shell = readRequired(shellPath)
const card = readRequired(cardPath)
const logic = readRequired(logicPath)
const runtimeTest = readRequired(runtimeTestPath)
const publisherHelper = readRequired(publisherHelperPath)
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
assert.match(service, /property int routeMetadataAttemptCount/,
  "metadata attempts are observable for bounded retry assertions")
assert.match(service, /revision !== service\.routeMetadataGeneration/,
  "stale metadata checks cannot validate a replacement file state")
assert.match(service, /routeMetadataSnapshotRevision/,
  "metadata stdout is associated with the revision that produced it")
assert.match(service, /routeMetadataSnapshot/,
  "metadata validation keeps one immutable candidate snapshot per process run")
assert.match(service, /SplitParser/)
assert.match(service, /onRead:[\s\S]*captureRouteMetadata\(/,
  "metadata promotion captures one bounded stdout JSON line per process run")
assert.match(service, /routeB64/)
assert.match(service, /leaseB64/)
assert.match(service, /Object\.freeze\(/,
  "candidate route and lease bytes are immutable after one process snapshot")
assert.match(service, /before.*after|after.*before/,
  "the fixed metadata command compares file identity before and after reading")
assert.match(service, /base64/,
  "the fixed metadata command safely encodes both raw payloads")
assert.match(service, /function scheduleRouteMetadataCheck\(\)/,
  "watched replacements have a coalesced metadata scheduling path")
assert.match(service, /onFileChanged:\s*\{[\s\S]*noteRouteCandidateChange\(\)[\s\S]*scheduleRouteMetadataCheck\(\)/,
  "watched replacements advance a candidate revision while scheduling metadata revalidation")
assert.match(service, /if \(!currentRevision\)[\s\S]*return[\s\S]*promoteRouteCandidate\(snapshot\)/,
  "stale metadata process results are discarded before they can promote a newer generation")
const finishRouteMetadataStart = service.indexOf("function finishRouteMetadata(")
const finishRouteMetadataEnd = service.indexOf("\n  function normalizedRouteCandidate", finishRouteMetadataStart)
const currentFailureStart = service.indexOf("if (!matchingSnapshot || Number(exitCode) !== 0)", finishRouteMetadataStart)
assert.ok(finishRouteMetadataStart >= 0 && finishRouteMetadataEnd > finishRouteMetadataStart)
assert.ok(currentFailureStart >= 0 && currentFailureStart < finishRouteMetadataEnd)
assert.doesNotMatch(service.slice(currentFailureStart, finishRouteMetadataEnd), /scheduleRouteMetadataCheck\(\)/,
  "same-revision metadata failures wait for file or fallback events instead of restarting the settle loop")
assert.match(service, /LC_ALL=C[\s\S]*stat -c/,
  "metadata type comparisons run in the C locale")
assert.match(service, /property int routeAcceptedGeneration/,
  "accepted route generation is retained independently from candidate events")
assert.match(service, /property var acceptedRoute/)
assert.match(service, /property var acceptedLease/)
assert.match(service, /routeCandidateSettleTimer/,
  "route and lease publication events have a coalesced candidate settle timer")
assert.match(service, /function promoteRouteCandidate\(/,
  "only a fully validated candidate can promote the accepted generation")
assert.match(service, /routeTransitionCount/,
  "route validity transitions are observable through the service IPC")
assert.match(service, /routeInvalidationCount/,
  "valid-to-invalid transitions are counted for steady-state assertions")
assert.match(service, /routeTransitionLog/,
  "route validity transitions retain a bounded diagnostic log")
assert.match(service, /property real routeAcceptedRefreshedAtMs/)
assert.match(service, /property real routeAcceptedExpiresAtMs/)
assert.match(service, /routeLastTransitionReason/)
assert.match(service, /routeMetadataAttemptCount\+\+/,
  "each metadata process start increments the attempt counter")
const invalidateMetadataStart = service.indexOf("function invalidateRouteMetadata(")
const invalidateMetadataEnd = service.indexOf("\n  }", invalidateMetadataStart)
assert.ok(invalidateMetadataStart >= 0 && invalidateMetadataEnd > invalidateMetadataStart)
assert.doesNotMatch(service.slice(invalidateMetadataStart, invalidateMetadataEnd), /routeMetadataValid\s*=\s*false/,
  "candidate metadata invalidation does not discard accepted metadata")
assert.doesNotMatch(service.slice(invalidateMetadataStart, invalidateMetadataEnd), /routeValid\s*=\s*false/,
  "candidate metadata invalidation does not discard accepted route validity")
for (const fileViewId of ["routeFile", "leaseFile"]) {
  const start = service.indexOf(`id: ${fileViewId}`)
  const end = service.indexOf("\n  }", start)
  assert.ok(start >= 0 && end > start, `${fileViewId} exists`)
  assert.match(service.slice(start, end), /onFileChanged:\s*\{[\s\S]*noteRouteCandidateChange\(\)[\s\S]*scheduleRouteMetadataCheck\(\)/,
    `${fileViewId} advances the candidate revision without loading route content`)
  assert.doesNotMatch(service.slice(start, end), /onLoaded|onLoadFailed|reload\(\)/,
    `${fileViewId} is a change watcher and cannot associate asynchronous text with a revision`)
}
assert.match(runtimeTest,
  /route_lease_max_age_ms=5000[\s\S]*refreshed_at_ms=\$\(date \+%s%3N\)[\s\S]*write_lease_payload "\$refreshed_at_ms" "\$\(\(refreshed_at_ms \+ route_lease_max_age_ms\)\)" "\$updated_at"/,
  "route-pair fixtures derive both millisecond lease endpoints from one timestamp")
assert.doesNotMatch(runtimeTest, /write_lease_payload "\$\(date \+%s%3N\)"/,
  "route-pair fixtures do not sample the lease endpoints independently")
assert.match(runtimeTest, /route_metadata_delay_bin[\s\S]*DESKTOP_SHELL_TEST_ROUTE_METADATA_BIN/,
  "runtime coverage can delay only the metadata process")
assert.match(runtimeTest, /race_a_refreshed_at_ms[\s\S]*race_b_refreshed_at_ms[\s\S]*stale delayed route generation was promoted/,
  "runtime coverage rejects a delayed stale generation after a newer pair is published")
assert.match(runtimeTest, /assert_metadata_failure_bounded\(\)\s*\{/,
  "runtime coverage bounds same-revision metadata failures")
assert.match(runtimeTest, /routeMetadataAttemptCount[\s\S]*event-driven recovery/,
  "runtime coverage exposes bounded attempts and event-driven recovery")
assert.match(publisherHelper, /NOTIFICATION_RECONCILE_INTERVAL=1/,
  "hermetic lease integration runs the real one-second watcher reconciliation path")
assert.match(publisherHelper, /notification_publisher_kill\(/,
  "hermetic lease integration has identity-checked publisher termination")
assert.match(runtimeTest, /routeInvalidationCount/,
  "runtime lease renewal asserts the accepted-generation invalidation counter")
assert.match(runtimeTest, /notification_publisher_kill[\s\S]*KILL/,
  "runtime lease renewal kills the publisher rather than the consumer")
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
assert.match(logic, /function normalizeImageSource\(value\)/,
  "notification images have one pure allowlist normalizer")
assert.match(logic, /function normalizeAppIconSource\(value\)/,
  "app icons have one pure allowlist normalizer")
assert.match(logic, /image:\s*normalizeImageSource\(/,
  "snapshot and restored image values are normalized")
assert.match(logic, /appIcon:\s*normalizeAppIconSource\(/,
  "snapshot and restored app-icon values are normalized")
assert.match(logic, /function actionOutcome\(actions, identifier, resident\)/)
assert.match(logic, /function durationFor\(urgency, expireTimeout/)
assert.match(logic, /function deadlineFor\(urgency, expireTimeout/)
assert.match(logic, /function remainingLifetime\(entry, now, fallbackDuration\)/)
assert.match(logic, /function refreshScheduleUpdate\(pending, key, request\)/)
assert.match(logic, /function cueGlyph\(direction\)/)
assert.match(logic, /if \(isEphemeral\(n\)\) result\.transient = true/)
assert.doesNotMatch(logic, /appName[\s\S]*notify-send|notify-send[\s\S]*appName/)

assert.match(service, /function invokePopupAction\(index, identifier, forceDismiss\)/)
assert.match(service, /forceDismiss === true \|\| ref\.resident !== true/)
assert.match(service,
  /function clickPopup\(index\)[\s\S]*invokePopupAction\(index,\s*"default",\s*true\)[\s\S]*dismissPopup\(index\)/)
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
assert.match(card, /cursorShape:\s*Qt\.PointingHandCursor/)
assert.match(card,
  /if \(mouse\.button === Qt\.RightButton\) root\.closeRequested\(\)\s*else root\.cardClicked\(\)/)
assert.doesNotMatch(card, /defaultActionAvailable/)
assert.match(card, /NotificationLogic\.normalizeImageSource\(/,
  "notification card revalidates image sources before Image.source")
assert.match(card, /NotificationLogic\.normalizeAppIconSource\(/,
  "notification card revalidates app icons before Image.source")
assert.match(service, /onActionClicked:\s*function\(identifier\)[\s\S]*invokePopupAction\(cardSlot\.index, identifier\)/)
assert.match(service, /onCardClicked:\s*service\.clickPopup\(cardSlot\.index\)/)
assert.match(service, /onExpireTimeoutChanged:/)
assert.match(service, /onUrgencyChanged:/)
assert.match(service, /required property var deadline/)
assert.match(service, /NotificationLogic\.deadlineFor/)
assert.match(service, /NotificationLogic\.remainingLifetime/)
assert.match(service, /entry\.deadline/)

const cueVisibleStart = service.indexOf("function cueVisibleOn")
const cueVisibleEnd = service.indexOf("Process {", cueVisibleStart)
const cueVisibleBody = service.slice(cueVisibleStart, cueVisibleEnd)
assert.match(cueVisibleBody, /service\.routeVisible/)
assert.match(cueVisibleBody, /cueOutput !== null[\s\S]*screenName\(screen\)/)
assert.match(cueVisibleBody, /popupModel\.count > 0/)
assert.doesNotMatch(cueVisibleBody, /direction !== null/)
assert.match(service, /readonly property int placementInset:\s*Style\.space\(56\)/)
assert.equal((service.match(/\+ popupWindow\.placementInset/g) || []).length, 4,
  "notification cards and cue share the down-left placement inset")
assert.match(service, /id:\s*cueSurface[\s\S]*implicitWidth:\s*Style\.space\(250\)/)
assert.match(service, /id:\s*cueSurface[\s\S]*implicitHeight:\s*Style\.space\(48\)/)
assert.match(service, /ElevatedSurface\s*\{[\s\S]*?id:\s*cueSurface/)
assert.match(service, /id:\s*cueSurface[\s\S]*radius:\s*0/)
assert.match(service, /id:\s*cueSurface[\s\S]*borderSpec:\s*Border\.none\(\)/)
assert.match(service, /id:\s*cueSurface[\s\S]*concealedScale:\s*1\.0/)
assert.match(service, /id:\s*cueSurface[\s\S]*motionDuration:\s*160/)
assert.match(service, /id:\s*cueSurface[\s\S]*entranceX:\s*Style\.space\(12\)/)
assert.match(service, /id:\s*cueSurface[\s\S]*shadowBlurMax:\s*48/)
assert.match(service, /id:\s*cueSurface[\s\S]*shadowOpacityAmount:\s*0\.78/)
assert.match(service, /id:\s*cueSurface[\s\S]*shadowOffsetY:\s*14/)
assert.match(service, /id:\s*cueSurface[\s\S]*shadowScaleAmount:\s*1\.03/)
assert.match(service, /id:\s*cueSurface[\s\S]*effectPaddingRect:\s*Qt\.rect\(-8, -8, 16, 30\)/)
assert.match(service, /id:\s*cueLabel[\s\S]*font\.pixelSize:\s*Style\.font\.display/)
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
assert.match(service, /function normalizedRouteCandidate\(routeRaw, leaseRaw\)[\s\S]*normalizeRoute\(routeRaw,\s*now\)/)
assert.match(service, /routeExpiryTimer/)
const leaseExpiryTimerStart = service.indexOf("id: routeLeaseExpiryTimer")
const leaseExpiryTimerEnd = service.indexOf("\n  }", leaseExpiryTimerStart)
assert.ok(leaseExpiryTimerStart >= 0 && leaseExpiryTimerEnd > leaseExpiryTimerStart,
  "one-shot lease expiry timer exists")
const leaseExpiryTimer = service.slice(leaseExpiryTimerStart, leaseExpiryTimerEnd)
assert.match(leaseExpiryTimer, /repeat:\s*false/)
assert.match(leaseExpiryTimer, /onTriggered:[\s\S]*failClosedRoute\("notification route lease expired"\)/,
  "lease expiry invalidates the route at the normalized deadline")
assert.match(service, /expiresAtMs\s*-\s*Date\.now\(\)/,
  "lease expiry scheduling uses the normalized millisecond absolute expiry")
assert.doesNotMatch(service, /expiresAt\s*\*\s*1000/,
  "lease expiry scheduling does not convert a millisecond expiry a second time")
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
assert.match(refreshPopupBody,
  /updated\.transient[\s\S]*deletePopupFileFor\(row\)/,
  "visible persistent-to-transient refresh explicitly deletes the prior popup file")
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
assert.match(scheduleSilencedBody,
  /if \(latest\.transient === true\)[\s\S]*deleteHistoryFileFor\(request\.persisted\)[\s\S]*livePersistenceSources\[request\.originalId\] = "none"[\s\S]*releaseSilenced\(request\.notification, request\.originalId\)/,
  "DND persistent-to-transient refresh deletes the exact prior history generation")
const transientRefreshStart = scheduleSilencedBody.indexOf("if (latest.transient === true)")
const transientRefreshEnd = scheduleSilencedBody.indexOf("service.writeSilenced", transientRefreshStart)
assert.ok(transientRefreshStart >= 0 && transientRefreshEnd > transientRefreshStart)
assert.doesNotMatch(scheduleSilencedBody.slice(transientRefreshStart, transientRefreshEnd),
  /writeSilenced\(/,
  "DND transient refresh never writes replacement content")
assert.match(service, /persistenceError:\s*service\.persistenceError/,
  "persistence failures are exposed through status")
assert.match(service, /liveCount:\s*service\.liveReferenceCount\(\)/,
  "status reports live notification references")
assert.match(service, /silencedRefreshCount:/)
assert.match(service, /silencedDirtyCount:/)
assert.match(service, /routeAcceptedGeneration:\s*service\.routeAcceptedGeneration/)
assert.match(service, /routeCandidateRevision:\s*service\.routeMetadataGeneration/)
assert.match(service, /routeValidationRevision:\s*service\.routeMetadataCheckGeneration/)
assert.match(service, /routeAcceptedRevision:\s*service\.routeAcceptedGeneration/)
assert.match(service, /routeAcceptedRefreshedAtMs:\s*service\.routeAcceptedRefreshedAtMs/)
assert.match(service, /routeAcceptedExpiresAtMs:\s*service\.routeAcceptedExpiresAtMs/)
assert.match(service, /routeMetadataAttemptCount:\s*service\.routeMetadataAttemptCount/)
assert.match(service, /routeLastTransitionReason:\s*service\.routeLastTransitionReason/)
assert.match(service, /routeTransitionCount:\s*service\.routeTransitionCount/)
assert.match(service, /routeInvalidationCount:\s*service\.routeInvalidationCount/)
assert.match(service, /routeTransitionLog:\s*service\.routeTransitionLog/)
assert.match(shell, /notificationRouteMetadataAttemptCount:\s*notificationService\s*\?\s*notificationService\.routeMetadataAttemptCount/,
  "shell health exposes notification metadata attempts")

assert.match(card, /^ElevatedSurface\s*\{/m)
assert.match(card, /Color\.notifications\.[A-Za-z]+/)
assert.match(card, /Style\.(?:space|font)\b/)
assert.match(card, /\bradius\s*:/)
assert.match(card, /\bimplicitWidth\s*:/)
assert.match(card, /readonly property color surfaceColor:\s*urgency === 0/)
assert.match(card, /readonly property string urgencyLabel:/)
assert.match(card, /readonly property string sourceLabel:/)
assert.match(card, /readonly property string timeLabel:/)
assert.match(card, /id:\s*metadataRule/)
assert.match(card, /id:\s*actionRule/)
assert.match(card, /onClicked:\s*root\.actionClicked\(String\(modelData\.identifier \|\| ""\)\)/)
assert.match(card, /Flow\s*\{[\s\S]*maximumWidth:\s*Style\.space\(140\)/)
assert.match(card, /Quickshell\.iconPath\(value, true\)/,
  "notification card resolves normalized theme icon names")
assert.doesNotMatch(card, /urgencyBadge/)
assert.doesNotMatch(card, /smallIconSlot/)
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
