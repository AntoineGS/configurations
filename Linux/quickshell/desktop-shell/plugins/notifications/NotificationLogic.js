var NOTIFICATION_LIMITS = {
  maxAppLength: 128,
  maxSummaryLength: 512,
  maxBodyLength: 4096,
  maxActionIdentifierLength: 256,
  maxActionLabelLength: 256,
  maxActions: 8,
  maxImageLength: 2048,
  maxSerializedPayload: 16384,
  maxActivePopups: 50,
  maxHistoryEntries: 200,
  maxPersistenceJobs: 100,
}

var MAX_ROUTE_LEASE_MS = 5000

function limits() {
  var result = {}
  for (var key in NOTIFICATION_LIMITS) result[key] = NOTIFICATION_LIMITS[key]
  return result
}

function boundedText(value, maxLength) {
  var text = value === undefined || value === null ? "" : String(value)
  return text.slice(0, maxLength)
}

function boundedSource(value, maxLength) {
  var source = value === undefined || value === null ? "" : String(value)
  return source.length > maxLength ? "" : source
}

var NOTIFICATION_IMAGE_SOURCE_RE =
  /^image:\/\/notification\/[A-Za-z0-9_-][A-Za-z0-9._~-]*(?:\/[A-Za-z0-9_-][A-Za-z0-9._~-]*)*$/

function normalizeImageSource(value) {
  var source = boundedSource(value, NOTIFICATION_LIMITS.maxImageLength)
  return NOTIFICATION_IMAGE_SOURCE_RE.test(source) ? source : ""
}

function normalizeAppIconSource(value) {
  var source = boundedSource(value, NOTIFICATION_LIMITS.maxAppLength)
  if (normalizeImageSource(source)) return source
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(source) ? source : ""
}

function isChromiumDerived(app, appIcon) {
  var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase()
  return source.indexOf("chrom") >= 0 || source.indexOf("brave") >= 0 ||
         source.indexOf("vivaldi") >= 0 || source.indexOf("microsoft-edge") >= 0 ||
         source.indexOf("opera") >= 0
}

function sanitizeBody(body, app, appIcon) {
  var text = String(body || "").replace(/<img[^>]*>/gi, "")
  if (!isChromiumDerived(app, appIcon)) return text

  return text
    .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
    .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
}

function shouldBypassDnd(notification, criticalUrgency) {
  return !!notification && notification.urgency === criticalUrgency
}

function isEphemeral(notification) {
  var hints = notification && notification.hints
  return !!(notification && notification.transient === true) || !!(hints && hints.transient)
}

function cueGlyph(direction) {
  switch (direction) {
  case "left": return "←"
  case "right": return "→"
  case "up": return "↑"
  case "down": return "↓"
  default: return "•"
  }
}
function deckProjection(phase, progress, incomingVisible) {
  var value = Math.max(0, Math.min(1, typeof progress === "number" && isFinite(progress) ? progress : 0))
  if (phase === "opening") return { outgoing: 0, incoming: value }
  if (phase === "closing") return { outgoing: value, incoming: 0 }
  if (phase === "switching") return incomingVisible ? { outgoing: 0, incoming: value } : { outgoing: value, incoming: 0 }
  return { outgoing: 0, incoming: 1 }
}
function deckOpacityProjection(phase, progress, incomingVisible) {
  var projection = deckProjection(phase, progress, incomingVisible)
  if (phase === "opening" || phase === "open" || (phase === "switching" && incomingVisible))
    return { incoming: projection.incoming, selected: projection.incoming }
  return { outgoing: projection.outgoing, selected: projection.outgoing }
}
function closingOwnershipInitialState() { return { owners: {} } }
function releaseTrackedNotification(notification) {
  if (notification) notification.tracked = false
  return notification
}
function closingOwnershipTransition(state, event) {
  var owners = state && state.owners ? state.owners : {}, id = event && String(event.originalId), owner = id ? owners[id] : null
  var next = { owners: Object.assign({}, owners) }
  if (!event || typeof event !== "object" || event.originalId === undefined || event.originalId === null)
    return { state: next, accepted: false, release: null }
  if (event.type === "begin") {
    next.owners[id] = { notification: event.notification, generation: event.generation, identity: event.identity }
    return { state: next, accepted: true, release: null }
  }
  if (!owner || owner.notification !== event.notification || owner.generation !== event.generation
      || owner.identity !== event.identity) return { state: next, accepted: false, release: null }
  if (event.type === "remove") return { state: next, accepted: true, release: null }
  if (event.type === "close" || event.type === "clear") {
    delete next.owners[id]
    return { state: next, accepted: true, release: owner.notification }
  }
  return { state: next, accepted: false, release: null }
}
function actionCloseNeedsGuard(source) { return source === "action" }
function actionCloseInitialState() { return { guards: {} } }
function actionCloseTransition(state, event) {
  var guards = state && state.guards ? state.guards : {}, id = event && String(event.originalId), guard = id ? guards[id] : null
  var next = { guards: Object.assign({}, guards) }
  if (!event || typeof event !== "object") return { state: next, accepted: false, flush: false }
  if (event.originalId === undefined || event.originalId === null) return { state: next, accepted: false, flush: false }
  if (event.type === "begin") {
    next.guards[id] = { notification: event.notification, generation: event.generation, inProgress: true, deferred: false }
    return { state: next, accepted: true, flush: false }
  }
  if (!guard || guard.notification !== event.notification || guard.generation !== event.generation)
    return { state: next, accepted: false, flush: false }
  if (event.type === "close" && guard.inProgress) {
    next.guards[id] = Object.assign({}, guard, { deferred: true })
    return { state: next, accepted: false, flush: false }
  }
  if (event.type === "complete") {
    next.guards[id] = Object.assign({}, guard, { inProgress: false })
    return { state: next, accepted: true, flush: guard.deferred }
  }
  if (event.type === "close" || event.type === "timeout" || event.type === "clear") {
    delete next.guards[id]
    return { state: next, accepted: true, flush: guard.deferred && !guard.inProgress }
  }
  return { state: next, accepted: false, flush: false }
}

