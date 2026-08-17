const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const shellRoot = path.resolve(__dirname, "..")
const modelPath = path.join(shellRoot, "plugins/menu/MenuModel.js")
const menuPath = path.join(shellRoot, "plugins/menu/Menu.qml")
const configPath = path.join(shellRoot, "config/menu.jsonc")

assert.ok(fs.existsSync(modelPath), "repository menu model exists")
assert.ok(fs.existsSync(menuPath), "repository menu QML exists")
assert.ok(fs.existsSync(configPath), "repository menu JSONC exists")

const menu = require(modelPath)
const menuQml = fs.readFileSync(menuPath, "utf8")
const configSource = fs.readFileSync(configPath, "utf8")

assert.match(
  menuQml,
  /id: keyCatcher[\s\S]*?anchors\.fill: parent[\s\S]*?anchors\.margins: card\.padding/,
  "menu content honors the card padding"
)

const parsed = menu.parseMenuJsonc(`
{
  // Comments and trailing commas are valid JSONC input.
  "root": { "label": "Control" },
  "trigger": { "label": "Trigger" },
  "trigger.capture": { "label": "Capture" },
  "trigger.capture.screenshot": {
    "label": "Screenshot",
    "aliases": "shot",
    "action": "trigger.screenshot",
  },
  "setup": { "label": "Setup" },
  "setup.audio": { "label": "Audio", "action": "setup.audio", "when": true },
}
`)

assert.equal(parsed.length, 6, "menu parses dotted JSONC entries")
assert.deepEqual(
  parsed.find(item => item.id === "trigger.capture.screenshot"),
  {
    id: "trigger.capture.screenshot",
    parent: "trigger.capture",
    kind: "action",
    icon: "",
    iconFont: "",
    label: "Screenshot",
    title: "",
    target: "",
    description: "",
    action: "trigger.screenshot",
    aliases: ["shot"],
    when: true,
    checked: false,
    disabled: false,
  },
  "menu normalizes an opaque action ID without interpreting it"
)
assert.equal(menu.normalizeItem("trigger.bad", { action: "touch /tmp/menu-test" }).action, "",
  "menu rejects shell fragments instead of treating them as actions")

const merged = menu.mergeMenuSources(parsed, [
  menu.normalizeItem("setup.audio", { label: "Audio setup", action: "setup.audio" }),
  menu.normalizeItem("tools", { label: "Tools" }),
])
assert.equal(merged.items["setup.audio"].label, "Audio setup", "later menu data overrides a row")
assert.equal(merged.items["setup.audio"].order, 5, "overrides preserve the first row position")
assert.equal(merged.items.root.parent, "", "the root row has no parent")

assert.equal(menu.pathFor(merged.items, "trigger.capture.screenshot"), "Trigger › Capture › Screenshot",
  "menu builds a dotted route path")
assert.equal(menu.parentPathFor(merged.items, "trigger.capture.screenshot"), "Trigger › Capture",
  "menu builds a parent path")
assert.equal(menu.depthFor(merged.items, "trigger.capture.screenshot"), 2,
  "menu calculates submenu depth")
assert.equal(menu.childCount(merged.items, merged.itemOrder, "trigger.capture"), 1,
  "menu counts children")
assert(menu.isDescendantOf(merged.items, "trigger.capture.screenshot", "trigger"),
  "menu detects dotted descendants")
assert.equal(menu.resolveRoute(merged.items, merged.itemOrder, "shot"), "trigger.capture.screenshot",
  "menu routes aliases")
assert.equal(menu.resolveRoute(merged.items, merged.itemOrder, "trigger_capture_screenshot"),
  "trigger-capture-screenshot", "menu normalizes underscore route input")
assert.equal(menu.resolveRoute(merged.items, merged.itemOrder, ""), "root",
  "menu routes an empty input to root")

const visibilityItems = {
  setup: menu.normalizeItem("setup", { label: "Setup" }),
  hidden: menu.normalizeItem("setup.hidden", { label: "Hidden", when: false, action: "setup.hidden" }),
  visible: menu.normalizeItem("setup.visible", { label: "Visible", when: true, action: "setup.visible" }),
  checked: menu.normalizeItem("setup.checked", { label: "Checked", checked: true, action: "setup.checked" }),
  disabled: menu.normalizeItem("setup.disabled", { label: "Disabled", disabled: true, action: "setup.disabled" }),
}
const visibilityOrder = Object.keys(visibilityItems)
assert(menu.isVisible(visibilityItems, visibilityOrder, {}, visibilityItems.setup),
  "menu keeps a submenu with a visible child")
assert(!menu.isVisible(visibilityItems, visibilityOrder, {}, visibilityItems.hidden),
  "menu hides a false conditional row")
assert.equal(menu.labelFor(visibilityItems.checked, {}, {}), "Checked ✓",
  "menu marks checked rows")
assert.equal(menu.labelFor(visibilityItems.disabled, {}, {}), "Disabled ✓",
  "menu marks disabled rows")
assert(menu.isDisabled({}, visibilityItems.disabled), "menu disables a boolean-disabled row")
assert(menu.matchesQuery(visibilityItems.visible, "vis", true), "menu searches labels")
assert(!menu.matchesQuery(visibilityItems.hidden, "hidden", false), "menu excludes invisible search rows")

