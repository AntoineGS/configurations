const assert = require("node:assert/strict")
const logic = require("../plugins/notifications/NotificationLogic.js")

const fresh = JSON.stringify({
  version: 1,
  visible: true,
  output: "DVI-D-1",
  cueOutput: "HDMI-A-1",
  direction: "left",
  updatedAt: 1786930000,
})

assert.deepEqual(logic.normalizeRoute(fresh, 1786930040000), {
  valid: true, visible: true, output: "DVI-D-1",
  cueOutput: "HDMI-A-1", direction: "left", updatedAt: 1786930000, error: "",
})
const freshLease = JSON.stringify({
  version: 2,
  refreshedAtMs: 1786930000000,
  expiresAtMs: 1786930005000,
  routeUpdatedAt: 1786930000,
})
assert.deepEqual(logic.normalizeLease(freshLease, 1786930000000, 1786930000), {
  valid: true,
  refreshedAtMs: 1786930000000,
  expiresAtMs: 1786930005000,
  routeUpdatedAt: 1786930000,
  error: "",
})
assert.deepEqual(logic.normalizeLease(freshLease, 1786930001000, 1786930000), {
  valid: true,
  refreshedAtMs: 1786930000000,
  expiresAtMs: 1786930005000,
  routeUpdatedAt: 1786930000,
  error: "",
})
assert.equal(logic.normalizeLease("", 1786930001000, 1786930000).valid, false)
assert.match(logic.normalizeLease(freshLease, 1786930005000, 1786930000).error, /stale/)
assert.match(logic.normalizeLease(freshLease, 1786930001000, 1786930001).error, /route timestamp/)
assert.match(logic.normalizeLease(freshLease, 1786930001000, "1786930000").error, /expected route timestamp/)
assert.match(logic.normalizeLease(JSON.stringify({
  version: 2,
  refreshedAtMs: 0,
  expiresAtMs: 1500,
  routeUpdatedAt: 0,
}), 0, null).error, /expected route timestamp/)
for (const raw of [
  "{",
  JSON.stringify({ version: 1, refreshedAt: 1786930000, expiresAt: 1786930001, routeUpdatedAt: 1786930000 }),
  JSON.stringify({ version: 2, refreshedAtMs: 1786930000000, expiresAtMs: 1786930005001, routeUpdatedAt: 1786930000 }),
  JSON.stringify({ version: 2, refreshedAtMs: 1786930001501, expiresAtMs: 1786930003001, routeUpdatedAt: 1786930000 }),
  JSON.stringify({ version: 2, refreshedAtMs: 1786930000000.5, expiresAtMs: 1786930001500, routeUpdatedAt: 1786930000 }),
  JSON.stringify({ version: 2, refreshedAtMs: -1, expiresAtMs: 1786930001500, routeUpdatedAt: 1786930000 }),
  JSON.stringify({ version: 2, refreshedAtMs: 1786930000000, expiresAtMs: 1786930001500.5, routeUpdatedAt: 1786930000 }),
  JSON.stringify({ version: 2, refreshedAtMs: 1786930000000, expiresAtMs: 1786930001500, routeUpdatedAt: "1786930000" }),
]) {
  const result = logic.normalizeLease(raw, 1786930001000, 1786930000)
  assert.equal(result.valid, false)
  assert.notEqual(result.error, "")
}
assert.equal(logic.normalizeLease(JSON.stringify({
  version: 2,
  refreshedAtMs: 1786930000000,
  expiresAtMs: 1786930001500,
  routeUpdatedAt: 1786930001,
}), 1786930001000, 1786930000).valid, false)
for (const raw of ["", "{", "{}", '{"version":2}',
  '{"version":1,"visible":true,"output":"../DP-1","updatedAt":1786930000}']) {
  assert.equal(logic.normalizeRoute(raw, 1786930040000).visible, false)
  assert.notEqual(logic.normalizeRoute(raw, 1786930040000).error, "")
  assert.equal(logic.normalizeRoute(raw, 1786930040000).updatedAt, null)
}
assert.match(logic.normalizeRoute(fresh, 1786930046000).error, /stale/)
assert.equal(logic.shouldBypassDnd({ appName: "Discord", urgency: 2 }, 2), true)
assert.equal(logic.shouldBypassDnd({ appName: "notify-send", urgency: 2 }, 2), true)
assert.equal(logic.shouldBypassDnd({ appName: "notify-send", urgency: 1 }, 2), false)
assert.equal(logic.isEphemeral({ appName: "notify-send", hints: {} }), false)
assert.equal(logic.isEphemeral({ appName: "other", transient: true, hints: {} }), true)
assert.equal(logic.isEphemeral({ appName: "build", hints: { transient: true } }), true)
assert.equal(logic.isEphemeral({ appName: "build", hints: {} }), false)

for (const output of ["DVI-D-1", "HDMI-A-1", "DP-2", "DP-1", "eDP-1"]) {
  const route = logic.normalizeRoute(JSON.stringify({
    version: 1,
    visible: true,
    output,
    cueOutput: output,
    direction: "left",
    updatedAt: 1786930000,
  }), 1786930040000)
  assert.equal(route.valid, true, `route output ${output} is allowlisted`)
  assert.equal(route.output, output)
  assert.equal(route.cueOutput, output)
}

assert.equal(logic.cueGlyph("left"), "←")
assert.equal(logic.cueGlyph("right"), "→")
assert.equal(logic.cueGlyph("up"), "↑")
assert.equal(logic.cueGlyph("down"), "↓")
assert.equal(logic.cueGlyph(null), "•")