function isActionList(value) {
  return !!value && typeof value.length === "number"
}

function actionMetadata(notification) {
  var actions = notification && notification.actions
  if (!isActionList(actions)) return []

  var result = []
  var limit = Math.min(actions.length, NOTIFICATION_LIMITS.maxActions)
  for (var i = 0; i < limit; i++) {
    var action = actions[i]
    var identifier = action && action.identifier === undefined ? "" : String(action && action.identifier || "")
    if (!identifier || identifier.length > NOTIFICATION_LIMITS.maxActionIdentifierLength) continue
    var metadata = {
      identifier: identifier,
      text: boundedText(action && action.text, NOTIFICATION_LIMITS.maxActionLabelLength),
    }
    result.push(metadata)
  }
  return result
}

function actionOutcome(actions, identifier, resident) {
  var wanted = String(identifier || "")
  if (!isActionList(actions) || !wanted) return { found: false, dismiss: false }
  var limit = Math.min(actions.length, NOTIFICATION_LIMITS.maxActions)
  for (var i = 0; i < limit; i++) {
    var action = actions[i]
    if (action && String(action.identifier || "") === wanted)
      return { found: true, dismiss: resident !== true }
  }
  return { found: false, dismiss: false }
}

function normalizedExpireTimeout(value) {
  var timeout = Number(value)
  if (!isFinite(timeout)) return -1
  if (timeout < -1) return -1
  if (timeout === -1) return -1
  if (timeout <= 0) return 0
  return Math.round(timeout)
}

function requestedDuration(expireTimeout) {
  return normalizedExpireTimeout(expireTimeout)
}

function durationFor(urgency, expireTimeout, criticalUrgency, lowUrgency, lowDefault, normalDefault, maxDuration) {
  var requested = requestedDuration(expireTimeout)
  if (requested === 0 || urgency === criticalUrgency) return 0

  var minimum = urgency === lowUrgency ? lowDefault : normalDefault
  var duration = requested === -1 ? minimum : requested
  return Math.min(maxDuration, Math.max(minimum, duration))
}

function deadlineFor(urgency, expireTimeout, startedAt, criticalUrgency, lowUrgency,
                     lowDefault, normalDefault, maxDuration) {
  var duration = durationFor(
    urgency, expireTimeout, criticalUrgency, lowUrgency, lowDefault, normalDefault, maxDuration)
  if (duration <= 0) return null
  var start = Number(startedAt)
  return isFinite(start) ? start + duration : null
}

function deadlineForReceipt(urgency, expireTimeout, identityTimestamp, receiptTimestamp,
                            criticalUrgency, lowUrgency, lowDefault, normalDefault, maxDuration) {
  var receipt = Number(receiptTimestamp)
  var start = isFinite(receipt) ? receipt : identityTimestamp
  return deadlineFor(urgency, expireTimeout, start, criticalUrgency, lowUrgency,
    lowDefault, normalDefault, maxDuration)
}

function remainingLifetime(entry, now, fallbackDuration) {
  var current = Number(now)
  if (!isFinite(current)) return 0

  var deadline = Number((entry || {}).deadline)
  if (isFinite(deadline) && deadline > 0) return Math.max(0, deadline - current)

  var duration = Number(fallbackDuration)
  var timestamp = Number((entry || {}).timestamp)
  if (!isFinite(duration) || duration <= 0 || !isFinite(timestamp)) return 0
  return Math.max(0, timestamp + duration - current)
}

function popupIdentity(entry) {
  var row = entry || {}
  return String(Number(row.timestamp) || 0) + ":" + String(Number(row.originalId) || 0)
}

