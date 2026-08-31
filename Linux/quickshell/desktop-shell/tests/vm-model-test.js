const assert = require("node:assert/strict")
const Model = require("../plugins/panels/vm/Model.js")

const cpuRaw = "cpu 100 20 30 400 10 5 15 2 0 0\n"
assert.deepEqual(Model.parseCpuSnapshot(cpuRaw), { total: 582, idle: 410 })
assert.deepEqual(Model.parseCpuSnapshot("cpu 100 20 30 400 10 5 15 2 99 77\n"), { total: 582, idle: 410 })
assert.equal(Model.parseCpuSnapshot("cpu 1 two 3 4\n"), null)
assert.equal(Model.parseCpuSnapshot("cpu 1 2\n"), null)
assert.equal(Model.parseCpuSnapshot("cpu 1 2 3 4 5 6 7\n"), null)
assert.equal(Model.cpuUsage(null, { total: 100, idle: 50 }), null)
assert.equal(Model.cpuUsage({ total: 100, idle: 50 }, { total: 100, idle: 50 }), null)
assert.equal(Model.cpuUsage({ total: 100, idle: 50 }, { total: 90, idle: 40 }), null)
assert.equal(Model.cpuUsage({ total: 100, idle: 50 }, { total: 200, idle: 100 }), 50)
assert.equal(Model.cpuUsage({ total: 100, idle: 100 }, { total: 200, idle: 100 }), 100)
assert.equal(Model.cpuUsage({ total: 100, idle: 0 }, { total: 200, idle: 200 }), 0)

assert.deepEqual(Model.parseMemorySnapshot(
  "MemTotal:       16384 kB\nMemAvailable:    4096 kB\nMemFree:         2048 kB\n"
), { totalKiB: 16384, availableKiB: 4096, usedKiB: 12288, percent: 75 })
assert.equal(Model.parseMemorySnapshot("MemTotal: 3 kB\nMemAvailable: 1 kB\n").percent, 67)
assert.equal(Model.parseMemorySnapshot("MemTotal: 16384 kB\n"), null)
assert.equal(Model.parseMemorySnapshot("MemTotal: 0 kB\nMemAvailable: 0 kB\n"), null)
assert.equal(Model.parseMemorySnapshot("MemTotal: 1024 kB\nMemAvailable: 2048 kB\n"), null)
assert.equal(Model.parseMemorySnapshot("MemTotal: nope kB\nMemAvailable: 1 kB\n"), null)
assert.equal(Model.formatKibGiB(12582912), "12.0")
assert.equal(Model.formatKibGiB(16777216), "16.0")
assert.equal(Model.formatMemoryTooltip({ usedKiB: 12582912, totalKiB: 16777216 }), "12.0 / 16 GiB")

assert.deepEqual([2, 4, 8, 16, 32, 60].map(Model.nextBackoff), [4, 8, 16, 32, 60, 60])
assert.equal(Model.nextBackoff(null), 2)
assert.equal(Model.popupOpenRefreshRequested(false, true), true)
assert.equal(Model.popupOpenRefreshRequested(true, true), false)
assert.equal(Model.popupOpenRefreshRequested(false, false), false)

let monitor = Model.vmMonitorState()
let transition = Model.vmMonitorTransition(monitor, "reconcile-request")
assert.equal(transition.startReconciliation, true)
monitor = transition.state
transition = Model.vmMonitorTransition(monitor, "reconcile-request")
assert.equal(transition.startReconciliation, false)
assert.equal(transition.state.reconciliationQueued, true)

const runningRaw = JSON.stringify({
  available: true,
  stale: false,
  error: null,
  data: {
    name: "workstation",
    vcpus: 4,
    cpu: { available: true, percent: 42 },
    memory: { allocationAvailable: true, usageAvailable: true, currentKiB: 1048576, maximumKiB: 2097152,
      usedKiB: 524288, percent: 50 }
  }
})
const running = Model.stateFromRaw(Model.emptyState(), runningRaw)
assert.equal(running.visible, true)
assert.equal(running.canResize, true)

const stopped = Model.stateFromRaw(running, JSON.stringify({
  available: false,
  stale: false,
  error: null,
  data: { name: "", vcpus: 0, cpu: { available: false }, memory: { allocationAvailable: false, usageAvailable: false } }
}))
assert.equal(stopped.visible, false)
assert.equal(stopped.canResize, false)

const stale = Model.stateFromRaw(running, JSON.stringify({
  available: true,
  stale: true,
  error: "more than one running VM was found",
  data: {
    name: "workstation",
    vcpus: 4,
    cpu: { available: true, percent: 42 },
    memory: { allocationAvailable: true, usageAvailable: true, currentKiB: 1048576, maximumKiB: 2097152,
      usedKiB: 524288, percent: 50 }
  }
}))
assert.equal(stale.visible, true)
assert.equal(stale.canResize, false)
assert.equal(stale.confirmedRunning, false)
assert.equal(stale.error, "more than one running VM was found")

