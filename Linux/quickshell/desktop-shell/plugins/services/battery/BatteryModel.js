function batteryPercentage(status) {
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

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    isPluggedIn: isPluggedIn,
    warningState: warningState
  }
}
