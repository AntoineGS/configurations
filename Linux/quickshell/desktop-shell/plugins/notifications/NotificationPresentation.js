"use strict"

var WATCHDOG = { open: 510, switch: 830, close: 470 }
var CLOSING_TOMBSTONE_TIMEOUT = 10000
var RETIRED_LIMIT = 128

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
function queueCritical(row) { return !!row && (row.queuePriority !== undefined ? row.queuePriority === true : row.urgency === 2) }
function activeCritical(row) { return !!row && row.urgency === 2 }
function emptyDeck() { return { snapshots: [], queuedCount: 0, criticalPending: false } }
function makeDeck(rows) { return { snapshots: rows.map(copy), queuedCount: rows.length, criticalPending: rows.some(activeCritical) } }
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
    hovered: false, countdown: { identity: "", duration: 0, remaining: 0, fraction: 1, visible: false, lastNow: 0 },
    retired: {}, retiredOrder: [], closing: {}, nextToken: 1 }
}
function isTransition(phase) { return phase === "opening" || phase === "switching" || phase === "closing" }
function validEventToken(event) { return finite(event.token) && event.token > 0 && typeof event.kind === "string" && event.kind !== "" && typeof event.output === "string" }
function matching(state, event) { return validEventToken(event) && state.visual.token === event.token && state.visual.kind === event.kind && state.visual.output === event.output }
function cancel(state, effects) {
  if (isTransition(state.phase) && state.visual.token > 0) effects.push({ type: "cancelWatchdog", token: state.visual.token, kind: state.visual.kind, output: state.visual.output })
}
function transition(state, phase, outgoing, incoming, kind, effects, outgoingRows, incomingRows) {
  var token
  if (!outgoingRows) outgoingRows = outgoing ? state.pending : []
  if (!incomingRows) incomingRows = state.pending
  cancel(state, effects)
  state.hovered = false
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
  rowCritical = queueCritical(row); rowOrder = row.queueOrder !== undefined ? row.queueOrder : row.timestamp
  for (i = 0; i < state.pending.length; i += 1) {
    current = state.pending[i]; currentCritical = queueCritical(current); currentOrder = current.queueOrder !== undefined ? current.queueOrder : current.timestamp
    if ((rowCritical && !currentCritical) || (rowCritical === currentCritical && rowOrder < currentOrder)) break
  }
  state.pending.splice(i, 0, copy(row))
}
function persist(row, effects) {
  if (row && row.transient !== true && Number(row.originalId) >= 0
      && row.presentationSource !== "history" && row.presentationSource !== "none")
    effects.push({ type: "persist", identity: identityOf(row), snapshot: copy(row) })
}
function cleanup(row, effects, reason) {
  if (row) effects.push({ type: "cleanup", identity: identityOf(row), snapshot: copy(row), reason: reason || "dismiss" })
}
function archive(row, effects, reason) {
  if (row && row.transient !== true && Number(row.originalId) >= 0 && reason !== "closed" && reason !== "replace")
    effects.push({ type: "archive", identity: identityOf(row), snapshot: copy(row), reason: reason || "dismiss" })
}
function startOpen(state, effects) { return transition(state, "opening", null, state.active, "open", effects) }
function startSwitch(state, outgoing, effects, outgoingRows, incomingRows) { return transition(state, "switching", outgoing, state.active, "switch", effects, outgoingRows, incomingRows) }
function startClose(state, outgoing, effects, outgoingRows, incomingRows) { return transition(state, "closing", outgoing, null, "close", effects, outgoingRows, incomingRows) }
function originalKey(row) { return row && row.originalId !== undefined ? String(row.originalId) : "" }
function retire(state, identity) {
  if (!identity || state.retired[identity]) return
  state.retired[identity] = true; state.retiredOrder.push(identity)
  while (state.retiredOrder.length > RETIRED_LIMIT) delete state.retired[state.retiredOrder.shift()]
}
function tombstone(state, row, now) {
  var key = originalKey(row)
  if (key) state.closing[key] = { identity: identityOf(row), expiresAt: (finite(now) ? now : 0) + CLOSING_TOMBSTONE_TIMEOUT }
}
function prune(state, now) {
  var key
  if (!finite(now)) return
  for (key in state.closing) if (Object.prototype.hasOwnProperty.call(state.closing, key)
      && state.closing[key].expiresAt <= now) delete state.closing[key]
}
function startCountdown(state) {
  var row = state.active, duration = Number(row.duration || 0), remaining = Number(row.remainingLifetime || 0)
  state.countdown = { identity: identityOf(row), duration: duration, remaining: remaining, fraction: duration > 0 ? Math.max(0, Math.min(1, remaining / duration)) : 1, visible: duration > 0 && !activeCritical(row), lastNow: 0 }
}
function startCountdownFor(state, row) {
  var duration = Number(row.duration || 0), remaining = Number(row.remainingLifetime || 0)
  state.countdown = { identity: identityOf(row), duration: duration, remaining: remaining,
    fraction: duration > 0 ? Math.max(0, Math.min(1, remaining / duration)) : 1,
    visible: duration > 0 && !activeCritical(row), lastNow: 0 }
}
function syncIncomingDeck(state) { state.visual.incomingDeck = makeDeck(state.pending) }
function criticalPendingIndex(rows) {
  for (var i = 0; i < rows.length; i += 1) if (activeCritical(rows[i])) return i
  return -1
}
function reconcileCritical(state, effects) {
  var index, outgoingRows, displaced
  if (state.phase !== "open" || state.hovered || activeCritical(state.active)) return false
  index = criticalPendingIndex(state.pending)
  if (index < 0) return false
  outgoingRows = state.pending.slice(); displaced = state.active
  state.active = state.pending.splice(index, 1)[0]
  insertPending(state, displaced)
  startSwitch(state, state.visual.incoming, effects, outgoingRows, state.pending)
  return true
}
function removeActive(state, effects, senderType, reason, now) {
  var old = state.active, displayed = state.visual.incoming || old, next, beforePending = state.pending.slice()
  if (!old) return
  state.hovered = false
  state.countdown.lastNow = 0
  retire(state, identityOf(old))
  if (reason !== "closed") tombstone(state, old, now)
  if (reason !== "closed" && Number(old.originalId) >= 0)
    effects.push({ type: senderType || "senderDismiss", identity: identityOf(old), snapshot: copy(old), reason: reason || "dismiss" })
  cleanup(old, effects, reason || "dismiss")
  archive(old, effects, reason || "dismiss")
  state.countdown.visible = false
  if (state.phase === "opening") {
    next = state.pending.length ? state.pending.shift() : null
    state.active = next
    if (next) startSwitch(state, displayed, effects, beforePending, state.pending)
    else { state.active = null; startClose(state, displayed, effects, beforePending, state.pending) }
    return
  }
  next = state.pending.length ? state.pending.shift() : null
  state.active = next
  if (next) startSwitch(state, displayed, effects, beforePending, state.pending); else startClose(state, displayed, effects, beforePending, state.pending)
}
function settle(state, event, effects) {
  if (!matching(state, event)) return
  cancel(state, effects)
  if (state.phase === "closing") {
    clearVisual(state)
    if (state.route.visible && state.pending.length) {
      var nextIndex = criticalPendingIndex(state.pending)
      state.active = state.pending.splice(nextIndex >= 0 ? nextIndex : 0, 1)[0]
      startOpen(state, effects)
    }
    else state.phase = state.route.visible ? "closed" : "hidden"
    return
  }
  state.visual.outgoing = null
  state.visual.incoming = state.active ? copy(state.active) : null
  state.visual.outgoingDeck = emptyDeck(); state.visual.incomingDeck = makeDeck(state.pending); state.visual.kind = ""; state.visual.token = 0; state.visual.output = ""
  state.phase = state.active ? "open" : "closed"
  if (state.active) startCountdown(state)
  // An arrival or replacement during a transition is reconsidered at the atomic boundary.
  reconcileCritical(state, effects)
}
function validRoute(event) { return typeof event.visible === "boolean" && (event.visible ? typeof event.output === "string" && event.output !== "" : event.output === null) }
function reduce(input, event) {
  var state = copy(input || createInitialState()), effects = [], row, oldIdentity, i, next, previous, found
  if (!event || typeof event.type !== "string") return { state: state, effects: effects }
  switch (event.type) {
    case "ARRIVE":
      row = createSnapshot(event.snapshot)
      if (!row || state.retired[identityOf(row)]) break
      if (state.closing[originalKey(row)]) {
        effects.push({ type: "release", identity: identityOf(row), snapshot: copy(row) })
        break
      }
      persist(row, effects)
      if (!state.route.visible || state.phase === "hidden" || state.phase === "closing" || isTransition(state.phase)) { insertPending(state, row); syncIncomingDeck(state); break }
      if (!state.active) { state.active = copy(row); startOpen(state, effects) }
      else if (state.phase === "open" && activeCritical(row) && !activeCritical(state.active) && !state.hovered) {
        next = state.pending.slice(); previous = state.active; state.active = copy(row); insertPending(state, previous)
        startSwitch(state, state.visual.incoming, effects, next, state.pending)
      } else { insertPending(state, row); syncIncomingDeck(state) }
      break
    case "REPLACE":
      row = createSnapshot(event.snapshot); oldIdentity = event.identity
      if (!row || typeof oldIdentity !== "string" || !oldIdentity || state.retired[identityOf(row)]) break
      if (state.closing[originalKey(row)]) {
        effects.push({ type: "release", identity: identityOf(row), snapshot: copy(row) })
        break
      }
      if (identityOf(row) === oldIdentity) break
       if (identityOf(state.active) === oldIdentity) {
        retire(state, oldIdentity)
        cleanup(state.active, effects, "replace")
        next = copy(row)
        if (state.phase === "open") {
          startCountdownFor(state, next)
        }
        state.active = copy(next)
        if (state.phase === "open") {
          state.visual.incoming = copy(next)
          state.countdown.visible = state.countdown.visible && !activeCritical(next)
        }
        persist(next, effects)
      }
      else {
        found = false
        for (i = 0; i < state.pending.length; i += 1) if (identityOf(state.pending[i]) === oldIdentity) {
          found = true; retire(state, oldIdentity)
          cleanup(state.pending[i], effects, "replace")
          next = copy(row); next.queuePriority = state.pending[i].queuePriority; next.queueOrder = state.pending[i].queueOrder
          state.pending[i] = next; persist(next, effects); syncIncomingDeck(state)
          if (state.phase === "open" && !state.hovered && activeCritical(next) && !activeCritical(state.active)) {
            var replacementRows = state.pending.slice()
            state.pending.splice(i, 1)
            previous = state.active; state.active = next; insertPending(state, previous)
            startSwitch(state, state.visual.incoming, effects, replacementRows, state.pending)
          }
          break
        }
        if (!found) break
      }
      break
    case "DISMISS":
      if (typeof event.identity !== "string") break
       if (state.active && event.identity === identityOf(state.active)) removeActive(state, effects,
         event.reason === "expire" ? "senderExpire" : "senderDismiss", event.reason || "dismiss", event.now)
      else {
        for (i = 0; i < state.pending.length; i += 1) if (identityOf(state.pending[i]) === event.identity) {
          row = state.pending.splice(i, 1)[0]; retire(state, event.identity); tombstone(state, row, event.now)
          if (Number(row.originalId) >= 0)
            effects.push({ type: "senderDismiss", identity: event.identity, snapshot: copy(row), reason: event.reason || "dismiss" })
           cleanup(row, effects, event.reason || "dismiss"); archive(row, effects, event.reason || "dismiss"); syncIncomingDeck(state); break
        }
      }
      break
    case "DISMISS_ALL":
      row = state.active ? copy(state.active) : null
      var outgoingRows = state.pending.slice()
       if (row) {
          retire(state, identityOf(row)); tombstone(state, row, event.now)
         if (Number(row.originalId) >= 0)
           effects.push({ type: "senderDismiss", identity: identityOf(row), snapshot: copy(row), reason: "dismiss" })
         cleanup(row, effects, "dismiss"); archive(row, effects, "dismiss")
       }
       state.pending.forEach(function (item) {
          retire(state, identityOf(item)); tombstone(state, item, event.now)
         if (Number(item.originalId) >= 0)
           effects.push({ type: "senderDismiss", identity: identityOf(item), snapshot: copy(item), reason: "dismiss" })
         cleanup(item, effects, "dismiss"); archive(item, effects, "dismiss")
      })
      state.active = null; state.pending = []; state.countdown.visible = false
      if (state.visual.incoming || state.visual.outgoing) startClose(state, state.visual.incoming || state.visual.outgoing, effects, outgoingRows, [])
      else state.phase = state.route.visible ? "closed" : "hidden"
      break
    case "HOVER_CHANGED":
      if (typeof event.hovered !== "boolean") break
      if (state.hovered === event.hovered) break
      state.hovered = event.hovered
      state.countdown.lastNow = 0
      if (!state.hovered && state.phase === "open" && state.pending.length && !activeCritical(state.active)) {
        var handoffRows = state.pending.slice(), criticalIndex = criticalPendingIndex(state.pending)
        if (criticalIndex < 0) break
        next = state.active
        state.active = state.pending.splice(criticalIndex, 1)[0]
        insertPending(state, next)
        startSwitch(state, state.visual.incoming, effects, handoffRows, state.pending)
      }
      break
    case "ROUTE_CHANGED":
       if (!validRoute(event)) break
       if (!event.visible) {
         if (!state.route.visible || state.phase === "hidden") break
          cancel(state, effects); state.hovered = false; state.route = { visible: false, output: "" }; clearVisual(state); state.phase = "hidden"; state.countdown.visible = false
        } else {
          var routeChanged = !state.route.visible || state.route.output !== event.output
          state.route = { visible: true, output: event.output || "" }
          if (state.phase === "closing" && routeChanged) {
            cancel(state, effects); clearVisual(state); state.countdown.visible = false
            state.phase = "closed"
            if (state.pending.length) { state.active = state.pending.shift(); startOpen(state, effects) }
          }
          else if (!state.active && state.pending.length) { state.active = state.pending.shift(); startOpen(state, effects) }
         else if (state.active && (state.phase === "hidden" || routeChanged)) startOpen(state, effects)
         else if (!routeChanged) break
       }
      break
    case "TRANSITION_FINISHED":
    case "TRANSITION_TIMED_OUT":
      settle(state, event, effects); break
    case "TICK":
      if (typeof event.identity !== "string" || !finite(event.now) || state.phase !== "open" || !state.active ||
        identityOf(state.active) !== event.identity || state.countdown.identity !== event.identity || !state.visual.incoming || identityOf(state.visual.incoming) !== event.identity || !state.countdown.visible) break
      if (state.hovered) { state.countdown.lastNow = event.now; state.active.remainingLifetime = state.countdown.remaining; break }
      if (state.countdown.lastNow !== 0) state.countdown.remaining = Math.max(0, state.countdown.remaining - Math.max(0, event.now - state.countdown.lastNow))
      state.countdown.lastNow = event.now
      state.active.remainingLifetime = state.countdown.remaining
      state.countdown.fraction = state.countdown.duration ? state.countdown.remaining / state.countdown.duration : 1
       if (state.countdown.remaining === 0) removeActive(state, effects, "senderExpire", "expire", event.now)
       break
    case "PRUNE":
      prune(state, event.now)
      break
    case "SENDER_CLOSED":
       if (typeof event.identity !== "string") break
       for (var closingKey in state.closing)
         if (Object.prototype.hasOwnProperty.call(state.closing, closingKey)
             && state.closing[closingKey].identity === event.identity) delete state.closing[closingKey]
       if (state.active && event.identity === identityOf(state.active)) removeActive(state, effects, null, "closed", event.now)
       else {
         for (i = 0; i < state.pending.length; i += 1) if (identityOf(state.pending[i]) === event.identity) {
            row = state.pending.splice(i, 1)[0]; retire(state, event.identity)
            cleanup(row, effects, "closed"); syncIncomingDeck(state); break
         }
       }
       break
  }
  return { state: state, effects: effects }
}
function presentationFrame(state) { return { phase: state.phase, active: copy(state.active), pending: copy(state.pending), visual: copy(state.visual), countdown: copy(state.countdown), route: copy(state.route), hovered: state.hovered } }
function assertInvariants(state) {
  var seen = {}, i, transient, validPhases = { closed: true, opening: true, open: true, switching: true, closing: true, hidden: true }
  if (!state || state.version !== 1 || !state.route || !state.visual || !state.countdown) throw new Error("invalid state")
  if (!Object.prototype.hasOwnProperty.call(validPhases, state.phase)) throw new Error("invalid phase")
  transient = isTransition(state.phase)
  for (i = 0; i < state.pending.length; i += 1) {
    if (!identityOf(state.pending[i]) || seen[identityOf(state.pending[i])] || identityOf(state.pending[i]) === identityOf(state.active) || state.retired[identityOf(state.pending[i])]) throw new Error("invalid pending identity")
    seen[identityOf(state.pending[i])] = true
  }
  if (state.active && state.retired[identityOf(state.active)]) throw new Error("retired active")
  if (transient && (!finite(state.visual.token) || state.visual.token <= 0 || state.visual.kind !== ({ opening: "open", switching: "switch", closing: "close" })[state.phase] || typeof state.visual.output !== "string" || state.visual.output !== state.route.output)) throw new Error("invalid transition token")
  if (!transient && (state.visual.token !== 0 || state.visual.kind !== "" || state.visual.output !== "")) throw new Error("stable transition metadata")
  if (state.phase === "opening" && (!state.visual.incoming || state.visual.outgoing)) throw new Error("invalid opening cards")
  if (state.phase === "switching" && (!state.visual.incoming || !state.visual.outgoing)) throw new Error("invalid switching cards")
  if (state.phase === "closing" && (!state.visual.outgoing || state.visual.incoming)) throw new Error("invalid closing cards")
  if (state.phase === "open" && (state.visual.outgoing || !state.active || !state.visual.incoming || identityOf(state.active) !== identityOf(state.visual.incoming) || state.countdown.identity !== identityOf(state.active) || (state.countdown.visible && state.countdown.identity !== identityOf(state.active)))) throw new Error("open identity mismatch")
  if (!state.visual.outgoing && !state.visual.incoming && !state.pending.length
      && (state.visual.outgoingDeck.snapshots.length || state.visual.incomingDeck.snapshots.length)) throw new Error("orphan deck")
  if (state.countdown.visible && state.phase !== "open") throw new Error("countdown outside open")
  return true
}
if (typeof module !== "undefined") module.exports = { createInitialState: createInitialState, createSnapshot: createSnapshot, reduce: reduce, presentationFrame: presentationFrame, assertInvariants: assertInvariants }
