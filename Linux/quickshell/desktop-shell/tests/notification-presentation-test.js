const assert = require("node:assert/strict")
const Presentation = require("../plugins/notifications/NotificationPresentation.js")
const logic = require("../plugins/notifications/NotificationLogic.js")

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
  }, hovered: false,
  countdown: { identity: "", duration: 0, remaining: 0, fraction: 1, visible: false, lastNow: 0 },
  retired: {}, retiredOrder: [], closing: {}, nextToken: 1,
})
const normalA = snapshot("1000:1", 1, 10000, 10000)
const normalB = snapshot("2000:2", 1, 10000, 10000)
const criticalC = snapshot("3000:3", 2, 0, 0)
const originalState = JSON.parse(JSON.stringify(state))
assert.equal(Presentation.createSnapshot({ identity: "1:1", originalId: 1, timestamp: 1 }, 1234).duration, 1234)
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
  assert.deepEqual(ids(s.visual.incomingDeck.snapshots), ["2000:2"])
  assert.equal(s.visual.incomingDeck.queuedCount, 1)
})
state = step(state, { type: "HOVER_CHANGED", hovered: true }, s => assert.equal(s.hovered, true))
state = step(state, { type: "ARRIVE", snapshot: criticalC }, s => {
  assert.equal(s.phase, "open")
  assert.deepEqual(ids(s.visual.incomingDeck.snapshots), ["3000:3", "2000:2"])
  assert.equal(s.visual.incomingDeck.criticalPending, true)
})
state = step(state, { type: "HOVER_CHANGED", hovered: false }, s => {
  assert.equal(s.phase, "switching")
  assert.equal(s.active.identity, "3000:3")
  assert.deepEqual(ids(s.pending), ["1000:1", "2000:2"])
  assert.equal(s.visual.outgoing.identity, "1000:1")
  assert.equal(s.visual.incoming.identity, "3000:3")
  assert.deepEqual(ids(s.visual.outgoingDeck.snapshots), ["3000:3", "2000:2"])
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

let hidden = Presentation.createInitialState({ routeVisible: false, output: "" })
hidden = step(hidden, { type: "ARRIVE", snapshot: snapshot("10001:100", 1, 1000, 1000) }, s => {
  assert.equal(s.active, null)
  assert.deepEqual(ids(s.pending), ["10001:100"])
})
hidden = step(hidden, { type: "ROUTE_CHANGED", visible: true, output: "DP-3" }, s => {
  assert.equal(s.phase, "opening")
  assert.equal(s.active.identity, "10001:100")
  assert.equal(s.visual.incoming.identity, "10001:100")
})

let pendingClose = openState(snapshot("10002:102", 2, 0, 0))
pendingClose = step(pendingClose, { type: "ARRIVE", snapshot: snapshot("10003:103", 1, 1000, 1000) })
const pendingCloseResult = apply(pendingClose, { type: "SENDER_CLOSED", identity: "10003:103" })
assert.deepEqual(ids(pendingCloseResult.state.pending), [])
assert.equal(pendingCloseResult.state.retired["10003:103"], true)
assert.ok(pendingCloseResult.effects.some(effect => effect.type === "cleanup" && effect.identity === "10003:103"))
const pendingDismissResult = apply(pendingClose, { type: "DISMISS", identity: "10003:103" })
assert.deepEqual(pendingDismissResult.effects.map(effect => effect.type), ["senderDismiss", "cleanup", "archive"])
assert.equal(pendingDismissResult.effects[0].reason, "dismiss")
assert.equal(pendingDismissResult.effects[1].snapshot.identity, "10003:103")

const sameRoute = openState(snapshot("10004:104", 1, 1000, 1000))
const sameRouteResult = apply(sameRoute, { type: "ROUTE_CHANGED", visible: true, output: "DP-1" })
assert.deepEqual(sameRouteResult.state, sameRoute)
assert.deepEqual(sameRouteResult.effects, [])

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
const deterministicDismissAll = openState(snapshot("12001:12", 1, 1000, 1000))
const dismissAllAtTime = apply(deterministicDismissAll, { type: "DISMISS_ALL", now: 5000 })
const dismissAllAtTimeAgain = apply(deterministicDismissAll, { type: "DISMISS_ALL", now: 5000 })
assert.deepEqual(dismissAllAtTime.state, dismissAllAtTimeAgain.state, "dismiss-all reducer state is deterministic from event time")
assert.equal(dismissAllAtTime.state.closing["12"].expiresAt, 15000)
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
assert.equal(closeResult.effects.filter(effect => effect.type === "archive").length, 1)
assert.equal(closeResult.effects.find(effect => effect.type === "archive").reason, "dismiss")

let closing = openState(snapshot("15000:15", 1, 1000, 1000))
let closingResult = apply(closing, { type: "DISMISS", identity: "15000:15" })
assert.equal(closingResult.state.phase, "closing")
const frozenClose = JSON.parse(JSON.stringify(closingResult.state.visual))
closingResult = apply(closingResult.state, { type: "ARRIVE", snapshot: snapshot("16000:16", 1, 1000, 1000) })
assert.equal(closingResult.state.visual.outgoing.identity, frozenClose.outgoing.identity)
assert.deepEqual(closingResult.state.visual.outgoingDeck, frozenClose.outgoingDeck)
assert.deepEqual(ids(closingResult.state.visual.incomingDeck.snapshots), ["16000:16"])
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
assert.equal(activeClose.effects.some(effect => effect.type === "senderDismiss"), false,
  "sender close does not redundantly dismiss an already-closed sender")

let priority = openState(snapshot("20000:20", 2, 0, 0))
priority = step(priority, { type: "ARRIVE", snapshot: snapshot("21000:21", 2, 0, 0) }, s => {
  assert.equal(s.phase, "open")
  assert.deepEqual(ids(s.pending), ["21000:21"])
})
priority = step(priority, { type: "ARRIVE", snapshot: snapshot("22000:22", 1, 1000, 1000) })
priority = step(priority, { type: "HOVER_CHANGED", hovered: true })
priority = step(priority, { type: "ARRIVE", snapshot: snapshot("23000:23", 2, 0, 0) })
priority = step(priority, { type: "HOVER_CHANGED", hovered: false }, s => assert.deepEqual(ids(s.pending), ["21000:21", "23000:23", "22000:22"]))

let hoveredDismissal = openState(snapshot("22000:220", 1, 1000, 1000))
hoveredDismissal = step(hoveredDismissal, { type: "ARRIVE", snapshot: snapshot("22100:221", 1, 1000, 1000) })
hoveredDismissal = step(hoveredDismissal, { type: "HOVER_CHANGED", hovered: true })
hoveredDismissal = step(hoveredDismissal, { type: "DISMISS", identity: "22000:220" }, s => {
  assert.equal(s.phase, "switching")
  assert.equal(s.hovered, false)
})
hoveredDismissal = step(hoveredDismissal, {
  type: "TRANSITION_FINISHED", token: hoveredDismissal.visual.token,
  kind: "switch", output: hoveredDismissal.visual.output,
})
assert.equal(hoveredDismissal.hovered, false)
hoveredDismissal = step(hoveredDismissal, { type: "TICK", identity: "22100:221", now: 100 })
const resumedTick = apply(hoveredDismissal, { type: "TICK", identity: "22100:221", now: 200 })
assert.equal(resumedTick.state.countdown.remaining, 900, "next card timer resumes after hovered card dismissal")

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
  assert.deepEqual(ids(s.visual.incomingDeck.snapshots), ["28000:28", "29000:27"])
  assert.equal(s.pending[1].queueOrder, 27000)
  assert.equal(s.pending[1].queuePriority, false)
})

