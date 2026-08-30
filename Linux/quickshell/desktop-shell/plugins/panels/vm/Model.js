var KIB_PER_GIB = 1048576
var MINIMUM_MEMORY_GIB = 1
var BACKOFF_SECONDS = [2, 4, 8, 16, 32, 60]

function nextBackoff(seconds) {
  var current = Number(seconds)
  if (!isFinite(current) || current <= 0) return BACKOFF_SECONDS[0]
  for (var i = 0; i < BACKOFF_SECONDS.length - 1; i++) {
    if (current <= BACKOFF_SECONDS[i]) return BACKOFF_SECONDS[i + 1]
  }
  return BACKOFF_SECONDS[BACKOFF_SECONDS.length - 1]
}

function vmMonitorState() {
  return {
    capabilityAvailable: false,
    watcherGeneration: 0,
    watcherStartedGeneration: 0,
    watcherFailureGeneration: 0,
    stabilityGeneration: 0,
    stableGeneration: 0,
    reconciliationRunning: false,
    reconciliationQueued: false,
    reconciliationGeneration: 0,
    reconciliationWatcherGeneration: 0,
    queuedReconciliationGeneration: 0,
    reconciliationFinishedGeneration: 0,
    startupPhase: true,
    backoffSeconds: 0,
    runningConfirmed: false,
  }
}

function vmMonitorTransition(state, event, argument) {
  var next = Object.assign({}, vmMonitorState(), state || {})
  var result = { state: next, startWatcher: false, retryWatcher: false, startReconciliation: false, generation: 0 }
  if (event === "capability-found") {
    next.capabilityAvailable = true
    next.watcherGeneration += 1
    next.watcherFailureGeneration = 0
    next.stabilityGeneration = 0
    next.stableGeneration = 0
    result.startWatcher = true
    if (next.reconciliationRunning) {
      next.reconciliationQueued = true
      next.queuedReconciliationGeneration = next.watcherGeneration
    } else {
      result.startReconciliation = true
      next.reconciliationRunning = true
      next.reconciliationGeneration += 1
      next.reconciliationWatcherGeneration = next.watcherGeneration
      result.generation = next.reconciliationGeneration
    }
  } else if (event === "capability-missing") {
    next.capabilityAvailable = false
    next.runningConfirmed = false
  } else if (event === "watcher-start") {
    next.watcherGeneration += 1
    next.watcherStartedGeneration = 0
    next.watcherFailureGeneration = 0
    next.stabilityGeneration = 0
    next.stableGeneration = 0
    result.startWatcher = true
    result.generation = next.watcherGeneration
  } else if (event === "watcher-started") {
    if (argument === next.watcherGeneration) {
      next.watcherStartedGeneration = argument
      next.stabilityGeneration = argument
    }
  } else if (event === "watcher-stopped" || event === "watcher-exited") {
    if (argument === next.watcherGeneration && next.watcherFailureGeneration !== argument) {
      next.watcherFailureGeneration = argument
      next.stabilityGeneration = 0
      next.stableGeneration = 0
      next.backoffSeconds = nextBackoff(next.backoffSeconds)
      result.retryWatcher = true
    }
  } else if (event === "watcher-stable") {
    var stability = argument || {}
    if (stability.generation === next.watcherGeneration && stability.running
        && next.stabilityGeneration === stability.generation)
      next.stableGeneration = stability.generation
  } else if (event === "reconcile-request") {
    if (next.reconciliationRunning) {
      next.reconciliationQueued = true
      next.queuedReconciliationGeneration = argument || next.watcherGeneration
    }
    else {
      next.reconciliationRunning = true
      next.reconciliationGeneration += 1
      next.reconciliationWatcherGeneration = argument || next.watcherGeneration
      result.generation = next.reconciliationGeneration
      result.startReconciliation = true
    }
  } else if (event === "schedule-tick") {
    next.startupPhase = false
    if (next.reconciliationRunning) {
      next.reconciliationQueued = true
      next.queuedReconciliationGeneration = next.watcherGeneration
    } else {
      next.reconciliationRunning = true
      next.reconciliationGeneration += 1
      next.reconciliationWatcherGeneration = next.watcherGeneration
      result.generation = next.reconciliationGeneration
      result.startReconciliation = true
    }
  } else if (event === "reconcile-finished") {
    var reconciliation = argument || {}
    if (reconciliation.generation !== next.reconciliationGeneration
        || next.reconciliationFinishedGeneration === reconciliation.generation) return result
    next.reconciliationRunning = false
    next.reconciliationFinishedGeneration = reconciliation.generation
    if (reconciliation.watcherGeneration === next.watcherGeneration && reconciliation.fresh
        && reconciliation.stable && next.stableGeneration === reconciliation.watcherGeneration) {
      next.backoffSeconds = 0
    }
    if (next.reconciliationQueued) {
      next.reconciliationQueued = false
      next.reconciliationRunning = true
      next.reconciliationGeneration += 1
      next.reconciliationWatcherGeneration = next.queuedReconciliationGeneration || next.watcherGeneration
      next.queuedReconciliationGeneration = 0
      result.generation = next.reconciliationGeneration
      result.startReconciliation = true
    }
  } else if (event === "reconcile-process-stopped") {
    var stopped = argument || {}
    if (stopped.generation !== next.reconciliationGeneration
        || next.reconciliationFinishedGeneration === stopped.generation) return result
    next.reconciliationRunning = false
    next.reconciliationFinishedGeneration = stopped.generation
    if (next.reconciliationQueued) {
      next.reconciliationQueued = false
      next.reconciliationRunning = true
      next.reconciliationGeneration += 1
      next.reconciliationWatcherGeneration = next.queuedReconciliationGeneration || next.watcherGeneration
      next.queuedReconciliationGeneration = 0
      result.generation = next.reconciliationGeneration
      result.startReconciliation = true
    }
  } else if (event === "state-applied") {
    next.runningConfirmed = argument === true
  }
  return result
}

