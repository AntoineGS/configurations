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
  cueOutput: "HDMI-A-1", direction: "left", error: "",
})
for (const raw of ["", "{", "{}", '{"version":2}',
  '{"version":1,"visible":true,"output":"../DP-1","updatedAt":1786930000}']) {
  assert.equal(logic.normalizeRoute(raw, 1786930040000).visible, false)
  assert.notEqual(logic.normalizeRoute(raw, 1786930040000).error, "")
}
assert.match(logic.normalizeRoute(fresh, 1786930046000).error, /stale/)
assert.equal(logic.shouldBypassDnd({ appName: "Discord", urgency: 2 }, 2), true)
assert.equal(logic.shouldBypassDnd({ appName: "notify-send", urgency: 2 }, 2), true)
assert.equal(logic.shouldBypassDnd({ appName: "notify-send", urgency: 1 }, 2), false)
assert.equal(logic.isEphemeral({ appName: "notify-send", hints: {} }), false)
assert.equal(logic.isEphemeral({ appName: "other", transient: true, hints: {} }), true)
assert.equal(logic.isEphemeral({ appName: "build", hints: { transient: true } }), true)
assert.equal(logic.isEphemeral({ appName: "build", hints: {} }), false)

assert.equal(logic.cueGlyph("left"), "←")
assert.equal(logic.cueGlyph("right"), "→")
assert.equal(logic.cueGlyph("up"), "↑")
assert.equal(logic.cueGlyph("down"), "↓")
assert.equal(logic.cueGlyph(null), "•")

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
assert.equal(logic.remainingLifetime({ deadline: 4000 }, 2500, 8000), 1500,
  "delegate lifetime uses the remaining absolute deadline")
assert.equal(logic.remainingLifetime({ deadline: 4000 }, 4500, 8000), 0,
  "expired absolute deadlines do not restart")
assert.equal(logic.remainingLifetime({ timestamp: 1000 }, 2500, 8000), 6500,
  "legacy rows derive a fixed deadline from their original timestamp")

const hintedImage = logic.snapshotOf({
  id: 43,
  appName: "build",
  hints: { "image-path": "/tmp/build.png" },
  image: "",
}, 1786930001000)
assert.equal(hintedImage.image, "/tmp/build.png",
  "image-path hints remain copyable when the server image property is empty")
const hintedImageUri = logic.snapshotOf({
  id: 44,
  hints: { "image-path": "/tmp/build-uri.png" },
  image: "image://icon//tmp/build-uri.png",
}, 1786930001000)
assert.equal(hintedImageUri.image, "/tmp/build-uri.png",
  "file-backed image hints replace transient image URLs before persistence")

const notification = {
  id: 42,
  appName: "build",
  appIcon: "build-icon",
  summary: "Build finished",
  body: "The build passed",
  image: "file:///tmp/build.png",
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
  image: "file:///tmp/build.png",
  urgency: 1,
  expireTimeout: 3000,
  timestamp: 1786930001000,
  actions,
}, "snapshot keeps notification display data without private action hints")

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
assert.equal(oversizedImage.image.length, logic.limits().maxImageLength)
assert.ok(logic.serializePopup({
  ...oversizedImage,
  body: "b".repeat(4096),
}, 1).length <= logic.limits().maxSerializedPayload,
"serialized popup payloads stay within the fixed bound")
assert.equal(logic.persistablePopup({
  ...oversizedImage,
  image: "https://example.com/" + "z".repeat(10000),
}, "/state/images/").entry.image.length, logic.limits().maxImageLength,
"persistable image URIs stay within the fixed bound")

const defaultTimeout = logic.snapshotOf({ id: 46, expireTimeout: -1 }, 1786930001000)
assert.equal(defaultTimeout.expireTimeout, -1, "-1 remains distinct from explicit zero")

const replacement = logic.replacementSnapshot({
  id: 99,
  appName: "build",
  appIcon: "updated-icon",
  summary: "Build updated",
  body: "The updated build passed",
  image: "",
  urgency: 2,
  expireTimeout: 5000,
}, 42, 1786930002000)
assert.deepEqual(replacement, {
  id: 42,
  originalId: 42,
  app: "build",
  appIcon: "updated-icon",
  summary: "Build updated",
  body: "The updated build passed",
  image: "",
  urgency: 2,
  expireTimeout: 5000,
  timestamp: 1786930002000,
  actions: [],
}, "replacement keeps the original popup identity while updating display data")
assert.deepEqual(logic.popupRoles(), [
  "app", "appIcon", "summary", "body", "image", "urgency", "expireTimeout", "deadline",
  "transient", "actions",
])
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
  image: "file:///tmp/build.png",
  urgency: 1,
  expireTimeout: 3000,
  timestamp: 1786930001000,
  actions: [],
  deadline: 1786930010000,
})
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
  image: "file:///tmp/build.png",
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
assert.equal(logic.localImageFile("file:///tmp/icon%20one.png"), "/tmp/icon one.png")
assert.equal(logic.localImageFile("image://notification/42"), "")
assert.deepEqual(logic.persistablePopup(imageEntry, "/state/images/"), {
  entry: {
    ...imageEntry,
    appIcon: "file:///state/images/1786930001000-42-appIcon",
    image: "file:///state/images/1786930001000-42-image",
    actions: [],
  },
  copies: [
    { from: "/tmp/icon one.png", to: "/state/images/1786930001000-42-appIcon" },
    { from: "/tmp/body.png", to: "/state/images/1786930001000-42-image" },
  ],
})
assert.deepEqual(logic.persistablePopup({ ...snapshot, image: "image://notification/42" }, "/state/images/").entry.image, "")
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
assert.deepEqual(logic.persistenceQueueUpdate(
  [{ key: "popup:1", value: "old" }],
  { key: "popup:1", value: "new" }, 100, false),
  { queue: [{ key: "popup:1", value: "new" }], dropped: null })
const newerQueuedJob = { key: "popup:2", generation: 2, value: "newer" }
const staleRetry = logic.persistenceQueueUpdate(
  [newerQueuedJob], { key: "popup:2", generation: 1, value: "stale" }, 100, true)
assert.equal(staleRetry.stale, true, "stale retries are rejected when newer intent is queued")
assert.deepEqual(staleRetry.queue, [newerQueuedJob])
const fullQueue = Array.from({ length: 100 }, (_, key) => ({ key }))
const boundedQueue = logic.persistenceQueueUpdate(fullQueue, { key: "new" }, 100, false)
assert.equal(boundedQueue.queue.length, 100)
assert.deepEqual(boundedQueue.dropped, { key: 0 })
assert.equal(boundedQueue.queue[99].key, "new")
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
  cueOutput: "DP-2", direction: null, error: "",
})
for (const raw of [
  JSON.stringify({ version: 1, visible: "true", output: "DP-1", updatedAt: 1786930000 }),
  JSON.stringify({ version: 1, visible: true, output: "DP-1", updatedAt: 1786930000.5 }),
  JSON.stringify({ version: 1, visible: true, output: "DP/1", updatedAt: 1786930000 }),
  JSON.stringify({ version: 1, visible: false, output: null, cueOutput: "DP/2", updatedAt: 1786930000 }),
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
  assert.notEqual(result.error, "")
}

console.log("notification-logic-test: route privacy, persistence, history, images, expiry, and placement verified")
