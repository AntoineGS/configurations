function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function stripJsonc(raw) {
  return String(raw || "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

function normalizeAliases(value) {
  if (Array.isArray(value)) return value.filter(function(item) { return item !== null && item !== "" }).map(String)
  if (typeof value === "string" && value) return [value]
  return []
}

function isOpaqueActionId(value) {
  return /^[a-z0-9]+(?:[.-][a-z0-9][a-z0-9-]*)+$/.test(String(value || ""))
}

function conditionValue(value, fallback) {
  return typeof value === "boolean" ? value : fallback
}

function normalizeItem(id, raw) {
  var value = isPlainObject(raw) ? raw : ({})
  var key = String(id || "")
  var parent = typeof value.parent === "string"
    ? value.parent
    : (key.indexOf(".") >= 0 ? key.split(".").slice(0, -1).join(".") : "root")
  if (key === "root") parent = ""

  var requestedAction = typeof value.action === "string" ? value.action : ""
  var action = isOpaqueActionId(requestedAction) ? requestedAction : ""
  var target = typeof value.target === "string" ? value.target : ""
  var kind = action ? "action" : (target ? "link" : "menu")

  return {
    id: key,
    parent: parent,
    kind: kind,
    icon: value.icon || "",
    iconFont: value.iconFont || "",
    label: value.label || key,
    title: value.title || "",
    target: target,
    description: value.description || "",
    action: action,
    aliases: normalizeAliases(value.aliases),
    when: conditionValue(value.when, true),
    checked: conditionValue(value.checked, false),
    disabled: conditionValue(value.disabled, false)
  }
}

function parseMenuJsoncResult(raw) {
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return { valid: false, items: [] }

  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (error) {
    return { valid: false, items: [] }
  }
  if (!isPlainObject(parsed)) return { valid: false, items: [] }

  var source = isPlainObject(parsed.items) ? parsed.items : parsed
  var out = []
  for (var id in source) {
    var entry = source[id]
    if (!isPlainObject(entry)) continue
    out.push(normalizeItem(id, entry))
  }
  return { valid: true, items: out }
}

function parseMenuJsonc(raw) {
  var result = parseMenuJsoncResult(raw)
  return result.valid ? result.items : []
}

function preserveLastValid(previous, result) {
  if (result && result.valid === true) return Array.isArray(result.items) ? result.items : []
  return Array.isArray(previous) ? previous.slice() : []
}

function mergeMenuSources(defaultItems, userItems) {
  var nextItems = ({})
  var nextOrder = []
  var sources = [defaultItems || [], userItems || []]

  for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex++) {
    var source = Array.isArray(sources[sourceIndex]) ? sources[sourceIndex] : []
    for (var i = 0; i < source.length; i++) {
      var entry = source[i]
      if (!entry || !entry.id) continue
      if (!nextItems[entry.id]) nextOrder.push(entry.id)
      var merged = {}
      var prior = nextItems[entry.id] || {}
      for (var key in prior) merged[key] = prior[key]
      for (var valueKey in entry) merged[valueKey] = entry[valueKey]
      merged.id = entry.id
      nextItems[entry.id] = merged
    }
  }

  if (!nextItems.root) {
    nextItems.root = normalizeItem("root", { label: "Control" })
    nextOrder.unshift("root")
  }
  for (var orderIndex = 0; orderIndex < nextOrder.length; orderIndex++)
    nextItems[nextOrder[orderIndex]].order = orderIndex

  return { items: nextItems, itemOrder: nextOrder }
}

function item(items, id) {
  return items && items[id] ? items[id] : null
}

function resolveRoute(items, itemOrder, input) {
  var raw = String(input || "").toLowerCase().replace(/_/g, "-")
  if (!raw || raw === "go" || raw === "menu" || raw === "root") return "root"
  if (item(items, raw)) return raw

  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(items, order[i])
    if (!entry || !entry.aliases) continue
    for (var j = 0; j < entry.aliases.length; j++) {
      var alias = String(entry.aliases[j] || "").toLowerCase().replace(/_/g, "-")
      if (alias === raw) return entry.id
    }
  }
  return raw
}

