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
  return String((notification && notification.appName) || "") === "notify-send"
    && notification && notification.urgency === criticalUrgency
}

function isEphemeral(notification) {
  var hints = notification && notification.hints
  return !!(hints && hints.transient)
    || String((notification && notification.appName) || "") === "notify-send"
}

function invalidRoute(error) {
  return {
    valid: false,
    visible: false,
    output: null,
    cueOutput: null,
    direction: null,
    error: String(error || "invalid route")
  }
}

function validRouteOutput(value) {
  return value === null || value === undefined ||
    (typeof value === "string" && /^[A-Za-z0-9_.-]+$/.test(value))
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
 * @returns {{valid: boolean, visible: boolean, output: (string|null), cueOutput: (string|null), direction: (string|null), error: string}}
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
    error: ""
  }
}

function snapshotOf(notification, timestamp) {
  var n = notification || {}
  var id = n.id || 0
  var expireTimeout = Number(n.expireTimeout || 0)
  if (!isFinite(expireTimeout) || expireTimeout < 0) expireTimeout = 0
  var image = String(n.image || "")
  var hintedImage = imagePathHint(n)
  if (!image || (image.indexOf("image://") === 0 && hintedImage)) image = hintedImage || image
  return {
    // The timestamp-plus-originalId file stem distinguishes generations that reuse an id.
    id: id,
    originalId: id,
    app: n.appName || "",
    appIcon: n.appIcon || "",
    summary: String(n.summary || ""),
    body: n.body || "",
    image: image,
    urgency: n.urgency,
    expireTimeout: expireTimeout,
    timestamp: timestamp === undefined ? Date.now() : timestamp
  }
}

var POPUP_ROLES = ["app", "appIcon", "summary", "body", "image", "urgency", "expireTimeout"]

function popupRoles() {
  return POPUP_ROLES
}

function popupRowChanged(row, updated) {
  var current = row || {}
  var next = updated || {}
  for (var i = 0; i < POPUP_ROLES.length; i++) {
    var role = POPUP_ROLES[i]
    if (current[role] !== next[role]) return true
  }
  return false
}

function imagePathHint(notification) {
  try {
    var hints = notification && notification.hints
    var value = hints && hints["image-path"]
    return value === undefined || value === null ? "" : String(value)
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
    app: e.app || "",
    appIcon: e.appIcon || "",
    summary: e.summary || "",
    body: e.body || "",
    image: e.image || "",
    urgency: typeof e.urgency === "number" ? e.urgency : normalUrgency,
    expireTimeout: 0,
    timestamp: e.timestamp || 0
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
  var expire = Number((value || {}).expireTimeout || 0)
  if (!isFinite(expire) || expire < 0) expire = 0
  entry.expireTimeout = expire

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
  return s.charAt(0) === "/" ? s : ""
}

function persistablePopup(entry, imagesDir) {
  var e = entry || {}
  var out = {}
  for (var key in e) out[key] = e[key]
  var copies = []
  for (var i = 0; i < PERSISTED_IMAGE_ROLES.length; i++) {
    var role = PERSISTED_IMAGE_ROLES[i]
    var value = String(out[role] || "")
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
  return { entry: out, copies: copies }
}

function serializePopup(entry, normalUrgency) {
  return JSON.stringify(popupEntry(entry, normalUrgency))
}

function parsePopupFiles(raw, normalUrgency) {
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
  return entries
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
  max = Math.max(0, max)

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
    isChromiumDerived: isChromiumDerived,
    sanitizeBody: sanitizeBody,
    normalizeRoute: normalizeRoute,
    shouldBypassDnd: shouldBypassDnd,
    isEphemeral: isEphemeral,
    snapshotOf: snapshotOf,
    popupRoles: popupRoles,
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
