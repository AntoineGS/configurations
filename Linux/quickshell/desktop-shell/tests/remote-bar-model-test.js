const assert = require("node:assert/strict")
const Model = require("../services/RemoteBarModel.js")

const snapshot = {
  schemaVersion: 1,
  host: "antoinews-linux",
  publishedAt: 100,
  widgets: { audio: { available: true } },
}

assert.deepEqual(Model.parseSnapshot(JSON.stringify(snapshot), "antoinews-linux"), snapshot)
assert.equal(Model.parseSnapshot(JSON.stringify(snapshot), "other-host"), null)
assert.equal(Model.parseSnapshot("not json", "antoinews-linux"), null)
assert.deepEqual(Model.freshness(snapshot, 129, 0, 30, 60), { state: "fresh", ageSeconds: 29 })
assert.deepEqual(Model.freshness(snapshot, 130, 0, 30, 60), { state: "stale", ageSeconds: 30 })
assert.deepEqual(Model.freshness(snapshot, 160, 0, 30, 60), { state: "offline", ageSeconds: 60 })
const servedSnapshot = Object.assign({}, snapshot, { servedAt: 105 })
assert.deepEqual(Model.freshness(servedSnapshot, 210, 200, 30, 60), { state: "fresh", ageSeconds: 15 })
assert.deepEqual(Model.widget(snapshot, "audio"), { available: true })
assert.deepEqual(Model.widget(snapshot, "missing"), {})
