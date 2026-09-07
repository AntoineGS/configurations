function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function displayIcon(count) {
  return Number(count) > 1 ? "󰍺" : "󰍹"
}

function parseState(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || typeof parsed !== "object" || !parsed.data || typeof parsed.data !== "object") return null
    return parsed
  } catch (error) {
    return null
  }
}

function enabledDisplayCount(displays) {
  var count = 0
  var values = Array.isArray(displays) ? displays : []
  for (var i = 0; i < values.length; i++) if (values[i] && values[i].enabled) count++
  return count
}

function normalizeMonitors(monitors, focusedMonitor) {
  var values = Array.isArray(monitors) ? monitors : []
  if (!Array.isArray(monitors) && monitors && typeof monitors === "object") {
    var keys = Object.keys(monitors).filter(function(key) { return /^\d+$/.test(key) })
    keys.sort(function(a, b) { return Number(a) - Number(b) })
    values = keys.map(function(key) { return monitors[key] })
  }
  var focusedName = focusedMonitor && typeof focusedMonitor.name === "string" ? focusedMonitor.name : ""
  var normalized = []

  for (var i = 0; i < values.length; i++) {
    var monitor = values[i] || {}
    var name = typeof monitor.name === "string" ? monitor.name : ""
    if (!name) continue
    var ipc = monitor.lastIpcObject && typeof monitor.lastIpcObject === "object" ? monitor.lastIpcObject : {}
    normalized.push({
      name: name,
      description: typeof monitor.description === "string" ? monitor.description : "",
      width: typeof monitor.width === "number" ? monitor.width : 0,
      height: typeof monitor.height === "number" ? monitor.height : 0,
      scale: typeof monitor.scale === "number" ? monitor.scale : 1,
      focused: name === focusedName,
      enabled: true,
      mirrorOf: typeof ipc.mirrorOf === "string" ? ipc.mirrorOf : "none"
    })
  }

  var internalMonitor = ""
  for (var j = 0; j < normalized.length; j++) {
    if (/^(eDP|LVDS|DSI)-/i.test(normalized[j].name)) {
      internalMonitor = normalized[j].name
      break
    }
  }

  var internalEnabled = false
  var mirrorEnabled = false
  for (var m = 0; m < normalized.length; m++) {
    var display = normalized[m]
    if (display.name === internalMonitor && display.enabled) internalEnabled = true
    if (internalMonitor && display.enabled && display.mirrorOf === internalMonitor) mirrorEnabled = true
  }

  return {
    monitors: normalized,
    focusedMonitor: focusedName,
    internalMonitor: internalMonitor,
    internalEnabled: internalEnabled,
    mirrorEnabled: mirrorEnabled
  }
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function isInteger(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
}

function isValidConnector(connector) {
  return typeof connector === "string" && /^[A-Za-z0-9_.:-]+$/.test(connector)
}

function isValidHash(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value)
}

function isValidEdid(value) {
  if (typeof value !== "string" || !/^[0-9a-f]{256}$/.test(value)
      || value.slice(0, 16) !== "00ffffffffffff00") return false
  var checksum = 0
  for (var i = 0; i < value.length; i += 2) checksum = (checksum + parseInt(value.slice(i, i + 2), 16)) % 256
  return checksum === 0
}

function isInternalConnector(connector) {
  return /^(eDP|LVDS|DSI)-/i.test(String(connector || ""))
}

function isSafeBus(value) {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]*)$/.test(value) || value.length > 15) return false
  var numeric = Number(value)
  return isFinite(numeric) && Math.floor(numeric) === numeric && numeric <= 9007199254740991
}

function isSafeBacklight(value) {
  return typeof value === "string" && value !== "." && value !== ".." && /^[A-Za-z0-9_.+-]+$/.test(value)
}