function popupQueuePriority(entry, criticalUrgency) {
  var row = entry || {}
  if (typeof row.queuePriority === "boolean") return row.queuePriority
  return Number(row.urgency) === Number(criticalUrgency)
}

function popupActiveCritical(entry, criticalUrgency) {
  return Number((entry || {}).urgency) === Number(criticalUrgency)
}

function popupQueueOrder(entry) {
  var value = Number((entry || {}).queueOrder)
  if (isFinite(value) && value >= 0) return value
  return Number((entry || {}).timestamp) || 0
}

function popupQueueOrderSeed(rows) {
  var values = Array.isArray(rows) ? rows : []
  var maximum = -1
  for (var i = 0; i < values.length; i++) {
    var order = Number(values[i] && values[i].queueOrder)
    if (isFinite(order) && order >= 0) maximum = Math.max(maximum, order)
  }
  return maximum
}

function popupArrivalPlan(rows, urgency, criticalUrgency, hovered) {
  var values = Array.isArray(rows) ? rows : []
  var incomingCritical = Number(urgency) === Number(criticalUrgency)
  if (!incomingCritical) {
    return { insertIndex: values.length, preempt: false, deferred: false }
  }

  var hasActive = values.length > 0
  var activeCritical = hasActive && popupActiveCritical(values[0], criticalUrgency)
  var index = hasActive ? 1 : 0
  while (index < values.length
      && popupQueuePriority(values[index], criticalUrgency)) index++

  return {
    insertIndex: index,
    preempt: hasActive && !activeCritical && hovered !== true,
    deferred: hasActive && !activeCritical && hovered === true,
  }
}

function sortPopupQueue(rows, criticalUrgency) {
  var values = Array.isArray(rows) ? rows.slice() : []
  return values.sort(function(left, right) {
    var leftCritical = popupQueuePriority(left, criticalUrgency)
    var rightCritical = popupQueuePriority(right, criticalUrgency)
    if (leftCritical !== rightCritical) return leftCritical ? -1 : 1
    var orderDifference = popupQueueOrder(left) - popupQueueOrder(right)
    return orderDifference || (Number(left && left.timestamp) || 0) - (Number(right && right.timestamp) || 0)
  })
}

function consumeRemainingLifetime(remaining, elapsed) {
  var value = Number(remaining)
  var used = Number(elapsed)
  if (!isFinite(value) || value <= 0) return 0
  if (!isFinite(used) || used <= 0) return value
  return Math.max(0, value - used)
}

function restoredRemainingLifetime(entry, duration, now) {
  var row = entry || {}
  var stored = Number(row.remainingLifetime)
  if (isFinite(stored) && stored >= 0) return stored

  var deadline = Number(row.deadline)
  var current = Number(now)
  if (isFinite(deadline) && deadline > 0 && isFinite(current))
    return Math.max(0, deadline - current)

  var fallback = Number(duration)
  return isFinite(fallback) && fallback > 0 ? fallback : 0
}

function migratePopupQueue(rows) {
  var values = Array.isArray(rows) ? rows.slice() : []
  var ordered = values.map(function(row, index) {
    return { row: row, index: index }
  }).sort(function(left, right) {
    var timestampDifference = (Number(left.row && left.row.timestamp) || 0)
      - (Number(right.row && right.row.timestamp) || 0)
    return timestampDifference || left.index - right.index
  })
  var maximum = popupQueueOrderSeed(values)
  for (var i = 0; i < ordered.length; i++) {
    var row = ordered[i].row
    var current = Number(row && row.queueOrder)
    if (isFinite(current) && current >= 0) continue
    var candidate = Number(row && row.timestamp)
    maximum = nextMonotonicTimestamp(maximum, candidate)
    if (row) row.queueOrder = maximum
  }
  return values
}

function shouldPersistPopup(entry) {
  var row = entry || {}
  return Number(row.originalId) >= 0 && row.transient !== true
}

function nextMonotonicTimestamp(previous, candidate) {
  var prior = Number(previous)
  if (!isFinite(prior)) prior = -1
  var requested = Number(candidate)
  if (!isFinite(requested)) requested = prior + 1
  return Math.max(requested, prior + 1)
}

function withPopupTiming(snapshot, duration) {
  var result = {}
  var value = Number(duration)
  for (var key in (snapshot || {})) if (Object.prototype.hasOwnProperty.call(snapshot, key)) result[key] = snapshot[key]
  result.duration = value
  result.remainingLifetime = value
  return result
}

function restorePopupTiming(snapshot, duration, now) {
  var result = {}
  var value = Number(duration)
  var remaining = restoredRemainingLifetime(snapshot, value, now)
  for (var key in (snapshot || {})) if (Object.prototype.hasOwnProperty.call(snapshot, key)) result[key] = snapshot[key]
  result.duration = value
  result.remainingLifetime = remaining
  return result
}

