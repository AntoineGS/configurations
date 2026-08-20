const assert = require("node:assert/strict")
const Model = require("../plugins/panels/vm/Model.js")

const fullPayload = {
  available: true,
  stale: false,
  error: null,
  data: {
    name: "win11-gaming",
    vcpus: 4,
    cpu: { available: true, percent: 18.4 },
    memory: {
      allocationAvailable: true,
      usageAvailable: true,
      currentKiB: 12582912,
      maximumKiB: 25165824,
      usedKiB: 5242880,
      percent: 41.7,
    },
  },
}

const full = Model.normalizeState(fullPayload)
assert.equal(full.visible, true)
assert.equal(full.showMemoryUsage, true)
assert.equal(full.canResize, true)
assert.equal(full.name, "win11-gaming")
assert.equal(full.vcpus, 4)
assert.equal(full.cpuPercent, 18.4)
assert.equal(full.memoryPercent, 41.7)
assert.equal(full.currentKiB, 12582912)
assert.equal(full.maximumKiB, 25165824)
assert.equal(full.usedKiB, 5242880)
assert.equal(Model.vmMetricText(full.memoryPercent), "(42%)")
assert.equal(Model.vmMetricText(full.cpuPercent), "(18%)")
assert.equal(Model.memoryCritical(full.memoryPercent), false)
assert.equal(Model.currentGiB(full), 12)
assert.equal(Model.maximumGiB(full), 24)
assert.equal(Model.formatGiB(5242880), "5 GiB")

const fullFromJson = Model.normalizeState(JSON.stringify(fullPayload))
assert.equal(fullFromJson.visible, true)
assert.equal(Model.vmMetricText(fullFromJson.memoryPercent), "(42%)")

const malformed = Model.normalizeState("{not-json")
assert.equal(malformed.visible, false)
assert.equal(malformed.available, false)
assert.equal(malformed.stale, true)
assert.equal(malformed.malformed, true)
assert.match(malformed.error, /JSON/)

const unavailable = Model.normalizeState({
  available: false,
  stale: false,
  error: null,
  data: fullPayload.data,
})
assert.equal(unavailable.visible, false)
assert.equal(unavailable.showMemoryUsage, false)
assert.equal(unavailable.canResize, false)

const stale = Model.normalizeState({
  available: true,
  stale: true,
  error: "virsh domstats failed",
  data: fullPayload.data,
})
assert.equal(stale.visible, true)
assert.equal(stale.canResize, false)
assert.equal(stale.name, "win11-gaming")
assert.equal(stale.currentKiB, 12582912)
assert.equal(Model.vmMetricText(stale.memoryPercent), "(42%)")

const firstCpuSample = Model.normalizeState({
  available: true,
  stale: false,
  error: null,
  data: {
    name: "win11-gaming",
    vcpus: 4,
    cpu: { available: false, percent: null },
    memory: { allocationAvailable: false, usageAvailable: false },
  },
})
assert.equal(firstCpuSample.cpuPercent, undefined)
assert.equal(Model.vmMetricText(firstCpuSample.cpuPercent), "(--%)")

const memoryOmitted = Model.normalizeState({
  available: true,
  stale: false,
  error: null,
  data: {
    name: "win11-gaming",
    vcpus: 4,
    cpu: { available: true, percent: 18.4 },
    memory: {
      allocationAvailable: true,
      usageAvailable: false,
      currentKiB: 12582912,
      maximumKiB: 25165824,
    },
  },
})
assert.equal(memoryOmitted.showMemoryUsage, false)
assert.equal(memoryOmitted.canResize, true)

const invalidNumbers = Model.normalizeState({
  available: true,
  stale: false,
  error: null,
  data: {
    name: "win11-gaming",
    vcpus: "not-a-number",
    cpu: { available: true, percent: "NaN" },
    memory: {
      allocationAvailable: true,
      usageAvailable: true,
      currentKiB: "NaN",
      maximumKiB: NaN,
      usedKiB: Infinity,
      percent: "NaN",
    },
  },
})
assert.equal(invalidNumbers.cpuPercent, undefined)
assert.equal(invalidNumbers.currentKiB, null)
assert.equal(invalidNumbers.maximumKiB, null)
assert.equal(invalidNumbers.usedKiB, null)
assert.equal(invalidNumbers.memoryPercent, undefined)
assert.equal(invalidNumbers.showMemoryUsage, false)
assert.equal(invalidNumbers.canResize, false)
assert.doesNotMatch(Model.vmMetricText(invalidNumbers.cpuPercent), /NaN/)

