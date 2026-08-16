function filterIPv4(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  for (var i = 0; i < ips.length; i++) {
    var ip = String(ips[i] || "")
    if (/^100\./.test(ip)) result.push(ip)
  }
  return result
}

function filterIPv6(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  for (var i = 0; i < ips.length; i++) {
    var ip = String(ips[i] || "")
    if (/^fd7a:115c:a1e0:/i.test(ip)) result.push(ip)
  }
  return result
}

function cleanDnsName(name) {
  var value = String(name || "")
  return value.charAt(value.length - 1) === "." ? value.slice(0, -1) : value
}

function displayHostName(hostName, dnsName) {
  var host = String(hostName || "")
  if (host !== "" && host.toLowerCase() !== "localhost") return host
  var dns = cleanDnsName(dnsName)
  return dns.split(".")[0] || host || "Unknown"
}

function osIcon(os) {
  var value = String(os || "").toLowerCase()
  if (value === "linux") return "󰌽"
  if (value === "macos" || value === "ios") return "󰀵"
  if (value === "windows") return "󰍲"
  if (value === "android") return "󰀲"
  return "󰟀"
}

function parseState(raw) {
  try {
    var envelope = JSON.parse(String(raw || ""))
    if (!envelope || typeof envelope !== "object" || !envelope.data || typeof envelope.data !== "object") return null
    var data = envelope.data
    return {
      available: envelope.available === true,
      stale: envelope.stale === true,
      error: envelope.error ? String(envelope.error) : "",
      backendState: String(data.backendState || "Unknown"),
      running: data.running === true,
      needsLogin: data.needsLogin === true,
      self: data.self || {},
      peers: Array.isArray(data.peers) ? data.peers : []
    }
  } catch (error) {
    return null
  }
}

function peerAddress(peer) {
  if (!peer) return ""
  var addresses = filterIPv4(peer.addresses || [])
  if (addresses.length > 0) return addresses[0]
  return String(peer.dnsName || peer.name || "")
}

function peerLabel(peer) {
  return peer ? displayHostName(peer.name, peer.dnsName) : "Unknown"
}

if (typeof module !== "undefined") {
  module.exports = {
    filterIPv4: filterIPv4,
    filterIPv6: filterIPv6,
    cleanDnsName: cleanDnsName,
    displayHostName: displayHostName,
    osIcon: osIcon,
    parseState: parseState,
    peerAddress: peerAddress,
    peerLabel: peerLabel
  }
}
