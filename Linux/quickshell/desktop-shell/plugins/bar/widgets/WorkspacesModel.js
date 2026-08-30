function objectModelValues(values) {
  if (Array.isArray(values)) return values.slice()
  if (!values || typeof values !== "object") return []

  return Object.keys(values)
    .filter(key => /^\d+$/.test(key))
    .sort((left, right) => Number(left) - Number(right))
    .map(key => values[key])
    .filter(value => value !== null && value !== undefined)
}

function activeWorkspaceId(monitors, screenName) {
  var values = objectModelValues(monitors)
  for (var i = 0; i < values.length; i++) {
    var monitor = values[i]
    if (!monitor || String(monitor.name || "") !== String(screenName || "")) continue
    var active = monitor.activeWorkspace
    var id = active ? Number(active.id) : -1
    return Number.isInteger(id) && id > 0 ? id : -1
  }
  return -1
}

function confirmedActiveWorkspaceId(previousId, monitors, screenName) {
  var id = activeWorkspaceId(monitors, screenName)
  return id > 0 ? id : previousId
}

if (typeof module !== "undefined") {
  module.exports = { objectModelValues, activeWorkspaceId, confirmedActiveWorkspaceId }
}
