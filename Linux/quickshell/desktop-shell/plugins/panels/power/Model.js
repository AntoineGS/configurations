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

function isCharging(status) {
  var value = String(status || "").toLowerCase()
  return value.indexOf("charging") !== -1 && value.indexOf("discharging") === -1
}

function batteryIcon(percent, status) {
  var value = Number(percent)
  if (!isFinite(value) || value < 0) return "󰂑"

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(value / 10)))
  return isCharging(status) ? chargingIcons[index] : defaultIcons[index]
}

function modeLabel(status) {
  var value = String(status || "")
  if (/fully charged/i.test(value)) return "Fully charged"
  if (/charging/i.test(value) && !/discharging/i.test(value)) return "Charging"
  if (/discharging/i.test(value)) return "On battery"
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
    isCharging: isCharging,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel,
    parseState: parseState,
    profileIcon: profileIcon
  }
}
