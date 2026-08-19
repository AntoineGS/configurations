const assert = require("node:assert/strict")
const Model = require("../plugins/panels/bluetooth/Model.js")

const splitPath = "/org/bluez/hci0/dev_SPLIT"
const fresh = JSON.stringify({
  available: true,
  stale: false,
  updatedAt: 1724060000,
  error: null,
  data: { devices: { [splitPath]: { central: 43, peripheral: 56 } } }
})

assert.deepEqual(Model.parseBatteryState(fresh), {
  [splitPath]: { central: 43, peripheral: 56 }
})
assert.deepEqual(Model.parseBatteryState(JSON.stringify({
  available: true,
  stale: false,
  error: null,
  data: { devices: { [splitPath]: { central: 43, peripheral: 56 } } }
})), {})
assert.deepEqual(Model.parseBatteryState(JSON.stringify({
  available: true,
  stale: false,
  updatedAt: 1724060000,
  error: null,
  data: { devices: { [splitPath]: { central: 43.5, peripheral: 56.25 } } }
})), {
  [splitPath]: { central: null, peripheral: null }
})
assert.deepEqual(Model.parseBatteryState(JSON.stringify({
  available: true, stale: true, updatedAt: 1724060000, error: "timeout",
  data: { devices: { [splitPath]: { central: 1, peripheral: 2 } } }
})), {})
assert.deepEqual(Model.parseBatteryState(JSON.stringify({
  available: true, updatedAt: 1724060000, error: null,
  data: { devices: { [splitPath]: { central: 1, peripheral: 2 } } }
})), {})
assert.deepEqual(Model.parseBatteryState(JSON.stringify({
  available: true, stale: "false", updatedAt: 1724060000, error: null,
  data: { devices: { [splitPath]: { central: 1, peripheral: 2 } } }
})), {})
assert.deepEqual(Model.parseBatteryState(JSON.stringify({
  available: true, stale: false, updatedAt: 1724060000, error: "timeout",
  data: { devices: { [splitPath]: { central: 1, peripheral: 2 } } }
})), {})
assert.deepEqual(Model.parseBatteryState(JSON.stringify({
  available: false, stale: false, updatedAt: 1724060000, error: null,
  data: { devices: { [splitPath]: { central: 1, peripheral: 2 } } }
})), {})
assert.deepEqual(Model.parseBatteryState(JSON.stringify({
  available: true, stale: false, updatedAt: 1724060000, error: null, data: { devices: "not-an-object" }
})), {})
const malformedDevices = function() {}
malformedDevices[splitPath] = { central: 1, peripheral: 2 }
assert.deepEqual(Model.parseBatteryState({
  available: true, stale: false, updatedAt: 1724060000, error: null, data: { devices: malformedDevices }
}), {})
assert.deepEqual(Model.parseBatteryState("not-json"), {})

const split = { dbusPath: splitPath, batteryAvailable: true, battery: 0.41 }
assert.deepEqual(Model.batteryValues(split, Model.parseBatteryState(fresh)), { central: 43, peripheral: 56 })
assert.deepEqual(Model.batteryValues({ dbusPath: "/native", batteryAvailable: true, battery: 0.72 }, {}), {
  central: 72, peripheral: null
})
assert.deepEqual(Model.batteryValues({ dbusPath: "/native-fraction", batteryAvailable: true, battery: 0.415 }, {
  "/native-fraction": { central: 43.5, peripheral: 56.25 }
}), {
  central: 42, peripheral: null
})

const row = Model.deviceRow({
  address: "AA:BB:CC:DD:EE:FF",
  name: "keyball",
  deviceName: "Keyball44-Blue",
  connected: true,
  paired: true,
  state: 1,
  batteryAvailable: true,
  battery: 0.41,
  pairing: false,
  dbusPath: splitPath
}, Model.parseBatteryState(fresh), "#fab387")
assert.equal(row.dbusPath, splitPath)
assert.deepEqual(row.batteryValues, { central: 43, peripheral: 56 })
assert.equal(row.batteryStatus, "Central 43% · Peripheral 56%")

assert.equal(Model.hasLowBattery([split], { [splitPath]: { central: 30, peripheral: 29 } }), true)
assert.equal(Model.hasLowBattery([split], { [splitPath]: { central: 30, peripheral: 30 } }), false)

assert.equal(
  Model.batteryStatus({ central: 43, peripheral: 29 }, "#fab387"),
  'Central 43% · Peripheral <span style="color: #fab387;">29%</span>'
)
assert.equal(
  Model.batteryStatus({ central: 72, peripheral: null }, "#fab387"),
  "Battery 72%"
)
assert.equal(
  Model.batteryStatus({ central: null, peripheral: 28 }, "#fab387"),
  'Peripheral <span style="color: #fab387;">28%</span>'
)
assert.equal(Model.batteryStatus({ central: null, peripheral: null }, "#fab387"), "Connected")

const tooltip = Model.batteryTooltip([
  { deviceName: "Keyball44-Blue", dbusPath: splitPath, batteryAvailable: true, battery: 0.43 },
  { deviceName: "Headphones & DAC", dbusPath: "/normal", batteryAvailable: true, battery: 0.72 }
], { [splitPath]: { central: 43, peripheral: 29 } }, "#fab387")
assert.match(tooltip, /Keyball44-Blue/)
assert.match(tooltip, /Central: 43%/)
assert.match(tooltip, /Peripheral: <span style="color: #fab387;">29%<\/span>/)
assert.match(tooltip, /Headphones &amp; DAC/)

console.log("bluetooth-model-test: battery parsing, formatting, and warning contracts verified")
