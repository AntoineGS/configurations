"use strict"

/* Pure, transport-independent notification presentation state machine. */
var WATCHDOG_TIMEOUT = 510

function copy(value) {
  if (value === null || typeof value !== "object") return value
  if (Array.isArray(value)) return value.map(copy)
  var result = {}
  Object.keys(value).forEach(function (key) { result[key] = copy(value[key]) })
  return result
}

function identityOf(row) { return row && row.identity ? row.identity : "" }
function critical(row) { return !!row && (row.queuePriority === true || row.urgency === 2) }
function deck(rows) {
  return { snapshots: rows.map(copy), queuedCount: rows.length, criticalPending: rows.some(critical) }
}
function emptyDeck() { return deck([]) }
function createSnapshot(row, duration) {
  var result = copy(row || {})
  if (!result.identity && result.timestamp !== undefined && result.originalId !== undefined) {
    result.identity = String(result.timestamp) + ":" + String(result.originalId)
  }
  result.actions = Array.isArray(result.actions) ? result.actions.map(copy) : []
  if (duration !== undefined && result.duration === undefined) result.duration = duration
  return result
}
function createInitialState(options) {
  options = options || {}
  return {
    version: 1, phase: "closed",
    route: { visible: options.routeVisible !== false, output: options.output || "" },
    active: null, pending: [],
    visual: { outgoing: null, incoming: null, outgoingDeck: emptyDeck(), incomingDeck: emptyDeck(),
      token: 0, kind: "", output: "" },
    hovered: false, deferredCritical: false,
    countdown: { identity: "", duration: 0, remaining: 0, fraction: 1, visible: false, lastNow: 0 },
    retired: {}, nextToken: 1,
  }
}
function matching(state, event) {
  return state.visual.token === event.token && state.visual.kind === event.kind && state.visual.output === event.output
}
function withTransition(state, phase, outgoing, incoming, kind) {
  var token = state.nextToken
  state.nextToken += 1
  state.phase = phase
  state.visual = { outgoing: outgoing ? copy(outgoing) : null, incoming: incoming ? copy(incoming) : null,
    outgoingDeck: deck(state.pending), incomingDeck: deck(state.pending), token: token, kind: kind,
    output: state.route.output || "" }
  state.countdown.visible = false
  return token
}
function startCountdown(state, row) {
  var duration = Number(row.duration || 0)
  var remaining = Number(row.remainingLifetime || 0)
  state.countdown = { identity: identityOf(row), duration: duration, remaining: remaining,
    fraction: duration > 0 ? Math.max(0, Math.min(1, remaining / duration)) : 1,
    visible: duration > 0 && !critical(row), lastNow: 0 }
}
function sortPending(rows) {
  return rows.slice().sort(function (a, b) {
    if (critical(a) !== critical(b)) return critical(a) ? -1 : 1
    return Number(a.queueOrder || a.timestamp || 0) - Number(b.queueOrder || b.timestamp || 0)
  })
}
function addPending(state, row) {
  var identity = identityOf(row)
  if (!identity || state.retired[identity] || identityOf(state.active) === identity) return
  var existing = state.pending.findIndex(function (item) { return identityOf(item) === identity })
  if (existing >= 0) state.pending[existing] = copy(row)
  else state.pending.push(copy(row))
  state.pending = sortPending(state.pending)
}
function effectsFor(row, effects) {
  if (row && row.transient !== true) effects.push({ type: "persist", snapshot: copy(row), identity: identityOf(row) })
}
function reconcileIncoming(state) {
  if (state.active && state.visual.incoming && identityOf(state.active) !== identityOf(state.visual.incoming)) {
    state.visual.incoming = copy(state.active)
  }
}
function finish(state, event) {
  if (!matching(state, event)) return
  if (state.phase === "opening" || state.phase === "switching") {
    reconcileIncoming(state)
    state.visual.outgoing = null
    state.visual.incoming = state.active ? copy(state.active) : null
    state.visual.kind = ""
    state.phase = state.active ? "open" : "closed"
    state.visual.outgoingDeck = emptyDeck(); state.visual.incomingDeck = deck(state.pending)
    if (state.active) startCountdown(state, state.active)
  } else if (state.phase === "closing") {
    state.visual = { outgoing: null, incoming: null, outgoingDeck: emptyDeck(), incomingDeck: emptyDeck(),
      token: 0, kind: "", output: "" }
    state.phase = state.route.visible && state.active ? "opening" : (state.route.visible ? "closed" : "hidden")
    if (state.phase === "opening") withTransition(state, "opening", null, state.active, "open")
  }
}
function reduce(input, event) {
  var state = copy(input || createInitialState())
  var effects = []
  if (!event || typeof event.type !== "string") return { state: state, effects: effects }
  var row, identity, index, token
  switch (event.type) {
    case "ARRIVE":
      if (!event.snapshot) break
      row = createSnapshot(event.snapshot)
      identity = identityOf(row)
      if (!identity || state.retired[identity]) break
      effectsFor(row, effects)
      if (!state.route.visible || state.phase === "hidden") { addPending(state, row); break }
      if (!state.active) {
        state.active = copy(row); token = withTransition(state, "opening", null, row, "open")
        effects.push({ type: "startWatchdog", token: token, kind: "open", output: state.route.output || "", timeout: WATCHDOG_TIMEOUT })
      } else if (state.phase === "open" && critical(row) && !state.hovered) {
        state.pending.unshift(copy(state.active)); state.pending = sortPending(state.pending)
        state.active = copy(row); withTransition(state, "switching", state.visual.incoming || state.active, row, "switch")
      } else if (state.phase === "open" && critical(row)) { addPending(state, row); state.deferredCritical = true }
      else addPending(state, row)
      break
    case "REPLACE":
      row = event.snapshot && createSnapshot(event.snapshot)
      identity = event.identity || identityOf(row)
      if (!row || !identity || state.retired[identity]) break
      row.identity = identity
      if (identityOf(state.active) === identity) {
        state.active = copy(row)
        if (state.phase === "open") state.visual.incoming = copy(row)
      } else {
        index = state.pending.findIndex(function (item) { return identityOf(item) === identity })
        if (index >= 0) { state.pending[index] = copy(row); state.pending = sortPending(state.pending) }
      }
      effectsFor(row, effects); break
    case "DISMISS":
      identity = event.identity
      if (!state.active || identity !== identityOf(state.active) || state.retired[identity]) break
      state.retired[identity] = true; effects.push({ type: "senderDismiss", identity: identity, snapshot: copy(state.active) })
      state.countdown.visible = false; row = state.pending.shift() || null; state.active = row
      if (row) withTransition(state, "switching", state.visual.incoming, row, "switch")
      else withTransition(state, "closing", state.visual.incoming, null, "close")
      break
    case "DISMISS_ALL":
      if (state.active) effects.push({ type: "senderDismiss", identity: identityOf(state.active), snapshot: copy(state.active) })
      state.pending.forEach(function (item) { state.retired[identityOf(item)] = true })
      if (state.active) state.retired[identityOf(state.active)] = true
      state.active = null; state.pending = []; state.countdown.visible = false
      if (state.visual.incoming || state.visual.outgoing) withTransition(state, "closing", state.visual.incoming || state.visual.outgoing, null, "close")
      else state.phase = state.route.visible ? "closed" : "hidden"
      break
    case "HOVER_CHANGED":
      state.hovered = event.hovered === true
      if (!state.hovered && state.deferredCritical && state.phase === "open") {
        state.deferredCritical = false; row = state.pending.shift()
        if (row) { state.pending.unshift(copy(state.active)); state.active = row; withTransition(state, "switching", state.visual.incoming, row, "switch") }
      }
      break
    case "ROUTE_CHANGED":
      state.route = { visible: event.visible === true, output: event.output || "" }
      if (!state.route.visible) { state.phase = "hidden"; state.visual = { outgoing: null, incoming: null, outgoingDeck: emptyDeck(), incomingDeck: emptyDeck(), token: 0, kind: "", output: "" }; state.countdown.visible = false }
      else if (state.active && (state.phase === "hidden" || state.visual.output !== state.route.output)) withTransition(state, "opening", null, state.active, "open")
      break
    case "TRANSITION_FINISHED":
    case "TRANSITION_TIMED_OUT":
      finish(state, event); break
    case "TICK":
      if (state.phase === "open" && state.countdown.visible && Number.isFinite(event.now) && state.countdown.lastNow) {
        var delta = Math.max(0, event.now - state.countdown.lastNow)
        state.countdown.remaining = Math.max(0, state.countdown.remaining - delta)
        state.countdown.fraction = state.countdown.duration ? state.countdown.remaining / state.countdown.duration : 1
        if (state.countdown.remaining === 0) { effects.push({ type: "senderExpire", identity: state.countdown.identity, snapshot: copy(state.active) }); state.retired[state.countdown.identity] = true; state.active = null; state.phase = "closed"; state.countdown.visible = false }
      }
      if (Number.isFinite(event.now)) state.countdown.lastNow = event.now
      break
    case "SENDER_CLOSED":
      if (event.identity && state.retired[event.identity]) break
      if (state.active && identityOf(state.active) === event.identity) state.active = null
      break
  }
  return { state: state, effects: effects }
}
function presentationFrame(state) {
  return { phase: state.phase, active: state.active ? copy(state.active) : null, pending: state.pending.map(copy),
    visual: copy(state.visual), countdown: copy(state.countdown), route: copy(state.route), hovered: state.hovered }
}
function assertInvariants(state) {
  var seen = {}
  state.pending.forEach(function (row) { if (seen[identityOf(row)] || identityOf(row) === identityOf(state.active) || state.retired[identityOf(row)]) throw new Error("invalid pending identity"); seen[identityOf(row)] = true })
  if (state.active && state.retired[identityOf(state.active)]) throw new Error("retired active")
  var transient = state.phase === "opening" || state.phase === "switching" || state.phase === "closing"
  if (transient && !state.visual.token) throw new Error("transient phase without token")
  if (!transient && state.phase !== "hidden" && state.visual.kind) throw new Error("stable phase has transition kind")
  if (state.phase === "open" && (!state.active || !state.visual.incoming || identityOf(state.active) !== identityOf(state.visual.incoming) || (state.countdown.visible && state.countdown.identity !== identityOf(state.active)))) throw new Error("open identity mismatch")
  if (!state.visual.outgoing && !state.visual.incoming && (state.visual.outgoingDeck.snapshots.length || state.visual.incomingDeck.snapshots.length)) throw new Error("orphan deck")
  if (state.countdown.visible && state.phase !== "open") throw new Error("countdown outside open")
  return true
}

if (typeof module !== "undefined") module.exports = { createInitialState: createInitialState, createSnapshot: createSnapshot, reduce: reduce, presentationFrame: presentationFrame, assertInvariants: assertInvariants }
