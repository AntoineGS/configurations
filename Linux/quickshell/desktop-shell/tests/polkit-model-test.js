const assert = require("node:assert/strict")
const model = require("../plugins/polkit/PolkitModel.js")

assert.equal(model.promptLooksFingerprint("Place your finger on the reader"), true)
assert.equal(model.promptLooksFingerprint("Password:"), false)
assert.equal(model.fingerprintConfiguredFromPamConfig(`
# auth sufficient pam_fprintd.so
auth optional pam_exec.so /usr/bin/check-lid
auth sufficient pam_fprintd.so
auth required pam_unix.so
`), true)
assert.equal(model.fingerprintConfiguredFromPamConfig("auth required pam_unix.so"), false)
assert.equal(model.fingerprintConfiguredFromPamConfig("# auth required pam_fprintd.so"), false,
  "comment-only PAM lines do not enable fingerprint authentication")
assert.equal(model.fingerprintConfiguredFromPamConfig("auth required pam_unix.so # pam_fprintd.so"), false,
  "inline PAM comments do not enable fingerprint authentication")
assert.equal(model.fingerprintConfiguredFromPamConfig("account required pam_fprintd.so"), false,
  "non-auth PAM lines do not enable fingerprint authentication")
assert.equal(model.fingerprintConfiguredFromPamConfig("auth required pam_unix.so /usr/lib/security/pam_fprintd.so"), false,
  "module arguments do not enable fingerprint authentication")
assert.equal(model.fingerprintConfiguredFromPamConfig("auth required pam_fprintd.so.extra"), false,
  "longer module names do not match pam_fprintd")
assert.equal(model.fingerprintConfiguredFromPamConfig("auth required pam_fprintd.so"), true,
  "ordinary auth lines match pam_fprintd")
assert.equal(model.fingerprintConfiguredFromPamConfig("auth [success=1 default=ignore] /usr/lib/security/pam_fprintd.so"), true,
  "bracketed control auth lines match the module basename")
assert.equal(model.authorizationLabel("Authentication is required to run 'pacman' as the super user"), "Authorize running 'pacman'")
assert.deepEqual(model.registrationState(false, false, ""), { registered: false, error: "registration disabled" })
assert.deepEqual(model.registrationState(true, true, "ignored"), { registered: true, error: "" })
assert.deepEqual(model.registrationState(true, false, "name already owned"), { registered: false, error: "name already owned" })
assert.deepEqual(model.registrationState(true, false, ""), { registered: false, error: "polkit registration failed" })

const firstScreen = { name: "DP-1" }
const focusedScreen = { name: "HDMI-A-1" }
assert.equal(model.screenForMonitor([firstScreen, focusedScreen], "HDMI-A-1"), focusedScreen,
  "focused monitor selects the matching screen")
assert.equal(model.screenForMonitor([firstScreen, focusedScreen], "missing"), null,
  "missing focused monitor leaves authentication pending")
assert.equal(model.screenForMonitor([firstScreen, focusedScreen], ""), null,
  "no focused monitor leaves authentication pending")
assert.equal(model.screenForMonitor([], "DP-1"), null,
  "an empty screen list leaves the dialog unmapped")

const screensBeforeResolution = [firstScreen]
assert.equal(model.screenForMonitor(screensBeforeResolution, "HDMI-A-1"), null,
  "an unresolved focused monitor starts unmapped")
screensBeforeResolution.push(focusedScreen)
assert.equal(model.screenForMonitor(screensBeforeResolution, "HDMI-A-1"), focusedScreen,
  "the matching screen maps when it later appears")
