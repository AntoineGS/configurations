const DEFAULT_MAX = 100
const DEFAULT_DURATION = 1200
const MAX_DURATION = 2147483647
const PAYLOAD_KEYS = ["icon", "message", "value", "max", "progressText", "duration"]

/**
 * Clamp a number to an inclusive range.
 *
 * @param {number} value
 * @param {number} min
 * @param {number} max
 * @returns {number}
 */
function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// The widest glyph `iconFor` can return. The progress OSD sizes its icon
// column to it so the bar keeps its place as the icon changes.
const widestIcon = ""

/**
 * Return the icon glyph for an OSD icon name or progress percentage.
 *
 * @param {string} name
 * @param {number} percent
 * @returns {string}
 */
function iconFor(name, percent) {
  const normalizedName = String(name || "").toLowerCase()
  if (normalizedName === "volume-muted" || normalizedName === "volume-mute" || normalizedName === "muted" || normalizedName === "mute") return ""
  if (normalizedName === "volume-low") return ""
  if (normalizedName === "volume-medium") return ""
  if (normalizedName === "volume-high" || normalizedName === "volume") return ""
  if (normalizedName === "microphone-muted" || normalizedName === "microphone-off" || normalizedName === "mic-muted" || normalizedName === "mic-off") return "󰍭"
  if (normalizedName === "microphone" || normalizedName === "mic") return "󰍬"
  if (normalizedName === "keyboard") return "󰌌"
  if (normalizedName === "brightness" || normalizedName === "display") return "󰍹"
  if (normalizedName === "touchpad") return "󰟸"
  if (normalizedName === "touch" || normalizedName === "touchscreen") return "󰝁"
  if (normalizedName === "reboot" || normalizedName === "restart") return "󰜉"
  if (normalizedName === "shutdown" || normalizedName === "power" || normalizedName === "poweroff") return "󰐥"
  if (normalizedName === "logout" || normalizedName === "sign-out" || normalizedName === "leave") return "󰍃"
  if (normalizedName === "media" || normalizedName === "player") return "󰝚"
  if (normalizedName === "media-source" || normalizedName === "player-source") return "󰝚"
  if (normalizedName === "media-play" || normalizedName === "player-play") return "󰐊"
  if (normalizedName === "media-pause" || normalizedName === "player-pause") return "󰏤"
  if (normalizedName === "media-next" || normalizedName === "player-next") return "󰒭"
  if (normalizedName === "media-previous" || normalizedName === "player-previous") return "󰒮"
  if (normalizedName.length > 0) return name
  if (percent <= 0) return ""
  if (percent <= 33) return ""
  if (percent <= 66) return ""
  return ""
}

/**
 * Resolve a focused compositor monitor to a Quickshell screen.
 *
 * If the focused monitor is unavailable or has not appeared in the screen
 * list yet, use the first available screen as the documented fallback. With
 * no screens, return null so the caller can leave the window unmapped.
 *
 * @param {ArrayLike<{name?: string}>|null} screens
 * @param {string} focusedMonitorName
 * @returns {object|null}
 */
function screenForMonitor(screens, focusedMonitorName) {
  const count = screens && typeof screens.length === "number" ? screens.length : 0
  const monitorName = String(focusedMonitorName || "")

  if (monitorName.length > 0) {
    for (let index = 0; index < count; index++) {
      const screen = screens[index]
      if (screen && String(screen.name || "") === monitorName) return screen
    }
  }

  return count > 0 ? screens[0] : null
}

/**
 * Check the shell-level availability contract for the keep-loaded OSD loader.
 *
 * @param {boolean} previewMode whether preview suppresses keep-loaded overlays
 * @param {{status: *, item: {ping: function}|null}|null} loader OSD loader
 * @param {*} errorStatus Loader.Error from QML
 * @returns {boolean}
 */
function healthAvailable(previewMode, loader, errorStatus) {
  if (previewMode || !loader || !loader.item) return false
  if (errorStatus !== undefined && loader.status === errorStatus) return false
  try {
    return typeof loader.item.ping === "function" && loader.item.ping() === "pong"
  } catch (error) {
    return false
  }
}

/**
 * Return the stable shape used for rejected payloads.
 *
 * @param {string} error
 * @returns {{valid: false, iconKey: string, icon: string, message: string, value: number, maxValue: number, hasProgress: boolean, duration: number, error: string}}
 */
