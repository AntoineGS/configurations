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

function batteryBarIcon(percent, state, onBattery) {
  return isFullyCharged(percent, state, onBattery) ? "󰚥" : batteryIcon(percent, state)
}

function batteryBarValue(percent, state, onBattery) {
  if (isFullyCharged(percent, state, onBattery)) return ""
  if (isCharging(state)) return percent + "%"
  if (isPluggedIn(onBattery)) return "󰚥"
  return percent + "%"
}

function batteryBarValueIsIcon(percent, state, onBattery) {
  return !isFullyCharged(percent, state, onBattery) && !isCharging(state) && isPluggedIn(onBattery)
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

function profileNames(hasPerformanceProfile) {
  return hasPerformanceProfile ? ["power-saver", "balanced", "performance"] : ["power-saver", "balanced"]
}

function nativeBatteryPercent(available, ratio) {
  var value = Number(ratio)
  return available && isFinite(value) && value >= 0 && value <= 1 ? Math.round(value * 100) : -1
}

function nativeBatteryState(state) {
  return ["unknown", "charging", "discharging", "empty", "fully-charged", "pending-charge", "pending-discharge"][
    Number(state)
  ] || "unknown"
}

function nativeProfileName(profile) {
  return ["power-saver", "balanced", "performance"][Number(profile)] || ""
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
    batteryBarIcon: batteryBarIcon,
    batteryBarValue: batteryBarValue,
    batteryBarValueIsIcon: batteryBarValueIsIcon,
    modeLabel: modeLabel,
    parseState: parseState,
    profileIcon: profileIcon,
    profileNames: profileNames,
    nativeBatteryPercent: nativeBatteryPercent,
    nativeBatteryState: nativeBatteryState,
    nativeProfileName: nativeProfileName
  }
}
