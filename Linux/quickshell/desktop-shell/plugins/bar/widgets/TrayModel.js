function itemId(item) {
  return item && item.id !== undefined ? String(item.id) : ""
}

function displayName(item) {
  if (!item) return ""
  var title = String(item.tooltipTitle || item.title || "").trim()
  return title || itemId(item)
}

function hasMenu(item) {
  return !!item && !!item.menu
}

if (typeof module !== "undefined") {
  module.exports = {
    itemId: itemId,
    displayName: displayName,
    hasMenu: hasMenu
  }
}