const sender = {}
let actionClose = logic.actionCloseInitialState()
actionClose = logic.actionCloseTransition(actionClose, { type: "begin", notification: sender, generation: 7 }).state
actionClose = logic.actionCloseTransition(actionClose, { type: "close", notification: sender, generation: 7 }).state
assert.equal(actionClose.deferred, true, "synchronous sender close is deferred while action is running")
let completedAction = logic.actionCloseTransition(actionClose, { type: "complete", notification: sender, generation: 7, success: true })
assert.equal(completedAction.flush, true, "successful action flushes deferred sender close after dismissal")
let matchingClose = logic.actionCloseTransition(completedAction.state, { type: "close", notification: sender, generation: 7 })
assert.equal(matchingClose.accepted, true, "matching sender close clears the completed action guard")
let staleClose = logic.actionCloseTransition(actionClose, { type: "close", notification: {}, generation: 7 })
assert.equal(staleClose.accepted, false, "stale sender object cannot clear the current action guard")
assert.equal(logic.actionCloseTransition(actionClose, { type: "close", notification: sender, generation: 8 }).accepted, false,
  "stale sender generation cannot clear the current action guard")
let failedAction = logic.actionCloseTransition(actionClose, { type: "complete", notification: sender, generation: 7, success: false })
assert.equal(failedAction.flush, true, "failed action flushes deferred sender close as ordinary close")

const actions = [
  { identifier: "default", text: "Open" },
  { identifier: "archive", text: "Archive" },
]
assert.deepEqual(logic.actionOutcome(actions, "default", false), { found: true, dismiss: true })
assert.deepEqual(logic.actionOutcome(actions, "archive", false), { found: true, dismiss: true })
assert.deepEqual(logic.actionOutcome(actions, "archive", true), { found: true, dismiss: false })
assert.deepEqual(logic.actionOutcome([{ identifier: "archive", text: "Archive" }], "default", false),
  { found: false, dismiss: false })
assert.deepEqual(logic.actionMetadata({ actions }), actions,
  "live action identifiers and labels are retained in popup metadata")
assert.deepEqual(logic.actionMetadata({ actions: { 0: actions[0], length: 1 } }), [actions[0]],
  "QML list-like action values retain their metadata")
const defaultAfterLimit = Array.from({ length: 8 }, (_, index) => ({
  identifier: "action-" + index,
  text: "Action " + index,
})).concat([{ identifier: "default", text: "Open" }])
assert.equal(logic.actionMetadata({ actions: defaultAfterLimit }).length, 8)
assert.equal(logic.actionMetadata({ actions: defaultAfterLimit })[7].identifier, "action-7",
  "the bounded action set does not inspect a late default action")

const liveDefaultRef = {
  actions: [
    { identifier: "default", text: "Open" },
    { identifier: "archive", text: "Archive" },
  ],
}
const historyIdentity = { originalId: 42, timestamp: 1786930001000 }
assert.equal(logic.nextMonotonicTimestamp(-1, 1786930001000), 1786930001000)
assert.equal(logic.nextMonotonicTimestamp(1786930001000, 1786930001000), 1786930001001)
assert.equal(logic.nextMonotonicTimestamp(1786930001001, 1786930000500), 1786930001002)
assert.equal(logic.popupQueueOrderSeed([
  { queueOrder: 12000 },
  { queueOrder: 4500 },
  { queueOrder: "invalid" },
]), 12000, "restored queue orders seed from the maximum valid value")
assert.equal(logic.nextMonotonicTimestamp(
  logic.popupQueueOrderSeed([{ queueOrder: 12000 }, { queueOrder: 4500 }]), 1000), 12001,
"new arrivals remain after restored rows when the wall clock rolls back")
assert.equal(logic.historyActionAvailable(historyIdentity, liveDefaultRef, 1786930001000), true)
assert.equal(logic.historyActionAvailable(historyIdentity, liveDefaultRef, 1786930002000), false,
  "a reused notification id cannot activate through an older history row")
assert.equal(logic.historyActionAvailable(historyIdentity, { actions: [] }, 1786930001000), false)
assert.equal(logic.historyActionAvailable(historyIdentity, null, 1786930001000), false)

const lateDefaultRef = {
  actions: Array.from({ length: 8 }, (_, index) => ({
    identifier: "action-" + index,
    text: "Action " + index,
  })).concat([{ identifier: "default", text: "Open" }]),
}
assert.equal(logic.historyActionAvailable(historyIdentity, lateDefaultRef, 1786930001000), false,
  "history activation obeys the same bounded action set as popup activation")
assert.equal(logic.historyActionRetryAllowed(historyIdentity, {}), true)
assert.equal(logic.historyActionRetryAllowed(historyIdentity, {
  [logic.historyActionIdentity(historyIdentity)]: true,
}), false, "a failed history identity cannot be retried")
assert.equal(logic.historyReadAccepted(true, 4, 4), true)
assert.equal(logic.historyReadAccepted(true, 3, 4), false, "stale history reads are discarded")
assert.equal(logic.historyReadAccepted(false, 4, 4), false, "closed history rejects late reads")
const capturedRead = logic.historyReadTransition(
  "", [{ ...historyIdentity, app: "captured", actionAvailable: false }], 1, 10, true, 4, 4)
assert.equal(capturedRead.accepted, true)
assert.equal(capturedRead.rows[0].app, "captured")
assert.equal(capturedRead.rows[0].actionAvailable, false,
  "accepted current reads apply captured unavailable rows")
