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

assert.match(service, /property string routeRaw/)
assert.match(service, /readonly property bool routeVisible/)
assert.match(service, /function refreshRoute\(\)/)
assert.match(service, /normalizeRoute\(service\.routeRaw,\s*Date\.now\(\)\)/)
assert.match(service, /routeExpiryTimer/)
assert.match(service, /return service\.routeVisible[\s\S]*service\.route\.output !== null/)
assert.match(service, /routeVisible:\s*service\.routeVisible/)

const restoreLastStart = service.indexOf("function restoreLast()")
const invokeLastStart = service.indexOf("function invokeLast()")
assert.ok(restoreLastStart >= 0 && invokeLastStart > restoreLastStart, "restoreLast root method exists")
const restoreLastBody = service.slice(restoreLastStart, invokeLastStart)
assert.match(restoreLastBody, /restoreLastProc/)
assert.doesNotMatch(restoreLastBody, /showRecentHistory|clearPopups/)
assert.match(service, /function restoreLastFromRaw\(raw\)[\s\S]*latestHistoryRow/)

assert.match(service, /property string persistenceError/)
assert.match(service, /property int persistenceRetryLimit/)
assert.match(service, /done\(success/)
assert.match(service, /onExited:\s*function\(exitCode/)
assert.doesNotMatch(service, /mkdir -p[^\n]*\|\| exit 0/)
assert.match(service, /umask 077/, "notification persistence uses a restrictive umask")
assert.match(service, /chmod 700/, "notification state directories repair their mode")
assert.match(service, /chmod 600/, "notification state files repair their mode")
assert.match(service, /settingsWriteProc/, "settings persistence has an explicit mode-controlled writer")
assert.match(service, /property bool settingsSavePending/,
  "settings persistence tracks an overlapping save")
assert.match(service,
  /if \(settingsWriteProc\.running\)\s*\{[\s\S]*settingsSavePending = true[\s\S]*return/,
  "an overlapping settings save is recorded instead of dropped")
assert.match(service,
  /onExited:[\s\S]*settingsSavePending[\s\S]*scheduleSettingsSave\(\)/,
  "settings exit schedules one pending follow-up save")
const writeSilencedStart = service.indexOf("function writeSilenced(")
const releaseSilencedStart = service.indexOf("function releaseSilenced(")
assert.ok(writeSilencedStart >= 0 && releaseSilencedStart > writeSilencedStart, "writeSilenced root method exists")
const writeSilencedBody = service.slice(writeSilencedStart, releaseSilencedStart)
assert.match(writeSilencedBody,
  /function\(success,\s*exitCode\)[\s\S]*if\s*\(!success\)\s*\{[\s\S]*releaseSilenced\(notification,\s*written\.originalId\)[\s\S]*return/,
  "failed DND persistence releases the live notification")
assert.match(service, /persistenceError:\s*service\.persistenceError/,
  "persistence failures are exposed through status")
assert.match(service, /liveCount:\s*service\.liveReferenceCount\(\)/,
  "status reports live notification references")

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