function restorePopupPlan(snapshot, duration, now, criticalUrgency) {
  var source = snapshot || {}
  var migrated = source.queuePriority === undefined
    || source.queueOrder === undefined
    || (source.remainingLifetime === undefined && source.deadline !== undefined)
  var entry = restorePopupTiming(source, duration, now)
  if (entry.queuePriority === undefined)
    entry.queuePriority = popupQueuePriority(entry, criticalUrgency)
  delete entry.deadline
  return {
    entry: entry,
    expired: Number(entry.duration) > 0 && Number(entry.remainingLifetime) <= 0,
    migrated: migrated,
  }
}

function replacementBookkeeping(generations, sources, originalId, timestamp, source) {
  var nextGenerations = {}, nextSources = {}, key
  for (key in (generations || {})) if (Object.prototype.hasOwnProperty.call(generations, key)) nextGenerations[key] = generations[key]
  for (key in (sources || {})) if (Object.prototype.hasOwnProperty.call(sources, key)) nextSources[key] = sources[key]
  nextGenerations[originalId] = timestamp
  nextSources[originalId] = source
  return { generations: nextGenerations, sources: nextSources, presentationSource: source }
}

function canAdmitPopup(activeCount, pendingCount, maximum) {
  return Number(activeCount) + Number(pendingCount) < Number(maximum)
}

function transitionCallbackEvent(state, token, output) {
  var visual = state && state.visual
  if (!visual || (state.phase !== "opening" && state.phase !== "switching" && state.phase !== "closing")
      || Number(token) !== visual.token || String(output) !== visual.output) return null
  return { type: "TRANSITION_FINISHED", token: visual.token, kind: visual.kind, output: visual.output }
}

function persistenceQueueUpdate(queue, job, maxLength, front, protectedKeys) {
  var next = Array.isArray(queue) ? queue.slice() : []
  var dropped = null
  if (job && job.key) {
    for (var i = next.length - 1; i >= 0; i--) {
      if (next[i] && next[i].key === job.key) {
        var currentGeneration = Number(next[i].generation)
        var incomingGeneration = Number(job.generation)
        if (isFinite(currentGeneration) && isFinite(incomingGeneration)
            && incomingGeneration < currentGeneration)
          return { queue: next, dropped: null, stale: true, outcome: "superseded" }
        var superseded = next[i]
        next.splice(i, 1)
        if (front) next.unshift(job)
        else next.splice(i, 0, job)
        return {
          queue: next,
          dropped: superseded,
          droppedOutcome: "superseded",
          outcome: "queued",
        }
      }
    }
  }
  if (next.length >= maxLength) {
    var dropIndex = 0
    var hasUnprotected = false
    for (var candidate = 0; candidate < next.length; candidate++) {
      var candidateKey = next[candidate] && next[candidate].key
      if (!protectedKeys || !protectedKeys[candidateKey]) {
        dropIndex = candidate
        hasUnprotected = true
        break
      }
    }
    if (!hasUnprotected) {
      return {
        queue: next,
        dropped: job,
        droppedOutcome: "capacity-dropped",
        outcome: "capacity-dropped",
      }
    }
    dropped = next.splice(dropIndex, 1)[0]
  }
  if (front) next.unshift(job)
  else next.push(job)
  return {
    queue: next,
    dropped: dropped,
    droppedOutcome: dropped ? "capacity-dropped" : null,
    outcome: dropped ? "capacity-dropped" : "queued",
  }
}

function refreshScheduleUpdate(pending, key, request) {
  var next = {}
  var source = pending && typeof pending === "object" ? pending : {}
  for (var existing in source) next[existing] = source[existing]
  var normalizedKey = String(key)
  var scheduled = !Object.prototype.hasOwnProperty.call(next, normalizedKey)
  next[normalizedKey] = request
  return { pending: next, scheduled: scheduled }
}

function admissionUpdate(timestamps, now, maxAccepted, windowMs) {
  var current = Number(now)
  var limit = Math.max(1, Math.floor(Number(maxAccepted)))
  var window = Math.max(1, Number(windowMs))
  if (!isFinite(current) || !isFinite(limit) || !isFinite(window))
    return { accepted: false, timestamps: [], dropped: 1 }

  var source = Array.isArray(timestamps) ? timestamps : []
  var start = Math.max(0, source.length - limit)
  var cutoff = current - window
  var next = []
  for (var i = start; i < source.length; i++) {
    var timestamp = Number(source[i])
    if (isFinite(timestamp) && timestamp > cutoff) next.push(timestamp)
  }
  if (next.length >= limit) return { accepted: false, timestamps: next, dropped: 1 }
  next.push(current)
  return { accepted: true, timestamps: next, dropped: 0 }
}