assert.equal(logic.historyReadTransition("", [], 1, 10, true, 3, 4).accepted, false,
  "stale reads produce no application")
assert.equal(logic.historyReadTransition("", [], 1, 10, false, 4, 4).accepted, false,
  "closed reads produce no application")

let failedActionState = logic.historyActionTransition(historyIdentity, {}, "check")
assert.equal(failedActionState.allowed, true)
failedActionState = logic.historyActionTransition(historyIdentity, failedActionState.failedIdentities, "failed")
assert.equal(failedActionState.allowed, false, "failed action identity is rejected immediately")
failedActionState = logic.historyActionTransition(historyIdentity, failedActionState.failedIdentities, "check")
assert.equal(failedActionState.allowed, false, "failed action identity remains rejected")
failedActionState = logic.historyActionTransition(historyIdentity, failedActionState.failedIdentities, "ended")
assert.equal(failedActionState.allowed, true, "ended generation clears failed action identity")

assert.equal(logic.durationFor(1, 0, 2, 0, 5000, 8000, 30000), 0,
  "explicit zero means never expire")
assert.equal(logic.durationFor(1, -1, 2, 0, 5000, 8000, 30000), 8000,
  "only the server-default sentinel receives the normal default")
assert.equal(logic.durationFor(1, 10000, 2, 0, 5000, 8000, 30000), 10000,
  "positive timeout is retained within bounds")
assert.equal(logic.durationFor(1, 50000, 2, 0, 5000, 8000, 30000), 30000,
  "positive timeout is capped")
assert.equal(logic.durationFor(2, 50000, 2, 0, 5000, 8000, 30000), 0,
  "critical notifications never timer-expire")
assert.equal(logic.deadlineFor(1, -1, 1000, 2, 0, 5000, 8000, 30000), 9000,
  "default lifetime becomes an absolute deadline")
assert.equal(logic.deadlineFor(1, 12000, 1000, 2, 0, 5000, 8000, 30000), 13000,
  "positive lifetime becomes an absolute deadline")
assert.equal(logic.deadlineFor(1, 0, 1000, 2, 0, 5000, 8000, 30000), null,
  "explicit zero has no deadline")
assert.equal(logic.deadlineFor(2, 3000, 1000, 2, 0, 5000, 8000, 30000), null,
  "critical notifications have no deadline")
assert.equal(logic.deadlineForReceipt(1, 12000, 1000, 900, 2, 0, 5000, 8000, 30000), 12900,
  "deadline uses receipt wall-clock time rather than monotonic identity")
assert.equal(logic.remainingLifetime({ deadline: 4000 }, 2500, 8000), 1500,
  "delegate lifetime uses the remaining absolute deadline")
assert.equal(logic.remainingLifetime({ deadline: 4000 }, 4500, 8000), 0,
  "expired absolute deadlines do not restart")
assert.equal(logic.remainingLifetime({ timestamp: 1000 }, 2500, 8000), 6500,
  "legacy rows derive a fixed deadline from their original timestamp")
assert.deepEqual(logic.restorePopupTiming(
  { timestamp: 1000, remainingLifetime: 700 }, 15000, 2000),
  { timestamp: 1000, remainingLifetime: 700, duration: 15000 },
  "persisted remaining lifetime is retained while restoring popup timing")
assert.deepEqual(logic.restorePopupTiming(
  { timestamp: 1000, deadline: 1500 }, 15000, 2000),
  { timestamp: 1000, deadline: 1500, remainingLifetime: 0, duration: 15000 },
  "expired legacy deadlines remain expired during restoration")
assert.equal(logic.restorePopupTiming({ timestamp: 1000 }, 15000, 2000).remainingLifetime, 15000,
  "missing persisted timing receives the full duration")
assert.equal(logic.restorePopupTiming({ timestamp: 1000, remainingLifetime: 0 }, 15000, 2000).remainingLifetime, 0,
  "explicit non-expiring history remains non-expiring")
assert.deepEqual(logic.restorePopupPlan({ timestamp: 1000, remainingLifetime: 700 }, 15000, 2000), {
  entry: { timestamp: 1000, remainingLifetime: 700, duration: 15000, queuePriority: false }, expired: false, migrated: true,
}, "service restoration plan retains persisted remaining lifetime")
assert.equal(logic.restorePopupPlan({ timestamp: 1000, deadline: 1500 }, 15000, 2000).expired, true,
  "service restoration plan marks expired legacy deadlines for archive")
assert.equal(logic.restorePopupPlan({ timestamp: 1000 }, 15000, 2000).entry.remainingLifetime, 15000,
  "service restoration plan assigns the full duration when timing is missing")
assert.equal(logic.restorePopupPlan({ timestamp: 1000, remainingLifetime: 0 }, 0, 2000).entry.remainingLifetime, 0,
  "service restoration plan keeps restore-last zero lifetime at zero")

const normalA = { originalId: 1, timestamp: 1000, urgency: 1 }
const normalB = { originalId: 2, timestamp: 2000, urgency: 1 }
const criticalA = { originalId: 3, timestamp: 3000, urgency: 2 }
const criticalB = { originalId: 4, timestamp: 4000, urgency: 2 }

