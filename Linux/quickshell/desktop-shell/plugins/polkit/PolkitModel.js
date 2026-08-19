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
 * Snapshot the stable authorization context for one native AuthFlow.
 *
 * The message is made suitable for the compact one-line context display. The
 * action ID is kept verbatim so the UI can show the backend's trusted identity
 * without deriving it from mutable prompt text.
 *
 * @param {*} message Authorization message at request start.
 * @param {*} actionId Native AuthFlow action ID at request start.
 * @returns {{message: string, actionId: string}} Stable request context.
 */
function snapshotAuthContext(message, actionId) {
  const messageText = message === null || message === undefined ? "" : String(message)
  const actionText = actionId === null || actionId === undefined ? "" : String(actionId)
  return {
    message: messageText.replace(/\s+/g, " ").trim(),
    actionId: actionText,
  }
}

/**
 * Parse the standalone PAM probe's deliberately tiny output contract.
 *
 * @param {*} raw Probe stdout.
 * @returns {boolean|null} Configuration state, or null for invalid output.
 */
function fingerprintConfiguredFromProbeOutput(raw) {
  const output = String(raw === null || raw === undefined ? "" : raw)
  if (output === "true" || output === "true\n") return true
  if (output === "false" || output === "false\n") return false
  return null
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
    snapshotAuthContext,
    fingerprintConfiguredFromProbeOutput,
    authorizationLabel,
    registrationState,
    screenForMonitor,
  }
}
