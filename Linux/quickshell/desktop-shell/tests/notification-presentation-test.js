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
  assert.equal(s.visual.token, 1)
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
timers = step(timers, { type: "TICK", now: 10 }, s => assert.equal(s.countdown.remaining, 0))
timers = step(timers, { type: "TRANSITION_FINISHED", token: 1, kind: "open", output: "DP-1" })
timers = step(timers, { type: "TICK", now: 1 })
timers = step(timers, { type: "TICK", now: 101 }, s => assert.equal(s.countdown.remaining, 900))
const expiry = apply(timers, { type: "TICK", now: 1101 })
assert.ok(expiry.effects.some(effect => effect.type === "senderExpire" && effect.identity === "11000:11"))
assert.equal(expiry.state.phase, "closed")

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
console.log("notification-presentation-test: immutable snapshot reducer, transitions, routing, timers, dismissal, replacement, and invariants verified")
