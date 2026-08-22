function hasValue(values, key) {
  var value = values[key]
  return typeof value === "string" && value.length > 0
}

function alpha(value, fallback) {
  if (typeof value !== "string" || value.length === 0) return fallback
  var number = Number(value)
  return isFinite(number) ? Math.max(0, Math.min(1, number)) : fallback
}

function inheritedPick(values, section, key, baseSection, fallback) {
  var ownKey = section + "." + key
  var baseKey = baseSection + "." + key
  return hasValue(values, ownKey) ? values[ownKey] : (hasValue(values, baseKey) ? values[baseKey] : fallback)
}

function inheritedAlpha(values, section, key, baseSection, fallback) {
  var ownKey = section + "." + key
  var baseKey = baseSection + "." + key
  if (hasValue(values, ownKey)) return alpha(values[ownKey], fallback)
  return hasValue(values, baseKey) ? alpha(values[baseKey], fallback) : fallback
}

function surfaceBase(section) {
  return section === "notifications" || section === "tooltip" || section === "bar-panels" ? "cards" : ""
}

function surfaceValue(values, section, key) {
  var ownKey = section + "." + key
  if (hasValue(values, ownKey)) return values[ownKey]
  var base = surfaceBase(section)
  return base.length > 0 && hasValue(values, base + "." + key) ? values[base + "." + key] : ""
}

function surfaceValueOr(values, section, keys) {
  for (var i = 0; i < keys.length; i++) {
    var ownKey = section + "." + keys[i]
    if (hasValue(values, ownKey)) return values[ownKey]
  }
  var base = surfaceBase(section)
  for (var j = 0; j < keys.length; j++) {
    var baseKey = base + "." + keys[j]
    if (base.length > 0 && hasValue(values, baseKey)) return values[baseKey]
  }
  return ""
}

function surfaceAlpha(values, section, key, fallback) {
  var raw = surfaceValue(values, section, key)
  return String(raw).length === 0 ? fallback : alpha(raw, fallback)
}

if (typeof module !== "undefined") {
  module.exports = {
    inheritedPick: inheritedPick,
    inheritedAlpha: inheritedAlpha,
    surfaceBase: surfaceBase,
    surfaceValue: surfaceValue,
    surfaceValueOr: surfaceValueOr,
    surfaceAlpha: surfaceAlpha,
  }
}