function sha256Hex(value) {
  var text = String(value)
  var bytes = []
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code < 0x80) bytes.push(code)
    else if (code < 0x800) bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f))
    else bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f))
  }
  var bitLength = bytes.length * 8
  bytes.push(0x80)
  while ((bytes.length + 8) % 64 !== 0) bytes.push(0)
  for (var lengthShift = 56; lengthShift >= 0; lengthShift -= 8)
    bytes.push(Math.floor(bitLength / Math.pow(2, lengthShift)) & 0xff)

  var constants = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]
  var hash = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
  var rotateRight = function(value, bits) { return (value >>> bits) | (value << (32 - bits)) }
  var choose = function(x, y, z) { return (x & y) ^ (~x & z) }
  var majority = function(x, y, z) { return (x & y) ^ (x & z) ^ (y & z) }
  var sigma0 = function(x) { return rotateRight(x, 2) ^ rotateRight(x, 13) ^ rotateRight(x, 22) }
  var sigma1 = function(x) { return rotateRight(x, 6) ^ rotateRight(x, 11) ^ rotateRight(x, 25) }
  var gamma0 = function(x) { return rotateRight(x, 7) ^ rotateRight(x, 18) ^ (x >>> 3) }
  var gamma1 = function(x) { return rotateRight(x, 17) ^ rotateRight(x, 19) ^ (x >>> 10) }

  for (var offset = 0; offset < bytes.length; offset += 64) {
    var schedule = []
    for (var word = 0; word < 16; word++) {
      var position = offset + word * 4
      schedule[word] = ((bytes[position] << 24) | (bytes[position + 1] << 16)
        | (bytes[position + 2] << 8) | bytes[position + 3]) | 0
    }
    for (var extended = 16; extended < 64; extended++)
      schedule[extended] = (gamma1(schedule[extended - 2]) + schedule[extended - 7]
        + gamma0(schedule[extended - 15]) + schedule[extended - 16]) | 0
    var working = hash.slice()
    for (var round = 0; round < 64; round++) {
      var temporary1 = (working[7] + sigma1(working[4]) + choose(working[4], working[5], working[6])
        + constants[round] + schedule[round]) | 0
      var temporary2 = (sigma0(working[0]) + majority(working[0], working[1], working[2])) | 0
      working = [(temporary1 + temporary2) | 0, working[0], working[1], working[2],
        (working[3] + temporary1) | 0, working[4], working[5], working[6]]
    }
    for (var result = 0; result < 8; result++) hash[result] = (hash[result] + working[result]) | 0
  }

  return hash.map(function(value) {
    var unsigned = value >>> 0
    return ("00000000" + unsigned.toString(16)).slice(-8)
  }).join("")
}

function copyBrightnessRecord(record) {
  if (!isObject(record)) return record
  var copy = Object.assign({}, record)
  if (isObject(record.selector)) copy.selector = Object.assign({}, record.selector)
  return copy
}

function unavailableBrightnessRecord(connector, error, previous) {
  var fallback = {
    connector: isValidConnector(connector) ? connector : "",
    backend: isInternalConnector(connector) ? "backlight" : "ddc",
    available: false,
    stale: false,
    error: String(error || "Brightness unavailable"),
    current: null,
    maximum: null,
    percent: null,
    identity: "",
    topology: "",
    edid: "",
    selector: null
  }
  if (isObject(previous) && isValidConnector(connector)) {
    var stale = copyBrightnessRecord(previous)
    stale.connector = connector
    stale.available = false
    stale.stale = true
    stale.error = fallback.error
    return stale
  }
  return fallback
}

function validMeasurement(record) {
  if (!isInteger(record.current) || record.current < 0) return false
  if (!isInteger(record.maximum) || record.maximum <= 0 || record.current > record.maximum) return false
  if (!isInteger(record.percent) || record.percent < 0 || record.percent > 100) return false
  return record.percent === Math.max(0, Math.min(100, Math.round(record.current * 100 / record.maximum)))
}

function validSelector(record) {
  if (!isObject(record.selector)) return false
  if (typeof record.selector.kind !== "string" || typeof record.selector.value !== "string") return false
  if (record.backend === "backlight") {
    return isInternalConnector(record.connector)
      && record.selector.kind === "backlight" && isSafeBacklight(record.selector.value)
  }
  if (record.backend !== "ddc") return false
  if (record.selector.kind === "bus") return isSafeBus(record.selector.value)
  return record.selector.kind === "edid"
    && record.selector.value === record.edid && isValidEdid(record.edid)
}

function isValidBrightnessTarget(record) {
  return isObject(record)
    && isValidConnector(record.connector)
    && (record.backend === "backlight" || record.backend === "ddc")
    && record.available === true
    && record.stale === false
    && record.error === ""
    && validMeasurement(record)
    && isValidHash(record.identity)
    && isValidHash(record.topology)
    && isValidEdid(record.edid)
    && validSelector(record)
    && record.identity === sha256Hex([
      record.connector, record.backend, record.edid, record.topology,
      record.selector.kind, record.selector.value
    ].join("\n"))
}