assert.equal(logic.popupIdentity(normalA), "1000:1")
assert.deepEqual(logic.popupArrivalPlan([], 1, 2, false), {
  insertIndex: 0, preempt: false, deferred: false,
})
assert.deepEqual(logic.popupArrivalPlan([normalA, normalB], 1, 2, false), {
  insertIndex: 2, preempt: false, deferred: false,
})
assert.deepEqual(logic.popupArrivalPlan([normalA, normalB], 2, 2, false), {
  insertIndex: 1, preempt: true, deferred: false,
})
assert.deepEqual(logic.popupArrivalPlan([normalA, normalB], 2, 2, true), {
  insertIndex: 1, preempt: false, deferred: true,
})
assert.deepEqual(logic.popupArrivalPlan([criticalA, normalA], 2, 2, false), {
  insertIndex: 1, preempt: false, deferred: false,
})
assert.deepEqual(logic.popupArrivalPlan([normalA, criticalA, normalB], 2, 2, true), {
  insertIndex: 2, preempt: false, deferred: true,
})
assert.deepEqual(logic.popupArrivalPlan([
  { ...normalA, queuePriority: true },
  { ...normalB, queuePriority: false },
], 2, 2, false), {
  insertIndex: 1, preempt: true, deferred: false,
}, "active preemption follows current urgency, not durable queue priority")
assert.deepEqual(logic.popupArrivalPlan([
  { ...criticalA, urgency: 1, queuePriority: true },
  { ...normalB, queuePriority: false },
], 2, 2, false), {
  insertIndex: 1, preempt: true, deferred: false,
}, "a critical replacement with normal urgency can be preempted")
assert.deepEqual(
  logic.sortPopupQueue([normalB, criticalB, normalA, criticalA], 2)
    .map(logic.popupIdentity),
  ["3000:3", "4000:4", "1000:1", "2000:2"],
)
const legacyQueue = logic.migratePopupQueue([
  { originalId: 2, timestamp: 2000 },
  { originalId: 1, timestamp: 1000 },
])
assert.deepEqual(legacyQueue.sort((a, b) => a.queueOrder - b.queueOrder).map(entry => entry.originalId), [1, 2],
  "all-legacy popup rows receive FIFO queue order")
const mixedQueue = logic.migratePopupQueue([
  { originalId: 4, timestamp: 4000, queueOrder: 20 },
  { originalId: 2, timestamp: 2000 },
  { originalId: 1, timestamp: 1000, queueOrder: 10 },
  { originalId: 3, timestamp: 3000 },
])
assert.equal(mixedQueue.find(entry => entry.originalId === 1).queueOrder, 10,
  "valid durable order remains unchanged during migration")
assert.deepEqual(mixedQueue.sort((a, b) => a.queueOrder - b.queueOrder).map(entry => entry.originalId), [1, 4, 2, 3],
  "missing mixed orders allocate oldest-to-newest after valid durable orders")
assert.equal(logic.shouldPersistPopup({ originalId: -1, transient: false }), false)
assert.equal(logic.shouldPersistPopup({ originalId: 1, transient: true }), false)
assert.equal(logic.shouldPersistPopup({ originalId: 1, transient: false }), true)
assert.deepEqual(logic.historyRows(
  '{"id":-1,"originalId":-1,"timestamp":3000}\n{"id":1,"originalId":1,"timestamp":2000}',
  [], 1, 10).map(entry => entry.originalId), [1],
  "internal confirmation rows cannot enter notification history")
assert.equal(logic.popupQueuePriority({ urgency: 2, queuePriority: false }, 2), false,
  "replacement display urgency cannot change queue priority")
assert.equal(logic.popupQueuePriority({ urgency: 1, queuePriority: true }, 2), true,
  "original critical priority survives display urgency replacement")
assert.equal(logic.popupQueuePriority({ urgency: 2 }, 2), true,
  "legacy rows derive queue priority from urgency")
assert.deepEqual(
  logic.sortPopupQueue([
    { ...normalA, urgency: 2, queuePriority: false },
    { ...normalB, urgency: 1, queuePriority: true },
  ], 2).map(logic.popupIdentity),
  ["2000:2", "1000:1"],
  "queue sorting uses durable priority rather than mutable urgency",
)
assert.deepEqual(
  logic.sortPopupQueue([
    { ...normalA, timestamp: 9000, queuePriority: true, queueOrder: 1 },
    { ...normalB, timestamp: 2000, queuePriority: true, queueOrder: 2 },
  ], 2).map(logic.popupIdentity),
  ["9000:1", "2000:2"],
  "retained queue order survives a newer replacement timestamp",
)

assert.equal(logic.consumeRemainingLifetime(10000, 5000), 5000)
assert.equal(logic.consumeRemainingLifetime(5000, 8000), 0)
assert.equal(logic.consumeRemainingLifetime(0, 5000), 0,
  "zero remains the non-expiring sentinel")
assert.equal(logic.restoredRemainingLifetime({ remainingLifetime: 7000 }, 10000, 5000), 7000)
assert.equal(logic.restoredRemainingLifetime({ deadline: 9000 }, 10000, 5000), 4000,
  "legacy absolute deadlines migrate once")
assert.equal(logic.restoredRemainingLifetime({}, 10000, 5000), 10000)

const hintedImage = logic.snapshotOf({
  id: 43,
  appName: "build",
  hints: { "image-path": "image://notification/build" },
  image: "",
}, 1786930001000)
assert.equal(hintedImage.image, "image://notification/build",
  "safe image hints remain usable when the server image property is empty")
const hintedImageUri = logic.snapshotOf({
  id: 44,
  hints: { "image-path": "/tmp/build-uri.png" },
  image: "image://icon/build-uri",
}, 1786930001000)
assert.equal(hintedImageUri.image, "",
  "an arbitrary image provider is rejected before the popup model")

