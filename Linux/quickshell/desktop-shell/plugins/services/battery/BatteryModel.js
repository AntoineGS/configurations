function batteryPercentage(status) {
  var match = String(status || "").match(/([0-9]{1,3})%/)
  if (!match) return -1
  return Math.max(0, Math.min(100, Number(match[1])))
}

function isDischarging(status) {
  var value = String(status || "").toLowerCase()
  return value.indexOf("discharging") !== -1 || value.indexOf("on battery") !== -1
}

function shouldWarnLowBattery(status, threshold, alreadyNotified) {
  var level = batteryPercentage(status)
  if (level < 0) return { level: level, notify: false, notifiedLowBattery: false }

  var low = isDischarging(status) && level <= threshold
  return {
    level: level,
    notify: low && !alreadyNotified,
    notifiedLowBattery: low
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    shouldWarnLowBattery: shouldWarnLowBattery
  }
}