const hardwareRoutes = {
  "setup.power-profile": "desktop.power",
  "setup.monitors": "desktop.monitor",
}
assert.deepEqual(
  menu.routeVisibility({ right: [{ id: "desktop.audio" }] }, hardwareRoutes),
  { "setup.power-profile": false, "setup.monitors": false },
  "menu hides hardware routes when compact bars omit their widgets"
)
assert.deepEqual(
  menu.routeVisibility({ right: [{ id: "desktop.monitor" }, { id: "desktop.power" }] }, hardwareRoutes),
  { "setup.power-profile": true, "setup.monitors": true },
  "menu keeps hardware routes on the Omarbook bar"
)

const displayed = menu.displayRow(
  merged.items,
  merged.itemOrder,
  {},
  {},
  merged.items["trigger.capture.screenshot"],
  "Trigger › Capture",
  12,
  "search"
)
assert.deepEqual(displayed, {
  itemId: "trigger.capture.screenshot",
  disabled: false,
  kind: "action",
  icon: "",
  iconFont: "",
  label: "Screenshot",
  target: "trigger.capture.screenshot",
  detail: "Trigger › Capture",
  path: "Trigger › Capture › Screenshot",
  childCount: 0,
  action: "trigger.screenshot",
  score: 12,
  section: "search",
}, "menu builds a display row for a leaf action")

const validItems = menu.parseMenuJsonc(configSource)
const invalid = menu.parseMenuJsoncResult('{ "trigger": { "label": "broken", }')
assert.equal(invalid.valid, false, "malformed JSONC is reported as invalid")
assert.deepEqual(menu.preserveLastValid(validItems, invalid), validItems,
  "malformed JSONC keeps the last valid menu")

const configuredMenu = menu.mergeMenuSources(validItems, [])
const compactVisibility = menu.routeVisibility(
  { right: [{ id: "desktop.audio" }] },
  hardwareRoutes
)
assert(!menu.isVisible(
  configuredMenu.items,
  configuredMenu.itemOrder,
  compactVisibility,
  configuredMenu.items["setup.power-profile"]
), "compact menu does not present Power profile")
assert(!menu.isVisible(
  configuredMenu.items,
  configuredMenu.itemOrder,
  compactVisibility,
  configuredMenu.items["setup.monitors"]
), "compact menu does not present Monitors")

const topLevel = validItems.filter(item => item.parent === "root").map(item => item.id)
assert.deepEqual(topLevel, ["trigger", "setup", "install", "remove", "update", "system"],
  "menu root groups keep the exact required order")

const expectedActions = [
  "trigger.screenshot", "trigger.screenrecord", "trigger.color",
  "trigger.share-clipboard", "trigger.share-file", "trigger.share-folder",
  "setup.audio", "setup.wifi", "setup.bluetooth", "setup.power-profile", "setup.monitors",
  "setup.dns", "setup.security", "setup.shell-config", "setup.shell-health",
  "install.package", "install.aur", "remove.package",
  "update.system", "update.audio", "update.wifi", "update.bluetooth",
  "update.shell-reload",
  "system.lock", "system.suspend", "system.hibernate", "system.logout",
  "system.reboot", "system.shutdown",
]
const configuredActions = validItems.filter(item => item.action).map(item => item.action)
assert.deepEqual(configuredActions, expectedActions, "menu exposes only the strict action ID set")
assert(configuredActions.every(action => /^[a-z0-9]+(?:[.-][a-z0-9-]+)+$/.test(action)),
  "menu actions are opaque IDs rather than shell fragments")
assert(!/\b(?:apps?|providers?|themes?|plugins?)\b/i.test(configSource),
  "menu config does not declare excluded app/provider/theme/plugin routes")

assert.match(menuQml, /Quickshell\.shellDir \+ "\/config\/menu\.jsonc"/,
  "menu watches the repository-owned JSONC path")
assert.match(menuQml, /actionProcess\.command\s*=\s*\["desktop-shell-action",\s*String\(action\)\]/,
  "menu passes action IDs to the strict action helper")
assert.match(menuQml, /MenuModel\.routeVisibility\(/,
  "menu derives route availability from the live bar layout")
assert.match(menuQml, /MenuModel\.isVisible\(root\.items, root\.itemOrder, root\.whenResults, entry\)/,
  "menu applies runtime route availability before presenting rows")
assert.match(menuQml, /if \(entry && entry\.kind === "action"\)[\s\S]*?if \(!root\.isVisible\(entry\)\) return "unknown"/,
  "menu rejects direct activation of unavailable routes")
assert.doesNotMatch(menuQml, /Util\.execDetached|\["bash",\s*"-(?:c|lc)"|\beval\b/,
  "menu QML contains no arbitrary command execution")
assert.match(menuQml, /function resolveRoute\(input\)[\s\S]*MenuModel\.resolveRoute/,
  "menu delegates route resolution to the neutral model")
assert.match(menuQml, /if \(result\.valid\)[\s\S]*preserveLastValid/,
  "menu keeps the previous model after malformed JSONC reloads")

console.log("menu-model-test: hierarchy, search, guards, reload retention, and opaque actions verified")
