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
    const line = lineValue.trim()
    if (!line || line.startsWith("#") || !/^auth\s+/.test(line)) return false
    return line.includes("pam_fprintd.so")
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

if (typeof module !== "undefined") {
  module.exports = {
    promptLooksFingerprint,
    fingerprintConfiguredFromPamConfig,
    authorizationLabel,
    registrationState,
  }
}
