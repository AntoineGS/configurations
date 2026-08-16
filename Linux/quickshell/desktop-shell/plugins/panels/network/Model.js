function wifiIconFor(strength) {
  var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
  var value = Number(strength)
  if (!isFinite(value)) value = 0
  var index = Math.max(0, Math.min(4, Math.ceil(value / 20) - 1))
  return icons[index]
}

function connectionIcon(kind, signalStrength) {
  if (kind === "wifi") return wifiIconFor(signalStrength)
  if (kind === "ethernet") return "󰈀"
  return "󰤮"
}

function wifiRow(network) {
  if (!network) return null
  var signal = Number(network.signalStrength || 0)
  if (signal <= 1) signal *= 100
  signal = Math.max(0, Math.min(100, Math.round(signal)))
  return {
    connected: !!network.connected,
    known: !!network.known,
    ssid: String(network.name || ""),
    signal: signal,
    security: network.security
  }
}

function sortWifiRows(rows) {
  var networks = Array.isArray(rows) ? rows.slice() : []
  networks.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    if (a.known !== b.known) return a.known ? -1 : 1
    return b.signal - a.signal
  })
  return networks
}

function wifiSectionTitle(networks, index) {
  if (!Array.isArray(networks) || index < 0 || index >= networks.length) return ""
  var network = networks[index]
  if (!network) return ""
  if (network.known && index === 0) return "KNOWN NETWORKS"
  if (!network.known && (index === 0 || (networks[index - 1] && networks[index - 1].known)))
    return "OTHER NETWORKS"
  return ""
}

function isProtected(security, openSecurity) {
  return security !== openSecurity
}

if (typeof module !== "undefined") {
  module.exports = {
    wifiIconFor: wifiIconFor,
    connectionIcon: connectionIcon,
    wifiRow: wifiRow,
    sortWifiRows: sortWifiRows,
    wifiSectionTitle: wifiSectionTitle,
    isProtected: isProtected
  }
}
