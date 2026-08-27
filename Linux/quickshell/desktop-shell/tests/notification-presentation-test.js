const assert = require("node:assert/strict")
const Presentation = require("../plugins/notifications/NotificationPresentation.js")

function snapshot(identity, urgency, duration, remaining) {
  const parts = identity.split(":")
  return Presentation.createSnapshot({
    identity,
    originalId: Number(parts[1]),
    timestamp: Number(parts[0]),
    app: "test",
    summary: identity,
    body: "body",
    urgency,
    actions: [{ identifier: "default", text: "Open" }],
    queuePriority: urgency === 2,
    queueOrder: Number(parts[0]),
    remainingLifetime: remaining,
  }, duration)
}

function ids(rows) { return rows.map(row => row.identity) }
function apply(state, event) {
  const before = JSON.parse(JSON.stringify(state))
  const result = Presentation.reduce(state, event)
  Presentation.assertInvariants(result.state)
  assert.deepEqual(state, before, "reducer does not mutate its state input")
  return result
}
function step(state, event, expected) {
  const result = apply(state, event)
  if (expected) expected(result.state, result.effects)
  return result.state
}

let state = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
assert.deepEqual(state, {
  version: 1, phase: "closed", route: { visible: true, output: "DP-1" }, active: null, pending: [],
  visual: {
    outgoing: null, incoming: null,
    outgoingDeck: { snapshots: [], queuedCount: 0, criticalPending: false },
    incomingDeck: { snapshots: [], queuedCount: 0, criticalPending: false },
    token: 0, kind: "", output: "",
  }, hovered: false, deferredCritical: false,
  countdown: { identity: "", duration: 0, remaining: 0, fraction: 1, visible: false, lastNow: 0 },
  retired: {}, nextToken: 1,
})
const normalA = snapshot("1000:1", 1, 10000, 10000)
const normalB = snapshot("2000:2", 1, 10000, 10000)
const criticalC = snapshot("3000:3", 2, 0, 0)
const originalState = JSON.parse(JSON.stringify(state))
let result = apply(state, { type: "ARRIVE", snapshot: normalA })
assert.equal(result.effects.length, 2)
assert.deepEqual(result.effects[1], { type: "startWatchdog", token: 1, kind: "open", output: "DP-1", timeout: 510 })
state = result.state
assert.equal(state.phase, "opening")
assert.equal(state.active.identity, "1000:1")
assert.equal(state.visual.incoming.identity, "1000:1")
assert.equal(state.countdown.visible, false)
assert.equal(state.visual.token, 1)
assert.deepEqual(originalState, Presentation.createInitialState({ routeVisible: true, output: "DP-1" }))

state = step(state, { type: "TRANSITION_FINISHED", token: 99, kind: "open", output: "DP-1" }, s => {
  assert.equal(s.phase, "opening")
})
state = step(state, { type: "TRANSITION_FINISHED", token: 1, kind: "open", output: "wrong" }, s => assert.equal(s.phase, "opening"))
state = step(state, { type: "TRANSITION_FINISHED", token: 1, kind: "open", output: "DP-1" }, s => {
  assert.equal(s.phase, "open")
  assert.equal(s.countdown.identity, "1000:1")
  assert.equal(s.countdown.visible, true)
})

