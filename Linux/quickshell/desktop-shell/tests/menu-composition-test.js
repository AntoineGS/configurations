const assert = require("node:assert/strict")
const model = require("../plugins/menu/MenuModel.js")

const commands = [{ kind: "action", itemId: "system.lock", label: "Lock", score: 1000 }]
const app = model.applicationRow({ id: "org.example.lock", name: "Locksmith", icon: "locksmith" }, {
  entryName: entry => entry.name,
  entrySubtext: () => "Utility",
}, 9000)
const calculator = model.calculatorRow("2 + 2", "4", 7)

assert.deepEqual(model.composeSearchResults(commands, [app], calculator).map(row => row.kind), ["calculator", "action", "application"])
assert.equal(model.isOpaqueActionId("org.example.lock"), true)
assert.equal(app.kind, "application")
assert.equal(app.action, "")
assert.equal(app.desktopId, "org.example.lock")
assert.equal(calculator.requestSerial, 7)