const unavailableMetrics = Model.normalizeState({
  available: true,
  stale: false,
  error: null,
  data: {
    name: "win11-gaming",
    vcpus: 4,
    cpu: { available: true, percent: NaN },
    memory: {
      allocationAvailable: false,
      usageAvailable: true,
      usedKiB: 5242880,
      percent: null,
    },
  },
})
assert.equal(unavailableMetrics.cpuPercent, undefined)
assert.equal(unavailableMetrics.showMemoryUsage, false)
assert.equal(Model.vmMetricText(unavailableMetrics.cpuPercent), "(--%)")
assert.equal(Model.currentGiB(), 1)
assert.equal(Model.maximumGiB(), 1)

const retained = Model.stateFromRaw(full, "")
assert.equal(retained.visible, true)
assert.equal(retained.available, true)
assert.equal(retained.stale, true)
assert.equal(retained.malformed, true)
assert.equal(retained.canResize, false)
assert.equal(retained.name, full.name)
assert.equal(retained.currentKiB, full.currentKiB)
assert.match(retained.error, /JSON/)

const retainedWithProcessError = Model.stateFromRaw(full, "", "state helper exited with code 7")
assert.equal(retainedWithProcessError.visible, true)
assert.equal(retainedWithProcessError.canResize, false)
assert.match(retainedWithProcessError.error, /state helper exited with code 7/)

const coldMalformed = Model.stateFromRaw(Model.emptyState(), "")
assert.equal(coldMalformed.visible, false)
assert.equal(coldMalformed.stale, true)
assert.equal(coldMalformed.malformed, true)
assert.match(coldMalformed.error, /JSON/)

const validUnavailable = Model.stateFromRaw(full, {
  available: false,
  stale: false,
  error: null,
  data: {},
})
assert.equal(validUnavailable.visible, false)
assert.equal(validUnavailable.stale, false)
assert.equal(validUnavailable.malformed, false)
assert.equal(validUnavailable.error, null)

assert.equal(Model.formatPercent(18.4), "18%")
assert.equal(Model.formatPercent(-5), "0%")
assert.equal(Model.formatPercent(101), "100%")
assert.equal(Model.formatPercent(undefined), "--%")
assert.equal(Model.formatPercent("not-a-number"), "--%")
assert.equal(Model.minimumGiB(), 1)
assert.equal(Model.currentGiB({ currentKiB: 12582911 }), 11)
assert.equal(Model.maximumGiB({ maximumKiB: 25165823 }), 23)
assert.equal(Model.formatGiB(6291455), "5 GiB")
assert.equal(Model.formatGiB(null), "-- GiB")

const hostMemory = Model.normalizeHostStat(JSON.stringify({
  text: " 75%",
  tooltip: "Memory usage: 75%",
  class: "",
  percentage: 75,
}))
assert.equal(hostMemory.available, true)
assert.equal(hostMemory.text, " 75%")
assert.equal(hostMemory.tooltip, "Memory usage: 75%")
assert.equal(hostMemory.percent, 75)
assert.equal(hostMemory.stale, false)

const staleHostMemory = Model.normalizeHostStat({
  text: " 86%",
  tooltip: "Memory usage: 86% · error: stale sample",
  class: "stale",
  percentage: 86,
})
assert.equal(staleHostMemory.available, true)
assert.equal(staleHostMemory.stale, true)
assert.equal(Model.memoryCritical(staleHostMemory.percent), true)
assert.equal(Model.memoryCritical(85), false)

const malformedHostStat = Model.normalizeHostStat('{"percentage":"75"}')
assert.equal(malformedHostStat.available, false)
assert.equal(Model.hostStateFromRaw(hostMemory, ""), hostMemory)

console.log("vm-model-test: normalization, metrics, stale retention, and GiB formatting verified")