state = step(state, { type: "ARRIVE", snapshot: normalB }, s => {
  assert.deepEqual(ids(s.pending), ["2000:2"])
  assert.equal(s.visual.token, 0)
})
state = step(state, { type: "HOVER_CHANGED", hovered: true }, s => assert.equal(s.hovered, true))
state = step(state, { type: "ARRIVE", snapshot: criticalC }, s => {
  assert.equal(s.phase, "open")
  assert.equal(s.deferredCritical, true)
})
state = step(state, { type: "HOVER_CHANGED", hovered: false }, s => {
  assert.equal(s.phase, "switching")
  assert.equal(s.active.identity, "3000:3")
  assert.deepEqual(ids(s.pending), ["1000:1", "2000:2"])
  assert.equal(s.visual.outgoing.identity, "1000:1")
  assert.equal(s.visual.incoming.identity, "3000:3")
  assert.deepEqual(ids(s.visual.outgoingDeck.snapshots), ["2000:2"])
  assert.deepEqual(ids(s.visual.incomingDeck.snapshots), ["1000:1", "2000:2"])
  assert.equal(s.countdown.visible, false)
})
const switchToken = state.visual.token
state = step(state, { type: "ARRIVE", snapshot: snapshot("4000:4", 1, 5000, 5000) }, s => {
  assert.equal(s.visual.token, switchToken)
  assert.deepEqual(ids(s.pending), ["1000:1", "2000:2", "4000:4"])
})
state = step(state, { type: "TRANSITION_FINISHED", token: switchToken, kind: "switch", output: "DP-1" }, s => {
  assert.equal(s.phase, "open")
  assert.equal(s.active.identity, "3000:3")
  assert.equal(s.countdown.visible, false)
})
state = step(state, { type: "DISMISS", identity: "3000:3" }, s => {
  assert.equal(s.phase, "switching")
  assert.equal(s.active.identity, "1000:1")
  assert.equal(s.visual.outgoing.identity, "3000:3")
  assert.equal(s.visual.incoming.identity, "1000:1")
})
const returnToken = state.visual.token
state = step(state, { type: "TRANSITION_FINISHED", token: returnToken, kind: "switch", output: "DP-1" }, s => {
  assert.equal(s.phase, "open")
  assert.equal(s.active.identity, "1000:1")
  assert.equal(s.countdown.remaining, 10000)
})

const replacementA = snapshot("1000:1", 1, 9000, 9000)
replacementA.summary = "replacement"
state = step(state, { type: "REPLACE", identity: "1000:1", snapshot: replacementA }, s => {
  assert.equal(s.active.identity, "1000:1")
  assert.equal(s.visual.incoming.identity, "1000:1")
})
state = step(state, { type: "DISMISS", identity: "1000:1" }, s => assert.equal(s.phase, "switching"))
const dismissToken = state.visual.token
state = step(state, { type: "REPLACE", identity: "1000:1", snapshot: snapshot("1000:1", 1, 9000, 9000) }, s => {
  assert.equal(s.active.identity, "2000:2")
  assert.equal(s.visual.incoming.identity, "2000:2")
})
state = step(state, { type: "TRANSITION_FINISHED", token: dismissToken, kind: "switch", output: "DP-1" }, s => assert.equal(s.phase, "open"))
state = step(state, { type: "DISMISS", identity: "2000:2" })
const closeToken = state.visual.token
state = step(state, { type: "ARRIVE", snapshot: snapshot("7000:7", 1, 1000, 1000) }, s => assert.equal(s.pending.length, 1))
state = step(state, { type: "TRANSITION_FINISHED", token: closeToken, kind: "switch", output: "DP-1" }, s => {
  assert.equal(s.phase, "open")
  assert.equal(s.active.identity, "4000:4")
})

let replaced = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
replaced = step(replaced, { type: "ARRIVE", snapshot: snapshot("8000:8", 1, 1000, 1000) })
const frozenIncoming = JSON.parse(JSON.stringify(replaced.visual.incoming))
const replacementB = snapshot("8000:8", 1, 1000, 1000)
replacementB.summary = "new generation"
replaced = step(replaced, { type: "REPLACE", identity: "8000:8", snapshot: replacementB }, s => {
  assert.equal(s.visual.incoming.identity, "8000:8")
  assert.equal(s.active.identity, "8000:8")
})
assert.deepEqual(frozenIncoming, replaced.visual.incoming)
replaced = step(replaced, { type: "TRANSITION_FINISHED", token: 1, kind: "open", output: "DP-1" }, s => {
  assert.equal(s.phase, "open")
  assert.equal(s.active.identity, "8000:8")
  assert.equal(s.visual.incoming.identity, "8000:8")
})

