"use strict"

var WATCHDOG = { open: 510, switch: 830, close: 470 }

function copy(value) {
  var result
  if (value === null || typeof value !== "object") return value
  if (Array.isArray(value)) return value.map(copy)
  result = {}
  Object.keys(value).forEach(function (key) { result[key] = copy(value[key]) })
  return result
}
function finite(value) { return typeof value === "number" && isFinite(value) }
function identityOf(row) { return row && typeof row.identity === "string" ? row.identity : "" }
function critical(row) { return !!row && (row.queuePriority !== undefined ? row.queuePriority === true : row.urgency === 2) }
function emptyDeck() { return { snapshots: [], queuedCount: 0, criticalPending: false } }
function makeDeck(rows) { return { snapshots: rows.map(copy), queuedCount: rows.length, criticalPending: rows.some(critical) } }
function createSnapshot(row, duration) {
  var result
  if (!row || typeof row !== "object" || Array.isArray(row)) return null
  result = copy(row)
  if (!identityOf(result) && result.timestamp !== undefined && result.originalId !== undefined) {
    result.identity = String(result.timestamp) + ":" + String(result.originalId)
  }
  if (!identityOf(result)) return null
  result.actions = Array.isArray(result.actions) ? result.actions.map(copy) : []
  if (duration !== undefined && result.duration === undefined) result.duration = duration
  return result
}
function createInitialState(options) {
  options = options || {}
  return { version: 1, phase: "closed", route: { visible: options.routeVisible !== false, output: options.output || "" },
    active: null, pending: [], visual: { outgoing: null, incoming: null, outgoingDeck: emptyDeck(), incomingDeck: emptyDeck(), token: 0, kind: "", output: "" },
    hovered: false, deferredCritical: false, countdown: { identity: "", duration: 0, remaining: 0, fraction: 1, visible: false, lastNow: 0 }, retired: {}, nextToken: 1 }
}
function isTransition(phase) { return phase === "opening" || phase === "switching" || phase === "closing" }
function validEventToken(event) { return finite(event.token) && event.token > 0 && typeof event.kind === "string" && typeof event.output === "string" }
function matching(state, event) { return validEventToken(event) && state.visual.token === event.token && state.visual.kind === event.kind && state.visual.output === event.output }
function cancel(state, effects) {
  if (isTransition(state.phase) && state.visual.token > 0) effects.push({ type: "cancelWatchdog", token: state.visual.token, kind: state.visual.kind, output: state.visual.output })
}
function transition(state, phase, outgoing, incoming, kind, effects, outgoingRows, incomingRows) {
  var token
  if (!outgoingRows) outgoingRows = outgoing ? state.pending : []
  if (!incomingRows) incomingRows = state.pending
  cancel(state, effects)
  token = state.nextToken
  state.nextToken += 1
  state.phase = phase
  state.visual = { outgoing: outgoing ? copy(outgoing) : null, incoming: incoming ? copy(incoming) : null,
    outgoingDeck: makeDeck(outgoingRows), incomingDeck: makeDeck(incomingRows), token: token, kind: kind, output: state.route.output }
  state.countdown.visible = false
  effects.push({ type: "startWatchdog", token: token, kind: kind, output: state.route.output, timeout: WATCHDOG[kind] })
  return token
}
function clearVisual(state) { state.visual = { outgoing: null, incoming: null, outgoingDeck: emptyDeck(), incomingDeck: emptyDeck(), token: 0, kind: "", output: "" } }
function insertPending(state, row) {
  var i, current, rowCritical, currentCritical, rowOrder, currentOrder
  if (!identityOf(row) || state.retired[identityOf(row)] || identityOf(state.active) === identityOf(row)) return
  for (i = 0; i < state.pending.length; i += 1) if (identityOf(state.pending[i]) === identityOf(row)) { state.pending[i] = copy(row); return }
  rowCritical = critical(row); rowOrder = row.queueOrder !== undefined ? row.queueOrder : row.timestamp
  for (i = 0; i < state.pending.length; i += 1) {
    current = state.pending[i]; currentCritical = critical(current); currentOrder = current.queueOrder !== undefined ? current.queueOrder : current.timestamp
    if ((rowCritical && !currentCritical) || (rowCritical === currentCritical && rowOrder < currentOrder)) break
  }
  state.pending.splice(i, 0, copy(row))
}
function persist(row, effects) { if (row && row.transient !== true) effects.push({ type: "persist", identity: identityOf(row), snapshot: copy(row) }) }
function archive(row, effects) { if (row) effects.push({ type: "archive", identity: identityOf(row), snapshot: copy(row) }) }
function startOpen(state, effects) { return transition(state, "opening", null, state.active, "open", effects) }
function startSwitch(state, outgoing, effects, outgoingRows, incomingRows) { return transition(state, "switching", outgoing, state.active, "switch", effects, outgoingRows, incomingRows) }
function startClose(state, outgoing, effects, outgoingRows, incomingRows) { return transition(state, "closing", outgoing, null, "close", effects, outgoingRows, incomingRows) }
function startCountdown(state) {
  var row = state.active, duration = Number(row.duration || 0), remaining = Number(row.remainingLifetime || 0)
  state.countdown = { identity: identityOf(row), duration: duration, remaining: remaining, fraction: duration > 0 ? Math.max(0, Math.min(1, remaining / duration)) : 1, visible: duration > 0 && !critical(row), lastNow: 0 }
}
function removeActive(state, effects, senderType) {
  var old = state.active, next, beforePending = state.pending.slice()
  if (!old) return
  state.retired[identityOf(old)] = true
  effects.push({ type: senderType || "senderDismiss", identity: identityOf(old), snapshot: copy(old) })
  archive(old, effects)
  state.countdown.visible = false
  next = state.pending.length ? state.pending.shift() : null
  state.active = next
  if (next) startSwitch(state, old, effects, beforePending, state.pending); else startClose(state, old, effects, beforePending, state.pending)
}
function settle(state, event, effects) {
  if (!matching(state, event)) return
  cancel(state, effects)
  if (state.phase === "closing") {
    clearVisual(state)
    if (state.route.visible && state.pending.length) { state.active = state.pending.shift(); startOpen(state, effects) }
    else state.phase = state.route.visible ? "closed" : "hidden"
    return
  }
  state.visual.outgoing = null
  state.visual.incoming = state.active ? copy(state.active) : null
  state.visual.outgoingDeck = emptyDeck(); state.visual.incomingDeck = makeDeck(state.pending); state.visual.kind = ""
  state.phase = state.active ? "open" : "closed"
  if (state.active) startCountdown(state)
  // An arrival during a transition is reconsidered at the atomic boundary.
  if (state.phase === "open" && !state.hovered && state.pending.length && critical(state.pending[0]) && !critical(state.active)) {
    state.active = state.pending.shift(); startSwitch(state, state.visual.incoming, effects)
  }
}
function validRoute(event) { return typeof event.visible === "boolean" && (event.output === null || typeof event.output === "string") }
function reduce(input, event) {
  var state = copy(input || createInitialState()), effects = [], row, oldIdentity, i, next, previous
  if (!event || typeof event.type !== "string") return { state: state, effects: effects }
  switch (event.type) {
    case "ARRIVE":
      row = createSnapshot(event.snapshot)
      if (!row || state.retired[identityOf(row)]) break
      persist(row, effects)
      if (!state.route.visible || state.phase === "hidden" || state.phase === "closing" || isTransition(state.phase)) { insertPending(state, row); break }
      if (!state.active) { state.active = copy(row); startOpen(state, effects) }
      else if (state.phase === "open" && critical(row) && !critical(state.active) && !state.hovered) {
        next = state.pending.slice(); previous = state.active; state.active = copy(row); insertPending(state, previous)
        startSwitch(state, state.visual.incoming, effects, next, state.pending)
      } else { insertPending(state, row); if (critical(row)) state.deferredCritical = state.hovered }
      break
    case "REPLACE":
      row = createSnapshot(event.snapshot); oldIdentity = event.identity
      if (!row || typeof oldIdentity !== "string" || !oldIdentity || state.retired[oldIdentity]) break
      if (identityOf(row) === oldIdentity) break
      state.retired[oldIdentity] = true
      if (identityOf(state.active) === oldIdentity) {
        state.active = copy(row)
        if (state.phase === "open") state.visual.incoming = copy(row)
        persist(row, effects)
      }
      else {
        for (i = 0; i < state.pending.length; i += 1) if (identityOf(state.pending[i]) === oldIdentity) {
          next = copy(row); next.queuePriority = state.pending[i].queuePriority; next.queueOrder = state.pending[i].queueOrder
          state.pending[i] = next; insertPending(state, state.pending.splice(i, 1)[0]); persist(row, effects); break
        }
      }
      break
    case "DISMISS":
      if (typeof event.identity !== "string" || !state.active || event.identity !== identityOf(state.active)) break
      removeActive(state, effects); break
    case "DISMISS_ALL":
      row = state.active ? copy(state.active) : null
      if (row) { state.retired[identityOf(row)] = true; effects.push({ type: "senderDismiss", identity: identityOf(row), snapshot: copy(row) }) }
      if (row) archive(row, effects)
      state.pending.forEach(function (item) { state.retired[identityOf(item)] = true; archive(item, effects) })
      state.active = null; state.pending = []; state.countdown.visible = false
      if (state.visual.incoming || state.visual.outgoing) startClose(state, state.visual.incoming || state.visual.outgoing, effects)
      else state.phase = state.route.visible ? "closed" : "hidden"
      break
    case "HOVER_CHANGED":
      if (typeof event.hovered !== "boolean") break
      state.hovered = event.hovered
      if (!state.hovered && state.phase === "open" && state.pending.length && critical(state.pending[0]) && !critical(state.active)) {
        next = state.active
        state.active = state.pending.shift()
        insertPending(state, next)
        startSwitch(state, state.visual.incoming, effects, state.pending.filter(function (item) { return identityOf(item) !== identityOf(next) }), state.pending)
      }
      break
    case "ROUTE_CHANGED":
      if (!validRoute(event)) break
      if (!event.visible) { cancel(state, effects); state.route = { visible: false, output: "" }; clearVisual(state); state.phase = "hidden"; state.countdown.visible = false }
      else {
        state.route = { visible: true, output: event.output || "" }
        if (state.active && (state.phase === "hidden" || state.visual.output !== state.route.output)) startOpen(state, effects)
      }
      break
    case "TRANSITION_FINISHED":
    case "TRANSITION_TIMED_OUT":
      settle(state, event, effects); break
    case "TICK":
      if (typeof event.identity !== "string" || !finite(event.now) || state.phase !== "open" || !state.active ||
        identityOf(state.active) !== event.identity || state.countdown.identity !== event.identity || !state.visual.incoming || identityOf(state.visual.incoming) !== event.identity || !state.countdown.visible) break
      if (state.hovered) { state.countdown.lastNow = event.now; break }
      if (state.countdown.lastNow !== 0) state.countdown.remaining = Math.max(0, state.countdown.remaining - Math.max(0, event.now - state.countdown.lastNow))
      state.countdown.lastNow = event.now
      state.countdown.fraction = state.countdown.duration ? state.countdown.remaining / state.countdown.duration : 1
      if (state.countdown.remaining === 0) removeActive(state, effects, "senderExpire")
      break
    case "SENDER_CLOSED":
      if (typeof event.identity !== "string" || !state.active || event.identity !== identityOf(state.active)) break
      removeActive(state, effects); break
  }
  return { state: state, effects: effects }
}
function presentationFrame(state) { return { phase: state.phase, active: copy(state.active), pending: copy(state.pending), visual: copy(state.visual), countdown: copy(state.countdown), route: copy(state.route), hovered: state.hovered } }
function assertInvariants(state) {
  var seen = {}, i, transient = isTransition(state.phase)
  if (!state || state.version !== 1 || !state.route || !state.visual || !state.countdown) throw new Error("invalid state")
  for (i = 0; i < state.pending.length; i += 1) {
    if (!identityOf(state.pending[i]) || seen[identityOf(state.pending[i])] || identityOf(state.pending[i]) === identityOf(state.active) || state.retired[identityOf(state.pending[i])]) throw new Error("invalid pending identity")
    seen[identityOf(state.pending[i])] = true
  }
  if (state.active && state.retired[identityOf(state.active)]) throw new Error("retired active")
  if (transient && (!finite(state.visual.token) || state.visual.token <= 0 || !state.visual.kind || typeof state.visual.output !== "string")) throw new Error("invalid transition token")
  if (!transient && state.phase !== "hidden" && state.visual.kind !== "") throw new Error("stable transition metadata")
  if (state.phase === "opening" && (!state.visual.incoming || state.visual.outgoing)) throw new Error("invalid opening cards")
  if (state.phase === "switching" && (!state.visual.incoming || !state.visual.outgoing)) throw new Error("invalid switching cards")
  if (state.phase === "closing" && (!state.visual.outgoing || state.visual.incoming)) throw new Error("invalid closing cards")
  if (state.phase === "open" && (!state.active || !state.visual.incoming || identityOf(state.active) !== identityOf(state.visual.incoming) || state.countdown.identity !== identityOf(state.active) || (state.countdown.visible && state.countdown.identity !== identityOf(state.active)))) throw new Error("open identity mismatch")
  if (!state.visual.outgoing && !state.visual.incoming && (state.visual.outgoingDeck.snapshots.length || state.visual.incomingDeck.snapshots.length)) throw new Error("orphan deck")
  if (state.countdown.visible && state.phase !== "open") throw new Error("countdown outside open")
  return true
}
if (typeof module !== "undefined") module.exports = { createInitialState: createInitialState, createSnapshot: createSnapshot, reduce: reduce, presentationFrame: presentationFrame, assertInvariants: assertInvariants }