function parseCpuSnapshot(raw) {
  if (typeof raw !== "string") return null
  var fields = raw.split(/\r?\n/)[0].trim().split(/\s+/)
  if (fields.length < 9 || fields[0] !== "cpu") return null
  var values = fields.slice(1, 9).map(function(value) { return /^\d+$/.test(value) ? Number(value) : NaN })
  if (values.some(function(value) { return !isFinite(value) })) return null
  var idle = values[3] + (values[4] || 0)
  var total = values.reduce(function(sum, value) { return sum + value }, 0)
  return isFinite(total) && isFinite(idle) ? { total: total, idle: idle } : null
}

function cpuUsage(previous, current) {
  if (!previous || !current) return null
  var totalDelta = current.total - previous.total
  var idleDelta = current.idle - previous.idle
  if (!isFinite(totalDelta) || !isFinite(idleDelta) || totalDelta <= 0 || idleDelta < 0) return null
  return Math.max(0, Math.min(100, Math.floor((totalDelta - idleDelta) * 100 / totalDelta)))
}

function parseMemorySnapshot(raw) {
  if (typeof raw !== "string") return null
  var values = {}
  raw.split(/\r?\n/).forEach(function(line) {
    var match = /^(MemTotal|MemAvailable):\s+(\d+)\s+kB\s*$/.exec(line)
    if (match) values[match[1]] = Number(match[2])
  })
  var total = values.MemTotal
  var available = values.MemAvailable
  if (!isFinite(total) || !isFinite(available) || total <= 0 || available < 0 || available > total) return null
  var used = total - available
  return { totalKiB: total, availableKiB: available, usedKiB: used, percent: 100 - Math.floor(available * 100 / total) }
}

function formatKibGiB(kib) {
  var tenths = Math.floor((kib * 10 + 524288) / 1048576)
  return Math.floor(tenths / 10) + "." + (tenths % 10)
}

function formatMemoryTooltip(snapshot) {
  return formatKibGiB(snapshot.usedKiB) + " / " + formatKibGiB(snapshot.totalKiB).replace(/\.0$/, "") + " GiB"
}

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function finiteNumber(value) {
  if (typeof value !== "number" || !isFinite(value)) return null
  return value
}

function nonNegativeNumber(value) {
  var number = finiteNumber(value)
  return number === null || number < 0 ? null : number
}

function errorValue(value) {
  if (value === null || value === undefined) return null
  return typeof value === "string" ? value : null
}

function availablePercent(available, value) {
  if (!available) return undefined
  var number = finiteNumber(value)
  return number === null ? undefined : number
}

/**
 * Return a safe model value for an unavailable or malformed VM payload.
 *
 * @param {string|null|undefined} error optional diagnostic to expose
 * @returns {Object} normalized state
 */