let pendingRemoval = openState(snapshot("26000:30", 2, 0, 0))
pendingRemoval = step(pendingRemoval, { type: "ARRIVE", snapshot: snapshot("27000:30", 1, 1000, 1000) })
pendingRemoval = step(pendingRemoval, { type: "ARRIVE", snapshot: snapshot("28000:30", 1, 1000, 1000) })
pendingRemoval = step(pendingRemoval, { type: "DISMISS", identity: "27000:30" }, s => {
  assert.deepEqual(ids(s.pending), ["28000:30"])
  assert.deepEqual(ids(s.visual.incomingDeck.snapshots), ["28000:30"])
})
pendingRemoval = step(pendingRemoval, { type: "SENDER_CLOSED", identity: "28000:30" }, s => {
  assert.deepEqual(s.pending, [])
  assert.deepEqual(s.visual.incomingDeck.snapshots, [])
})

let allDeck = openState(snapshot("26000:40", 1, 1000, 1000))
allDeck = step(allDeck, { type: "HOVER_CHANGED", hovered: true })
allDeck = step(allDeck, { type: "ARRIVE", snapshot: snapshot("27000:40", 2, 0, 0) })
const allDeckResult = apply(allDeck, { type: "DISMISS_ALL" })
assert.deepEqual(ids(allDeckResult.state.visual.outgoingDeck.snapshots), ["27000:40"])
assert.equal(allDeckResult.state.visual.outgoingDeck.criticalPending, true)

