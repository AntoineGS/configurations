function parseEmojis(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

function normalizedQuery(query) {
  return String(query || "").trim().toLowerCase()
}

function keywordText(item) {
  return String((item && item.k) || "").toLowerCase()
}

function filterEmojis(emojis, query, limit) {
  var values = Array.isArray(emojis) ? emojis : []
  var needle = normalizedQuery(query)
  var max = limit === undefined || limit === null ? 1000 : Number(limit)
  if (isNaN(max)) max = 1000
  max = Math.max(0, max)
  if (max === 0) return []

  var out = []
  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (!item || !item.e) continue
    if (!needle || keywordText(item).indexOf(needle) >= 0) {
      out.push(item)
      if (out.length >= max) break
    }
  }
  return out
}

function normalizeRecentEmojis(values, limit) {
  var source = Array.isArray(values) ? values : []
  var max = Number(limit)
  if (isNaN(max)) max = 8
  max = Math.max(0, max)

  var out = []
  for (var i = 0; i < source.length && out.length < max; i++) {
    var emoji = typeof source[i] === "string" ? source[i] : ""
    if (emoji && out.indexOf(emoji) < 0) out.push(emoji)
  }
  return out
}

function parseRecentEmojis(raw, limit) {
  try {
    return normalizeRecentEmojis(JSON.parse(String(raw || "")), limit)
  } catch (e) {
    return []
  }
}

function addRecentEmoji(values, emoji, limit) {
  return normalizeRecentEmojis([emoji].concat(Array.isArray(values) ? values : []), limit)
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEmojis: parseEmojis,
    normalizedQuery: normalizedQuery,
    filterEmojis: filterEmojis,
    parseRecentEmojis: parseRecentEmojis,
    addRecentEmoji: addRecentEmoji
  }
}