let routed = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
routed = step(routed, { type: "ARRIVE", snapshot: snapshot("10000:10", 1, 1000, 1000) })
routed = step(routed, { type: "ROUTE_CHANGED", visible: false, output: null }, s => {
  assert.equal(s.phase, "hidden")
  assert.equal(s.visual.token, 0)
  assert.equal(s.countdown.visible, false)
})
routed = step(routed, { type: "TICK", now: 2000 }, s => assert.equal(s.countdown.remaining, 0))
routed = step(routed, { type: "ROUTE_CHANGED", visible: true, output: "DP-2" }, s => {
  assert.equal(s.phase, "opening")
  assert.equal(s.visual.token, 2)
  assert.equal(s.visual.output, "DP-2")
})

let timers = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
timers = step(timers, { type: "ARRIVE", snapshot: snapshot("11000:11", 1, 1000, 1000) })
timers = step(timers, { type: "TICK", identity: "11000:11", now: 10 }, s => assert.equal(s.countdown.remaining, 0))
timers = step(timers, { type: "TRANSITION_FINISHED", token: 1, kind: "open", output: "DP-1" })
timers = step(timers, { type: "TICK", identity: "11000:11", now: 1 })
timers = step(timers, { type: "TICK", identity: "11000:11", now: 101 }, s => assert.equal(s.countdown.remaining, 900))
const expiry = apply(timers, { type: "TICK", identity: "11000:11", now: 1101 })
assert.ok(expiry.effects.some(effect => effect.type === "senderExpire" && effect.identity === "11000:11"))
assert.equal(expiry.state.phase, "closing")

let all = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
all = step(all, { type: "ARRIVE", snapshot: snapshot("12000:12", 1, 1000, 1000) })
all = step(all, { type: "DISMISS_ALL" }, s => {
  assert.equal(s.active, null)
  assert.deepEqual(s.pending, [])
  assert.equal(s.phase, "closing")
})
all = step(all, { type: "SENDER_CLOSED", identity: "12000:12" }, s => assert.equal(s.active, null))
for (const event of [null, {}, { type: "UNKNOWN" }, { type: "ARRIVE" }, { type: "TICK", now: "bad" }]) {
  all = step(all, event, s => assertInvariantsOnly(s))
}

function assertInvariantsOnly(value) { assert.equal(Presentation.assertInvariants(value), true) }
assert.equal(Presentation.presentationFrame(all).phase, all.phase)
function finishOpen(value) {
  return step(value, { type: "TRANSITION_FINISHED", token: value.visual.token, kind: "open", output: value.visual.output })
}
function openState(row) {
  let value = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
  value = step(value, { type: "ARRIVE", snapshot: row })
  return finishOpen(value)
}

// Round 1 review races: every event continues through apply(), including malformed input.
let watchdog = openState(snapshot("13000:13", 1, 1000, 1000))
let watchdogResult = apply(watchdog, { type: "ARRIVE", snapshot: snapshot("14000:14", 2, 0, 0) })
assert.ok(watchdogResult.effects.some(effect => effect.type === "startWatchdog" && effect.timeout === 830 && effect.kind === "switch"))
watchdog = watchdogResult.state
const switchToken2 = watchdog.visual.token
watchdogResult = apply(watchdog, { type: "TRANSITION_TIMED_OUT", token: switchToken2, kind: "switch", output: "DP-1" })
assert.ok(watchdogResult.effects.some(effect => effect.type === "cancelWatchdog" && effect.token === switchToken2))
watchdog = watchdogResult.state
const closeResult = apply(openState(snapshot("14500:145", 1, 1000, 1000)), { type: "DISMISS", identity: "14500:145" })
assert.ok(closeResult.effects.some(effect => effect.type === "startWatchdog" && effect.timeout === 470 && effect.kind === "close"))

