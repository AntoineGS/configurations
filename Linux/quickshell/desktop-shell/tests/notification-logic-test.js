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
assert.equal(logic.shouldBypassDnd({ appName: "Discord", urgency: 2 }, 2), false)
assert.equal(logic.shouldBypassDnd({ appName: "notify-send", urgency: 2 }, 2), true)
assert.equal(logic.isEphemeral({ appName: "notify-send", hints: {} }), true)
assert.equal(logic.isEphemeral({ appName: "build", hints: { transient: true } }), true)
assert.equal(logic.isEphemeral({ appName: "build", hints: {} }), false)

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
}, "snapshot keeps notification display data without private action hints")

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
}, "replacement keeps the original popup identity while updating display data")
assert.deepEqual(logic.popupRoles(), [
  "app", "appIcon", "summary", "body", "image", "urgency", "expireTimeout",
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
  },
  copies: [
    { from: "/tmp/icon one.png", to: "/state/images/1786930001000-42-appIcon" },
    { from: "/tmp/body.png", to: "/state/images/1786930001000-42-image" },
  ],
})
assert.deepEqual(logic.persistablePopup({ ...snapshot, image: "image://notification/42" }, "/state/images/").entry.image, "")

assert.equal(logic.popupExpired({ deadline: 1000 }, 5000, 1000), true)
assert.equal(logic.popupExpired({ deadline: 1001 }, 5000, 1000), false)
assert.equal(logic.popupExpired({ timestamp: 1000 }, 5000, 6000), true)
assert.equal(logic.popupExpired({ timestamp: 1000 }, 0, 600000), false)
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