function invalidRoute(error) {
  return {
    valid: false,
    visible: false,
    output: null,
    cueOutput: null,
    direction: null,
    updatedAt: null,
    error: String(error || "invalid route")
  }
}

function invalidLease(error) {
  return {
    valid: false,
    refreshedAtMs: null,
    expiresAtMs: null,
    routeUpdatedAt: null,
    error: String(error || "invalid lease")
  }
}

function validRouteOutput(value) {
  return value === null || value === undefined ||
    value === "DVI-D-1" || value === "HDMI-A-1" || value === "DP-2" ||
    value === "DP-1" || value === "eDP-1"
}

function validRouteDirection(value) {
  return value === null || value === undefined ||
    (typeof value === "string" && /^(left|right|up|down)$/.test(value))
}

/**
 * Parse and fail closed on a notification route state payload.
 *
 * @param {string} raw JSON route state
 * @param {number} nowMs current time in milliseconds
 * @returns {{valid: boolean, visible: boolean, output: (string|null), cueOutput: (string|null), direction: (string|null), updatedAt: (number|null), error: string}}
 */
function normalizeRoute(raw, nowMs) {
  var parsed
  try {
    parsed = JSON.parse(String(raw || ""))
  } catch (e) {
    return invalidRoute("invalid route JSON")
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return invalidRoute("route must be an object")
  if (parsed.version !== 1) return invalidRoute("unsupported route version")
  if (typeof parsed.visible !== "boolean") return invalidRoute("route visibility is invalid")
  if (typeof parsed.updatedAt !== "number" || !isFinite(parsed.updatedAt) ||
      Math.floor(parsed.updatedAt) !== parsed.updatedAt)
    return invalidRoute("route timestamp is invalid")
  if (typeof nowMs !== "number" || !isFinite(nowMs)) return invalidRoute("current time is invalid")

  var age = nowMs - (parsed.updatedAt * 1000)
  if (age < 0) return invalidRoute("route timestamp is from the future")
  if (age > 45000) return invalidRoute("route is stale")

  var output = parsed.output === undefined ? null : parsed.output
  var cueOutput = parsed.cueOutput === undefined ? null : parsed.cueOutput
  var direction = parsed.direction === undefined ? null : parsed.direction
  if (!validRouteOutput(output)) return invalidRoute("route output is invalid")
  if (!validRouteOutput(cueOutput)) return invalidRoute("route cue output is invalid")
  if (!validRouteDirection(direction)) return invalidRoute("route direction is invalid")
  if (parsed.visible && output === null) return invalidRoute("visible route has no output")

  return {
    valid: true,
    visible: parsed.visible,
    output: output,
    cueOutput: cueOutput,
    direction: direction,
    updatedAt: parsed.updatedAt,
    error: ""
  }
}

function normalizeLease(raw, nowMs, expectedRouteUpdatedAt) {
  var parsed
  try {
    parsed = JSON.parse(String(raw || ""))
  } catch (e) {
    return invalidLease("invalid lease JSON")
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return invalidLease("lease must be an object")
  if (parsed.version !== 2) return invalidLease("unsupported lease version")
  if (typeof nowMs !== "number" || !isFinite(nowMs)) return invalidLease("current time is invalid")

  var refreshedAtMs = parsed.refreshedAtMs
  var expiresAtMs = parsed.expiresAtMs
  var routeUpdatedAt = parsed.routeUpdatedAt
  if (typeof refreshedAtMs !== "number" || !isFinite(refreshedAtMs) ||
      Math.floor(refreshedAtMs) !== refreshedAtMs || refreshedAtMs < 0)
    return invalidLease("lease refreshedAtMs is invalid")
  if (typeof expiresAtMs !== "number" || !isFinite(expiresAtMs) ||
      Math.floor(expiresAtMs) !== expiresAtMs || expiresAtMs < 0)
    return invalidLease("lease expiresAtMs is invalid")
  if (typeof routeUpdatedAt !== "number" || !isFinite(routeUpdatedAt) || Math.floor(routeUpdatedAt) !== routeUpdatedAt || routeUpdatedAt < 0)
    return invalidLease("lease routeUpdatedAt is invalid")

  if (refreshedAtMs > nowMs) return invalidLease("lease refreshedAtMs is from the future")
  if (expiresAtMs <= nowMs) return invalidLease("lease is stale")
  if (expiresAtMs < refreshedAtMs) return invalidLease("lease lifetime is invalid")
  if (expiresAtMs - refreshedAtMs > MAX_ROUTE_LEASE_MS) return invalidLease("lease lifetime is too long")

  if (typeof expectedRouteUpdatedAt !== "number" || !isFinite(expectedRouteUpdatedAt) ||
      Math.floor(expectedRouteUpdatedAt) !== expectedRouteUpdatedAt || expectedRouteUpdatedAt < 0)
    return invalidLease("expected route timestamp is invalid")
  if (routeUpdatedAt !== expectedRouteUpdatedAt) return invalidLease("lease route timestamp does not match route")

  return {
    valid: true,
    refreshedAtMs: refreshedAtMs,
    expiresAtMs: expiresAtMs,
    routeUpdatedAt: routeUpdatedAt,
    error: ""
  }
}

function snapshotOf(notification, timestamp) {
  var n = notification || {}
  var id = n.id || 0
  var expireTimeout = normalizedExpireTimeout(n.expireTimeout)
  var image = normalizeImageSource(n.image)
  var hintedImage = imagePathHint(n)
  if (!image && hintedImage) image = hintedImage
  var result = {
    // The timestamp-plus-originalId file stem distinguishes generations that reuse an id.
    id: id,
    originalId: id,
    app: boundedText(n.appName, NOTIFICATION_LIMITS.maxAppLength),
    appIcon: normalizeAppIconSource(n.appIcon),
    summary: boundedText(n.summary, NOTIFICATION_LIMITS.maxSummaryLength),
    body: boundedText(n.body, NOTIFICATION_LIMITS.maxBodyLength),
    image: image,
    urgency: n.urgency,
    expireTimeout: expireTimeout,
    timestamp: timestamp === undefined ? Date.now() : timestamp,
    actions: actionMetadata(n),
  }
  if (isEphemeral(n)) result.transient = true
  return result
}

var POPUP_ROLES = ["app", "appIcon", "summary", "body", "image", "urgency", "expireTimeout", "remainingLifetime", "queuePriority", "queueOrder", "transient", "actions"]

function popupRoles() {
  return POPUP_ROLES
}

function actionsEqual(first, second) {
  var left = isActionList(first) ? first : []
  var right = isActionList(second) ? second : []
  if (left.length !== right.length) return false
  for (var i = 0; i < left.length; i++) {
    if (!left[i] || !right[i] || left[i].identifier !== right[i].identifier || left[i].text !== right[i].text)
      return false
  }
  return true
}

function popupRowChanged(row, updated) {
  var current = row || {}
  var next = updated || {}
  for (var i = 0; i < POPUP_ROLES.length; i++) {
    var role = POPUP_ROLES[i]
    if (role === "actions") {
      if (!actionsEqual(current[role], next[role])) return true
      continue
    }
    if (current[role] !== next[role]) return true
  }
  return false
}

function imagePathHint(notification) {
  try {
    var hints = notification && notification.hints
    var value = hints && hints["image-path"]
    return normalizeImageSource(value)
  } catch (e) {
    return ""
  }
}

function replacementSnapshot(notification, originalId, timestamp) {
  var updated = snapshotOf(notification, timestamp)
  updated.id = originalId
  updated.originalId = originalId
  return updated
}

function historyEntry(value, normalUrgency) {
  var e = value || {}
  return {
    id: e.id || 0,
    originalId: e.originalId || e.id || 0,
    app: boundedText(e.app, NOTIFICATION_LIMITS.maxAppLength),
    appIcon: normalizeAppIconSource(e.appIcon),
    summary: boundedText(e.summary, NOTIFICATION_LIMITS.maxSummaryLength),
    body: boundedText(e.body, NOTIFICATION_LIMITS.maxBodyLength),
    image: normalizeImageSource(e.image),
    urgency: typeof e.urgency === "number" ? e.urgency : normalUrgency,
    expireTimeout: 0,
    timestamp: e.timestamp || 0,
    actions: [],
  }
}

function historyDisplayEntry(value, normalUrgency) {
  var entry = historyEntry(value, normalUrgency)
  entry.actionAvailable = !!value && value.actionAvailable === true
  return entry
}

function parseSettings(raw) {
  var text = String(raw || "").trim()
  if (!text) return { error: false, dnd: null, legacy: false }

  try {
    var parsed = JSON.parse(text)
    return {
      error: false,
      dnd: parsed && typeof parsed.dnd === "boolean" ? parsed.dnd : null,
      legacy: !!(parsed && (parsed.pending || parsed.past || parsed.entries))
    }
  } catch (e) {
    return { error: true, errorMessage: String(e), dnd: null, legacy: false }
  }
}

function popupEntry(value, normalUrgency) {
  var entry = historyEntry(value, normalUrgency)
  var source = value || {}
  var hasExpireTimeout = Object.prototype.hasOwnProperty.call(source, "expireTimeout")
  entry.expireTimeout = normalizedExpireTimeout(hasExpireTimeout ? source.expireTimeout : -1)
  if (typeof source.queuePriority === "boolean") entry.queuePriority = source.queuePriority
  if (typeof source.queueOrder === "number"
      && isFinite(source.queueOrder) && source.queueOrder >= 0)
    entry.queueOrder = source.queueOrder

  var remaining = Number(source.remainingLifetime)
  if (isFinite(remaining) && remaining >= 0) entry.remainingLifetime = remaining

  var deadline = Number(source.deadline)
  if (entry.remainingLifetime === undefined && isFinite(deadline) && deadline > 0)
    entry.deadline = deadline
  return entry
}

function popupFileName(entry) {
  // File identity includes both generation time and original id, not id alone.
  return imageStem(entry) + ".json"
}

var PERSISTED_IMAGE_ROLES = ["appIcon", "image"]

function imageStem(entry) {
  var e = entry || {}
  return String(e.timestamp || 0) + "-" + String(e.originalId || 0)
}

function localImageFile(value) {
  return ""
}

function persistablePopup(entry, imagesDir) {
  var e = entry || {}
  var out = {}
  for (var key in e) out[key] = e[key]
  var copies = []
  for (var i = 0; i < PERSISTED_IMAGE_ROLES.length; i++) {
    var role = PERSISTED_IMAGE_ROLES[i]
    var value = role === "appIcon"
      ? normalizeAppIconSource(out[role])
      : normalizeImageSource(out[role])
    out[role] = value
    if (!value) continue
    if (value.indexOf("image://") === 0) out[role] = ""
  }
  if (Object.prototype.hasOwnProperty.call(out, "actions")) out.actions = []
  return { entry: out, copies: copies }
}

function serializePopup(entry, normalUrgency) {
  var popup = popupEntry(entry, normalUrgency)
  var serialized = JSON.stringify(popup)
  if (serialized.length <= NOTIFICATION_LIMITS.maxSerializedPayload) return serialized

  popup.appIcon = ""
  popup.image = ""
  popup.body = ""
  popup.summary = boundedText(popup.summary, 128)
  return JSON.stringify(popup)
}

function parsePopupFiles(raw, normalUrgency) {
  var limit = arguments.length > 2 ? Number(arguments[2]) : 0
  if (!isFinite(limit) || limit < 0) limit = 0
  limit = Math.min(NOTIFICATION_LIMITS.maxActivePopups, Math.floor(limit))
  var lines = String(raw || "").split("\n")
  var entries = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var value = JSON.parse(line)
      if (value && typeof value === "object") entries.push(popupEntry(value, normalUrgency))
    } catch (e) {
      // Ignore an incomplete final line so one interrupted write cannot hide valid history.
    }
  }
  entries.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return limit > 0 ? entries.slice(0, limit) : entries
}

