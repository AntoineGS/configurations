const assert = require("node:assert/strict")
const Model = require("../plugins/panels/monitor/Model.js")

const topology = Model.normalizeMonitors([
  {
    name: "eDP-1",
    description: "Internal display",
    width: 1920,
    height: 1080,
    scale: 1.25,
    focused: true,
    lastIpcObject: { disabled: false, mirrorOf: "none" }
  },
  {
    name: "DP-1",
    width: 2560,
    scale: 2,
    focused: false,
    lastIpcObject: { disabled: false, mirrorOf: "none" }
  },
  { name: "HDMI-1", lastIpcObject: {} },
  { description: "ignored without a name" }
], { name: "eDP-1" })

assert.deepEqual(topology.monitors, [
  {
    name: "eDP-1",
    description: "Internal display",
    width: 1920,
    height: 1080,
    scale: 1.25,
    focused: true,
    enabled: true,
    mirrorOf: "none"
  },
  {
    name: "DP-1",
    description: "",
    width: 2560,
    height: 0,
    scale: 2,
    focused: false,
    enabled: true,
    mirrorOf: "none"
  },
  {
    name: "HDMI-1",
    description: "",
    width: 0,
    height: 0,
    scale: 1,
    focused: false,
    enabled: true,
    mirrorOf: "none"
  }
])
assert.equal(topology.focusedMonitor, "eDP-1")
assert.equal(topology.internalMonitor, "eDP-1")
assert.equal(topology.internalEnabled, true)
assert.equal(Model.enabledDisplayCount(topology.monitors), 3)
assert.equal(topology.mirrorEnabled, false)

const qmlObjectList = {
  0: { name: "eDP-1", lastIpcObject: { mirrorOf: "none" } },
  1: { name: "DP-1", lastIpcObject: { mirrorOf: "eDP-1" } }
}
assert.equal(Model.normalizeMonitors(qmlObjectList, { name: "eDP-1" }).monitors.length, 2)
assert.equal(Model.normalizeMonitors(qmlObjectList, { name: "eDP-1" }).mirrorEnabled, true)

const mirrored = Model.normalizeMonitors([
  { name: "eDP-1", lastIpcObject: { disabled: false } },
  { name: "DP-1", lastIpcObject: { disabled: false, mirrorOf: "eDP-1" } },
  { name: "DP-2", lastIpcObject: { disabled: false, mirrorOf: "HDMI-1" } }
], null)
assert.equal(mirrored.focusedMonitor, "")
assert.equal(mirrored.internalEnabled, true)
assert.equal(mirrored.mirrorEnabled, true)
assert.equal(Model.normalizeMonitors([
  { name: "eDP-1", lastIpcObject: { mirrorOf: "none" } },
  { name: "DP-2", lastIpcObject: { mirrorOf: "HDMI-1" } }
], null).mirrorEnabled, false)

const missing = Model.normalizeMonitors(null, null)
assert.deepEqual(missing, {
  monitors: [],
  focusedMonitor: "",
  internalMonitor: "",
  internalEnabled: false,
  mirrorEnabled: false
})

let inactive = Model.normalizeMonitors([], null)
assert.equal(inactive.internalMonitor, "")
assert.equal(inactive.internalEnabled, false)
assert.equal(inactive.mirrorEnabled, false)
let active = Model.normalizeMonitors([{ name: "eDP-1", focused: true }], { name: "eDP-1" })
assert.equal(active.internalMonitor, "eDP-1")
assert.equal(active.internalEnabled, true)
assert.equal(active.monitors[0].enabled, true)
const refreshed = Model.normalizeMonitors([
  { name: "eDP-1", lastIpcObject: { mirrorOf: "none" } },
  { name: "DP-1", lastIpcObject: { mirrorOf: "none" } }
], null)
assert.equal(refreshed.mirrorEnabled, false)

let operation = Model.monitorOperationState()
let transition = Model.monitorOperationTransition(operation, "reconcile-request")
operation = transition.state
transition = Model.monitorOperationTransition(operation, "action-request", ["monitor", "toggle-mirror"])
operation = transition.state
assert.deepEqual(operation, {
  actionRunning: false,
  reconciliationRunning: true,
  reconciliationQueued: false,
  actionQueue: [["monitor", "toggle-mirror"]],
  postActionQueued: false
})
transition = Model.monitorOperationTransition(operation, "reconcile-finished")
operation = transition.state
assert.equal(operation.actionRunning, true)
assert.deepEqual(transition.startAction, ["monitor", "toggle-mirror"])
transition = Model.monitorOperationTransition(operation, "action-request", ["monitor", "set-keyboard-brightness", "up"])
operation = transition.state
transition = Model.monitorOperationTransition(operation, "reconcile-request")
operation = transition.state
transition = Model.monitorOperationTransition(operation, "action-finished")
operation = transition.state
assert.equal(operation.postActionQueued, true)
transition = Model.monitorOperationTransition(operation, "reconcile-request")
operation = transition.state
assert.equal(operation.reconciliationRunning, true)
assert.equal(operation.actionQueue.length, 1)
transition = Model.monitorOperationTransition(operation, "reconcile-finished")
assert.deepEqual(transition.startAction, ["monitor", "set-keyboard-brightness", "up"])
operation = transition.state
transition = Model.monitorOperationTransition(operation, "action-finished")
operation = transition.state
transition = Model.monitorOperationTransition(operation, "reconcile-request")
operation = transition.state
transition = Model.monitorOperationTransition(operation, "reconcile-finished")
operation = transition.state
assert.equal(transition.startReconciliation, false)
assert.equal(operation.postActionQueued, false)

let brightness = Model.brightnessState({ brightnessPercent: 50, lastConfirmedBrightnessPercent: 50 }, {
  available: true,
  percent: 80,
  device: "backlight"
}, {
  available: true,
  percent: 30
})
assert.equal(brightness.brightnessPercent, 80)
assert.equal(brightness.lastConfirmedBrightnessPercent, 80)
brightness = Model.brightnessState(brightness, { available: false, percent: 0 }, { available: false, percent: 0 })
assert.equal(brightness.brightnessPercent, 80)
assert.equal(brightness.brightness.available, false)
assert.equal(brightness.keyboardBrightness.available, false)
brightness = Model.brightnessState(brightness, null, null)
assert.equal(brightness.brightnessPercent, 80)
assert.equal(brightness.brightness.available, false)

assert.equal(Model.shouldRefreshNativeMonitors("toggle-internal"), true)
assert.equal(Model.shouldRefreshNativeMonitors("toggle-mirror"), true)
assert.equal(Model.shouldRefreshNativeMonitors("set-display-brightness"), false)