let urgencyReplacement = openState(Object.assign(snapshot("26000:50", 2, 0, 0), { queuePriority: true }))
const normalReplacement = Object.assign(snapshot("27000:50", 1, 1000, 1000), { queuePriority: true })
urgencyReplacement = step(urgencyReplacement, { type: "REPLACE", identity: "26000:50", snapshot: normalReplacement })
assert.equal(urgencyReplacement.countdown.visible, true, "critical queue priority does not suppress a normal active countdown")
urgencyReplacement = step(urgencyReplacement, { type: "TICK", identity: "27000:50", now: 1 })
const urgencyExpiry = apply(urgencyReplacement, { type: "TICK", identity: "27000:50", now: 1001 })
assert.equal(urgencyExpiry.state.phase, "closing", "normal replacement remains expiring")

let promotedReplacement = openState(snapshot("26000:60", 2, 0, 0))
const retainedNormal = snapshot("27000:60", 1, 1000, 1000)
const laterNormal = snapshot("28000:60", 1, 1000, 1000)
promotedReplacement = step(promotedReplacement, { type: "ARRIVE", snapshot: retainedNormal })
promotedReplacement = step(promotedReplacement, { type: "ARRIVE", snapshot: laterNormal })
const retainedCritical = Object.assign(snapshot("29000:60", 2, 0, 0), { queuePriority: false })
promotedReplacement = step(promotedReplacement, { type: "REPLACE", identity: "27000:60", snapshot: retainedCritical }, s => {
  assert.deepEqual(ids(s.pending), ["29000:60", "28000:60"], "replacement retains documented queue position")
  assert.equal(s.pending[0].queuePriority, false, "replacement retains documented queue priority")
})
promotedReplacement = step(promotedReplacement, { type: "DISMISS", identity: "26000:60" })
promotedReplacement = step(promotedReplacement, {
  type: "TRANSITION_FINISHED", token: promotedReplacement.visual.token,
  kind: "switch", output: "DP-1",
})
assert.equal(promotedReplacement.active.identity, "29000:60")
assert.equal(promotedReplacement.countdown.visible, false, "promoted critical urgency is non-expiring")

let urgentPendingReplacement = openState(snapshot("26000:70", 1, 1000, 1000))
const queuedNormal = Object.assign(snapshot("27000:70", 1, 1000, 1000), { queuePriority: false, queueOrder: 7 })
urgentPendingReplacement = step(urgentPendingReplacement, { type: "ARRIVE", snapshot: queuedNormal })
const queuedCritical = Object.assign(snapshot("28000:70", 2, 0, 0), { queuePriority: false, queueOrder: 999 })
urgentPendingReplacement = step(urgentPendingReplacement, { type: "REPLACE", identity: "27000:70", snapshot: queuedCritical }, s => {
  assert.equal(s.phase, "switching", "normal-to-critical pending replacement preempts when unhovered")
  assert.equal(s.active.identity, "28000:70")
  assert.equal(s.visual.outgoing.identity, "26000:70")
  assert.equal(s.visual.incoming.identity, "28000:70")
  assert.deepEqual(ids(s.visual.outgoingDeck.snapshots), ["28000:70"])
  assert.deepEqual(ids(s.visual.incomingDeck.snapshots), ["26000:70"])
  assert.equal(s.visual.outgoingDeck.criticalPending, true)
  assert.equal(s.countdown.visible, false)
  assert.equal(s.active.queueOrder, 7, "replacement preserves queue order")
  assert.equal(s.active.queuePriority, false, "replacement preserves queue priority")
})