let closing = openState(snapshot("15000:15", 1, 1000, 1000))
let closingResult = apply(closing, { type: "DISMISS", identity: "15000:15" })
assert.equal(closingResult.state.phase, "closing")
const frozenClose = JSON.parse(JSON.stringify(closingResult.state.visual))
closingResult = apply(closingResult.state, { type: "ARRIVE", snapshot: snapshot("16000:16", 1, 1000, 1000) })
assert.deepEqual(closingResult.state.visual, frozenClose)
assert.deepEqual(ids(closingResult.state.pending), ["16000:16"])
const closeToken2 = closingResult.state.visual.token
closingResult = apply(closingResult.state, { type: "TRANSITION_FINISHED", token: closeToken2, kind: "close", output: "DP-1" })
assert.equal(closingResult.state.phase, "opening")
assert.equal(closingResult.state.active.identity, "16000:16")
assert.ok(closingResult.effects.some(effect => effect.type === "startWatchdog" && effect.timeout === 510))
const closeSettled = apply(closingResult.state, { type: "TRANSITION_FINISHED", token: closingResult.state.visual.token, kind: "open", output: "DP-1" })
assert.deepEqual(closeSettled.effects, [{ type: "cancelWatchdog", token: closingResult.state.visual.token, kind: "open", output: "DP-1" }])

let hiddenTransition = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
hiddenTransition = step(hiddenTransition, { type: "ARRIVE", snapshot: snapshot("15500:155", 1, 1000, 1000) })
const hiddenResult = apply(hiddenTransition, { type: "ROUTE_CHANGED", visible: false, output: null })
assert.deepEqual(hiddenResult.effects, [{ type: "cancelWatchdog", token: 1, kind: "open", output: "DP-1" }])
const staleResult = apply(hiddenResult.state, { type: "TRANSITION_FINISHED", token: 1, kind: "open", output: "DP-1" })
assert.deepEqual(staleResult.effects, [])

let timerState = openState(snapshot("17000:17", 1, 1000, 1000))
timerState = step(timerState, { type: "TICK", identity: "wrong", now: 100 }, s => assert.equal(s.countdown.remaining, 1000))
timerState = step(timerState, { type: "TICK", identity: "17000:17", now: 100 })
timerState = step(timerState, { type: "TICK", identity: "17000:17", now: 200 }, s => assert.equal(s.countdown.remaining, 900))
timerState = step(timerState, { type: "HOVER_CHANGED", hovered: true })
timerState = step(timerState, { type: "TICK", identity: "17000:17", now: 300 }, s => assert.equal(s.countdown.remaining, 900))
timerState = step(timerState, { type: "HOVER_CHANGED", hovered: false })
timerState = step(timerState, { type: "TICK", identity: "17000:17", now: 400 }, s => assert.equal(s.countdown.remaining, 900))
timerState = step(timerState, { type: "TICK", identity: "17000:17", now: 500 }, s => assert.equal(s.countdown.remaining, 800))
assert.equal(timerState.active.remainingLifetime, 800)
const repeatedHover = JSON.parse(JSON.stringify(timerState))
repeatedHover.hovered = true
repeatedHover.countdown.lastNow = 77
const repeatedHoverResult = apply(repeatedHover, { type: "HOVER_CHANGED", hovered: true })
assert.deepEqual(repeatedHoverResult.state, repeatedHover)
assert.deepEqual(repeatedHoverResult.effects, [])
const expiryResult = apply(timerState, { type: "TICK", identity: "17000:17", now: 1300 })
assert.equal(expiryResult.state.phase, "closing")
assert.equal(expiryResult.state.visual.outgoing.identity, "17000:17")
assert.ok(expiryResult.effects.some(effect => effect.type === "senderExpire"))

