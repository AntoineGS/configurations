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

function limits() {
  var result = {}
  for (var key in NOTIFICATION_LIMITS) result[key] = NOTIFICATION_LIMITS[key]
  return result
}

function boundedText(value, maxLength) {
  var text = value === undefined || value === null ? "" : String(value)
  return text.slice(0, maxLength)
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
    refreshedAt: null,
    expiresAt: null,
    routeUpdatedAt: null,
    error: String(error || "invalid lease")
  }
}

function validRouteOutput(value) {
  return value === null || value === undefined ||
    value === "DVI-D-1" || value === "HDMI-A-1" || value === "DP-2"
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
  if (parsed.version !== 1) return invalidLease("unsupported lease version")
  if (typeof nowMs !== "number" || !isFinite(nowMs)) return invalidLease("current time is invalid")

  var refreshedAt = parsed.refreshedAt
  var expiresAt = parsed.expiresAt
  var routeUpdatedAt = parsed.routeUpdatedAt
  if (typeof refreshedAt !== "number" || !isFinite(refreshedAt) || Math.floor(refreshedAt) !== refreshedAt || refreshedAt < 0)
    return invalidLease("lease refreshedAt is invalid")
  if (typeof expiresAt !== "number" || !isFinite(expiresAt) || Math.floor(expiresAt) !== expiresAt || expiresAt < 0)
    return invalidLease("lease expiresAt is invalid")
  if (typeof routeUpdatedAt !== "number" || !isFinite(routeUpdatedAt) || Math.floor(routeUpdatedAt) !== routeUpdatedAt || routeUpdatedAt < 0)
    return invalidLease("lease routeUpdatedAt is invalid")

  var current = Math.floor(nowMs / 1000)
  if (refreshedAt > current) return invalidLease("lease refreshedAt is from the future")
  if (expiresAt <= current) return invalidLease("lease is stale")
  if (expiresAt > current + 1) return invalidLease("lease expires too far in the future")
  if (expiresAt - refreshedAt > 1) return invalidLease("lease expires too long after refresh")

  if (typeof expectedRouteUpdatedAt !== "number" || !isFinite(expectedRouteUpdatedAt) ||
      Math.floor(expectedRouteUpdatedAt) !== expectedRouteUpdatedAt || expectedRouteUpdatedAt < 0)
    return invalidLease("expected route timestamp is invalid")
  if (routeUpdatedAt !== expectedRouteUpdatedAt) return invalidLease("lease route timestamp does not match route")

  return {
    valid: true,
    refreshedAt: refreshedAt,
    expiresAt: expiresAt,
    routeUpdatedAt: routeUpdatedAt,
    error: ""
  }
}

function snapshotOf(notification, timestamp) {
  var n = notification || {}
  var id = n.id || 0
  var expireTimeout = normalizedExpireTimeout(n.expireTimeout)
  var image = boundedText(n.image, NOTIFICATION_LIMITS.maxImageLength)
  var hintedImage = imagePathHint(n)
  if (!image || (image.indexOf("image://") === 0 && hintedImage)) image = hintedImage || image
  var result = {
    // The timestamp-plus-originalId file stem distinguishes generations that reuse an id.
    id: id,
    originalId: id,
    app: boundedText(n.appName, NOTIFICATION_LIMITS.maxAppLength),
    appIcon: boundedText(n.appIcon, NOTIFICATION_LIMITS.maxAppLength),
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

var POPUP_ROLES = ["app", "appIcon", "summary", "body", "image", "urgency", "expireTimeout", "deadline", "transient", "actions"]

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
    return value === undefined || value === null ? "" : boundedText(value, NOTIFICATION_LIMITS.maxImageLength)
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
    appIcon: boundedText(e.appIcon, NOTIFICATION_LIMITS.maxAppLength),
    summary: boundedText(e.summary, NOTIFICATION_LIMITS.maxSummaryLength),
    body: boundedText(e.body, NOTIFICATION_LIMITS.maxBodyLength),
    image: boundedText(e.image, NOTIFICATION_LIMITS.maxImageLength),
    urgency: typeof e.urgency === "number" ? e.urgency : normalUrgency,
    expireTimeout: 0,
    timestamp: e.timestamp || 0,
    actions: [],
  }
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

  var deadline = Number((value || {}).deadline || 0)
  if (isFinite(deadline) && deadline > 0) entry.deadline = deadline
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
  var s = String(value || "")
  if (s.indexOf("file://") === 0) {
    s = s.slice(7)
    try { s = decodeURIComponent(s) } catch (e) {}
  }
  return s.charAt(0) === "/" && s.length <= NOTIFICATION_LIMITS.maxImageLength ? s : ""
}

function persistablePopup(entry, imagesDir) {
  var e = entry || {}
  var out = {}
  for (var key in e) out[key] = e[key]
  var copies = []
  for (var i = 0; i < PERSISTED_IMAGE_ROLES.length; i++) {
    var role = PERSISTED_IMAGE_ROLES[i]
    var value = boundedText(out[role], NOTIFICATION_LIMITS.maxImageLength)
    out[role] = value
    if (!value) continue
    var source = localImageFile(value)
    if (source) {
      var copy = String(imagesDir || "") + imageStem(e) + "-" + role
      if (source !== copy) copies.push({ from: source, to: copy })
      out[role] = "file://" + copy
    } else if (value.indexOf("image://") === 0) {
      out[role] = ""
    }
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
      if (!entry) continue
      // Live and archived snapshots can overlap while a persistence job is queued.
      var key = popupFileName(entry)
      if (seen[key]) continue
      seen[key] = true
      out.push(historyEntry(entry, normalUrgency))
    }
  }

  collect(Array.isArray(liveRows) ? liveRows : [])
  collect(parsePopupFiles(raw, normalUrgency))
  out.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return out.slice(0, max)
}

function latestHistoryRow(raw, normalUrgency) {
  var entries = parsePopupFiles(raw, normalUrgency)
  return entries.length > 0 ? historyEntry(entries[0], normalUrgency) : null
}

if (typeof module !== "undefined") {
  module.exports = {
    limits: limits,
    boundedText: boundedText,
    isChromiumDerived: isChromiumDerived,
    sanitizeBody: sanitizeBody,
    normalizeRoute: normalizeRoute,
    normalizeLease: normalizeLease,
    shouldBypassDnd: shouldBypassDnd,
    isEphemeral: isEphemeral,
    cueGlyph: cueGlyph,
    actionMetadata: actionMetadata,
    actionOutcome: actionOutcome,
    normalizedExpireTimeout: normalizedExpireTimeout,
    requestedDuration: requestedDuration,
    durationFor: durationFor,
    deadlineFor: deadlineFor,
    remainingLifetime: remainingLifetime,
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
