const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.resolve(__dirname, "..")
const servicePath = path.join(root, "plugins/notifications/Service.qml")
const cardPath = path.join(root, "plugins/notifications/components/NotificationCard.qml")
const manifestPath = path.join(root, "plugins/notifications/manifest.json")
const sourcePath = path.join(root, "SOURCE")
const selectedPluginsPath = path.join(root, "SELECTED_PLUGINS")

function readRequired(file) {
  assert.ok(fs.existsSync(file), `required notification artifact is missing: ${file}`)
  return fs.readFileSync(file, "utf8")
}

const service = readRequired(servicePath)
const card = readRequired(cardPath)
const manifest = JSON.parse(readRequired(manifestPath))
const source = readRequired(sourcePath)
const selected = readRequired(selectedPluginsPath)

assert.equal(manifest.id, "desktop.notifications")
assert.deepEqual(manifest.kinds, ["service"])
assert.equal(manifest.entryPoints.service, "Service.qml")

assert.match(service, /target:\s*"desktop\.notifications"/)
assert.match(service, /NotificationServer/)
assert.match(service, /notification-route\.json/)
assert.match(service, /desktop-shell\/notifications/)
assert.match(service, /property bool notificationsOwned/)
assert.match(service, /property string ownershipError/)
assert.match(service, /property bool routeValid/)
assert.match(service, /property string routeError/)
assert.doesNotMatch(service + card, /omarchy|OMARCHY|omarchy-glyph|omarchy-exec/)

assert.match(card, /^BorderSurface\s*\{/m)
assert.match(card, /Color\.notifications\.[A-Za-z]+/)
assert.match(card, /Style\.(?:space|font)\b/)
assert.match(card, /\bradius\s*:/)
assert.match(card, /\bimplicitWidth\s*:/)
assert.doesNotMatch(card, /#[0-9A-Fa-f]{3,8}\b/)
assert.doesNotMatch(card, /\b(?:color|border\.color)\s*:\s*["']/)

for (const notificationPath of [
  "shell/plugins/notifications/manifest.json",
  "shell/plugins/notifications/Service.qml",
  "shell/plugins/notifications/NotificationLogic.js",
  "shell/plugins/notifications/components/NotificationCard.qml",
]) {
  assert.ok(source.includes(notificationPath), `SOURCE omits ${notificationPath}`)
}

assert.match(selected, /desktop\.notifications\|omarchy\.notifications\|shell\/plugins\/notifications\/manifest\.json shell\/plugins\/notifications\/Service\.qml shell\/plugins\/notifications\/NotificationLogic\.js shell\/plugins\/notifications\/components\/NotificationCard\.qml/)

console.log("notification-service-test: source, manifest, neutral card, and provenance contract verified")
