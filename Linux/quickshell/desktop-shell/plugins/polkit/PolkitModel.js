/**
 * Check whether an authentication prompt suggests fingerprint input.
 *
 * @param {*} text Backend prompt text.
 * @returns {boolean} Whether the prompt mentions fingerprint input.
 */
function promptLooksFingerprint(text) {
  const normalized = String(text || "").toLowerCase()
  return normalized.includes("finger") || normalized.includes("fprint") || normalized.includes("swipe")
}

/**
 * Check whether an active PAM auth line enables pam_fprintd.
 *
 * Blank lines and comment-only lines are ignored. PAM modules in other
 * management groups do not count as fingerprint authentication configuration.
 *
 * @param {*} raw PAM configuration text.
 * @returns {boolean} Whether pam_fprintd is present in the auth stack.
 */
function fingerprintConfiguredFromPamConfig(raw) {
  return String(raw || "").split("\n").some(lineValue => {
    const line = lineValue.replace(/#.*/, "").trim()
    if (!line || !/^auth\s+/.test(line)) return false

    const fields = line.match(/\[[^\]]*\]|[^\s]+/g) || []
    if (fields.length < 3) return false

    const moduleName = fields[2].split("/").pop()
    return moduleName === "pam_fprintd.so"
  })
}

/**
 * Convert a polkit authorization message into a concise display label.
 *
 * @param {*} message Authorization message.
 * @returns {string} Concise label or the original message when unmatched.
 */
function authorizationLabel(message) {
  const text = String(message || "")
  const match = text.match(/^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i)
  return match ? `Authorize running '${match[1]}'` : text
}

/**
 * Normalize polkit registration state for the agent UI.
 *
 * @param {boolean} enabled Whether registration is enabled.
 * @param {boolean} registered Whether registration succeeded.
 * @param {*} error Registration error text.
 * @returns {{registered: boolean, error: string}} Stable registration state.
 */
function registrationState(enabled, registered, error) {
  if (!enabled) return { registered: false, error: "registration disabled" }
  if (registered) return { registered: true, error: "" }
  return { registered: false, error: String(error || "polkit registration failed") }
}

/**
 * Resolve a focused Hyprland monitor to a Quickshell screen.
 *
 * @param {ArrayLike<{name?: string}>|null} screens Available screens.
 * @param {*} focusedMonitorName Focused monitor name.
 * @returns {object|null} Matching screen or null while the focused screen is unresolved.
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

  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    promptLooksFingerprint,
    fingerprintConfiguredFromPamConfig,
    authorizationLabel,
    registrationState,
    screenForMonitor,
  }
}