function depthFor(items, id) {
  var depth = 0
  var current = item(items, id)
  var guard = 0
  while (current && current.parent && current.parent !== "root" && guard < 32) {
    depth += 1
    current = item(items, current.parent)
    guard += 1
  }
  return depth
}

function pathFor(items, id) {
  var labels = []
  var current = item(items, id)
  var guard = 0
  while (current && current.id !== "root" && guard < 32) {
    labels.unshift(String(current.label || current.id))
    current = item(items, current.parent)
    guard += 1
  }
  return labels.join(" › ")
}

function parentPathFor(items, id) {
  var entry = item(items, id)
  if (!entry || !entry.parent || entry.parent === "root") return ""
  return pathFor(items, entry.parent)
}

function isDescendantOf(items, id, ancestorId) {
  if (ancestorId === "root") return id !== "root"
  var current = item(items, id)
  var guard = 0
  while (current && current.parent && guard < 32) {
    if (current.parent === ancestorId) return true
    current = item(items, current.parent)
    guard += 1
  }
  return false
}

function childCount(items, itemOrder, id) {
  var count = 0
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(items, order[i])
    if (entry && entry.parent === id) count += 1
  }
  return count
}

function layoutEntryId(entry) {
  if (typeof entry === "string") return entry
  if (isPlainObject(entry) && entry.id !== undefined && entry.id !== null) return String(entry.id)
  return ""
}

function hasConfiguredBarWidget(layout, widgetId) {
  if (!isPlainObject(layout)) return false
  var wanted = String(widgetId || "")
  if (!wanted) return false
  var sections = ["left", "center", "right"]
  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
    var entries = layout[sections[sectionIndex]]
    if (!Array.isArray(entries)) continue
    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      if (layoutEntryId(entries[entryIndex]) === wanted) return true
    }
  }
  return false
}

function routeVisibility(layout, routeWidgets) {
  var result = {}
  if (!isPlainObject(routeWidgets)) return result
  for (var route in routeWidgets)
    result[route] = hasConfiguredBarWidget(layout, routeWidgets[route])
  return result
}

function hasResult(results, id) {
  return !!results && Object.prototype.hasOwnProperty.call(results, id)
}

function isVisible(items, itemOrder, whenResults, entry, depth) {
  if (!entry) return false
  if (entry.when === false) return false
  if (hasResult(whenResults, entry.id) && whenResults[entry.id] === false) return false
  if (entry.kind === "action") return true
  if (entry.kind === "link") return true

  var guard = depth || 0
  if (guard >= 32) return false
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var child = item(items, order[i])
    if (child && child.parent === entry.id && isVisible(items, order, whenResults, child, guard + 1)) return true
  }
  return false
}

function isDisabled(disabledResults, entry) {
  if (!entry) return false
  if (entry.disabled === true) return true
  return hasResult(disabledResults, entry.id) && disabledResults[entry.id] === true
}

function labelFor(entry, checkedResults, disabledResults) {
  if (!entry) return ""
  var checked = entry.checked === true || (hasResult(checkedResults, entry.id) && checkedResults[entry.id] === true)
  return checked || isDisabled(disabledResults, entry) ? entry.label + " ✓" : entry.label
}

function searchableToken(value) {
  return String(value || "").replace(/[._-]+/g, " ")
}

function leafIdFor(id) {
  var parts = String(id || "").split(".")
  return parts.length > 0 ? parts[parts.length - 1] : String(id || "")
}

function nameSearchText(entry) {
  if (!entry) return ""
  var aliases = Array.isArray(entry.aliases) ? entry.aliases.map(searchableToken).join(" ") : ""
  return [entry.label, searchableToken(leafIdFor(entry.id)), aliases].join(" ").toLowerCase()
}

function termInSearchWords(term, text) {
  var words = String(text || "").toLowerCase().split(/\s+/)
  for (var i = 0; i < words.length; i++) if (words[i] === term) return true
  return false
}

