var KIB_PER_GIB = 1048576
var MINIMUM_MEMORY_GIB = 1

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
    canResize: false
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
    var percent = nonNegativeNumber(payload.percentage)
    if (percent === null || percent > 100) throw new Error("host stat percentage must be between 0 and 100")
    return {
      available: true,
      stale: payload.class === "stale",
      text: payload.text,
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
        && maximumKiB > 0
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
    memoryCritical: memoryCritical
  }
}
