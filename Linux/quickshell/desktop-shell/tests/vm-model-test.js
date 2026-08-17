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
assert.equal(Model.barText(full), " 42%   18%")
assert.equal(Model.currentGiB(full), 12)
assert.equal(Model.maximumGiB(full), 24)
assert.equal(Model.formatGiB(5242880), "5 GiB")

const fullFromJson = Model.normalizeState(JSON.stringify(fullPayload))
assert.equal(fullFromJson.visible, true)
assert.equal(Model.barText(fullFromJson), " 42%   18%")

const malformed = Model.normalizeState("{not-json")
assert.equal(malformed.visible, false)
assert.equal(malformed.available, false)
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
assert.equal(Model.barText(unavailable), "")

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
assert.equal(Model.barText(stale), " 42%   18%")

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
assert.equal(Model.barText(firstCpuSample), " --%")

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
assert.equal(Model.barText(memoryOmitted), " 18%")

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
assert.doesNotMatch(Model.barText(invalidNumbers), /NaN/)

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
assert.equal(Model.barText(unavailableMetrics), " --%")
assert.equal(Model.currentGiB(), 1)
assert.equal(Model.maximumGiB(), 1)

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

console.log("vm-model-test: normalization, metrics, stale retention, and GiB formatting verified")
