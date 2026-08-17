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

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    displayIcon: displayIcon,
    parseState: parseState,
    enabledDisplayCount: enabledDisplayCount
  }
}