function emptyState(error) {
  return {
    available: false,
    stale: false,
    malformed: false,
    error: errorValue(error),
    visible: false,
    name: "",
    vcpus: 0,
    cpuAvailable: false,
    cpuPercent: undefined,
    memoryAllocationAvailable: false,
    memoryUsageAvailable: false,
    memoryPercent: undefined,
    currentKiB: null,
    maximumKiB: null,
    usedKiB: null,
    showMemoryUsage: false,
    canResize: false,
    confirmedRunning: false
  }
}

function malformedState(error) {
  var state = emptyState(error)
  state.stale = true
  state.malformed = true
  return state
}

function emptyHostStat() {
  return {
    available: false,
    stale: false,
    text: "",
    icon: "",
    value: "",
    tooltip: "",
    percent: undefined
  }
}

function normalizeHostStat(raw) {
  try {
    var payload = typeof raw === "string" ? JSON.parse(raw) : raw
    if (!isPlainObject(payload)) throw new Error("host stat must be an object")
    if (typeof payload.text !== "string") throw new Error("host stat text must be a string")
    if (typeof payload.tooltip !== "string") throw new Error("host stat tooltip must be a string")
    if (typeof payload.class !== "string") throw new Error("host stat class must be a string")
    var hasIcon = Object.prototype.hasOwnProperty.call(payload, "icon")
    var hasValue = Object.prototype.hasOwnProperty.call(payload, "value")
    if (hasIcon !== hasValue || (hasIcon && (typeof payload.icon !== "string" || typeof payload.value !== "string")))
      throw new Error("host stat icon and value must both be strings")
    var percent = nonNegativeNumber(payload.percentage)
    if (percent === null || percent > 100) throw new Error("host stat percentage must be between 0 and 100")
    return {
      available: true,
      stale: payload.class === "stale",
      text: payload.text,
      icon: hasIcon ? payload.icon : "",
      value: hasValue ? payload.value : payload.text,
      tooltip: payload.tooltip,
      percent: percent
    }
  } catch (_) {
    return emptyHostStat()
  }
}

function hostStateFromRaw(previous, raw) {
  var parsed = normalizeHostStat(raw)
  if (parsed.available) return parsed
  return previous && previous.available === true ? previous : parsed
}

/**
 * Normalize a VM state envelope received as JSON or as an already parsed object.
 * Only scalar fields needed by the widget are copied out of the payload.
 *
 * @param {string|Object} raw state envelope
 * @returns {Object} normalized widget state
 */
function normalizeState(raw) {
  try {
    var envelope = typeof raw === "string" ? JSON.parse(raw) : raw
    if (!isPlainObject(envelope)) throw new Error("VM state must be an object")
    if (typeof envelope.available !== "boolean") throw new Error("VM state available flag must be boolean")
    if (typeof envelope.stale !== "boolean") throw new Error("VM state stale flag must be boolean")
    if (!Object.prototype.hasOwnProperty.call(envelope, "error")) throw new Error("VM state error field is missing")
    if (envelope.error !== null && typeof envelope.error !== "string")
      throw new Error("VM state error field must be a string or null")
    if (!isPlainObject(envelope.data)) throw new Error("VM state data must be an object")

    var data = envelope.data
    var cpu = isPlainObject(data.cpu) ? data.cpu : {}
    var memory = isPlainObject(data.memory) ? data.memory : {}
    var available = envelope.available === true
    var stale = envelope.stale === true
    var cpuAvailable = cpu.available === true
    var memoryAllocationAvailable = memory.allocationAvailable === true
    var memoryUsageAvailable = memory.usageAvailable === true
    var vcpus = finiteNumber(data.vcpus)
    var currentKiB = nonNegativeNumber(memory.currentKiB)
    var maximumKiB = nonNegativeNumber(memory.maximumKiB)
    var usedKiB = nonNegativeNumber(memory.usedKiB)
    var cpuPercent = availablePercent(cpuAvailable, cpu.percent)
    var memoryPercent = availablePercent(memoryUsageAvailable, memory.percent)

    if (vcpus === null || vcpus < 0 || vcpus % 1 !== 0) vcpus = 0

    return {
      available: available,
      stale: stale,
      malformed: false,
      error: errorValue(envelope.error),
      visible: available,
      name: typeof data.name === "string" ? data.name : "",
      vcpus: vcpus,
      cpuAvailable: cpuAvailable,
      cpuPercent: cpuPercent,
      memoryAllocationAvailable: memoryAllocationAvailable,
      memoryUsageAvailable: memoryUsageAvailable,
      memoryPercent: memoryPercent,
      currentKiB: currentKiB,
      maximumKiB: maximumKiB,
      usedKiB: usedKiB,
      showMemoryUsage: available && memoryUsageAvailable && memoryPercent !== undefined && memoryPercent !== null
        && usedKiB !== null,
      canResize: available && !stale && memoryAllocationAvailable && currentKiB !== null && maximumKiB !== null
        && maximumKiB > 0,
      confirmedRunning: available && !stale
    }
  } catch (error) {
    return malformedState(error && error.message ? error.message : String(error))
  }
}