let lifecycle = Model.vmMonitorState()
let capability = Model.vmMonitorTransition(lifecycle, "capability-found")
assert.equal(capability.startWatcher, true)
assert.equal(capability.startReconciliation, true)
lifecycle = capability.state
assert.equal(lifecycle.watcherGeneration, 1)
assert.equal(lifecycle.reconciliationGeneration, 1)

let failedStart = Model.vmMonitorTransition(lifecycle, "watcher-stopped", 1)
assert.equal(failedStart.retryWatcher, true)
assert.equal(failedStart.state.backoffSeconds, 2)
failedStart = Model.vmMonitorTransition(failedStart.state, "watcher-exited", 1)
assert.equal(failedStart.retryWatcher, false)

const nextWatcher = Model.vmMonitorTransition(failedStart.state, "watcher-start")
assert.equal(nextWatcher.state.watcherGeneration, 2)
assert.equal(nextWatcher.startWatcher, true)
const oldFailure = Model.vmMonitorTransition(nextWatcher.state, "watcher-exited", 1)
assert.equal(oldFailure.state.backoffSeconds, 2)
const currentFailure = Model.vmMonitorTransition(nextWatcher.state, "watcher-stopped", 2)
assert.equal(currentFailure.state.backoffSeconds, 4)

let reconcileState = Model.vmMonitorTransition(currentFailure.state, "reconcile-process-stopped", { generation: 1 }).state
reconcileState = Model.vmMonitorTransition(reconcileState, "watcher-started", 2).state
reconcileState = Model.vmMonitorTransition(reconcileState, "watcher-stable", { generation: 2, running: true }).state
reconcileState = Model.vmMonitorTransition(reconcileState, "reconcile-request", 2).state
const staleReconcile = Model.vmMonitorTransition(reconcileState, "reconcile-finished", {
  generation: 1, fresh: true, stable: true
})
assert.equal(staleReconcile.state.backoffSeconds, 4)
const freshReconcile = Model.vmMonitorTransition(reconcileState, "reconcile-finished", {
  generation: 2, watcherGeneration: 2, fresh: true, stable: true
})
assert.equal(freshReconcile.state.backoffSeconds, 0)
assert.equal(Model.vmMonitorTransition(reconcileState, "reconcile-finished", {
  generation: 2, watcherGeneration: 2, fresh: false, stable: true
}).state.backoffSeconds, 4)

const runningWithoutMetrics = Model.stateFromRaw(Model.emptyState(), JSON.stringify({
  available: true, stale: false, error: null,
  data: { name: "workstation", vcpus: 4, cpu: { available: false },
    memory: { allocationAvailable: true, usageAvailable: false, currentKiB: 1048576, maximumKiB: 2097152 } }
}))
assert.equal(runningWithoutMetrics.available, true)
assert.equal(runningWithoutMetrics.confirmedRunning, true)
assert.equal(Model.vmMonitorTransition(Model.vmMonitorState(), "state-applied", true).state.runningConfirmed, true)

let backoffState = Model.vmMonitorState()
for (const expected of [2, 4, 8, 16, 32, 60, 60]) {
  backoffState = Model.vmMonitorTransition(backoffState, "watcher-start").state
  backoffState = Model.vmMonitorTransition(backoffState, "watcher-stopped", backoffState.watcherGeneration).state
  assert.equal(backoffState.backoffSeconds, expected)
}

let stable = Model.vmMonitorState()
stable = Model.vmMonitorTransition(stable, "capability-found").state
const watcherGeneration = stable.watcherGeneration
stable = Model.vmMonitorTransition(stable, "watcher-started", watcherGeneration).state
assert.equal(stable.stabilityGeneration, watcherGeneration)
stable = Model.vmMonitorTransition(stable, "watcher-stable", { generation: watcherGeneration, running: false }).state
assert.equal(stable.stableGeneration, 0)
stable = Model.vmMonitorTransition(stable, "watcher-stable", { generation: watcherGeneration, running: true }).state
assert.equal(stable.stableGeneration, watcherGeneration)

const queued = Model.vmMonitorTransition(stable, "reconcile-request", watcherGeneration)
assert.equal(queued.state.reconciliationGeneration, 1)
const queuedAgain = Model.vmMonitorTransition(queued.state, "reconcile-request", watcherGeneration + 1)
assert.equal(queuedAgain.state.reconciliationGeneration, watcherGeneration)
assert.equal(queuedAgain.state.queuedReconciliationGeneration, watcherGeneration + 1)
const followed = Model.vmMonitorTransition(queuedAgain.state, "reconcile-finished", {
  generation: 1, watcherGeneration: watcherGeneration, fresh: true, stable: true
})
assert.equal(followed.startReconciliation, true)
assert.equal(followed.state.reconciliationGeneration, 2)

const failedStateProcess = Model.vmMonitorTransition(followed.state, "reconcile-process-stopped", {
  generation: 2
})
assert.equal(failedStateProcess.state.reconciliationRunning, false)
