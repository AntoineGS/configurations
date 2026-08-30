const assert = require("node:assert/strict")
const BatteryModel = require("../plugins/services/battery/BatteryModel.js")

assert.equal(BatteryModel.batteryPercentage(39.6), 40)
assert.equal(BatteryModel.batteryPercentage(-1), -1)

let result = BatteryModel.warningState("Battery 20%", true, 20, 10, false, false)
assert.deepEqual(result, {
  level: 20,
  notify: true,
  urgency: "normal",
  lowNotified: true,
  criticalNotified: false
})

result = BatteryModel.warningState("Battery 20%", true, 20, 10, true, false)
assert.equal(result.notify, false)

result = BatteryModel.warningState("Battery 10%", true, 20, 10, true, false)
assert.equal(result.notify, true)
assert.equal(result.urgency, "critical")

result = BatteryModel.warningState("Battery 10%", false, 20, 10, true, true)
assert.deepEqual(result, {
  level: 10,
  notify: false,
  urgency: "",
  lowNotified: false,
  criticalNotified: false
})

result = BatteryModel.warningState("Battery unknown", true, 20, 10, false, false)
assert.equal(result.notify, false)
assert.equal(result.level, -1)

result = BatteryModel.warningState(-1, true, 20, 10, false, false)
assert.equal(result.notify, false)
assert.equal(result.level, -1)

const low = BatteryModel.warningState(20, true, 20, 10, false, false)
const critical = BatteryModel.warningState(10, true, 20, 10, true, false)
let delivery = { active: low, queued: null }
delivery = BatteryModel.warningDeliveryTransition(delivery, "warning", critical).state
assert.deepEqual(delivery.queued, critical)

let failed = BatteryModel.warningDeliveryTransition(delivery, "failure")
assert.equal(failed.committed, null)
assert.equal(failed.action, "retry")
assert.deepEqual(failed.state.queued, critical)

let reset = BatteryModel.warningDeliveryTransition({ active: low, queued: critical }, "ac-reset")
assert.equal(reset.committed, null)
assert.equal(reset.state.active, null)
assert.equal(reset.state.queued, null)

let delivered = BatteryModel.warningDeliveryTransition({ active: critical, queued: null }, "success")
assert.deepEqual(delivered.committed, { lowNotified: true, criticalNotified: true })
assert.equal(delivered.state.active, null)

let race = BatteryModel.warningDeliveryTransition({ active: null, queued: null }, "warning", low)
race = BatteryModel.warningDeliveryTransition(race.state, "started")
race = BatteryModel.warningDeliveryTransition(race.state, "ac-reset")
race = BatteryModel.warningDeliveryTransition(race.state, "warning", low)
assert.equal(race.state.active, null)
assert.deepEqual(race.state.queued, low)
race = BatteryModel.warningDeliveryTransition(race.state, "success")
assert.equal(race.committed, null)
assert.equal(race.action, "retry")
let relaunched = BatteryModel.warningDeliveryTransition(race.state, "warning", low)
assert.equal(relaunched.action, "send")
assert.deepEqual(relaunched.state.active, low)
