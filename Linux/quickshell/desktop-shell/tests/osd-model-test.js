const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const model = require("../plugins/osd/OsdModel.js")

assert.deepEqual(model.normalizePayload('{"icon":"volume","message":"","value":140,"max":100,"progressText":"140%","duration":1500}'), {
  valid: true,
  iconKey: "volume",
  icon: "",
  message: "140%",
  value: 100,
  maxValue: 100,
  hasProgress: true,
  duration: 1500,
  error: "",
})

for (const raw of ["", "{", "[]", '{"value":"loud"}', '{"max":0}', '{"duration":-1}', '{"extra":true}']) {
  assert.equal(model.normalizePayload(raw).valid, false, `expected invalid payload: ${raw}`)
}

assert.equal(model.iconFor("volume-muted", 0), "")
assert.equal(model.iconFor("microphone-muted", 0), "󰍭")
assert.equal(model.iconFor("brightness", 50), "󰍹")

assert.deepEqual(model.normalizePayload('{"icon":"volume","message":"","value":12.5,"max":25.5,"progressText":"49%","duration":0.5}'), {
  valid: true,
  iconKey: "volume",
  icon: "",
  message: "49%",
  value: 12.5,
  maxValue: 25.5,
  hasProgress: true,
  duration: 1,
  error: "",
})

assert.deepEqual(model.normalizePayload('{"value":1e308,"max":1e308,"duration":2147483648}'), {
  valid: true,
  iconKey: "",
  icon: "",
  message: "100%",
  value: 1e308,
  maxValue: 1e308,
  hasProgress: true,
  duration: 2147483647,
  error: "",
})

assert.deepEqual(model.normalizePayload('{"value":-5,"max":10,"duration":0}'), {
  valid: true,
  iconKey: "",
  icon: "",
  message: "0%",
  value: 0,
  maxValue: 10,
  hasProgress: true,
  duration: 0,
  error: "",
})

assert.deepEqual(model.normalizePayload("{}"), {
  valid: true,
  iconKey: "",
  icon: "",
  message: "",
  value: 0,
  maxValue: 100,
  hasProgress: false,
  duration: 1200,
  error: "",
})

const repeatedPayload = '{"icon":"volume","message":"","value":25,"max":100,"duration":0}'
const firstState = model.normalizePayload(repeatedPayload)
const firstStateJson = JSON.stringify(firstState)
const repeatedState = model.normalizePayload(repeatedPayload)
assert.deepEqual(repeatedState, firstState)
assert.notStrictEqual(repeatedState, firstState)
assert.equal(model.normalizePayload('{"extra":true}').valid, false)
assert.equal(JSON.stringify(firstState), firstStateJson)

const screens = [{ name: "DP-1" }, { name: "HDMI-A-1" }]
assert.equal(model.screenForMonitor(screens, "HDMI-A-1"), screens[1])
assert.equal(model.screenForMonitor(screens, "missing-monitor"), screens[0])
assert.equal(model.screenForMonitor([], "HDMI-A-1"), null)

const qml = fs.readFileSync(path.join(__dirname, "../plugins/osd/Osd.qml"), "utf8")
assert.match(qml, /target:\s*"desktop\.osd"/)
assert.match(qml, /namespace:\s*"desktop-shell-osd"/)
assert.match(qml, /import Quickshell\.Hyprland/)
assert.match(qml, /property real value/)
assert.match(qml, /property real maxValue/)
assert.match(qml, /property int duration/)
assert.match(qml, /screen:\s*root\.targetScreen/)
assert.match(qml, /function updateScreen\(\)/)
assert.match(qml, /onFocusedMonitorNameChanged/)
assert.match(qml, /screenForMonitor/)
assert.match(qml, /WlrLayer\.Overlay/)
assert.match(qml, /KeyboardFocus\.None/)
assert.match(qml, /Region \{\s*\}/)
assert.doesNotMatch(qml, /omarchy|OMARCHY/)
