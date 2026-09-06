import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

SharedService {
  id: root

  property var batteryDevices: ({})
  property bool batteryCollectorLoaded: true
  property bool batteryRefreshQueued: false
  property int batteryRefreshGeneration: 0
  property string batteryTopologyKey: ""
  property string batteryExecutable: "desktop-hardware-state"
  property var batteryWorker: null

  property var pendingActions: ({})
  property string actionExecutable: "desktop-connectivity-action"
  property var adapterOverride
  property var devicesOverride
  property bool scanOwned: false

  readonly property var adapter: adapterOverride === undefined ? Bluetooth.defaultAdapter : adapterOverride
  readonly property var devices: devicesOverride === undefined
    ? (Bluetooth.devices ? Bluetooth.devices.values : []) : devicesOverride
  readonly property var connectedDevices: Model.deviceLists(devices).connected || []
  readonly property bool scanningRequested: collecting && detailed
  readonly property bool busy: Object.keys(pendingActions).length > 0

  function helper(args) {
    Quickshell.execDetached([root.actionExecutable].concat(args))
  }

  function syncScanning() {
    if (root.scanningRequested && root.adapter) {
      if (!root.scanOwned) {
        helper(["bluetooth", "scan", "on"])
        root.scanOwned = true
      }
      return
    }

    if (!root.adapter) {
      root.scanOwned = false
      return
    }
    if (!root.scanningRequested && root.scanOwned) helper(["bluetooth", "scan", "off"])
    root.scanOwned = false
  }

  function toggleBluetooth() {
    if (!root.adapter) return false
    helper(["bluetooth", "power", root.adapter.enabled ? "off" : "on"])
    return true
  }

  function refreshBatteries() {
    if (!root.batteryCollectorLoaded || !root.collecting || root.consumerCount === 0) return false
    root.batteryRefreshGeneration++
    if (root.batteryWorker) {
      root.batteryRefreshQueued = true
      return true
    }
    startBatteryWorker()
    return true
  }

  function startBatteryWorker() {
    if (!root.collecting || root.batteryWorker) return
    var worker = batteryComponent.createObject(root, {
      refreshGeneration: root.batteryRefreshGeneration
    })
    if (!worker) return
    root.batteryWorker = worker
    worker.running = true
  }

  function finishBatteryWorker(worker, exitCode) {
    if (worker !== root.batteryWorker) return
    var completedGeneration = worker.refreshGeneration
    root.batteryWorker = null
    if (completedGeneration === root.batteryRefreshGeneration)
      root.batteryDevices = Model.parseBatteryState(worker.stdoutOutput.text || "")
    destroyWorker(worker)
    if (!root.batteryCollectorLoaded) return
    if (root.batteryRefreshQueued) {
      root.batteryRefreshQueued = false
      startBatteryWorker()
    }
  }

  function syncBatteryTopology() {
    var nextKey = Model.deviceTopologyKey(root.connectedDevices)
    if (nextKey === root.batteryTopologyKey) return
    root.batteryTopologyKey = nextKey
    root.refreshBatteries()
  }

  function deviceFor(address) {
    var target = String(address || "")
    if (target === "") return null
    var devices = Model.toArray(root.devices)
    for (var i = 0; i < devices.length; i++) {
      if (devices[i] && String(devices[i].address || "") === target) return devices[i]
    }
    return null
  }

  function pendingAction(address) {
    return Model.pendingAction(root.pendingActions, address)
  }

  function setPendingAction(address, action) {
    if (!address) return
    root.pendingActions = Model.withPendingAction(root.pendingActions, address, action)
  }

  function runDeviceAction(row, action, pending) {
    if (!row || !row.address || root.pendingAction(row.address) !== "") return false
    setPendingAction(row.address, pending)
    root.operationPending = true
    helper(["bluetooth", action, row.address])
    pendingTimer.restart()
    pendingTimeout.restart()
    return true
  }

  function syncPendingActions() {
    var next = Model.cloneMap(root.pendingActions)
    var changed = false
    for (var address in next) {
      var device = deviceFor(address)
      var action = next[address]
      var finished = (action === "connecting" && device && device.connected)
        || (action === "disconnecting" && device && !device.connected)
        || (action === "pairing" && device && (device.paired || device.bonded || device.trusted))
        || (action === "removing" && (!device || (!device.paired && !device.bonded && !device.trusted)))
      if (finished) {
        delete next[address]
        changed = true
      }
    }
    if (changed) root.pendingActions = next
    if (Object.keys(next).length === 0) {
      root.operationPending = false
      pendingTimeout.stop()
    }
  }

  function clearPendingActions() {
    root.pendingActions = ({})
    root.operationPending = false
    pendingTimer.stop()
  }

  function destroyWorker(worker) {
    if (!worker) return
    worker.running = false
    var staleWorker = worker
    Qt.callLater(function() { if (staleWorker) staleWorker.destroy() })
  }

  function stopBatteryCollection() {
    root.batteryRefreshQueued = false
    var oldWorker = root.batteryWorker
    root.batteryWorker = null
    destroyWorker(oldWorker)
  }

  onScanningRequestedChanged: syncScanning()
  onAdapterChanged: syncScanning()
  onConnectedDevicesChanged: syncBatteryTopology()
  onCollectingChanged: {
    if (!root.collecting) stopBatteryCollection()
    else root.refreshBatteries()
  }

  Timer {
    id: pendingTimer
    interval: 500
    repeat: true
    running: root.collecting && root.busy
    onTriggered: root.syncPendingActions()
  }

  Timer {
    id: pendingTimeout
    interval: 20000
    repeat: false
    onTriggered: root.clearPendingActions()
  }

  Timer {
    interval: 300000
    repeat: true
    running: root.collecting
    onTriggered: root.refreshBatteries()
  }

  Component {
    id: batteryComponent

    Process {
      id: process
      property int refreshGeneration: 0
      command: [root.batteryExecutable, "bluetooth"]
      stdout: StdioCollector {
        id: stdoutCollector
        waitForEnd: true
      }
      stderr: StdioCollector { waitForEnd: true }
      property alias stdoutOutput: stdoutCollector
      onExited: function(exitCode) { root.finishBatteryWorker(process, Number(exitCode)) }
    }
  }

  Component.onCompleted: {
    syncScanning()
    syncBatteryTopology()
  }
  Component.onDestruction: {
    root.batteryCollectorLoaded = false
    stopBatteryCollection()
    pendingTimer.stop()
    pendingTimeout.stop()
    if (root.scanOwned && root.adapter) helper(["bluetooth", "scan", "off"])
    root.scanOwned = false
  }
}
