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
assert.equal(model.authorizationLabel("Authentication is required to run 'pacman' as the super user"), "Authorize running 'pacman'")
assert.deepEqual(model.registrationState(false, false, ""), { registered: false, error: "registration disabled" })
assert.deepEqual(model.registrationState(true, true, "ignored"), { registered: true, error: "" })
assert.deepEqual(model.registrationState(true, false, "name already owned"), { registered: false, error: "name already owned" })
assert.deepEqual(model.registrationState(true, false, ""), { registered: false, error: "polkit registration failed" })