function descriptionTextMatches(query, text) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termInSearchWords(terms[i], text)) return false
  }
  return true
}

function matchesQuery(entry, query, visible) {
  if (!entry || entry.id === "root" || !visible) return false
  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    var term = terms[i]
    if (!term) continue
    if (nameText.indexOf(term) >= 0) continue
    if (termInSearchWords(term, descriptionText)) continue
    return false
  }
  return true
}

function searchScore(items, entry, query) {
  var needle = String(query || "").toLowerCase().trim()
  var label = String(entry.label || "").toLowerCase()
  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var score = 80
  if (label === needle) score = entry.parent === "root" ? 2 : 0
  else if (label.indexOf(needle) === 0) score = 10
  else if (label.indexOf(needle) >= 0) score = 30
  else if (nameText.indexOf(needle) >= 0) score = 40
  else if (descriptionTextMatches(needle, descriptionText)) score = 60
  if (entry.kind === "menu" || entry.kind === "link") score -= 2
  return score * 1000 + depthFor(items, entry.id) * 25 + (entry.order || 0)
}

function displayRow(items, itemOrder, checkedResults, disabledResults, entry, detail, score, section) {
  var target = entry.kind === "link" ? entry.target : entry.id
  return {
    itemId: entry.id,
    disabled: isDisabled(disabledResults, entry),
    kind: entry.kind,
    icon: entry.icon,
    iconFont: entry.iconFont || "",
    appIcon: "",
    label: labelFor(entry, checkedResults, disabledResults),
    target: target,
    detail: detail || "",
    path: pathFor(items, entry.id),
    childCount: (entry.kind === "menu" || entry.kind === "link") ? childCount(items, itemOrder, target) : 0,
    desktopId: "",
    action: entry.action || "",
    selection: "",
    requestSerial: 0,
    score: score || 0,
    section: section || ""
  }
}

function applicationRow(entry, appLibrary, score) {
  return {
    itemId: "app:" + String((entry && entry.id) || ""),
    disabled: false,
    kind: "application",
    icon: "",
    iconFont: "",
    appIcon: String((entry && entry.icon) || ""),
    label: appLibrary.entryName(entry),
    target: "",
    detail: appLibrary.entrySubtext(entry),
    path: "",
    childCount: 0,
    desktopId: String((entry && entry.id) || ""),
    action: "",
    selection: "",
    score: 20000 - Number(score || 0),
    section: "apps"
  }
}

function calculatorRow(query, result, serial) {
  return {
    itemId: "calculator",
    disabled: false,
    kind: "calculator",
    icon: "=",
    iconFont: "",
    appIcon: "",
    label: String(result || ""),
    target: "",
    detail: String(query || ""),
    path: "",
    childCount: 0,
    desktopId: "",
    action: "",
    selection: "",
    requestSerial: Number(serial || 0),
    score: -1000,
    section: "calculator"
  }
}

function composeSearchResults(commandRows, appRows, calculatorResult) {
  var rows = []
  if (calculatorResult) rows.push(calculatorResult)
  rows = rows.concat(commandRows || [], appRows || [])
  rows.sort(function(left, right) {
    if (left.score !== right.score) return left.score - right.score
    return String(left.label).localeCompare(String(right.label))
  })
  return rows
}

function dmenuRows(options, query) {
  var values = Array.isArray(options) ? options : []
  var needle = String(query || "").trim().toLowerCase()
  var rows = []
  for (var i = 0; i < values.length; i++) {
    var selection = String(values[i] || "")
    if (!selection) continue
    var parts = selection.split("\t")
    var label = parts.shift() || ""
    var detail = parts.join("\t")
    if (needle && (label + " " + detail).toLowerCase().indexOf(needle) < 0) continue
    rows.push({
      itemId: "dmenu:" + String(i),
      disabled: false,
      kind: "dmenu",
      icon: "",
      iconFont: "",
      appIcon: "",
      label: label,
      target: "",
      detail: detail,
      path: "",
      childCount: 0,
      desktopId: "",
      action: "",
      selection: selection,
      requestSerial: 0,
      score: i,
      section: "dmenu"
    })
  }
  return rows
}

