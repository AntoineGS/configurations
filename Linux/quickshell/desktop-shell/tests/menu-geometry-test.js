const assert = require("node:assert/strict")
const model = require("../plugins/menu/MenuModel.js")

assert.equal(model.launcherCardTop(1080, 399, 5), 360)
assert.equal(model.launcherCardTop(1080, 304, 5), 360)
assert.equal(model.launcherCardTop(720, 500, 5), 215)
assert.equal(model.launcherCardTop(720, 710, 5), 5)
assert.equal(model.launcherCardTop(0, 399, 5), 0)
