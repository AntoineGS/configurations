import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugins/panels/bluetooth" as Bluetooth

Item {
  id: root

  readonly property string actionLogPath: Quickshell.env("BLUETOOTH_ACTION_LOG")
  readonly property string batteryLogPath: Quickshell.env("BLUETOOTH_BATTERY_LOG")
  readonly property string batteryHoldPath: Quickshell.env("BLUETOOTH_BATTERY_HOLD")
  readonly property string batteryOldOutputPath: Quickshell.env("BLUETOOTH_BATTERY_OLD_OUTPUT")
  readonly property string batteryNewOutputPath: Quickshell.env("BLUETOOTH_BATTERY_NEW_OUTPUT")
  readonly property string fakeAction: Qt.resolvedUrl("tests/fixtures/connectivity/fake-bluetooth-action")
    .toString().replace("file://", "")
  readonly property string fakeBattery: Qt.resolvedUrl("tests/fixtures/connectivity/fake-bluetooth-state")
    .toString().replace("file://", "")

  property var adapterData: ({ enabled: true, discovering: true })
  property var connectedFixture: [
    {
      address: "AA:BB:CC:DD:EE:01",
      dbusPath: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_01",
      deviceName: "Keyboard One",
      name: "Keyboard One",
      connected: true,
      paired: true,
      batteryAvailable: false
    },
    {
      address: "AA:BB:CC:DD:EE:02",
      dbusPath: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_02",
      deviceName: "Mouse Two",
      name: "Mouse Two",
      connected: true,
      paired: true,
      batteryAvailable: false
    }
  ]
  property var disconnectedFixture: [
    {
      address: "AA:BB:CC:DD:EE:01",
      dbusPath: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_01",
      deviceName: "Keyboard One",
      name: "Keyboard One",
      connected: false,
      paired: true,
      batteryAvailable: false
    },
    {
      address: "AA:BB:CC:DD:EE:02",
      dbusPath: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_02",
      deviceName: "Mouse Two",
      name: "Mouse Two",
      connected: false,
      paired: true,
      batteryAvailable: false
    }
  ]
  property int phase: 0
  property bool sawAdapterArrival: false
  property bool sawSharedScan: false
  property bool sawPendingReservation: false
  property bool sawInitialBatteryDemand: false
  property bool sawBatteryGeneration: false
  property bool sawReattachedCollector: false
  property bool sawDestructionCleanup: false
  property string actionLogText: ""
  property string batteryLogText: ""

  QtObject {
    id: fakeShell
    property bool previewMode: false

    function widgetSettingsFor(pluginId) { return ({}) }
  }

  Bluetooth.Service {
    id: service
    shell: fakeShell
    manifest: ({ id: "desktop.bluetooth" })
    actionExecutable: root.fakeAction
    batteryExecutable: root.fakeBattery
    adapterOverride: null
    devicesOverride: root.connectedFixture
  }

  ServiceConsumer {
    id: left
    service: service
    details: true
  }

  ServiceConsumer {
    id: right
    service: service
    details: true
  }

  FileView {
    id: actionLog
    path: root.actionLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.actionLogText = text()
  }

  FileView {
    id: batteryLog
    path: root.batteryLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.batteryLogText = text()
  }

  FileView {
    id: batteryOldOutput
    path: root.batteryOldOutputPath
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: batteryNewOutput
    path: root.batteryNewOutputPath
    blockWrites: false
    printErrors: false
  }

  FileView {
    id: batteryHold
    path: root.batteryHoldPath
    blockWrites: false
    printErrors: false
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: root.advance()
  }

  Timer {
    interval: 30000
    running: true
    repeat: false
    onTriggered: root.fail("watchdog expired")
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  function lines(text) {
    return String(text || "").split("\n").filter(function(line) { return line !== "" })
  }

  function device(address) {
    for (var i = 0; i < root.connectedFixture.length; i++) {
      if (root.connectedFixture[i].address === address) return root.connectedFixture[i]
    }
    return null
  }

  function finish() {
    var success = sawAdapterArrival && sawSharedScan && sawPendingReservation
      && sawInitialBatteryDemand
      && sawBatteryGeneration && sawReattachedCollector && sawDestructionCleanup
    if (!success) {
        console.error("bluetooth fixture failed", sawAdapterArrival, sawSharedScan,
          sawPendingReservation, sawInitialBatteryDemand, sawBatteryGeneration, sawReattachedCollector,
        sawDestructionCleanup, service.consumerCount, service.collecting,
        service.detailed, service.scanningRequested, service.pendingActions,
        actionLogText, batteryLogText)
    } else {
      console.log("bluetooth fake-helper fixture passed")
    }
    Qt.exit(success ? 0 : 1)
  }

  function fail(message) {
    console.error("bluetooth-service-runtime-test: " + String(message))
    Qt.exit(1)
  }

  function advance() {
    try {
      var actionLines = lines(actionLogText)
      var batteryLines = lines(batteryLogText)

      if (phase === 0) {
        if (service.consumerCount !== 2 || !service.detailed || !service.scanningRequested) return
        batteryLog.reload()
        batteryLines = lines(batteryLogText)
        if (service.batteryRefreshGeneration < 1 || batteryLines.length < 1) return
        check(batteryLines.length === 1, "first demand starts one shared battery collector")
        sawInitialBatteryDemand = true
        check(actionLines.length === 0, "adapter absence does not invoke scan helper")
        service.adapterOverride = root.adapterData
        phase = 1
        return
      }

      if (phase === 1) {
        actionLog.reload()
        actionLines = lines(actionLogText)
        if (actionLines.length < 1) return
        check(actionLines[0] === "bluetooth scan on", "adapter arrival starts one shared scan")
        left.active = false
        phase = 2
        return
      }

      if (phase === 2) {
        if (service.consumerCount !== 1 || !service.detailed || actionLines.length !== 1) return
        sawSharedScan = true
        var first = device("AA:BB:CC:DD:EE:01")
        var second = device("AA:BB:CC:DD:EE:02")
        check(first && second, "fixture devices are available")
        var sameDeviceFirst = service.runDeviceAction(first, "disconnect", "disconnecting")
        var sameDeviceSecond = service.runDeviceAction(first, "remove", "removing")
        var differentDevice = service.runDeviceAction(second, "disconnect", "disconnecting")
        sawPendingReservation = sameDeviceFirst && !sameDeviceSecond && differentDevice
        check(sawPendingReservation, "pending actions reserve independently by address")
        phase = 3
        return
      }

      if (phase === 3) {
        actionLog.reload()
        actionLines = lines(actionLogText)
        if (actionLines.length < 3) return
        check(actionLines.indexOf("bluetooth disconnect AA:BB:CC:DD:EE:01") >= 0,
          "first device action uses the fake helper")
        check(actionLines.indexOf("bluetooth disconnect AA:BB:CC:DD:EE:02") >= 0,
          "different device action remains available")
        check(service.pendingAction("AA:BB:CC:DD:EE:01") === "disconnecting"
          && service.pendingAction("AA:BB:CC:DD:EE:02") === "disconnecting",
          "pending action map is shared")
        right.active = false
        phase = 4
        return
      }

      if (phase === 4) {
        actionLog.reload()
        actionLines = lines(actionLogText)
        if (service.consumerCount !== 0 || service.detailed || actionLines.length < 4) return
        check(actionLines[3] === "bluetooth scan off", "last detail consumer stops the scan")
        service.devicesOverride = root.disconnectedFixture
        phase = 5
        return
      }

      if (phase === 5) {
        if (service.collecting || Object.keys(service.pendingActions).length > 0) return
        service.adapterOverride = null
        right.active = true
        phase = 6
        return
      }

      if (phase === 6) {
        if (service.consumerCount !== 1 || !service.detailed || actionLines.length !== 4) return
        root.writeBatteryOutputs()
        root.writeBatteryHold(true)
        service.adapterOverride = root.adapterData
        service.refreshBatteries()
        phase = 7
        return
      }

      if (phase === 7) {
        batteryLog.reload()
        batteryLines = lines(batteryLogText)
        actionLog.reload()
        actionLines = lines(actionLogText)
        if (actionLines.length < 5 || batteryLines.length < 1 || !service.batteryWorker) return
        check(actionLines[4] === "bluetooth scan on", "adapter arrival restores requested scanning")
        sawAdapterArrival = true
        service.refreshBatteries()
        root.writeBatteryHold(false)
        phase = 8
        return
      }

      if (phase === 8) {
        batteryLog.reload()
        batteryLines = lines(batteryLogText)
        if (batteryLines.length < 2 || service.batteryWorker) return
        check(service.batteryDevices["/org/bluez/hci0/dev_fixture"]
          && service.batteryDevices["/org/bluez/hci0/dev_fixture"].central === 82,
          "latest battery generation wins")
        sawBatteryGeneration = true
        root.writeBatteryHold(true)
        service.refreshBatteries()
        phase = 9
        return
      }

      if (phase === 9) {
        batteryLog.reload()
        batteryLines = lines(batteryLogText)
        if (batteryLines.length < 3 || !service.batteryWorker) return
        service.adapterOverride = null
        right.active = false
        root.writeBatteryHold(false)
        phase = 10
        return
      }

      if (phase === 10) {
        batteryLog.reload()
        batteryLines = lines(batteryLogText)
        if (service.collecting || service.batteryWorker || batteryLines.length < 3) return
        check(service.batteryDevices["/org/bluez/hci0/dev_fixture"]
          && service.batteryDevices["/org/bluez/hci0/dev_fixture"].central === 82,
          "stopped old battery worker cannot publish a result")
        right.active = true
        service.adapterOverride = root.adapterData
        phase = 11
        return
      }

      if (phase === 11) {
        batteryLog.reload()
        batteryLines = lines(batteryLogText)
        actionLog.reload()
        actionLines = lines(actionLogText)
        if (service.batteryWorker || batteryLines.length < 4 || actionLines.length < 6) return
        check(actionLines[5] === "bluetooth scan on", "reattached consumer starts one scan")
        check(service.batteryDevices["/org/bluez/hci0/dev_fixture"]
          && service.batteryDevices["/org/bluez/hci0/dev_fixture"].central === 82,
          "reattached collector publishes current battery state")
        check(batteryLines.length === 6, "one battery collector remains after demand transitions")
        sawReattachedCollector = true
        service.destroy()
        phase = 12
        return
      }

      if (phase === 12) {
        actionLog.reload()
        actionLines = lines(actionLogText)
        if (actionLines.length < 7) return
        check(actionLines[6] === "bluetooth scan off", "service destruction releases owned scan")
        sawDestructionCleanup = true
        finish()
      }
    } catch (error) {
      fail(error && error.message ? error.message : error)
    }
  }

  function batteryPayload(value, updatedAt) {
    return JSON.stringify({
      available: true,
      stale: false,
      updatedAt: updatedAt,
      error: null,
      data: { devices: ({ "/org/bluez/hci0/dev_fixture": { central: value } }) }
    })
  }

  function writeBatteryOutputs() {
    batteryOldOutput.setText(batteryPayload(21, 1) + "\n")
    batteryNewOutput.setText(batteryPayload(82, 2) + "\n")
  }

  function writeBatteryHold(enabled) {
    batteryHold.setText(enabled ? "hold\n" : "release\n")
  }
}
