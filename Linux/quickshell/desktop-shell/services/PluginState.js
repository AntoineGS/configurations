var ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/
var SECTIONS = ["left", "center", "right"]

function clone(value) {
  return JSON.parse(JSON.stringify(value === undefined ? null : value))
}

function emptyState() {
  return { version: 1 }
}

function isThirdPartyId(id) {
  var value = String(id || "")
  return ID_PATTERN.test(value)
    && value.indexOf("..") === -1
    && value.indexOf("desktop.") !== 0
    && value.indexOf("omarchy.") !== 0
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function hasOnly(object, fields) {
  return Object.keys(object).every(function (key) { return fields.indexOf(key) !== -1 })
}

function validateIdList(items, seen) {
  if (!Array.isArray(items)) return "enabledPlugins must be an array"
  for (var item of items) {
    if (!isPlainObject(item) || !hasOnly(item, ["id"]) || !isThirdPartyId(item.id))
      return "invalid enabled plugin"
    if (seen[item.id]) return "duplicate plugin id: " + item.id
    seen[item.id] = true
  }
  return ""
}

function validateState(state) {
  if (!isPlainObject(state) || state.version !== 1)
    return "plugin state version must be 1"
  if (!hasOnly(state, ["version", "enabledPlugins", "barWidgets", "barPluginId"]))
    return "unknown plugin state field"

  var seen = {}
  var error = ""
  if (state.enabledPlugins !== undefined) error = validateIdList(state.enabledPlugins, seen)
  if (error) return error
  if (state.barPluginId !== undefined) {
    if (!isThirdPartyId(state.barPluginId) || seen[state.barPluginId]) return "invalid or duplicate bar plugin id"
    seen[state.barPluginId] = true
  }
  if (state.barWidgets !== undefined) {
    if (!Array.isArray(state.barWidgets)) return "barWidgets must be an array"
    for (var widget of state.barWidgets) {
      if (!isPlainObject(widget) || !hasOnly(widget, ["id", "section", "index", "settings"]))
        return "invalid bar widget"
      if (!isThirdPartyId(widget.id) || seen[widget.id]) return "invalid or duplicate widget id"
      if (SECTIONS.indexOf(widget.section) === -1 || !Number.isInteger(widget.index) || widget.index < 0)
        return "invalid widget placement"
      if (widget.settings !== undefined && !isPlainObject(widget.settings)) return "widget settings must be an object"
      seen[widget.id] = true
    }
  }
  return ""
}

function normalizeState(state) {
  var next = emptyState()
  if (state.enabledPlugins && state.enabledPlugins.length)
    next.enabledPlugins = state.enabledPlugins.map(function (plugin) { return { id: plugin.id } })
  if (state.barWidgets && state.barWidgets.length)
    next.barWidgets = state.barWidgets.map(function (widget) {
      var result = { id: widget.id, section: widget.section, index: widget.index }
      if (widget.settings && Object.keys(widget.settings).length) result.settings = clone(widget.settings)
      return result
    })
  if (state.barPluginId !== undefined) next.barPluginId = state.barPluginId
  return next
}

function parseState(raw) {
  if (raw === undefined || raw === null || String(raw).trim() === "")
    return { valid: true, state: emptyState(), error: "" }
  try {
    var state = JSON.parse(String(raw))
    var error = validateState(state)
    return error
      ? { valid: false, state: emptyState(), error: error }
      : { valid: true, state: normalizeState(state), error: "" }
  } catch (error) {
    return { valid: false, state: emptyState(), error: "invalid plugin state JSON: " + error }
  }
}

function layoutFor(config, section) {
  var layout = config && config.bar && config.bar.layout
  return layout && Array.isArray(layout[section]) ? layout[section] : []
}

function widgetValue(widget) {
  var value = { id: widget.id }
  if (widget.settings) Object.keys(widget.settings).forEach(function (key) {
    if (key !== "id") value[key] = clone(widget.settings[key])
  })
  return value
}

function mergeConfig(defaultConfig, state) {
  var effective = clone(defaultConfig || {})
  effective.plugins = Array.isArray(effective.plugins) ? effective.plugins : []
  effective.bar = effective.bar || {}
  effective.bar.layout = effective.bar.layout || {}
  SECTIONS.forEach(function (section) {
    effective.bar.layout[section] = Array.isArray(effective.bar.layout[section])
      ? effective.bar.layout[section].map(clone) : []
  })
  var current = normalizeState(state || emptyState())
  ;(current.enabledPlugins || []).forEach(function (plugin) { effective.plugins.push(clone(plugin)) })
  var inserted = { left: [], center: [], right: [] }
  ;(current.barWidgets || []).forEach(function (widget) {
    var list = effective.bar.layout[widget.section]
    var offset = inserted[widget.section].filter(function (index) { return index <= widget.index }).length
    var index = Math.min(widget.index + offset, list.length)
    list.splice(index, 0, widgetValue(widget))
    inserted[widget.section].push(widget.index)
  })
  if (current.barPluginId !== undefined) effective.bar.id = current.barPluginId
  return effective
}

function success(state) { return { ok: true, state: state, error: "" } }
function failure(state, error) { return { ok: false, state: clone(state), error: error } }

function placementFor(manifest, placement) {
  var section = placement && placement.section
  if (!section && manifest.barWidget) section = manifest.barWidget.defaultSection
  if (!section) section = "center"
  if (SECTIONS.indexOf(section) === -1) return null
  return { section: section, index: Number.isInteger(placement && placement.index) ? placement.index : 0 }
}

function upsertEnabledPlugin(state, id) {
  state.enabledPlugins = state.enabledPlugins || []
  if (!state.enabledPlugins.some(function (plugin) { return plugin.id === id })) state.enabledPlugins.push({ id: id })
  return state
}

function upsertWidget(state, manifest, placement, effectiveConfig) {
  var position = placementFor(manifest, placement)
  if (!position) return null
  var existing = (state.barWidgets || []).find(function (widget) { return widget.id === manifest.id })
  var remaining = (state.barWidgets || []).filter(function (widget) { return widget.id !== manifest.id })
  var limit = layoutFor(effectiveConfig, position.section).length + remaining.filter(function (widget) {
    return widget.section === position.section
  }).length
  var index = Math.max(0, Math.min(position.index, limit))
  if (existing && existing.section === position.section && existing.index === index) return state
  state.barWidgets = remaining
  state.barWidgets.push({
    id: manifest.id,
    section: position.section,
    index: index,
    settings: existing && existing.settings ? clone(existing.settings) : {},
  })
  return state
}

function removeId(state, id) {
  if (state.enabledPlugins) state.enabledPlugins = state.enabledPlugins.filter(function (plugin) { return plugin.id !== id })
  if (state.barWidgets) state.barWidgets = state.barWidgets.filter(function (widget) { return widget.id !== id })
  if (state.barPluginId === id) delete state.barPluginId
  return normalizeState(state)
}

function setEnabled(state, manifest, enabled, placement, effectiveConfig) {
  var next = clone(state)
  var id = String(manifest && manifest.id || "")
  var kinds = Array.isArray(manifest && manifest.kinds) ? manifest.kinds : []
  if (manifest && manifest.__isFirstParty) {
    if (enabled && id === "desktop.bar") {
      delete next.barPluginId
      return success(normalizeState(next))
    }
    return failure(state, "first-party plugin state is repository-managed")
  }
  if (!isThirdPartyId(id)) return failure(state, "invalid third-party plugin id")
  if (!enabled) return success(removeId(next, id))
  if (kinds.indexOf("bar") !== -1) {
    next.barPluginId = id
    return success(normalizeState(next))
  }
  if (kinds.indexOf("bar-widget") !== -1) {
    if (placement && placement.headless === true) {
      if (manifest.keepLoaded !== true) return failure(state, "headless bar widget must set keepLoaded")
      next = removeId(next, id)
      next = upsertEnabledPlugin(next, id)
    } else {
      next.enabledPlugins = (next.enabledPlugins || []).filter(function (plugin) { return plugin.id !== id })
      next = upsertWidget(normalizeState(next), manifest, placement || {}, effectiveConfig || {})
      if (!next) return failure(state, "invalid widget placement")
    }
  } else next = upsertEnabledPlugin(next, id)
  return success(normalizeState(next))
}

function moveWidget(state, id, placement, effectiveConfig) {
  var next = clone(state)
  var widget = (next.barWidgets || []).find(function (item) { return item.id === id })
  var position = placementFor({}, placement || {})
  if (!widget) return failure(state, "widget is not enabled")
  if (!position) return failure(state, "invalid widget placement")
  widget.section = position.section
  widget.index = Math.max(0, Math.min(position.index, layoutFor(effectiveConfig, position.section).length + next.barWidgets.length - 1))
  return success(normalizeState(next))
}

function setWidget(state, id, key, value) {
  var next = clone(state)
  var widget = (next.barWidgets || []).find(function (item) { return item.id === id })
  if (!widget || typeof key !== "string" || key === "id") return failure(state, "widget is not enabled")
  widget.settings = widget.settings || {}
  if (value === undefined) delete widget.settings[key]
  else widget.settings[key] = clone(value)
  return success(normalizeState(next))
}

function inBar(state, id) {
  return !!(state && state.barWidgets && state.barWidgets.some(function (widget) { return widget.id === id }))
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyState: emptyState,
    parseState: parseState,
    mergeConfig: mergeConfig,
    setEnabled: setEnabled,
    moveWidget: moveWidget,
    setWidget: setWidget,
    inBar: inBar,
  }
}
