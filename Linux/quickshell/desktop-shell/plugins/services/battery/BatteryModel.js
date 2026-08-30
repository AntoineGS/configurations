function batteryPercentage(status) {
  if (typeof status === "number") {
    return isFinite(status) && status >= 0 && status <= 100 ? Math.round(status) : -1
  }
  var match = String(status || "").match(/([0-9]{1,3})%/)
  if (!match) return -1
  return Math.max(0, Math.min(100, Number(match[1])))
}

function isDischarging(onBattery) {
  return onBattery === true
}

function isPluggedIn(onBattery) {
  return onBattery === false
}

function warningState(status, onBattery, lowThreshold, criticalThreshold, lowNotified, criticalNotified) {
  var level = batteryPercentage(status)
  var lowSent = lowNotified === true
  var criticalSent = criticalNotified === true

  if (isPluggedIn(onBattery)) {
    return { level: level, notify: false, urgency: "", lowNotified: false, criticalNotified: false }
  }
  if (!isDischarging(onBattery) || level < 0) {
    return {
      level: level,
      notify: false,
      urgency: "",
      lowNotified: lowSent,
      criticalNotified: criticalSent
    }
  }
  if (level <= criticalThreshold) {
    return {
      level: level,
      notify: !criticalSent,
      urgency: "critical",
      lowNotified: true,
      criticalNotified: true
    }
  }
  if (level <= lowThreshold) {
    return {
      level: level,
      notify: !lowSent,
      urgency: "normal",
      lowNotified: true,
      criticalNotified: criticalSent
    }
  }

  return {
    level: level,
    notify: false,
    urgency: "",
    lowNotified: lowSent,
    criticalNotified: criticalSent
  }
}

function warningDeliveryTransition(state, event, result) {
  var current = state || {}
  var next = {
    active: current.active || null,
    queued: current.queued || null,
    processRunning: current.processRunning === true
  }
  var committed = null
  var action = ""
  var reset = false

  if (event === "warning") {
    if (result && result.notify === true) {
      if (next.active || next.processRunning) next.queued = result
      else {
        next.active = result
        action = "send"
      }
    } else {
      next.queued = null
    }
  } else if (event === "started") {
    next.processRunning = true
  } else if (event === "success") {
    if (next.active) committed = {
      lowNotified: next.active.lowNotified,
      criticalNotified: next.active.criticalNotified
    }
    next.active = null
    next.processRunning = false
    if (next.queued) action = "retry"
  } else if (event === "failure") {
    next.active = null
    next.processRunning = false
    if (next.queued) action = "retry"
  } else if (event === "ac-reset") {
    next.active = null
    next.queued = null
    reset = true
  }

  return { state: next, committed: committed, action: action, reset: reset }
}

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    isPluggedIn: isPluggedIn,
    warningState: warningState,
    warningDeliveryTransition: warningDeliveryTransition
  }
}
