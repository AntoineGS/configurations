function frame(screenName, monitor, toplevelCount) {
  if (!monitor || !screenName || monitor.name !== screenName || !monitor.focused
      || !monitor.activeWorkspace || !Number.isInteger(monitor.activeWorkspace.id)
      || monitor.activeWorkspace.id <= 0 || toplevelCount !== 0) return null

  var ipc = monitor.lastIpcObject
  if (!ipc || !Array.isArray(ipc.reserved) || ipc.reserved.length !== 4
      || !ipc.specialWorkspace || ipc.specialWorkspace.id !== 0) return null

  var insets = ipc.reserved
  if (!insets.every(value => Number.isFinite(value) && value >= 0)
      || !Number.isFinite(monitor.width) || !Number.isFinite(monitor.height)) return null

  var width = monitor.width - insets[0] - insets[2]
  var height = monitor.height - insets[1] - insets[3]
  return width > 0 && height > 0
    ? { x: insets[0], y: insets[1], width: width, height: height } : null
}

if (typeof module !== "undefined") module.exports = { frame }