function isValidBrightnessRecord(record, connector, topology) {
  if (!isObject(record) || record.connector !== connector
      || (record.backend !== "backlight" && record.backend !== "ddc")
      || typeof record.error !== "string") return false
  var emptyMeasurement = record.current === null && record.maximum === null && record.percent === null
  if (record.available === true)
    return record.stale === false && record.topology === topology && isValidBrightnessTarget(record)
  if (record.stale === true) {
    if (record.identity === "" && record.topology === "" && record.edid === "" && record.selector === null)
      return emptyMeasurement
    return isValidHash(record.identity) && isValidHash(record.topology) && isValidEdid(record.edid)
      && validMeasurement(record) && validSelector(record)
      && record.identity === sha256Hex([
        record.connector, record.backend, record.edid, record.topology,
        record.selector.kind, record.selector.value
      ].join("\n"))
  }
  if (record.topology !== "" && record.topology !== topology) return false
  if (record.stale !== false) return false
  if (!emptyMeasurement) return false
  if (record.identity === "" && record.selector === null) return record.edid === "" || isValidEdid(record.edid)
  return isValidHash(record.identity) && isValidEdid(record.edid) && validSelector(record)
    && record.identity === sha256Hex([
      record.connector, record.backend, record.edid, record.topology,
      record.selector.kind, record.selector.value
    ].join("\n"))
}

function normalizeBrightnessRecord(record, connector, topology, previous) {
  var fallbackError = "Invalid brightness record"
  if (!isValidConnector(connector) || !isObject(record) || record.connector !== connector) {
    return unavailableBrightnessRecord(connector, fallbackError, previous)
  }

  var normalized = copyBrightnessRecord(record)
  var common = (normalized.backend === "backlight" || normalized.backend === "ddc")
    && typeof normalized.available === "boolean"
    && typeof normalized.stale === "boolean"
    && typeof normalized.error === "string"
  if (!common) return unavailableBrightnessRecord(connector, fallbackError, previous)

  if (!isValidBrightnessRecord(normalized, connector, topology))
    return unavailableBrightnessRecord(connector, fallbackError, previous)
  return normalized
}

function validBrightnessSnapshotTopLevel(snapshot, allowEmptyTopology) {
  return isObject(snapshot)
    && snapshot.version === 1
    && isObject(snapshot.monitors)
    && (isValidHash(snapshot.topology)
      || (allowEmptyTopology === true && snapshot.topology === "" && Object.keys(snapshot.monitors).length === 0))
}

function normalizeSnapshotOnly(snapshot, allowEmptyTopology, previous) {
  if (!validBrightnessSnapshotTopLevel(snapshot, allowEmptyTopology)) return null
  var normalized = { version: 1, topology: snapshot.topology, monitors: {} }
  var previousMonitors = isObject(previous) && isObject(previous.monitors) ? previous.monitors : null
  var keys = Object.keys(snapshot.monitors)
  for (var i = 0; i < keys.length; i++) {
    var connector = keys[i]
    if (!isValidConnector(connector)) continue
    normalized.monitors[connector] = normalizeBrightnessRecord(
      snapshot.monitors[connector], connector, snapshot.topology,
      previousMonitors && Object.prototype.hasOwnProperty.call(previousMonitors, connector)
        ? previousMonitors[connector] : null)
  }
  return normalized
}

function staleBrightnessRecord(connector, record, error) {
  var stale = copyBrightnessRecord(record)
  if (!isObject(stale) || stale.connector !== connector
      || (stale.available === true && !isValidBrightnessTarget(stale)))
    stale = unavailableBrightnessRecord(connector, error)
  stale.available = false
  stale.stale = true
  stale.error = String(error || "Monitor topology changed")
  return stale
}

function invalidateBrightnessSnapshot(snapshot, error) {
  var normalized = normalizeSnapshotOnly(snapshot, true)
  if (!normalized) return { version: 1, topology: "", monitors: {} }
  var invalidated = { version: 1, topology: normalized.topology, monitors: {} }
  var keys = Object.keys(normalized.monitors)
  for (var i = 0; i < keys.length; i++) {
    var connector = keys[i]
    invalidated.monitors[connector] = staleBrightnessRecord(
      connector, normalized.monitors[connector], error || "Brightness snapshot is stale")
  }
  return invalidated
}