function popupExpired(entry, duration, now) {
  var deadline = Number((entry || {}).deadline || 0)
  if (isFinite(deadline) && deadline > 0) return Number(now) >= deadline
  var lifetime = Number(duration || 0)
  if (!isFinite(lifetime) || lifetime <= 0) return false
  return (Number(now) - Number((entry || {}).timestamp || 0)) >= lifetime
}

function popupPlacement(barPosition, barClearance, gapsOut) {
  var position = String(barPosition || "top")
  var clearance = Number(barClearance)
  var gap = Number(gapsOut)
  if (!isFinite(clearance)) clearance = 0
  if (!isFinite(gap)) gap = 0

  return {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: {
      top: position === "top" ? clearance : gap,
      bottom: gap,
      left: gap,
      right: position === "right" ? clearance : gap
    }
  }
}

function historyRows(raw, liveRows, normalUrgency, limit) {
  var max = limit === undefined || limit === null ? 10 : Number(limit)
  if (isNaN(max)) max = 10
  max = Math.min(NOTIFICATION_LIMITS.maxHistoryEntries, Math.max(0, max))

  var out = []
  var seen = {}
  function collect(rows) {
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i]
      if (!entry || Number(entry.originalId) < 0) continue
      // Live and archived snapshots can overlap while a persistence job is queued.
      var key = popupFileName(entry)
      if (seen[key]) continue
      seen[key] = true
      out.push(historyDisplayEntry(entry, normalUrgency))
    }
  }

  collect(Array.isArray(liveRows) ? liveRows : [])
  collect(parsePopupFiles(raw, normalUrgency))
  out.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return out.slice(0, max)
}

