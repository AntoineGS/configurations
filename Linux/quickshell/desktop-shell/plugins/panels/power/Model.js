function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function batteryPercentage(status) {
  var match = String(status || "").match(/([0-9]{1,3})%/)
  if (!match) return -1
  return Math.max(0, Math.min(100, Number(match[1])))
}

function normalizedBatteryState(state) {
  return String(state || "").trim().toLowerCase()
}

function isCharging(state) {
  var value = normalizedBatteryState(state)
  return value === "charging" || value === "pending-charge"
}

function isPluggedIn(onBattery) {
  return onBattery === false
}

function isFullyCharged(percent, state, onBattery) {
  return isPluggedIn(onBattery)
    && (normalizedBatteryState(state) === "fully-charged" || Number(percent) >= 100)
}

function batteryIcon(percent, state) {
  var value = Number(percent)
  if (!isFinite(value) || value < 0) return "󰂑"

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(value / 10)))
  return isCharging(state) ? chargingIcons[index] : defaultIcons[index]
}

function batteryBarText(percent, state, onBattery) {
  if (isFullyCharged(percent, state, onBattery)) return "󰚥"
  if (isPluggedIn(onBattery)) return batteryIcon(percent, state) + " 󰚥"
  return batteryIcon(percent, state) + " " + percent + "%"
}

function batteryBarSlots(percent, state, onBattery) {
  return isFullyCharged(percent, state, onBattery) ? 1 : 2
}

function modeLabel(state) {
  var value = normalizedBatteryState(state)
  if (value === "fully-charged") return "Fully charged"
  if (isCharging(value)) return "Charging"
  if (value === "discharging" || value === "pending-discharge") return "On battery"
  return "Battery"
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

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    batteryPercentage: batteryPercentage,
    normalizedBatteryState: normalizedBatteryState,
    isCharging: isCharging,
    isPluggedIn: isPluggedIn,
    isFullyCharged: isFullyCharged,
    batteryIcon: batteryIcon,
    batteryBarText: batteryBarText,
    batteryBarSlots: batteryBarSlots,
    modeLabel: modeLabel,
    parseState: parseState,
    profileIcon: profileIcon
  }
}