function staleState(previous, error) {
  var retained = {}
  var source = isPlainObject(previous) ? previous : emptyState()

  for (var key in source) retained[key] = source[key]
  retained.stale = true
  retained.malformed = true
  retained.error = errorValue(error) || "VM state helper output was malformed"
    retained.canResize = false
    retained.confirmedRunning = false
  return retained
}

function diagnostic(parseError, processError) {
  var parseMessage = errorValue(parseError)
  var processMessage = errorValue(processError)
  if (parseMessage && processMessage) return parseMessage + "; " + processMessage
  return parseMessage || processMessage || "VM state helper output was malformed"
}

/**
 * Apply helper output without allowing malformed data to erase a visible VM.
 *
 * @param {Object} previous previously displayed normalized state
 * @param {string|Object} raw state helper output
 * @param {string|null|undefined} processError process-level diagnostic
 * @returns {Object} normalized or retained stale state
 */
function stateFromRaw(previous, raw, processError) {
  var parsed = normalizeState(raw)
  if (!parsed.malformed) return parsed

  var error = diagnostic(parsed.error, processError)
  if (previous && previous.visible === true) return staleState(previous, error)
  return malformedState(error)
}

function clampPercent(value) {
  var number = Number(value)
  if (!isFinite(number)) return null
  return Math.max(0, Math.min(100, Math.round(number)))
}

/**
 * Format a percentage without allowing invalid numeric output.
 *
 * @param {*} value percentage value
 * @returns {string} display percentage
 */
function formatPercent(value) {
  var percent = clampPercent(value)
  return percent === null ? "--%" : percent + "%"
}

/**
 * Format a KiB value as a floored GiB label.
 *
 * @param {*} kib memory in KiB
 * @returns {string} display memory value
 */
function formatGiB(kib) {
  var value = nonNegativeNumber(kib)
  if (value === null) return "-- GiB"
  return Math.floor(value / KIB_PER_GIB) + " GiB"
}

/**
 * Return the smallest memory size accepted by the VM action.
 *
 * @returns {number} minimum memory in GiB
 */
function minimumGiB() {
  return MINIMUM_MEMORY_GIB
}

function memoryGiB(state, key) {
  var value = state && typeof state === "object" ? nonNegativeNumber(state[key]) : null
  if (value === null || value === undefined) return minimumGiB()
  return Math.max(minimumGiB(), Math.floor(value / KIB_PER_GIB))
}

/**
 * Return the maximum whole GiB supported by a normalized VM state.
 *
 * @param {Object} state normalized VM state
 * @returns {number} maximum memory in GiB
 */
function maximumGiB(state) {
  return memoryGiB(state, "maximumKiB")
}

/**
 * Return the current whole GiB value from a normalized VM state.
 *
 * @param {Object} state normalized VM state
 * @returns {number} current memory in GiB
 */
function currentGiB(state) {
  return memoryGiB(state, "currentKiB")
}

function vmMetricText(percent) {
  return "(" + formatPercent(percent) + ")"
}

function memoryCritical(percent) {
  var value = finiteNumber(percent)
  return value !== null && value > 85
}

if (typeof module !== "undefined") {
  module.exports = {
    parseCpuSnapshot: parseCpuSnapshot,
    cpuUsage: cpuUsage,
    parseMemorySnapshot: parseMemorySnapshot,
    formatKibGiB: formatKibGiB,
    formatMemoryTooltip: formatMemoryTooltip,
    emptyState: emptyState,
    emptyHostStat: emptyHostStat,
    normalizeState: normalizeState,
    normalizeHostStat: normalizeHostStat,
    stateFromRaw: stateFromRaw,
    hostStateFromRaw: hostStateFromRaw,
    formatPercent: formatPercent,
    formatGiB: formatGiB,
    minimumGiB: minimumGiB,
    maximumGiB: maximumGiB,
    currentGiB: currentGiB,
    vmMetricText: vmMetricText,
    memoryCritical: memoryCritical,
    nextBackoff: nextBackoff,
    vmMonitorState: vmMonitorState,
    vmMonitorTransition: vmMonitorTransition,
  }
}