let generation = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
generation = step(generation, { type: "ARRIVE", snapshot: snapshot("18000:18", 1, 1000, 1000) })
const newGeneration = snapshot("19000:18", 1, 2000, 2000)
generation = step(generation, { type: "REPLACE", identity: "18000:18", snapshot: newGeneration }, s => {
  assert.equal(s.active.identity, "19000:18")
  assert.equal(s.visual.incoming.identity, "18000:18")
  assert.equal(s.retired["18000:18"], true)
})
generation = finishOpen(generation)
assert.equal(generation.visual.incoming.identity, "19000:18")
generation = step(generation, { type: "SENDER_CLOSED", identity: "18000:18" }, s => assert.equal(s.active.identity, "19000:18"))
const activeClose = apply(generation, { type: "SENDER_CLOSED", identity: "19000:18" })
assert.equal(activeClose.state.phase, "closing")

let priority = openState(snapshot("20000:20", 2, 0, 0))
priority = step(priority, { type: "ARRIVE", snapshot: snapshot("21000:21", 2, 0, 0) }, s => {
  assert.equal(s.phase, "open")
  assert.deepEqual(ids(s.pending), ["21000:21"])
})
priority = step(priority, { type: "ARRIVE", snapshot: snapshot("22000:22", 1, 1000, 1000) })
priority = step(priority, { type: "HOVER_CHANGED", hovered: true })
priority = step(priority, { type: "ARRIVE", snapshot: snapshot("23000:23", 2, 0, 0) })
priority = step(priority, { type: "HOVER_CHANGED", hovered: false }, s => assert.deepEqual(ids(s.pending), ["21000:21", "23000:23", "22000:22"]))

let openingBoundary = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
openingBoundary = step(openingBoundary, { type: "ARRIVE", snapshot: snapshot("23100:231", 1, 1000, 1000) })
openingBoundary = step(openingBoundary, { type: "ARRIVE", snapshot: snapshot("23200:232", 2, 0, 0) }, s => {
  assert.equal(s.phase, "opening")
  assert.deepEqual(ids(s.pending), ["23200:232"])
})
openingBoundary = step(openingBoundary, { type: "TRANSITION_FINISHED", token: openingBoundary.visual.token, kind: "open", output: "DP-1" }, s => {
  assert.equal(s.phase, "switching")
  assert.equal(s.active.identity, "23200:232")
  assert.deepEqual(ids(s.pending), ["23100:231"])
  assert.deepEqual(ids(s.visual.outgoingDeck.snapshots), ["23200:232"])
  assert.deepEqual(ids(s.visual.incomingDeck.snapshots), ["23100:231"])
})

let boundaryCritical = openState(snapshot("23500:235", 1, 1000, 1000))
boundaryCritical = step(boundaryCritical, { type: "ARRIVE", snapshot: snapshot("23600:236", 2, 0, 0) })
boundaryCritical = step(boundaryCritical, { type: "ARRIVE", snapshot: snapshot("23700:237", 2, 0, 0) }, s => {
  assert.equal(s.phase, "switching")
  assert.deepEqual(ids(s.pending), ["23700:237", "23500:235"])
})
boundaryCritical = step(boundaryCritical, { type: "TRANSITION_FINISHED", token: boundaryCritical.visual.token, kind: "switch", output: "DP-1" }, s => {
  assert.equal(s.phase, "open")
  assert.equal(s.active.identity, "23600:236")
  assert.deepEqual(ids(s.pending), ["23700:237", "23500:235"])
})

let tiedReplacement = openState(snapshot("23800:238", 2, 0, 0))
const tiedOne = snapshot("23900:239", 1, 1000, 1000); tiedOne.queueOrder = 0
const tiedTwo = snapshot("24000:240", 1, 1000, 1000); tiedTwo.queueOrder = 0
tiedReplacement = step(tiedReplacement, { type: "ARRIVE", snapshot: tiedOne })
tiedReplacement = step(tiedReplacement, { type: "ARRIVE", snapshot: tiedTwo })
const tiedNext = snapshot("24100:239", 2, 0, 0)
tiedReplacement = step(tiedReplacement, { type: "REPLACE", identity: "23900:239", snapshot: tiedNext }, s => {
  assert.deepEqual(ids(s.pending), ["24100:239", "24000:240"])
  assert.equal(s.pending[0].queueOrder, 0)
  assert.equal(s.pending[0].queuePriority, false)
})