for (const source of [
  "http://example.test/icon.png",
  "https://example.test/icon.png",
  "ftp://example.test/icon.png",
  "data:image/png;base64,AAAA",
  "file:///tmp/icon.png",
  "/tmp/icon.png",
  "relative/icon.png",
  "icon://provider/icon",
  "image://notification",
  "image://notification/",
  "image://icon/build",
  "image://other/build",
  "image://notification/../build",
  "image://notification/build/../../secret",
  "image://notification/build%2Fsecret",
  "image://notification/build%5Csecret",
  "image://notification/build?size=large",
  "image://notification/build#fragment",
  "image://notification/build with-space",
  "image://notification//build",
  "image://notification/./build",
  "image://notification/build/./icon",
  "image://notification/build/../icon",
  "image://notification/" + "x".repeat(logic.limits().maxImageLength),
]) {
  assert.equal(logic.normalizeImageSource(source), "", `unsafe or oversized image source rejected: ${source}`)
}
assert.equal(logic.normalizeImageSource("image://notification/icon"), "image://notification/icon")
assert.equal(logic.normalizeImageSource("image://notification/icon/path"), "image://notification/icon/path")

for (const source of [
  "http://example.test/icon.png",
  "https://example.test/icon.png",
  "ftp://example.test/icon.png",
  "data:image/png;base64,AAAA",
  "file:///tmp/icon.png",
  "/tmp/icon.png",
  "relative/icon.png",
  "icon name",
  "image://notification",
  "image://icon/build",
  "image://other/build",
  "image://notification/../build",
  "image://notification/build%2Fsecret",
  "image://notification/build?size=large",
  "image://notification/build#fragment",
  "image://" + "x".repeat(logic.limits().maxAppLength),
]) {
  assert.equal(logic.normalizeAppIconSource(source), "", `unsafe or oversized app icon rejected: ${source}`)
}
assert.equal(logic.normalizeAppIconSource("build-icon"), "build-icon")
assert.equal(logic.normalizeAppIconSource("image://notification/build"), "image://notification/build")

const notification = {
  id: 42,
  appName: "build",
  appIcon: "build-icon",
  summary: "Build finished",
  body: "The build passed",
  image: "image://notification/build",
  urgency: 1,
  expireTimeout: 3000,
  hints: { transient: false },
  actions,
}
const snapshot = logic.snapshotOf(notification, 1786930001000)
assert.deepEqual(snapshot, {
  id: 42,
  originalId: 42,
  app: "build",
  appIcon: "build-icon",
  summary: "Build finished",
  body: "The build passed",
  image: "image://notification/build",
  urgency: 1,
  expireTimeout: 3000,
  timestamp: 1786930001000,
  actions,
}, "snapshot keeps notification display data without private action hints")

const unsafeSnapshot = logic.snapshotOf({
  id: 49,
  appName: "unsafe",
  appIcon: "file:///tmp/icon.png",
  image: "https://example.com/image.png",
}, 1786930001000)
assert.equal(unsafeSnapshot.appIcon, "", "unsafe app icons never enter the popup model")
assert.equal(unsafeSnapshot.image, "", "unsafe images never enter the popup model")

const transientSnapshot = logic.snapshotOf({
  id: 47,
  appName: "transient-build",
  summary: "Transient build",
  transient: true,
}, 1786930001000)
assert.equal(transientSnapshot.transient, true,
  "transient notifications carry a no-persistence marker through the model")

const bounded = logic.snapshotOf({
  id: 45,
  appName: "a".repeat(200),
  summary: "s".repeat(600),
  body: "b".repeat(5000),
  expireTimeout: 0,
  actions: Array.from({ length: 10 }, (_, index) => ({
    identifier: "action-" + index,
    text: "x".repeat(300),
  })),
}, 1786930001000)
assert.equal(bounded.app.length, 128)
assert.equal(bounded.summary.length, 512)
assert.equal(bounded.body.length, 4096)
assert.equal(bounded.actions.length, 8)
assert.equal(bounded.actions[0].text.length, 256)
assert.equal(bounded.expireTimeout, 0)

const oversizedImage = logic.snapshotOf({
  id: 48,
  image: "https://example.com/" + "x".repeat(10000),
  hints: { "image-path": "/tmp/" + "y".repeat(10000) },
}, 1786930001000)
assert.equal(oversizedImage.image, "")
assert.ok(logic.serializePopup({
  ...oversizedImage,
  body: "b".repeat(4096),
}, 1).length <= logic.limits().maxSerializedPayload,
"serialized popup payloads stay within the fixed bound")
assert.equal(logic.persistablePopup({
  ...oversizedImage,
  image: "https://example.com/" + "z".repeat(10000),
}, "/state/images/").entry.image, "",
"persistable image URIs reject active remote sources")

const defaultTimeout = logic.snapshotOf({ id: 46, expireTimeout: -1 }, 1786930001000)
assert.equal(defaultTimeout.expireTimeout, -1, "-1 remains distinct from explicit zero")

