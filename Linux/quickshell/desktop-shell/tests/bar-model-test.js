const assert = require("node:assert/strict")
const model = require("../plugins/bar/BarModel.js")

assert.deepStrictEqual(model.pinTrayToInner([
  { id: "desktop.audio" }, { id: "desktop.tray" }, { id: "cpu" }
], "right"), [
  { id: "desktop.tray" }, { id: "desktop.audio" }, { id: "cpu" }
])
assert.strictEqual(model.normalizePosition("top"), "top")
assert.strictEqual(model.normalizePosition("invalid"), "top")
assert.strictEqual(model.customModuleSafeName("../escape"), false)

console.log("bar-model-test: neutral BarModel contract verified")