let hoveredPendingReplacement = openState(snapshot("26000:71", 1, 1000, 1000))
hoveredPendingReplacement = step(hoveredPendingReplacement, { type: "HOVER_CHANGED", hovered: true })
hoveredPendingReplacement = step(hoveredPendingReplacement, { type: "ARRIVE", snapshot: Object.assign(snapshot("27000:71", 1, 1000, 1000), { queuePriority: false, queueOrder: 7 }) })
hoveredPendingReplacement = step(hoveredPendingReplacement, { type: "REPLACE", identity: "27000:71", snapshot: Object.assign(snapshot("28000:71", 2, 0, 0), { queuePriority: false, queueOrder: 99 }) }, s => {
  assert.equal(s.phase, "open")
  assert.equal(s.active.identity, "26000:71")
  assert.deepEqual(ids(s.pending), ["28000:71"])
  assert.equal(s.visual.incomingDeck.criticalPending, true)
  assert.equal(s.countdown.visible, true)
})
hoveredPendingReplacement = step(hoveredPendingReplacement, { type: "HOVER_CHANGED", hovered: false }, s => {
  assert.equal(s.phase, "switching")
  assert.equal(s.active.identity, "28000:71")
  assert.deepEqual(ids(s.visual.outgoingDeck.snapshots), ["28000:71"])
  assert.equal(s.visual.outgoingDeck.criticalPending, true)
  assert.equal(s.countdown.visible, false)
})

let normalPendingReplacement = openState(snapshot("26000:72", 1, 1000, 1000))
normalPendingReplacement = step(normalPendingReplacement, { type: "HOVER_CHANGED", hovered: true })
normalPendingReplacement = step(normalPendingReplacement, { type: "ARRIVE", snapshot: Object.assign(snapshot("27000:72", 2, 0, 0), { queuePriority: true, queueOrder: 7 }) })
normalPendingReplacement = step(normalPendingReplacement, { type: "REPLACE", identity: "27000:72", snapshot: Object.assign(snapshot("28000:72", 1, 1000, 1000), { queuePriority: false, queueOrder: 999 }) }, s => {
  assert.equal(s.phase, "open", "critical-to-normal pending replacement does not preempt")
  assert.equal(s.active.identity, "26000:72")
  assert.deepEqual(ids(s.pending), ["28000:72"])
  assert.equal(s.visual.incomingDeck.criticalPending, false)
  assert.equal(s.countdown.visible, true)
})

const allSenderDismiss = allResult.effects.filter(effect => effect.type === "senderDismiss")
assert.deepEqual(allSenderDismiss.map(effect => effect.identity), ["24000:24", "25000:25", "25000:26"])

let sourceAware = openState(snapshot("25000:250", 1, 1000, 1000))
const sourceAwareDismiss = apply(sourceAware, { type: "SENDER_CLOSED", identity: "25000:250" })
assert.deepEqual(sourceAwareDismiss.effects, [
  { type: "cleanup", identity: "25000:250", snapshot: sourceAware.active, reason: "closed" },
  { type: "startWatchdog", token: 2, kind: "close", output: "DP-1", timeout: 470 },
], "active sender close has the exact cleanup/watchdog lifecycle and closed reason")
const internal = openState(snapshot("-1:-1", 1, 1000, 1000))
const internalDismiss = apply(internal, { type: "DISMISS", identity: "-1:-1" })
assert.equal(internalDismiss.effects.some(effect => effect.type === "archive"), false)
assert.equal(internalDismiss.effects.some(effect => effect.type === "senderDismiss"), false)
assert.equal(apply(Presentation.createInitialState({ routeVisible: true, output: "DP-1" }), {
  type: "ARRIVE", snapshot: Object.assign(snapshot("-2:-2", 1, 1000, 1000), { presentationSource: "none" })
}).effects.some(effect => effect.type === "persist"), false)

let transient = openState(Object.assign(snapshot("25001:251", 1, 1000, 1000), { transient: true }))
const transientDismiss = apply(transient, { type: "DISMISS", identity: "25001:251" })
assert.equal(transientDismiss.effects.some(effect => effect.type === "archive"), false)
const expired = apply(openState(snapshot("25001:252", 1, 1000, 1000)), { type: "DISMISS", identity: "25001:252", reason: "expire" })
assert.deepEqual(expired.effects.map(effect => effect.type), ["senderExpire", "cleanup", "archive", "startWatchdog"])
assert.equal(expired.effects[0].reason, "expire")

