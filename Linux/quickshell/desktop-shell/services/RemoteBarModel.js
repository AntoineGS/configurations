function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function parseSnapshot(raw, expectedHost) {
  try {
    var value = typeof raw === "string" ? JSON.parse(raw) : raw
    if (!isPlainObject(value) || value.schemaVersion !== 1) return null
    if (typeof value.host !== "string" || value.host === "") return null
    if (expectedHost && value.host !== expectedHost) return null
    if (typeof value.publishedAt !== "number" || !isFinite(value.publishedAt) || value.publishedAt <= 0) return null
    if (!isPlainObject(value.widgets)) return null
    return value
  } catch (_) {
    return null
  }
}

function freshness(snapshot, nowSeconds, receivedAtSeconds, staleAfterSeconds, offlineAfterSeconds) {
  if (!snapshot) return { state: "offline", ageSeconds: -1 }
  var age
  if (typeof snapshot.servedAt === "number" && isFinite(snapshot.servedAt)
      && typeof receivedAtSeconds === "number" && isFinite(receivedAtSeconds)) {
    age = Math.max(0, Math.floor(snapshot.servedAt - snapshot.publishedAt))
      + Math.max(0, Math.floor(Number(nowSeconds) - receivedAtSeconds))
  } else {
    age = Math.max(0, Math.floor(Number(nowSeconds) - Number(snapshot.publishedAt)))
  }
  if (!isFinite(age)) return { state: "offline", ageSeconds: -1 }
  if (age >= Number(offlineAfterSeconds)) return { state: "offline", ageSeconds: age }
  if (age >= Number(staleAfterSeconds)) return { state: "stale", ageSeconds: age }
  return { state: "fresh", ageSeconds: age }
}

function widget(snapshot, name) {
  if (!snapshot || !isPlainObject(snapshot.widgets)) return ({})
  var value = snapshot.widgets[name]
  return isPlainObject(value) ? value : ({})
}

if (typeof module !== "undefined") {
  module.exports = {
    parseSnapshot: parseSnapshot,
    freshness: freshness,
    widget: widget,
  }
}
