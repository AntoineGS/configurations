const assert = require("node:assert/strict")
const model = require("../plugins/panels/network/Model.js")

const session = model.connectionSessionKey("wlan0", "connected", "Cafe WiFi")
assert.equal(session, model.connectionSessionKey("wlan0", "connected", "Cafe WiFi"))
assert.notEqual(session, model.connectionSessionKey("wlan0", "disconnected", "Cafe WiFi"))
assert.notEqual(session, model.connectionSessionKey("wlan1", "connected", "Cafe WiFi"))
assert.notEqual(session, model.connectionSessionKey("wlan0", "connected", "Other WiFi"))
