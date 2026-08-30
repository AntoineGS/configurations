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
    next.actionQueue.push(args)
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
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    displayIcon: displayIcon,
    parseState: parseState,
    enabledDisplayCount: enabledDisplayCount,
    normalizeMonitors: normalizeMonitors,
    monitorOperationState: monitorOperationState,
    monitorOperationTransition: monitorOperationTransition,
    brightnessState: brightnessState,
    shouldRefreshNativeMonitors: shouldRefreshNativeMonitors
  }
}
