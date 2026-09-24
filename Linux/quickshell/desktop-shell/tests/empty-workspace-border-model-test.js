const test = require("node:test")
const assert = require("node:assert/strict")
const { frame } = require("../Ui/EmptyWorkspaceBorderModel.js")

function monitor(changes = {}) {
  return {
    name: "DP-1", focused: true, activeWorkspace: { id: 2 },
    width: 1920, height: 1080,
    lastIpcObject: { reserved: [0, 28, 0, 0], specialWorkspace: { id: 0, name: "" } },
    ...changes,
  }
}

test("focused empty workspace uses compositor workarea", () => {
  assert.deepEqual(frame("DP-1", monitor(), 0), { x: 0, y: 28, width: 1920, height: 1052 })
  assert.deepEqual(frame("DP-1", monitor({ lastIpcObject: {
    reserved: [3, 0, 7, 5], specialWorkspace: { id: 0, name: "" },
  } }), 0), { x: 3, y: 0, width: 1910, height: 1075 })
  assert.deepEqual(frame("DP-1", monitor({ width: 2560, height: 1440 }), 0),
    { x: 0, y: 28, width: 2560, height: 1412 })
})

test("unknown or occupied workspace and wrong output stay hidden", () => {
  assert.equal(frame("DP-2", monitor(), 0), null)
  assert.equal(frame("DP-1", monitor({ focused: false }), 0), null)
  assert.equal(frame("DP-1", monitor({ activeWorkspace: null }), 0), null)
  assert.equal(frame("DP-1", monitor(), undefined), null)
  assert.equal(frame("DP-1", monitor(), 1), null) // includes a floating-only workspace
  assert.equal(frame("DP-1", monitor({ lastIpcObject: {
    reserved: [0, 28, 0, 0], specialWorkspace: { id: -99, name: "special" },
  } }), 0), null)
})

test("invalid insets or nonpositive workarea stay hidden", () => {
  assert.equal(frame("DP-1", monitor({ lastIpcObject: {} }), 0), null)
  assert.equal(frame("DP-1", monitor({ lastIpcObject: { reserved: [0, -1, 0, 0] } }), 0), null)
  assert.equal(frame("DP-1", monitor({ width: 10,
    lastIpcObject: { reserved: [5, 0, 5, 0] } }), 0), null)
})
