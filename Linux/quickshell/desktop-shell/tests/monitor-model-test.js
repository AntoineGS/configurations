const assert = require("node:assert/strict")
const crypto = require("node:crypto")
const fs = require("node:fs")
const path = require("node:path")
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
assert.equal(Model.shouldRefreshNativeMonitors("set-scale"), true)
assert.equal(Model.shouldRefreshNativeMonitors("set-layout"), true)
assert.equal(Model.shouldRefreshNativeMonitors("set-display-brightness"), false)

let targetedAction = ["monitor", "set-scale", "DP-1", "1.25"]
let targetedTransition = Model.monitorOperationTransition(
  Model.monitorOperationState(), "action-request", targetedAction)
assert.deepEqual(targetedTransition.startAction, targetedAction)

function fixtureEdid(name) {
  return fs.readFileSync(path.join(__dirname, "../../../os/tests/fixtures/monitor-brightness", name + ".edid.hex"), "utf8")
    .replace(/[\r\n\s]/g, "")
}

const edidA = fixtureEdid("display-a")
const edidB = fixtureEdid("display-b")
const edidC = fixtureEdid("display-c")
const sha256 = value => crypto.createHash("sha256").update(value).digest("hex")
const topologyHash = "4c05fc30acaebba57ab4c39415d88198f02eaacc232fc25b6b5e17bd8316ec90"
const replacementTopologyHash = "36bd9a2d1c574957d5f82ba206180062053f13e120183d56b3eb60233c717185"

function targetRecord(connector, topology = topologyHash, percent = 50, options = {}) {
  const edid = options.edid || (connector === "HDMI-1" ? edidB : edidA)
  const selector = options.selector || { kind: "bus", value: connector === "HDMI-1" ? "4" : "3" }
  const identity = options.identity || sha256([
    connector, "ddc", edid, topology, selector.kind, selector.value
  ].join("\n"))
  return {
    connector,
    backend: "ddc",
    available: true,
    stale: false,
    error: "",
    current: percent,
    maximum: 100,
    percent,
    identity,
    topology,
    edid,
    selector
  }
}

const targetA = targetRecord("DP-1", topologyHash, 30)
const targetALatest = targetRecord("DP-1", topologyHash, 80, { identity: targetA.identity })
const targetB = targetRecord("HDMI-1", topologyHash, 40)
const targetAReplacement = targetRecord("DP-1", topologyHash, 60, { edid: edidC })
const firstBrightness = ["monitor", "set-display-brightness", "30", JSON.stringify(targetA)]
const latestBrightness = ["monitor", "set-display-brightness", "80", JSON.stringify(targetALatest)]
const otherBrightness = ["monitor", "set-display-brightness", "40", JSON.stringify(targetB)]
const layoutAction = ["monitor", "set-layout", "physical"]
assert.equal(Model.brightnessActionConnector(firstBrightness), "DP-1")
assert.equal(Model.brightnessActionConnector(["monitor", "set-display-brightness", "30", "not-json"]), "")

let heldRead = Model.monitorOperationState()
heldRead = Model.monitorOperationTransition(heldRead, "reconcile-request").state
heldRead = Model.monitorOperationTransition(heldRead, "action-request", firstBrightness).state
const canceledRead = Model.monitorOperationTransition(heldRead, "reconcile-cancelled")
assert.deepEqual(canceledRead.startAction, firstBrightness)
assert.equal(canceledRead.state.reconciliationRunning, false)
assert.equal(canceledRead.state.actionRunning, true)

assert.deepEqual(Model.queueMonitorAction([firstBrightness], latestBrightness), [latestBrightness])
assert.deepEqual(Model.queueMonitorAction([firstBrightness, layoutAction], latestBrightness),
  [firstBrightness, layoutAction, latestBrightness])
assert.deepEqual(Model.queueMonitorAction([firstBrightness, otherBrightness], latestBrightness),
  [latestBrightness, otherBrightness])
assert.deepEqual(Model.queueMonitorAction([firstBrightness], [
  "monitor", "set-display-brightness", "60", JSON.stringify(targetAReplacement)
]), [firstBrightness, ["monitor", "set-display-brightness", "60", JSON.stringify(targetAReplacement)]])
assert.deepEqual(Model.queueMonitorAction([firstBrightness], [
  "monitor", "set-display-brightness", "60", "not-json"
]), [firstBrightness, ["monitor", "set-display-brightness", "60", "not-json"]])
const queueBeforeCoalesce = [firstBrightness, otherBrightness]
const queueAfterCoalesce = Model.queueMonitorAction(queueBeforeCoalesce, latestBrightness)
assert.deepEqual(queueBeforeCoalesce, [firstBrightness, otherBrightness])
assert.notStrictEqual(queueAfterCoalesce, queueBeforeCoalesce)

const fullBrightnessSnapshot = {
  version: 1,
  topology: topologyHash,
  monitors: {
    "DP-1": targetA,
    "HDMI-1": targetB
  }
}
assert.equal(Model.normalizeBrightnessSnapshot(fullBrightnessSnapshot, null).valid, true)
const partialBrightnessSnapshot = {
  version: 1,
  topology: topologyHash,
  monitors: { "DP-1": targetALatest }
}
const mergedBrightnessSnapshot = Model.mergeBrightnessSnapshot(fullBrightnessSnapshot, partialBrightnessSnapshot, "DP-1")
assert.equal(mergedBrightnessSnapshot.topologyChanged, false)
assert.deepEqual(mergedBrightnessSnapshot.snapshot.monitors["DP-1"], targetALatest)
assert.deepEqual(mergedBrightnessSnapshot.snapshot.monitors["HDMI-1"], targetB)