const replacement = logic.replacementSnapshot({
  id: 99,
  appName: "build",
  appIcon: "file:///tmp/updated-icon.png",
  summary: "Build updated",
  body: "The updated build passed",
  image: "https://example.com/updated.png",
  urgency: 2,
  expireTimeout: 5000,
}, 42, 1786930002000)
assert.deepEqual(replacement, {
  id: 42,
  originalId: 42,
  app: "build",
  appIcon: "",
  summary: "Build updated",
  body: "The updated build passed",
  image: "",
  urgency: 2,
  expireTimeout: 5000,
  timestamp: 1786930002000,
  actions: [],
}, "replacement keeps the original popup identity while updating display data")
assert.deepEqual(logic.popupRoles(), [
  "app", "appIcon", "summary", "body", "image", "urgency", "expireTimeout", "remainingLifetime",
  "queuePriority", "queueOrder", "transient", "actions",
])
assert.ok(logic.popupRoles().includes("queueOrder"))
assert.equal(logic.popupRowChanged(snapshot, snapshot), false)
assert.equal(logic.popupRowChanged(snapshot, replacement), true)

assert.equal(logic.sanitizeBody("hello <img src=\"avatar\">", "build", ""), "hello ")
assert.equal(logic.sanitizeBody("https://example.com Build finished", "Chromium", ""), "Build finished")
assert.equal(logic.sanitizeBody("https://example.com Build finished", "build", ""),
  "https://example.com Build finished")

const persisted = logic.popupEntry({ ...snapshot, deadline: 1786930010000 }, 1)
assert.deepEqual(persisted, {
  id: 42,
  originalId: 42,
  app: "build",
  appIcon: "build-icon",
  summary: "Build finished",
  body: "The build passed",
  image: "image://notification/build",
  urgency: 1,
  expireTimeout: 3000,
  timestamp: 1786930001000,
  actions: [],
  deadline: 1786930010000,
})
const persistedRemaining = logic.popupEntry({ ...snapshot, remainingLifetime: 2500 }, 1)
assert.equal(persistedRemaining.remainingLifetime, 2500)
assert.equal(JSON.parse(logic.serializePopup(persistedRemaining, 1)).remainingLifetime, 2500)
assert.equal(logic.popupEntry({ ...snapshot, queuePriority: true }, 1).queuePriority, true)
assert.equal(JSON.parse(logic.serializePopup({ ...snapshot, queuePriority: false }, 1)).queuePriority, false)
assert.equal(logic.popupEntry({ ...snapshot, queueOrder: 7 }, 1).queueOrder, 7)
assert.equal(JSON.parse(logic.serializePopup({ ...snapshot, queueOrder: 7 }, 1)).queueOrder, 7)
for (const invalidQueueOrder of ["7", null, -1, Infinity, NaN]) {
  assert.equal(logic.popupEntry({ ...snapshot, queueOrder: invalidQueueOrder }, 1).queueOrder,
    undefined, `invalid persisted queue order is migrated: ${String(invalidQueueOrder)}`)
}
assert.deepEqual(logic.historyEntry({ id: 7, app: "unknown", timestamp: 10 }, 1), {
  id: 7,
  originalId: 7,
  app: "unknown",
  appIcon: "",
  summary: "",
  body: "",
  image: "",
  urgency: 1,
  expireTimeout: 0,
  timestamp: 10,
  actions: [],
})
assert.deepEqual(logic.parseSettings('{"dnd":true,"past":[]}'), {
  error: false, dnd: true, legacy: true,
})
assert.deepEqual(logic.parseSettings(""), { error: false, dnd: null, legacy: false })
assert.equal(logic.parseSettings("{").error, true)
assert.equal(logic.serializePopup(snapshot, 1), JSON.stringify({
  id: 42,
  originalId: 42,
  app: "build",
  appIcon: "build-icon",
  summary: "Build finished",
  body: "The build passed",
  image: "image://notification/build",
  urgency: 1,
  expireTimeout: 3000,
  timestamp: 1786930001000,
  actions: [],
}))

const popupLines = [
  '{"id":8,"originalId":8,"app":"older","appIcon":"","summary":"Older","body":"","image":"","urgency":1,"expireTimeout":0,"timestamp":1786930000000}',
  "torn write",
  '{"id":9,"originalId":9,"app":"newer","appIcon":"","summary":"Newer","body":"","image":"","urgency":2,"expireTimeout":0,"timestamp":1786930003000}',
].join("\n")
assert.deepEqual(logic.parsePopupFiles(popupLines, 1).map(entry => entry.id), [9, 8])
assert.deepEqual(logic.historyRows(popupLines, [snapshot], 1, 3).map(entry => entry.id), [9, 42, 8])
assert.deepEqual(logic.historyRows(popupLines, [snapshot], 1, 1).map(entry => entry.id), [9])
const liveHistorySnapshot = { ...snapshot, actionAvailable: true }
const mergedHistory = logic.historyRows(popupLines, [liveHistorySnapshot], 1, 3)
assert.deepEqual(mergedHistory.map(entry => ({ id: entry.id, actionAvailable: entry.actionAvailable })), [
  { id: 9, actionAvailable: false },
  { id: 42, actionAvailable: true },
  { id: 8, actionAvailable: false },
])

const duplicateLiveHistory = {
  id: 9,
  originalId: 9,
  app: "newer-live",
  timestamp: 1786930003000,
  actionAvailable: true,
}
const deduplicatedHistory = logic.historyRows(popupLines, [duplicateLiveHistory], 1, 10)
assert.deepEqual(deduplicatedHistory.map(entry => entry.id), [9, 8])
assert.equal(deduplicatedHistory[0].app, "newer-live")
assert.equal(deduplicatedHistory[0].actionAvailable, true)
const capturedUnavailable = logic.historyRows("", [{
  id: 77,
  originalId: 77,
  app: "captured",
  timestamp: 1786930007000,
  actionAvailable: false,
}], 1, 10)
assert.equal(capturedUnavailable[0].app, "captured")
assert.equal(capturedUnavailable[0].actionAvailable, false, "unavailable rows remain readable")
assert.deepEqual(
  logic.historyRows("", Array.from({ length: 12 }, (_, id) => ({ id, timestamp: id })))
    .map(entry => entry.id),
  [11, 10, 9, 8, 7, 6, 5, 4, 3, 2],
  "history defaults to ten newest rows")
