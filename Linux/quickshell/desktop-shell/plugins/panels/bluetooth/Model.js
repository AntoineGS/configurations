var LOW_BATTERY_THRESHOLD = 30

function deviceLabel(device) {
  if (!device) return ""
  return String(device.deviceName || device.name || "").trim()
}

function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()

  var length = Number(values.length || 0)
  if (!isFinite(length) || length <= 0) return []

  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

function batteryPercent(value) {
  if (typeof value !== "number" || !isFinite(value)) return null
  var rounded = Math.round(value)
  return rounded >= 0 && rounded <= 100 ? rounded : null
}

function parseBatteryState(raw) {
  try {
    var envelope = typeof raw === "string" ? JSON.parse(raw) : raw
    if (!envelope || envelope.available !== true || envelope.stale === true
        || !envelope.data || !envelope.data.devices || Array.isArray(envelope.data.devices)) return {}
    var devices = {}
    for (var path in envelope.data.devices) {
      var source = envelope.data.devices[path]
      if (!source || typeof source !== "object" || Array.isArray(source)) continue
      devices[path] = {
        central: batteryPercent(source.central),
        peripheral: batteryPercent(source.peripheral)
      }
    }
    return devices
  } catch (error) {
    return {}
  }
}

function batteryValues(device, supplementalDevices) {
  var path = String(device && device.dbusPath || "")
  var supplemental = supplementalDevices && supplementalDevices[path] || {}
  var central = batteryPercent(supplemental.central)
  var peripheral = batteryPercent(supplemental.peripheral)
  if (central === null && device && device.batteryAvailable)
    central = batteryPercent(Number(device.battery) * 100)
  return { central: central, peripheral: peripheral }
}

function isLowBattery(value) {
  var percent = batteryPercent(value)
  return percent !== null && percent < LOW_BATTERY_THRESHOLD
}

function hasLowBattery(devices, supplementalDevices) {
  var values = toArray(devices)
  for (var i = 0; i < values.length; i++) {
    var batteries = batteryValues(values[i], supplementalDevices)
    if (isLowBattery(batteries.central) || isLowBattery(batteries.peripheral)) return true
  }
  return false
}

function escapeHtml(value) {
  return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}

function formattedPercent(value, warningColor) {
  var text = batteryPercent(value) + "%"
  return isLowBattery(value)
    ? '<span style="color: ' + escapeHtml(warningColor) + ';">' + text + "</span>"
    : text
}

function batteryStatus(values, warningColor) {
  if (values.central !== null && values.peripheral !== null)
    return "Central " + formattedPercent(values.central, warningColor)
    + " · Peripheral " + formattedPercent(values.peripheral, warningColor)
  if (values.central !== null) return "Battery " + formattedPercent(values.central, warningColor)
  if (values.peripheral !== null) return "Peripheral " + formattedPercent(values.peripheral, warningColor)
  return "Connected"
}

function batteryTooltip(devices, supplementalDevices, warningColor) {
  var list = toArray(devices)
  var blocks = []
  for (var i = 0; i < list.length; i++) {
    var device = list[i]
    var values = batteryValues(device, supplementalDevices)
    var lines = ["<span>" + escapeHtml(deviceLabel(device) || "Device") + "</span>"]
    if (values.central !== null && values.peripheral !== null) {
      lines.push("Central: " + formattedPercent(values.central, warningColor))
      lines.push("Peripheral: " + formattedPercent(values.peripheral, warningColor))
    } else if (values.central !== null) {
      lines.push("Battery: " + formattedPercent(values.central, warningColor))
    } else if (values.peripheral !== null) {
      lines.push("Peripheral: " + formattedPercent(values.peripheral, warningColor))
    } else {
      lines.push("Connected")
    }
    blocks.push(lines.join("\n"))
  }
  return blocks.join("\n\n")
}

function isUuidLike(value) {
  var text = String(value || "").trim()
  if (text === "") return false
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
    || /^[0-9a-f]{32}$/i.test(text)
    || /^0x[0-9a-f]{4,32}$/i.test(text)
}

function isAddressLike(value) {
  var text = String(value || "").trim()
  return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text)
}

function hasHumanName(device) {
  var label = deviceLabel(device)
  return label !== "" && !isUuidLike(label) && !isAddressLike(label)
}

function sortedByLabel(devices) {
  var list = toArray(devices)
  list.sort(function(a, b) { return deviceLabel(a).localeCompare(deviceLabel(b)) })
  return list
}

function deviceRow(device, supplementalDevices, warningColor) {
  if (!device) return null
  var values = batteryValues(device, supplementalDevices)
  return {
    address: String(device.address || ""),
    name: String(device.name || ""),
    deviceName: String(device.deviceName || ""),
    connected: !!device.connected,
    paired: !!(device.paired || device.bonded || device.trusted),
    state: device.state !== undefined ? device.state : -1,
    batteryAvailable: !!device.batteryAvailable,
    battery: device.battery !== undefined ? device.battery : 0,
    pairing: !!device.pairing,
    dbusPath: String(device.dbusPath || ""),
    batteryValues: values,
    batteryStatus: batteryStatus(values, warningColor)
  }
}

function deviceLists(devices) {
  var values = toArray(devices)
  var connected = []
  var known = []
  var discovered = []

  for (var i = 0; i < values.length; i++) {
    var device = values[i]
    if (!device || !hasHumanName(device)) continue
    if (device.connected) connected.push(device)
    else if (device.paired || device.bonded || device.trusted) known.push(device)
    else discovered.push(device)
  }

  return {
    connected: sortedByLabel(connected),
    known: sortedByLabel(known),
    discovered: sortedByLabel(discovered)
  }
}

function cloneMap(map) {
  var next = ({})
  for (var key in map || {}) next[key] = map[key]
  return next
}

function pendingAction(actions, address) {
  return address && actions && actions[address] ? actions[address] : ""
}

function withPendingAction(actions, address, action) {
  var next = cloneMap(actions)
  if (!address) return next
  if (action) next[address] = action
  else delete next[address]
  return next
}

function visibleSections(lists, discovering) {
  var sections = []
  if (lists && lists.connected && lists.connected.length > 0) sections.push("connected")
  if (lists && lists.known && lists.known.length > 0) sections.push("known")
  if (discovering && lists && lists.discovered && lists.discovered.length > 0) sections.push("discovered")
  return sections
}

function sectionDevices(lists, section) {
  if (!lists) return []
  if (section === "connected") return lists.connected || []
  if (section === "known") return lists.known || []
  if (section === "discovered") return lists.discovered || []
  return []
}

if (typeof module !== "undefined") {
  module.exports = {
    deviceLabel: deviceLabel,
    toArray: toArray,
    parseBatteryState: parseBatteryState,
    batteryValues: batteryValues,
    isLowBattery: isLowBattery,
    hasLowBattery: hasLowBattery,
    batteryStatus: batteryStatus,
    batteryTooltip: batteryTooltip,
    isUuidLike: isUuidLike,
    isAddressLike: isAddressLike,
    hasHumanName: hasHumanName,
    sortedByLabel: sortedByLabel,
    deviceRow: deviceRow,
    deviceLists: deviceLists,
    cloneMap: cloneMap,
    pendingAction: pendingAction,
    withPendingAction: withPendingAction,
    visibleSections: visibleSections,
    sectionDevices: sectionDevices
  }
}