function normalizeBrightnessSnapshot(snapshot, previous) {
  var requestedConnector = arguments.length > 2 ? arguments[2] : ""
  var previousNormalized = normalizeSnapshotOnly(previous, true)
  var incoming = normalizeSnapshotOnly(snapshot, false, previousNormalized)
  if (!incoming) {
    return {
      snapshot: previousNormalized
        ? invalidateBrightnessSnapshot(previousNormalized, "Invalid brightness snapshot")
        : { version: 1, topology: "", monitors: {} },
      valid: false,
      topologyChanged: false,
      incomingSnapshot: null,
      requestedRecord: null,
      requestedRecordValid: false
    }
  }

  if (incoming.topology === "" && previousNormalized && previousNormalized.topology !== "") {
    return {
      snapshot: invalidateBrightnessSnapshot(previousNormalized, "Brightness snapshot is unavailable"),
      valid: false,
      topologyChanged: false,
      incomingSnapshot: incoming,
      requestedRecord: null,
      requestedRecordValid: false
    }
  }

  var incomingValid = validBrightnessSnapshotRecords(snapshot, incoming)
  var partial = isValidConnector(requestedConnector)
  var requestedSource = partial && Object.prototype.hasOwnProperty.call(snapshot.monitors, requestedConnector)
    ? snapshot.monitors[requestedConnector] : null
  var requestedRecord = partial && Object.prototype.hasOwnProperty.call(incoming.monitors, requestedConnector)
    ? incoming.monitors[requestedConnector] : null
  var requestedRecordValid = partial && requestedSource !== null
    && isValidBrightnessRecord(requestedSource, requestedConnector, incoming.topology)
    && isValidBrightnessTarget(requestedRecord)
  var topologyChanged = !!previousNormalized
    && previousNormalized.topology !== ""
    && incoming.topology !== ""
    && previousNormalized.topology !== incoming.topology
  var merged = { version: 1, topology: incoming.topology, monitors: {} }
  var previousKeys = previousNormalized ? Object.keys(previousNormalized.monitors) : []
  var incomingKeys = Object.keys(incoming.monitors)

  if (!partial) {
    merged = incoming
  } else if (!topologyChanged && previousNormalized) {
    for (var p = 0; p < previousKeys.length; p++) {
      var previousConnector = previousKeys[p]
      merged.monitors[previousConnector] = previousNormalized.monitors[previousConnector]
    }
  } else if (topologyChanged && previousNormalized) {
    for (var s = 0; s < previousKeys.length; s++) {
      var staleConnector = previousKeys[s]
      if (!Object.prototype.hasOwnProperty.call(incoming.monitors, staleConnector)) {
        merged.monitors[staleConnector] = staleBrightnessRecord(
          staleConnector, previousNormalized.monitors[staleConnector], "Monitor topology changed")
      }
    }
  }
  for (var i = 0; i < incomingKeys.length; i++) {
    var connector = incomingKeys[i]
    merged.monitors[connector] = incoming.monitors[connector]
  }

  return {
    snapshot: merged,
    valid: incomingValid && (!partial || requestedRecordValid),
    topologyChanged: topologyChanged,
    incomingSnapshot: incoming,
    requestedRecord: requestedRecord,
    requestedRecordValid: requestedRecordValid
  }
}

function validBrightnessSnapshotRecords(source, normalized) {
  if (!isObject(source) || !isObject(normalized)) return false
  var keys = Object.keys(source.monitors)
  for (var i = 0; i < keys.length; i++) {
    var connector = keys[i]
    if (!isValidConnector(connector) || !Object.prototype.hasOwnProperty.call(normalized.monitors, connector)
        || !isValidBrightnessRecord(source.monitors[connector], connector, source.topology)) return false
  }
  return true
}

function mergeBrightnessSnapshot(previous, incoming, requestedConnector) {
  return normalizeBrightnessSnapshot(incoming, previous, requestedConnector)
}

function brightnessFor(snapshot, connector) {
  if (!isValidConnector(connector) || !validBrightnessSnapshotTopLevel(snapshot, true))
    return unavailableBrightnessRecord(connector, "Brightness unavailable")
  var record = snapshot.monitors[connector]
  if (!isObject(record)) return unavailableBrightnessRecord(connector, "Brightness unavailable")
  return normalizeBrightnessRecord(record, connector, snapshot.topology)
}

function brightnessActionTarget(args) {
  if (!Array.isArray(args) || args.length !== 4
      || args[0] !== "monitor" || args[1] !== "set-display-brightness") return null
  if (typeof args[2] !== "string" || !/^([1-9]|[1-9][0-9]|100)$/.test(args[2])) return null
  var target
  try {
    target = JSON.parse(String(args[3]))
  } catch (error) {
    return null
  }
  if (!isValidBrightnessTarget(target)) return null
  return { connector: target.connector, identity: target.identity, topology: target.topology, record: target }
}