function invalidState(error) {
  return {
    valid: false,
    iconKey: "",
    icon: "",
    message: "",
    value: 0,
    maxValue: DEFAULT_MAX,
    hasProgress: false,
    duration: DEFAULT_DURATION,
    error: String(error),
  }
}

/**
 * Check that a parsed value is a finite JSON number.
 *
 * @param {*} value
 * @returns {boolean}
 */
function isFiniteNumber(value) {
  return typeof value === "number" && isFinite(value)
}

/**
 * Normalize a non-negative duration to the QML/Timer signed-int range.
 * Positive fractions round up so they cannot become an accidental zero timer.
 *
 * @param {number} value
 * @returns {number}
 */
function normalizeDuration(value) {
  if (value === 0) return 0
  return Math.min(MAX_DURATION, Math.max(1, Math.ceil(value)))
}

/**
 * Normalize the JSON payload accepted by the OSD IPC endpoint.
 *
 * Unknown fields and malformed values are rejected without throwing. Missing
 * max and duration retain the pinned OSD defaults for compatibility.
 *
 * @param {string} payloadJson
 * @returns {{valid: boolean, iconKey: string, icon: string, message: string, value: number, maxValue: number, hasProgress: boolean, duration: number, error: string}}
 */
function normalizePayload(payloadJson) {
  let payload
  try {
    if (typeof payloadJson !== "string" || payloadJson.length === 0) return invalidState("payload must be a JSON object")
    payload = JSON.parse(payloadJson)
  } catch (error) {
    return invalidState("payload is not valid JSON")
  }

  if (payload === null || typeof payload !== "object" || Array.isArray(payload))
    return invalidState("payload must be a JSON object")

  for (const key of Object.keys(payload)) {
    if (!PAYLOAD_KEYS.includes(key)) return invalidState(`unsupported payload field: ${key}`)
  }

  for (const key of ["value", "max", "duration"]) {
    if (payload[key] !== undefined && !isFiniteNumber(payload[key]))
      return invalidState(`${key} must be a finite number`)
  }

  for (const key of ["icon", "message", "progressText"]) {
    if (payload[key] !== undefined && typeof payload[key] !== "string")
      return invalidState(`${key} must be a string`)
  }

  const maxValue = payload.max === undefined ? DEFAULT_MAX : payload.max
  if (maxValue <= 0) return invalidState("max must be greater than 0")

  const rawDuration = payload.duration === undefined ? DEFAULT_DURATION : payload.duration
  if (rawDuration < 0) return invalidState("duration must be non-negative")
  const duration = normalizeDuration(rawDuration)

  const iconKey = String(payload.icon || "").toLowerCase()
  const rawMessage = payload.message || ""
  const hasProgress = payload.value !== undefined && rawMessage === ""
  const value = hasProgress ? clamp(payload.value, 0, maxValue) : 0
  const percent = hasProgress ? Math.round(value / maxValue * 100) : -1
  const message = rawMessage || (hasProgress ? (payload.progressText || `${percent}%`) : "")

  return {
    valid: true,
    iconKey,
    icon: iconFor(payload.icon, percent),
    message,
    value,
    maxValue,
    hasProgress,
    duration,
    error: "",
  }
}

/**
 * Preserve the pinned model's direct state helper for existing consumers.
 * New OSD IPC calls use normalizePayload so malformed JSON cannot escape.
 *
 * @param {string} iconName
 * @param {string} rawMessage
 * @param {string|number} rawValue
 * @param {string|number} rawMax
 * @param {string} rawProgressText
 * @param {string|number} rawDuration
 * @returns {{iconKey: string, maxValue: number, hasProgress: boolean, value: number, message: string, icon: string, duration: number}}
 */
function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
  const maxValue = Math.max(1, parseInt(rawMax || "100", 10))
  const parsedValue = parseInt(rawValue || "0", 10)
  const hasProgress = rawValue !== "" && !isNaN(parsedValue) && rawMessage === ""
  const value = hasProgress ? clamp(parsedValue, 0, maxValue) : 0
  const percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
  const parsedDuration = parseInt(rawDuration || "1200", 10)

  return {
    iconKey: String(iconName || "").toLowerCase(),
    maxValue,
    hasProgress,
    value,
    message: String(rawMessage || (hasProgress ? (rawProgressText || `${percent}%`) : "")),
    icon: iconFor(iconName, percent),
    duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration),
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    widestIcon,
    iconFor,
    normalizePayload,
    screenForMonitor,
    healthAvailable,
    stateForShow,
  }
}