assert.deepEqual(logic.latestHistoryRow(popupLines, 1), {
  id: 9,
  originalId: 9,
  app: "newer",
  appIcon: "",
  summary: "Newer",
  body: "",
  image: "",
  urgency: 2,
  expireTimeout: 0,
  timestamp: 1786930003000,
  actions: [],
}, "restore selects only the newest archived entry")
assert.equal(logic.latestHistoryRow("", 1), null)
assert.equal(logic.popupFileName(snapshot), "1786930001000-42.json")

const imageEntry = {
  ...snapshot,
  appIcon: "file:///tmp/icon%20one.png",
  image: "/tmp/body.png",
}
assert.equal(logic.imageStem(imageEntry), "1786930001000-42")
assert.equal(logic.localImageFile("file:///tmp/icon%20one.png"), "")
assert.equal(logic.localImageFile("image://notification/42"), "")
assert.deepEqual(logic.persistablePopup(imageEntry, "/state/images/"), {
  entry: {
    ...imageEntry,
    appIcon: "",
    image: "",
    actions: [],
  },
  copies: [],
})
assert.deepEqual(logic.persistablePopup({ ...snapshot, image: "image://notification/42" }, "/state/images/").entry.image, "")
assert.equal(logic.historyEntry({
  ...snapshot,
  appIcon: "https://example.com/icon.png",
  image: "data:image/png;base64,AAAA",
}, 1).appIcon, "")
assert.equal(logic.historyEntry({
  ...snapshot,
  image: "image://notification/history",
}, 1).image, "image://notification/history")
assert.equal(logic.popupEntry({
  ...snapshot,
  appIcon: "/tmp/icon.png",
  image: "ftp://example.com/image.png",
}, 1).appIcon, "")
assert.equal(logic.popupEntry({
  ...snapshot,
  image: "image://notification/restore",
}, 1).image, "image://notification/restore")
assert.deepEqual(logic.persistablePopup(snapshot, "/state/images/").entry.actions, [],
  "persisted popup entries do not retain stale live action objects")
assert.deepEqual(JSON.parse(logic.serializePopup(snapshot, 1)).actions, [],
  "serialized popup entries contain no stale actions")

const replacementTimeout = logic.replacementSnapshot({
  id: 99,
  expireTimeout: -1,
  actions: [{ identifier: "archive", text: "Archive" }],
}, 42, 1786930002000)
assert.equal(replacementTimeout.expireTimeout, -1)
assert.deepEqual(replacementTimeout.actions, [{ identifier: "archive", text: "Archive" }])
assert.equal(logic.popupEntry(replacementTimeout, 1).expireTimeout, -1,
  "replacement timeout survives persistence and restart parsing")

assert.equal(logic.popupExpired({ deadline: 1000 }, 5000, 1000), true)
assert.equal(logic.popupExpired({ deadline: 1001 }, 5000, 1000), false)
assert.equal(logic.popupExpired({ timestamp: 1000 }, 5000, 6000), true)
assert.equal(logic.popupExpired({ timestamp: 1000 }, 0, 600000), false)
assert.equal(logic.limits().maxActivePopups, 50)
assert.equal(logic.limits().maxPersistenceJobs, 100)
assert.equal(logic.limits().maxHistoryEntries, 200)
assert.deepEqual(logic.admissionUpdate([], 1000, 120, 60000), {
  accepted: true, timestamps: [1000], dropped: 0,
})
const admissionWindow = Array.from({ length: 120 }, (_, index) => index + 1)
const admissionRejected = logic.admissionUpdate(admissionWindow, 60000, 120, 60000)
assert.equal(admissionRejected.accepted, false, "the global admission window rejects the 121st notification")
assert.equal(admissionRejected.dropped, 1)
assert.equal(admissionRejected.timestamps.length, 120)
assert.deepEqual(logic.admissionUpdate([0, 1000], 60999, 120, 60000), {
  accepted: true, timestamps: [1000, 60999], dropped: 0,
}, "admission timestamps expire through the injected clock")
const supersededQueuedJob = { key: "popup:1", value: "old" }
assert.deepEqual(logic.persistenceQueueUpdate(
  [supersededQueuedJob],
  { key: "popup:1", value: "new" }, 100, false),
  {
    queue: [{ key: "popup:1", value: "new" }],
    dropped: supersededQueuedJob,
    droppedOutcome: "superseded",
    outcome: "queued",
  })
const newerQueuedJob = { key: "popup:2", generation: 2, value: "newer" }
const staleRetry = logic.persistenceQueueUpdate(
  [newerQueuedJob], { key: "popup:2", generation: 1, value: "stale" }, 100, true)