const historyRestored = openState(Object.assign(snapshot("25001:253", 1, 1000, 1000), { presentationSource: "history" }))
assert.equal(apply(Presentation.createInitialState({ routeVisible: true, output: "DP-1" }), {
  type: "ARRIVE", snapshot: Object.assign(snapshot("25001:254", 1, 1000, 1000), { presentationSource: "history" })
}).effects.some(effect => effect.type === "persist"), false)
const historyRemoval = apply(historyRestored, { type: "DISMISS", identity: "25001:253" })
assert.equal(historyRemoval.effects.find(effect => effect.type === "archive").snapshot.presentationSource, "history")
assert.equal(historyRemoval.effects[0].snapshot.identity, "25001:253")

let replacementCleanup = openState(snapshot("25002:252", 1, 1000, 1000))
const replacementResult = apply(replacementCleanup, {
  type: "REPLACE", identity: "25002:252", snapshot: snapshot("25003:252", 1, 1000, 1000)
})
assert.deepEqual(replacementResult.effects.map(effect => effect.type), ["cleanup", "persist"])
assert.ok(replacementResult.effects.some(effect => effect.type === "cleanup" && effect.identity === "25002:252" && effect.reason === "replace"))
assert.equal(replacementResult.state.retired["25002:252"], true)
assert.equal(replacementResult.state.active.identity, "25003:252")

let switchCallback = openState(snapshot("25004:254", 1, 1000, 1000))
switchCallback = step(switchCallback, { type: "ARRIVE", snapshot: snapshot("25005:255", 2, 0, 0) })
const switchCallbackToken = switchCallback.visual.token
const switchCallbackResult = apply(switchCallback, {
  type: "TRANSITION_FINISHED", token: switchCallbackToken, kind: "switch", output: "DP-1"
})
assert.equal(switchCallbackResult.state.phase, "open")

let stableReplacement = openState(snapshot("29500:295", 1, 1000, 1000))
stableReplacement = step(stableReplacement, { type: "TICK", identity: "29500:295", now: 100 })
stableReplacement = step(stableReplacement, { type: "TICK", identity: "29500:295", now: 200 })
const stableNext = snapshot("29600:295", 2, 7000, 7000)
stableReplacement = step(stableReplacement, { type: "REPLACE", identity: "29500:295", snapshot: stableNext }, (s, effects) => {
  assert.equal(s.active.identity, "29600:295")
  assert.equal(s.visual.incoming.identity, "29600:295")
  assert.equal(s.countdown.identity, "29600:295")
  assert.equal(s.countdown.duration, 7000)
  assert.equal(s.countdown.remaining, 7000)
  assert.equal(s.active.remainingLifetime, 7000)
  assert.equal(effects.find(effect => effect.type === "persist").snapshot.remainingLifetime, 7000)
})

let openingDismissal = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
openingDismissal = step(openingDismissal, { type: "ARRIVE", snapshot: snapshot("31000:310", 1, 1000, 1000) })
openingDismissal = step(openingDismissal, { type: "ARRIVE", snapshot: snapshot("31100:311", 1, 1000, 1000) })
openingDismissal = step(openingDismissal, { type: "DISMISS", identity: "31000:310" }, s => {
  assert.equal(s.phase, "switching")
  assert.equal(s.active.identity, "31100:311")
  assert.equal(s.visual.outgoing.identity, "31000:310")
  assert.equal(s.visual.incoming.identity, "31100:311")
})

let tombstone = openState(snapshot("31200:312", 1, 1000, 1000))
tombstone = step(tombstone, { type: "DISMISS", identity: "31200:312", now: 0 })
const lateReplacement = apply(tombstone, {
  type: "REPLACE", identity: "31200:312", snapshot: snapshot("31300:312", 1, 1000, 1000), now: 100
})
assert.equal(lateReplacement.state.phase, "closing")
assert.equal(lateReplacement.state.active, null)
assert.ok(lateReplacement.effects.some(effect => effect.type === "release" && effect.identity === "31300:312"))
const senderClose = apply(lateReplacement.state, { type: "SENDER_CLOSED", identity: "31200:312", now: 101 })
assert.equal(senderClose.state.closing["312"], undefined)
const expiredTombstone = apply(lateReplacement.state, { type: "PRUNE", now: 100 + 10000 })
assert.equal(expiredTombstone.state.closing["312"], undefined)
let failedActionPresenter = openState(snapshot("31400:314", 1, 1000, 1000))
const failedSender = {}
let failedGuard = logic.actionCloseTransition(logic.actionCloseInitialState(),
  logic.actionCloseBeginEvent(314, failedSender, 31400, "31400:314")).state