const fullReplacement = Model.mergeBrightnessSnapshot(fullBrightnessSnapshot, {
  version: 1,
  topology: topologyHash,
  monitors: { "DP-1": targetALatest }
})
assert.equal(fullReplacement.snapshot.monitors["HDMI-1"], undefined)

const partialMissing = Model.mergeBrightnessSnapshot(fullBrightnessSnapshot, {
  version: 1,
  topology: topologyHash,
  monitors: { "HDMI-1": targetB }
}, "DP-1")
assert.equal(partialMissing.requestedRecordValid, false)

const partialWrong = Model.mergeBrightnessSnapshot(fullBrightnessSnapshot, {
  version: 1,
  topology: topologyHash,
  monitors: { "HDMI-1": targetB }
}, "DP-1")
assert.equal(partialWrong.requestedRecordValid, false)

const changedBrightnessSnapshot = Model.mergeBrightnessSnapshot(fullBrightnessSnapshot, {
  version: 1,
  topology: replacementTopologyHash,
  monitors: { "DP-1": targetRecord("DP-1", replacementTopologyHash, 70, { edid: edidC }) }
})
assert.equal(changedBrightnessSnapshot.topologyChanged, true)
assert.equal(changedBrightnessSnapshot.snapshot.monitors["DP-1"].available, true)
assert.equal(changedBrightnessSnapshot.snapshot.monitors["HDMI-1"], undefined)

const malformedTargetedSnapshot = Model.mergeBrightnessSnapshot(fullBrightnessSnapshot, {
  version: 1,
  topology: topologyHash,
  monitors: { "DP-1": Object.assign({}, targetA, { current: "30" }) }
}, "DP-1")
const preservedMalformedTarget = malformedTargetedSnapshot.snapshot.monitors["DP-1"]
assert.equal(preservedMalformedTarget.available, false)
assert.equal(preservedMalformedTarget.stale, true)
assert.equal(preservedMalformedTarget.current, targetA.current)
assert.equal(preservedMalformedTarget.identity, targetA.identity)
assert.equal(preservedMalformedTarget.topology, targetA.topology)

const changedTargetedSnapshot = Model.mergeBrightnessSnapshot(fullBrightnessSnapshot, {
  version: 1,
  topology: replacementTopologyHash,
  monitors: { "DP-1": targetRecord("DP-1", replacementTopologyHash, 70, { edid: edidC }) }
}, "DP-1")
const staleOmittedTarget = changedTargetedSnapshot.snapshot.monitors["HDMI-1"]
assert.equal(staleOmittedTarget.available, false)
assert.equal(staleOmittedTarget.stale, true)
assert.equal(staleOmittedTarget.current, targetB.current)
assert.equal(staleOmittedTarget.identity, targetB.identity)
assert.equal(staleOmittedTarget.topology, targetB.topology)
assert.deepEqual(Model.brightnessFor(changedTargetedSnapshot.snapshot, "HDMI-1"), staleOmittedTarget)

const malformedSnapshot = Model.normalizeBrightnessSnapshot({
  version: 1,
  topology: topologyHash,
  monitors: {
    "DP-1": Object.assign({}, targetA, { identity: "not-an-identity" }),
    "HDMI-1": Object.assign({}, targetB, { current: "40" })
  }
}, null)
assert.equal(malformedSnapshot.snapshot.monitors["DP-1"].available, false)
assert.equal(malformedSnapshot.snapshot.monitors["HDMI-1"].available, false)
assert.equal(malformedSnapshot.snapshot.monitors["DP-1"].percent, null)
assert.equal(malformedSnapshot.snapshot.monitors["HDMI-1"].percent, null)
assert.equal(Model.brightnessFor(fullBrightnessSnapshot, "missing").available, false)

assert.equal(Model.validBrightnessSnapshotTopLevel({ version: 1, topology: topologyHash, monitors: {} }), true)
assert.equal(Model.validBrightnessSnapshotTopLevel({ version: 1, topology: "a".repeat(63) + "g", monitors: {} }), false)
assert.equal(Model.isValidBrightnessTarget(Object.assign({}, targetA, {
  edid: "00ffffffffffff00" + "00".repeat(120)
})), false)
assert.equal(Model.isValidBrightnessTarget(Object.assign({}, targetA, {
  selector: { kind: "edid", value: edidB }
})), false)
assert.equal(Model.isValidBrightnessTarget(Object.assign({}, targetA, {
  selector: { kind: "bus", value: "bus-3" }
})), false)
const backlightDot = {
  connector: "eDP-1",
  backend: "backlight",
  available: true,
  stale: false,
  error: "",
  current: 50,
  maximum: 100,
  percent: 50,
  identity: sha256(["eDP-1", "backlight", edidA, topologyHash, "backlight", "."].join("\n")),
  topology: topologyHash,
  edid: edidA,
  selector: { kind: "backlight", value: "." }
}
assert.equal(Model.isValidBrightnessTarget(backlightDot), false)
assert.equal(Model.isValidBrightnessTarget(Object.assign({}, backlightDot, {
  identity: sha256(["eDP-1", "backlight", edidA, topologyHash, "backlight", ".."].join("\n")),
  selector: { kind: "backlight", value: ".." }
})), false)
assert.equal(Model.isValidBrightnessTarget(Object.assign({}, targetA, {
  identity: "f".repeat(64)
})), false)
assert.equal(Model.isValidBrightnessTarget(Object.assign({}, targetA, {
  backend: "backlight",
  selector: { kind: "backlight", value: "../panel" }
})), false)