function brightnessActionConnector(args) {
  if (!Array.isArray(args) || args.length !== 4
      || args[0] !== "monitor" || args[1] !== "set-display-brightness") return ""
  try {
    var target = JSON.parse(String(args[3]))
    return isObject(target) && isValidConnector(target.connector) ? target.connector : ""
  } catch (error) {
    return ""
  }
}

function queueMonitorAction(queue, args) {
  var next = Array.isArray(queue) ? queue.slice() : []
  var latest = brightnessActionTarget(args)
  if (!latest) {
    next.push(args)
    return next
  }

  for (var i = next.length - 1; i >= 0; i--) {
    var previous = brightnessActionTarget(next[i])
    if (!previous) break
    if (previous.connector === latest.connector && previous.identity === latest.identity) {
      next[i] = args
      return next
    }
  }
  next.push(args)
  return next
}

function monitorOperationState() {
  return {
    actionRunning: false,
    reconciliationRunning: false,
    reconciliationQueued: false,
    actionQueue: [],
    postActionQueued: false
  }
}

function monitorOperationTransition(state, event, args) {
  var next = Object.assign({}, state)
  next.actionQueue = Array.isArray(state.actionQueue) ? state.actionQueue.slice() : []
  var result = { state: next, startAction: null, startReconciliation: false }
  if (event === "reconcile-request") {
    if (next.actionRunning || next.reconciliationRunning) next.reconciliationQueued = true
    else {
      next.postActionQueued = false
      next.reconciliationRunning = true
      result.startReconciliation = true
    }
  } else if (event === "action-request") {
    next.actionQueue = queueMonitorAction(next.actionQueue, args)
    if (!next.actionRunning && !next.reconciliationRunning) {
      next.actionRunning = true
      result.startAction = next.actionQueue.shift()
    }
  } else if (event === "reconcile-finished") {
    next.reconciliationRunning = false
    if (next.actionQueue.length > 0) {
      next.actionRunning = true
      next.reconciliationQueued = false
      result.startAction = next.actionQueue.shift()
    } else if (next.reconciliationQueued || next.postActionQueued) {
      next.reconciliationQueued = false
      next.postActionQueued = false
      next.reconciliationRunning = true
      result.startReconciliation = true
    }
  } else if (event === "reconcile-cancelled") {
    next.reconciliationRunning = false
    if (next.actionQueue.length > 0) {
      next.actionRunning = true
      next.reconciliationQueued = false
      result.startAction = next.actionQueue.shift()
    } else if (next.reconciliationQueued || next.postActionQueued) {
      next.reconciliationQueued = false
      next.postActionQueued = false
      next.reconciliationRunning = true
      result.startReconciliation = true
    }
  } else if (event === "action-finished") {
    next.actionRunning = false
    next.reconciliationQueued = false
    next.postActionQueued = true
  }
  return result
}

function brightnessState(current, brightness, keyboardBrightness) {
  var next = Object.assign({}, current)
  if (brightness && brightness.available === true) {
    next.lastConfirmedBrightnessPercent = clampBrightness(brightness.percent)
    next.brightnessPercent = next.lastConfirmedBrightnessPercent
  } else next.brightnessPercent = next.lastConfirmedBrightnessPercent
  if (brightness) next.brightness = brightness
  if (keyboardBrightness) next.keyboardBrightness = keyboardBrightness
  return next
}

function shouldRefreshNativeMonitors(action) {
  return action === "toggle-internal" || action === "toggle-mirror"
    || action === "set-scale" || action === "set-layout"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    displayIcon: displayIcon,
    parseState: parseState,
    enabledDisplayCount: enabledDisplayCount,
    normalizeMonitors: normalizeMonitors,
    isValidConnector: isValidConnector,
    isValidEdid: isValidEdid,
    isValidBrightnessTarget: isValidBrightnessTarget,
    normalizeBrightnessRecord: normalizeBrightnessRecord,
    validBrightnessSnapshotTopLevel: validBrightnessSnapshotTopLevel,
    normalizeBrightnessSnapshot: normalizeBrightnessSnapshot,
    mergeBrightnessSnapshot: mergeBrightnessSnapshot,
    invalidateBrightnessSnapshot: invalidateBrightnessSnapshot,
    brightnessFor: brightnessFor,
    brightnessActionTarget: brightnessActionTarget,
    brightnessActionConnector: brightnessActionConnector,
    queueMonitorAction: queueMonitorAction,
    monitorOperationState: monitorOperationState,
    monitorOperationTransition: monitorOperationTransition,
    brightnessState: brightnessState,
    shouldRefreshNativeMonitors: shouldRefreshNativeMonitors
  }
}
