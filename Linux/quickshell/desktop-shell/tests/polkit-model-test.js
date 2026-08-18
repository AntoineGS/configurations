const assert = require("node:assert/strict")
const model = require("../plugins/polkit/PolkitModel.js")

assert.equal(model.promptLooksFingerprint("Place your finger on the reader"), true)
assert.equal(model.promptLooksFingerprint("Password:"), false)
assert.deepEqual(model.snapshotAuthContext(
  "Authentication is required\nMessage supplied by backend",
  "org.example.desktop.modify"
), {
  message: "Authentication is required Message supplied by backend",
  actionId: "org.example.desktop.modify"
})
assert.equal(model.snapshotAuthContext(
  "spoof-like requester application text\nAction ID: org.attacker.fake",
  "org.freedesktop.policykit.exec"
).actionId, "org.freedesktop.policykit.exec",
  "the action ID remains independent from message text")
assert.equal(model.snapshotAuthContext(
  "spoof-like requester application text\nAction ID: org.attacker.fake",
  "org.freedesktop.policykit.exec"
).message, "spoof-like requester application text Action ID: org.attacker.fake",
  "message text is kept on one line and cannot replace the trusted action ID")
const longActionIdA = "org.example.desktop." + "A".repeat(128) + "-middle-a-" + "z".repeat(180)
const longActionIdB = "org.example.desktop." + "A".repeat(128) + "-middle-b-" + "z".repeat(180)
const longContextA = model.snapshotAuthContext("Request message", longActionIdA)
const longContextB = model.snapshotAuthContext("Request message", longActionIdB)
assert.equal(longContextA.actionId.length, 256, "action IDs have a bounded display snapshot")
assert.equal(longContextB.actionId.length, 256, "bounded action IDs remain readable")
assert.notEqual(longContextA.actionId, longContextB.actionId,
  "long action IDs that differ in the middle remain distinguishable")
assert.equal(model.fingerprintConfiguredFromProbeOutput("true\n"), true)
assert.equal(model.fingerprintConfiguredFromProbeOutput("false\n"), false)
assert.equal(model.fingerprintConfiguredFromProbeOutput("true false\n"), null)
assert.equal(model.fingerprintConfiguredFromProbeOutput("true "), null)
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
