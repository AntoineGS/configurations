import QtQuick

Item {
  id: service

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var consumers: []
  property bool operationPending: false

  signal invalidated()

  readonly property var settings: shell && manifest
    ? shell.widgetSettingsFor(String(manifest.id || "")) : ({})
  readonly property int consumerCount: consumers.length
  readonly property bool detailed: consumers.some(function(entry) { return entry.details })
  readonly property bool collecting: !!shell && !shell.previewMode
    && (consumerCount > 0 || operationPending)

  function setConsumer(owner, details) {
    if (!owner) return
    var current = consumers.find(function(entry) { return entry.owner === owner })
    if (current && current.details === (details === true)) return
    var next = consumers.filter(function(entry) { return entry.owner !== owner })
    next.push({ owner: owner, details: details === true })
    consumers = next
  }

  function removeConsumer(owner) {
    var next = consumers.filter(function(entry) { return entry.owner !== owner })
    if (next.length !== consumers.length) consumers = next
  }

  Component.onDestruction: invalidated()
}