assert.equal(staleRetry.stale, true, "stale retries are rejected when newer intent is queued")
assert.equal(staleRetry.outcome, "superseded")
assert.deepEqual(staleRetry.queue, [newerQueuedJob])
const fullQueue = Array.from({ length: 100 }, (_, key) => ({ key }))
const boundedQueue = logic.persistenceQueueUpdate(fullQueue, { key: "new" }, 100, false)
assert.equal(boundedQueue.queue.length, 100)
assert.deepEqual(boundedQueue.dropped, { key: 0 })
assert.equal(boundedQueue.droppedOutcome, "capacity-dropped")
assert.equal(boundedQueue.outcome, "capacity-dropped")
assert.equal(boundedQueue.queue[99].key, "new")
const firstRefresh = logic.refreshScheduleUpdate({}, "42", { timestamp: 1, value: "first" })
assert.equal(firstRefresh.scheduled, true, "the first property signal schedules one refresh")
const coalescedRefresh = logic.refreshScheduleUpdate(
  firstRefresh.pending, "42", { timestamp: 2, value: "latest" })
assert.equal(coalescedRefresh.scheduled, false, "additional property signals coalesce")
assert.deepEqual(coalescedRefresh.pending["42"], { timestamp: 2, value: "latest" })
const archiveQueuedJob = { key: "popup:3", generation: 2, value: "archive" }
const deleteQueued = logic.persistenceQueueUpdate(
  [archiveQueuedJob], { key: "popup:3", generation: 3, value: "delete" }, 100, true)
assert.equal(deleteQueued.dropped, archiveQueuedJob, "same-key delete supersedes queued archive")
assert.equal(deleteQueued.droppedOutcome, "superseded")
const protectedWrite = { key: "popup:target", generation: 2, value: "write" }
const protectedQueue = logic.persistenceQueueUpdate(
  [protectedWrite, { key: "history:other" }],
  { key: "history:new", generation: 3, value: "write" }, 2, false, { "popup:target": true })
assert.equal(protectedQueue.dropped.key, "history:other", "running same-key intent is protected from eviction")
assert.equal(protectedQueue.queue[0], protectedWrite)
assert.equal(logic.historyRows("", Array.from({ length: 205 }, (_, id) => ({ id, timestamp: id })), 1, 500).length, 200)
assert.equal(logic.parsePopupFiles(
  Array.from({ length: 55 }, (_, id) => JSON.stringify({ id, timestamp: id })).join("\n"), 1, 50).length, 50)
assert.deepEqual(logic.popupPlacement("top", 12, 4), {
  anchors: { top: true, bottom: false, left: false, right: true },
  margins: { top: 12, bottom: 4, left: 4, right: 4 },
})
assert.deepEqual(logic.popupPlacement("right", 12, 4), {
  anchors: { top: true, bottom: false, left: false, right: true },
  margins: { top: 4, bottom: 4, left: 4, right: 12 },
})

const validHidden = JSON.stringify({
  version: 1,
  visible: false,
  output: null,
  cueOutput: "DP-2",
  direction: null,
  updatedAt: 1786930000,
})
assert.deepEqual(logic.normalizeRoute(validHidden, 1786930045000), {
  valid: true, visible: false, output: null,
  cueOutput: "DP-2", direction: null, updatedAt: 1786930000, error: "",
})
for (const raw of [
  JSON.stringify({ version: 1, visible: "true", output: "DP-1", updatedAt: 1786930000 }),
  JSON.stringify({ version: 1, visible: true, output: "DP-1", updatedAt: 1786930000.5 }),
  JSON.stringify({ version: 1, visible: true, output: "DP/1", updatedAt: 1786930000 }),
  JSON.stringify({ version: 1, visible: true, output: "DP-9", updatedAt: 1786930000 }),
  JSON.stringify({ version: 1, visible: false, output: null, cueOutput: "DP/2", updatedAt: 1786930000 }),
  JSON.stringify({ version: 1, visible: false, output: null, cueOutput: "HDMI-A-9", updatedAt: 1786930000 }),
  JSON.stringify({ version: 1, visible: false, output: null, direction: "diagonal", updatedAt: 1786930000 }),
  JSON.stringify({ version: 1, visible: true, output: null, updatedAt: 1786930000 }),
  JSON.stringify({ version: 1, visible: true, output: "DP-1", updatedAt: 1786930050 }),
]) {
  const result = logic.normalizeRoute(raw, 1786930040000)
  assert.equal(result.valid, false)
  assert.equal(result.visible, false)
  assert.equal(result.output, null)
  assert.equal(result.cueOutput, null)
  assert.equal(result.direction, null)
  assert.equal(result.updatedAt, null)
  assert.notEqual(result.error, "")
}

const timed = logic.withPopupTiming({ identity: "1:1", remainingLifetime: 7 }, 1500)
assert.equal(timed.duration, 1500)
assert.equal(timed.remainingLifetime, 1500)
const bookkeeping = logic.replacementBookkeeping(
  { 9: 100 }, { 9: "popup" }, 9, 101, "history")
assert.equal(bookkeeping.generations[9], 101)
assert.equal(bookkeeping.sources[9], "history")
assert.equal(logic.canAdmitPopup(1, 2, 3), false)
assert.equal(logic.canAdmitPopup(1, 1, 3), true)
const transitionState = { phase: "switching", visual: { token: 4, kind: "switch", output: "DP-1" } }
assert.deepEqual(logic.transitionCallbackEvent(transitionState, 4, "DP-1"), {
  type: "TRANSITION_FINISHED", token: 4, kind: "switch", output: "DP-1",
})
assert.equal(logic.transitionCallbackEvent(transitionState, 4, "DP-2"), null)

console.log("notification-logic-test: route privacy, queue ordering, visible lifetime, persistence, history, images, and placement verified")