function historyActionAvailable(entry, liveRef, liveGeneration) {
  if (!entry || !liveRef || Number(entry.timestamp) !== Number(liveGeneration)) return false
  var actions = liveRef.actions
  if (!isActionList(actions)) return false
  var limit = Math.min(actions.length, NOTIFICATION_LIMITS.maxActions)
  for (var i = 0; i < limit; i++) {
    if (actions[i] && String(actions[i].identifier || "") === "default") return true
  }
  return false
}

function historyActionIdentity(entry) {
  var value = entry || {}
  return String(value.timestamp || 0) + "-" + String(value.originalId || value.id || 0)
}

function historyActionRetryAllowed(entry, failedIdentities) {
  var failed = failedIdentities && typeof failedIdentities === "object" ? failedIdentities : {}
  return failed[historyActionIdentity(entry)] !== true
}

function historyReadAccepted(open, requestGeneration, currentGeneration) {
  return open === true && Number(requestGeneration) === Number(currentGeneration)
}

function historyReadTransition(raw, liveRows, normalUrgency, limit, open, requestGeneration, currentGeneration) {
  if (!historyReadAccepted(open, requestGeneration, currentGeneration))
    return { accepted: false, rows: null }
  return {
    accepted: true,
    rows: historyRows(raw, liveRows, normalUrgency, limit),
  }
}

