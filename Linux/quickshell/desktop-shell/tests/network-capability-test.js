const assert = require("node:assert/strict")
const model = require("../plugins/panels/network/Model.js")

assert.equal(
  model.networkCapabilityAvailable("none", "network-manager", []),
  false,
  "an unavailable backend must not reserve a network widget slot"
)
assert.equal(
  model.networkCapabilityAvailable("network-manager", "network-manager", []),
  true,
  "an available backend may expose an empty device list"
)
assert.equal(
  model.networkCapabilityAvailable("network-manager", "network-manager", undefined),
  false,
  "an absent device service is not a usable capability"
)

console.log("network-capability-test: backend capability contract verified")