function planRowReconciliation(currentRows, nextRows) {
  var current = Array.isArray(currentRows) ? currentRows.slice() : []
  var next = Array.isArray(nextRows) ? nextRows : []
  var desired = {}
  var operations = []

  function sameRow(left, right) {
    if (left === right) return true
    if (!left || !right) return false
    var leftKeys = Object.keys(left)
    var rightKeys = Object.keys(right)
    if (leftKeys.length !== rightKeys.length) return false
    for (var keyIndex = 0; keyIndex < leftKeys.length; keyIndex++) {
      var key = leftKeys[keyIndex]
      if (!(key in right) || left[key] !== right[key]) return false
    }
    return true
  }

  for (var desiredIndex = 0; desiredIndex < next.length; desiredIndex++)
    desired["$" + String(next[desiredIndex].itemId || "")] = true

  for (var removeIndex = current.length - 1; removeIndex >= 0; removeIndex--) {
    var removeKey = "$" + String(current[removeIndex].itemId || "")
    if (desired[removeKey]) continue
    operations.push({ type: "remove", index: removeIndex })
    current.splice(removeIndex, 1)
  }

  for (var targetIndex = 0; targetIndex < next.length; targetIndex++) {
    var targetRow = next[targetIndex]
    var targetKey = String(targetRow.itemId || "")
    if (targetIndex < current.length && String(current[targetIndex].itemId || "") === targetKey) {
      if (!sameRow(current[targetIndex], targetRow))
        operations.push({ type: "set", index: targetIndex, row: targetRow })
      current[targetIndex] = targetRow
      continue
    }

    var foundIndex = -1
    for (var searchIndex = targetIndex + 1; searchIndex < current.length; searchIndex++) {
      if (String(current[searchIndex].itemId || "") === targetKey) {
        foundIndex = searchIndex
        break
      }
    }

    if (foundIndex >= 0) {
      var moved = current.splice(foundIndex, 1)[0]
      current.splice(targetIndex, 0, moved)
      operations.push({ type: "move", from: foundIndex, to: targetIndex })
      if (!sameRow(current[targetIndex], targetRow))
        operations.push({ type: "set", index: targetIndex, row: targetRow })
      current[targetIndex] = targetRow
    } else {
      current.splice(targetIndex, 0, targetRow)
      operations.push({ type: "insert", index: targetIndex, row: targetRow })
    }
  }

  for (var extraIndex = current.length - 1; extraIndex >= next.length; extraIndex--) {
    operations.push({ type: "remove", index: extraIndex })
    current.splice(extraIndex, 1)
  }

  return operations
}

if (typeof module !== "undefined") {
  module.exports = {
    isOpaqueActionId: isOpaqueActionId,
    stripJsonc: stripJsonc,
    normalizeAliases: normalizeAliases,
    normalizeItem: normalizeItem,
    parseMenuJsoncResult: parseMenuJsoncResult,
    parseMenuJsonc: parseMenuJsonc,
    preserveLastValid: preserveLastValid,
    mergeMenuSources: mergeMenuSources,
    item: item,
    resolveRoute: resolveRoute,
    depthFor: depthFor,
    pathFor: pathFor,
    parentPathFor: parentPathFor,
    isDescendantOf: isDescendantOf,
    childCount: childCount,
    routeVisibility: routeVisibility,
    isVisible: isVisible,
    isDisabled: isDisabled,
    labelFor: labelFor,
    searchableToken: searchableToken,
    leafIdFor: leafIdFor,
    nameSearchText: nameSearchText,
    termInSearchWords: termInSearchWords,
    descriptionTextMatches: descriptionTextMatches,
    matchesQuery: matchesQuery,
    searchScore: searchScore,
    displayRow: displayRow,
    applicationRow: applicationRow,
    calculatorRow: calculatorRow,
    composeSearchResults: composeSearchResults,
    dmenuRows: dmenuRows,
    planRowReconciliation: planRowReconciliation
  }
}