function historyActionTransition(entry, failedIdentities, transition) {
  var next = {}
  var source = failedIdentities && typeof failedIdentities === "object" ? failedIdentities : {}
  for (var key in source) {
    if (Object.prototype.hasOwnProperty.call(source, key) && source[key] === true) next[key] = true
  }

  var identity = historyActionIdentity(entry)
  if (transition === "failed") next[identity] = true
  else if (transition === "ended") delete next[identity]
  return { identity: identity, allowed: next[identity] !== true, failedIdentities: next }
}

function latestHistoryRow(raw, normalUrgency) {
  var entries = parsePopupFiles(raw, normalUrgency)
  for (var i = 0; i < entries.length; i++) {
    if (Number(entries[i].originalId) >= 0) return historyEntry(entries[i], normalUrgency)
  }
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    limits: limits,
    boundedText: boundedText,
    normalizeImageSource: normalizeImageSource,
    normalizeAppIconSource: normalizeAppIconSource,
    isChromiumDerived: isChromiumDerived,
    sanitizeBody: sanitizeBody,
    normalizeRoute: normalizeRoute,
    normalizeLease: normalizeLease,
    shouldBypassDnd: shouldBypassDnd,
    isEphemeral: isEphemeral,
    cueGlyph: cueGlyph,
    deckProjection: deckProjection,
    deckOpacityProjection: deckOpacityProjection,
    closingOwnershipInitialState: closingOwnershipInitialState,
    closingOwnershipTransition: closingOwnershipTransition,
    releaseTrackedNotification: releaseTrackedNotification,
    actionCloseNeedsGuard: actionCloseNeedsGuard,
    actionCloseInitialState: actionCloseInitialState,
    actionCloseTransition: actionCloseTransition,
    actionMetadata: actionMetadata,
    actionOutcome: actionOutcome,
    normalizedExpireTimeout: normalizedExpireTimeout,
    requestedDuration: requestedDuration,
    durationFor: durationFor,
    deadlineFor: deadlineFor,
    deadlineForReceipt: deadlineForReceipt,
    remainingLifetime: remainingLifetime,
    popupIdentity: popupIdentity,
    popupQueuePriority: popupQueuePriority,
    popupActiveCritical: popupActiveCritical,
    popupQueueOrder: popupQueueOrder,
    popupQueueOrderSeed: popupQueueOrderSeed,
    popupArrivalPlan: popupArrivalPlan,
    sortPopupQueue: sortPopupQueue,
    consumeRemainingLifetime: consumeRemainingLifetime,
    restoredRemainingLifetime: restoredRemainingLifetime,
    migratePopupQueue: migratePopupQueue,
    shouldPersistPopup: shouldPersistPopup,
    nextMonotonicTimestamp: nextMonotonicTimestamp,
    withPopupTiming: withPopupTiming,
    restorePopupTiming: restorePopupTiming,
    restorePopupPlan: restorePopupPlan,
    replacementBookkeeping: replacementBookkeeping,
    canAdmitPopup: canAdmitPopup,
    transitionCallbackEvent: transitionCallbackEvent,
    persistenceQueueUpdate: persistenceQueueUpdate,
    refreshScheduleUpdate: refreshScheduleUpdate,
    admissionUpdate: admissionUpdate,
    snapshotOf: snapshotOf,
    popupRoles: popupRoles,
    actionsEqual: actionsEqual,
    popupRowChanged: popupRowChanged,
    replacementSnapshot: replacementSnapshot,
    historyEntry: historyEntry,
    parseSettings: parseSettings,
    historyActionAvailable: historyActionAvailable,
    historyActionIdentity: historyActionIdentity,
    historyActionRetryAllowed: historyActionRetryAllowed,
    historyReadAccepted: historyReadAccepted,
    historyReadTransition: historyReadTransition,
    historyActionTransition: historyActionTransition,
    historyRows: historyRows,
    popupEntry: popupEntry,
    popupFileName: popupFileName,
    imageStem: imageStem,
    localImageFile: localImageFile,
    persistablePopup: persistablePopup,
    serializePopup: serializePopup,
    parsePopupFiles: parsePopupFiles,
    latestHistoryRow: latestHistoryRow,
    popupExpired: popupExpired,
    popupPlacement: popupPlacement
  }
}
