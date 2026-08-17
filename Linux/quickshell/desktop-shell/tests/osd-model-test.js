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

const qml = fs.readFileSync(path.join(__dirname, "../plugins/osd/Osd.qml"), "utf8")
assert.match(qml, /target:\s*"desktop\.osd"/)
assert.match(qml, /namespace:\s*"desktop-shell-osd"/)
assert.match(qml, /WlrLayer\.Overlay/)
assert.match(qml, /KeyboardFocus\.None/)
assert.match(qml, /Region \{\s*\}/)
assert.doesNotMatch(qml, /omarchy|OMARCHY/)