let allEffects = openState(snapshot("24000:24", 1, 1000, 1000))
allEffects = step(allEffects, { type: "ARRIVE", snapshot: snapshot("25000:25", 1, 1000, 1000) })
allEffects = step(allEffects, { type: "ARRIVE", snapshot: snapshot("25000:26", 1, 1000, 1000) })
const allResult = apply(allEffects, { type: "DISMISS_ALL" })
assert.equal(allResult.effects.filter(effect => effect.type === "archive").length, 3)
assert.ok(allResult.effects.filter(effect => effect.type === "archive" || effect.type === "senderDismiss").every(effect => effect.snapshot && effect.identity))

let pendingReplacement = openState(snapshot("26000:26", 2, 0, 0))
pendingReplacement = step(pendingReplacement, { type: "ARRIVE", snapshot: snapshot("27000:27", 1, 1000, 1000) })
pendingReplacement = step(pendingReplacement, { type: "ARRIVE", snapshot: snapshot("28000:28", 2, 0, 0) })
pendingReplacement = step(pendingReplacement, { type: "REPLACE", identity: "27000:27", snapshot: snapshot("29000:27", 2, 0, 0) }, s => {
  assert.deepEqual(ids(s.pending), ["28000:28", "29000:27"])
  assert.equal(s.pending[1].queueOrder, 27000)
  assert.equal(s.pending[1].queuePriority, false)
})

const allSenderDismiss = allResult.effects.filter(effect => effect.type === "senderDismiss")
assert.deepEqual(allSenderDismiss.map(effect => effect.identity), ["24000:24", "25000:25", "25000:26"])

let stableReplacement = openState(snapshot("29500:295", 1, 1000, 1000))
stableReplacement = step(stableReplacement, { type: "TICK", identity: "29500:295", now: 100 })
stableReplacement = step(stableReplacement, { type: "TICK", identity: "29500:295", now: 200 })
const stableNext = snapshot("29600:295", 2, 7000, 7000)
stableReplacement = step(stableReplacement, { type: "REPLACE", identity: "29500:295", snapshot: stableNext }, (s, effects) => {
  assert.equal(s.active.identity, "29600:295")
  assert.equal(s.visual.incoming.identity, "29600:295")
  assert.equal(s.countdown.identity, "29600:295")
  assert.equal(s.countdown.duration, 1000)
  assert.equal(s.countdown.remaining, 900)
  assert.equal(s.active.remainingLifetime, 900)
  assert.equal(effects.find(effect => effect.type === "persist").snapshot.remainingLifetime, 900)
})

let frozenReplacement = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
frozenReplacement = step(frozenReplacement, { type: "ARRIVE", snapshot: snapshot("29700:297", 1, 1000, 1000) })
const frozenNext = snapshot("29800:297", 1, 1000, 1000)
frozenReplacement = step(frozenReplacement, { type: "REPLACE", identity: "29700:297", snapshot: frozenNext })
frozenReplacement = step(frozenReplacement, { type: "ARRIVE", snapshot: snapshot("29900:299", 1, 1000, 1000) })
const frozenDismiss = apply(frozenReplacement, { type: "DISMISS", identity: "29800:297" })
assert.equal(frozenDismiss.state.phase, "closing")
assert.equal(frozenDismiss.state.active, null)
assert.equal(frozenDismiss.state.visual.outgoing.identity, "29700:297")
assert.deepEqual(ids(frozenDismiss.state.pending), ["29900:299"])

