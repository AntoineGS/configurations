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

assert.deepEqual(model.dmenuRows(["One", "Two\tSecond option"], "two").map(row => ({
  label: row.label,
  detail: row.detail,
  selection: row.selection,
})), [{ label: "Two", detail: "Second option", selection: "Two\tSecond option" }])

const contextOptions = [
  { key: "source", label: "Edit script" },
  { key: "source-location", label: "Browse script location" },
]
const contextRows = model.contextRows(contextOptions, "browse")
assert.deepEqual(contextRows.map(row => ({
  kind: row.kind,
  label: row.label,
  selection: row.selection,
})), [{
  kind: "edit-context",
  label: "Browse script location",
  selection: "source-location",
}])
assert.deepEqual(model.contextRows([{ key: "../../bad", label: "Unsafe" }, null], ""), [])