failedGuard = logic.actionCloseTransition(failedGuard, { type: "close", originalId: 314, notification: failedSender, generation: 31400 }).state
const failedCompletion = logic.actionCloseTransition(failedGuard, {
  type: "complete", originalId: 314, notification: failedSender, generation: 31400, success: false,
})
assert.equal(failedCompletion.flush, true)
assert.equal(failedCompletion.state.guards["314"].identity, "31400:314")
const failedClose = apply(failedActionPresenter, {
  type: "SENDER_CLOSED", identity: failedCompletion.state.guards["314"].identity, now: 31401,
})
assert.equal(failedClose.state.active, null, "failed synchronous close removes the active presenter entry")
assert.equal(failedClose.state.visual.outgoing.identity, "31400:314")
const senderClosedReuse = apply(lateReplacement.state, { type: "SENDER_CLOSED", identity: "31200:312", now: 101 })
const reused = apply(senderClosedReuse.state, { type: "ARRIVE", snapshot: snapshot("31400:312", 1, 1000, 1000) })
assert.deepEqual(ids(reused.state.pending), ["31400:312"], "sender close permits immediate original-ID reuse")

assert.deepEqual(logic.deckProjection("opening", 0, true), { outgoing: 0, incoming: 0 })
assert.deepEqual(logic.deckProjection("opening", 0.5, true), { outgoing: 0, incoming: 0.5 })
assert.deepEqual(logic.deckProjection("closing", 0.5, false), { outgoing: 0.5, incoming: 0 })
assert.deepEqual(logic.deckProjection("switching", 1, false), { outgoing: 1, incoming: 0 })
assert.deepEqual(logic.deckProjection("switching", 0.5, false), { outgoing: 0.5, incoming: 0 })
assert.deepEqual(logic.deckProjection("switching", 0, false), { outgoing: 0, incoming: 0 })
assert.deepEqual(logic.deckProjection("switching", 0, true), { outgoing: 0, incoming: 0 })
assert.deepEqual(logic.deckProjection("switching", 0.5, true), { outgoing: 0, incoming: 0.5 })
assert.deepEqual(logic.deckProjection("switching", 1, true), { outgoing: 0, incoming: 1 })

let frozenReplacement = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
frozenReplacement = step(frozenReplacement, { type: "ARRIVE", snapshot: snapshot("29700:297", 1, 1000, 1000) })
const frozenNext = snapshot("29800:297", 1, 1000, 1000)
frozenReplacement = step(frozenReplacement, { type: "REPLACE", identity: "29700:297", snapshot: frozenNext })
frozenReplacement = step(frozenReplacement, { type: "ARRIVE", snapshot: snapshot("29900:299", 1, 1000, 1000) })
const frozenDismiss = apply(frozenReplacement, { type: "DISMISS", identity: "29800:297" })
assert.equal(frozenDismiss.state.phase, "switching")
assert.equal(frozenDismiss.state.active.identity, "29900:299")
assert.equal(frozenDismiss.state.visual.outgoing.identity, "29700:297")
assert.deepEqual(ids(frozenDismiss.state.pending), [])

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
const invalidHidden = Presentation.createInitialState({ routeVisible: false, output: "" })
invalidHidden.phase = "hidden"
invalidHidden.visual.token = 2
invalidHidden.visual.kind = "open"
invalidHidden.visual.output = "DP-1"
assert.throws(() => Presentation.assertInvariants(invalidHidden), /stable transition metadata/)
const invalidPhase = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
invalidPhase.phase = "bogus"
assert.throws(() => Presentation.assertInvariants(invalidPhase), /invalid phase/)
const inheritedPhase = Presentation.createInitialState({ routeVisible: true, output: "DP-1" })
inheritedPhase.phase = "toString"
assert.throws(() => Presentation.assertInvariants(inheritedPhase), /invalid phase/)
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
console.log("notification-presentation-test: immutable snapshot reducer, transitions, routing, timers, dismissal, replacement, and invariants verified")
