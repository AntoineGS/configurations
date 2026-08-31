const assert = require("node:assert/strict")
const model = require("../plugins/panels/bluetooth/Model.js")

const first = [
  { address: "AA:BB:CC:DD:EE:02", battery: 0.2 },
  { address: "AA:BB:CC:DD:EE:01", battery: 0.8 }
]
const reorderedWithNewBattery = [
  { address: "AA:BB:CC:DD:EE:01", battery: 0.1 },
  { address: "AA:BB:CC:DD:EE:02", battery: 0.9 }
]

assert.equal(model.deviceTopologyKey(first), model.deviceTopologyKey(reorderedWithNewBattery))
assert.notEqual(model.deviceTopologyKey(first), model.deviceTopologyKey(first.slice(0, 1)))
assert.equal(model.deviceTopologyKey([{ dbusPath: "/org/bluez/hci0/dev_01" }]), "/org/bluez/hci0/dev_01")