let malformed = openState(snapshot("30000:30", 1, 1000, 1000))
for (const badEvent of [null, {}, { type: "ARRIVE" }, { type: "ARRIVE", snapshot: {} },
  { type: "REPLACE", identity: "30000:30" }, { type: "ROUTE_CHANGED", visible: "true", output: "DP-1" },
  { type: "REPLACE", identity: "unknown", snapshot: snapshot("30001:30", 1, 1000, 1000) },
  { type: "TRANSITION_FINISHED", token: 0, kind: "", output: "" },
  { type: "ROUTE_CHANGED", visible: true, output: null },
  { type: "TRANSITION_FINISHED", token: "1", kind: "open", output: "DP-1" },
  { type: "TICK", identity: "30000:30", now: "bad" }]) {
  const before = JSON.parse(JSON.stringify(malformed))
  const badResult = apply(malformed, badEvent)
  assert.deepEqual(badResult.state, before)
  assert.deepEqual(badResult.effects, [])
}
let retiredTarget = openState(snapshot("30100:301", 1, 1000, 1000))
retiredTarget.retired["30200:302"] = true
const retiredBefore = JSON.parse(JSON.stringify(retiredTarget))
const retiredReplacement = apply(retiredTarget, { type: "REPLACE", identity: "30100:301", snapshot: snapshot("30200:302", 1, 1000, 1000) })
assert.deepEqual(retiredReplacement.state, retiredBefore)
assert.deepEqual(retiredReplacement.effects, [])

const invalidOpening = step(Presentation.createInitialState({ routeVisible: true, output: "DP-1" }), { type: "ARRIVE", snapshot: snapshot("30300:303", 1, 1000, 1000) })
const invalidOpeningKind = JSON.parse(JSON.stringify(invalidOpening)); invalidOpeningKind.visual.kind = "switch"
assert.throws(() => Presentation.assertInvariants(invalidOpeningKind), /invalid transition token/)
const invalidOpeningOutput = JSON.parse(JSON.stringify(invalidOpening)); invalidOpeningOutput.visual.output = "DP-2"
assert.throws(() => Presentation.assertInvariants(invalidOpeningOutput), /invalid transition token/)
const invalidClosed = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
invalidClosed.visual.token = 2
assert.throws(() => Presentation.assertInvariants(invalidClosed), /stable transition metadata/)
const invalidOpen = openState(snapshot("30400:304", 1, 1000, 1000))
invalidOpen.visual.token = 2
invalidOpen.visual.output = "DP-1"
assert.throws(() => Presentation.assertInvariants(invalidOpen), /stable transition metadata/)
const invalidOpenCard = openState(snapshot("30500:305", 1, 1000, 1000))
invalidOpenCard.visual.outgoing = snapshot("30600:306", 1, 1000, 1000)
assert.throws(() => Presentation.assertInvariants(invalidOpenCard), /open identity mismatch/)
const invalidSwitch = openState(snapshot("30700:307", 1, 1000, 1000))
const invalidSwitchResult = apply(invalidSwitch, { type: "ARRIVE", snapshot: snapshot("30800:308", 2, 0, 0) })
invalidSwitchResult.state.visual.kind = "close"
assert.throws(() => Presentation.assertInvariants(invalidSwitchResult.state), /invalid transition token/)
const invalidClosing = openState(snapshot("30900:309", 1, 1000, 1000))
const invalidClosingResult = apply(invalidClosing, { type: "DISMISS", identity: "30900:309" })
invalidClosingResult.state.visual.incoming = snapshot("31000:310", 1, 1000, 1000)
assert.throws(() => Presentation.assertInvariants(invalidClosingResult.state), /invalid closing cards/)
const source = require("node:fs").readFileSync(require.resolve("../plugins/notifications/NotificationPresentation.js"), "utf8")
assert.equal(source.includes("findIndex"), false)
assert.equal(source.includes("Number.isFinite"), false)
console.log("notification-presentation-test: immutable snapshot reducer, transitions, routing, timers, dismissal, replacement, and invariants verified")
