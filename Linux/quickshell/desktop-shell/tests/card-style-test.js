#!/usr/bin/env node
"use strict"

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const shellRoot = path.resolve(__dirname, "..")
const read = relative => fs.readFileSync(path.join(shellRoot, relative), "utf8")
const cardStyle = require("../Commons/CardStyle.js")
const geometry = {}
vm.runInNewContext(read("Commons/BorderGeometry.js").replace(".pragma library", ""), geometry)

const theme = read("config/shell.toml")
const color = read("Commons/Color.qml")
const border = read("Commons/Border.qml")
const cardStyleSource = read("Commons/CardStyle.js")

const sharedValues = {
  "cards.background-alpha": "0.35",
  "cards.border": "#52476a",
  "cards.border-gradient": "90deg #52476a #cba6f7",
  "cards.border-width": "1 2 3 4",
  "cards.border-width-right": "5",
  "notifications.background-alpha": "not-a-number",
  "notifications.border-width-left": "6",
}
assert.equal(cardStyle.inheritedAlpha(sharedValues, "notifications", "background-alpha", "cards", 0.8), 0.8)
assert.equal(cardStyle.inheritedAlpha({ "cards.background-alpha": "0.35" }, "notifications", "background-alpha", "cards", 0.8), 0.35)
assert.equal(cardStyle.inheritedPick({}, "notifications", "background", "cards", "#1e1e2e"), "#1e1e2e")
assert.equal(cardStyle.surfaceValueOr({
  "cards.selected-border-width": "3",
  "notifications.border-width": "7",
}, "notifications", ["selected-border-width", "border-width"]), "7")
const borderWidths = geometry.withSideOverrides(
  geometry.parseWidthSpec(cardStyle.surfaceValueOr(sharedValues, "notifications", ["border-width"]), 2),
  cardStyle.surfaceValueOr(sharedValues, "notifications", ["border-width-top"]),
  cardStyle.surfaceValueOr(sharedValues, "notifications", ["border-width-right"]),
  cardStyle.surfaceValueOr(sharedValues, "notifications", ["border-width-bottom"]),
  cardStyle.surfaceValueOr(sharedValues, "notifications", ["border-width-left"])
)
assert.deepEqual(JSON.parse(JSON.stringify(borderWidths)), { top: 1, right: 5, bottom: 3, left: 6 })
assert.deepEqual(JSON.parse(JSON.stringify(geometry.parseGradientSpec(
  cardStyle.surfaceValueOr(sharedValues, "notifications", ["border-gradient"]), "#1e1e2e", 1))), {
  colors: ["#52476a", "#cba6f7"],
  angle: 90,
  enabled: true,
})

function section(name) {
  const marker = `[${name}]\n`
  const start = theme.indexOf(marker)
  if (start < 0) return ""
  const rest = theme.slice(start + marker.length)
  const next = rest.search(/^\[/m)
  return next < 0 ? rest : rest.slice(0, next)
}

function hexToken(body, key) {
  const match = body.match(new RegExp(`^${key}\\s*=\\s*"(#[0-9a-f]{6})"$`, "im"))
  assert.ok(match, `${key} must be a six-digit hex color`)
  return match[1].toLowerCase()
}

function relativeLuminance(hex) {
  const channels = hex.slice(1).match(/../g).map(value => parseInt(value, 16) / 255)
    .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4)
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}

function contrastRatio(left, right) {
  const values = [relativeLuminance(left), relativeLuminance(right)].sort((a, b) => b - a)
  return (values[0] + 0.05) / (values[1] + 0.05)
}

const cards = section("cards")
assert.match(cards, /^background\s*=\s*"#403651"$/m)
assert.match(cards, /^background-alpha\s*=\s*1\.0$/m)
assert.match(cards, /^text\s*=\s*"#f8f5ff"$/m)
assert.match(cards, /^text-secondary\s*=\s*"#b8c9ff"$/m)
assert.match(cards, /^border\s*=\s*"#403651"$/m)
assert.match(cards, /^border-alpha\s*=\s*1\.0$/m)
assert.match(cards, /^border-width\s*=\s*2$/m)

const cardBackground = hexToken(cards, "background")
assert.ok(contrastRatio(cardBackground, hexToken(cards, "text")) >= 4.5,
  "primary card text meets WCAG AA contrast")
assert.ok(contrastRatio(cardBackground, hexToken(cards, "text-secondary")) >= 4.5,
  "secondary card text meets WCAG AA contrast")

const notifications = section("notifications")
assert.doesNotMatch(notifications, /^(?:background|background-alpha|text|border|border-alpha|border-width)\s*=/m)
assert.match(notifications, /^countdown\s*=\s*"#cdd6f4"$/m)
assert.match(notifications, /^low\s*=\s*"#89b4fa"$/m)
assert.match(notifications, /^critical\s*=\s*"#f38ba8"$/m)
assert.equal(section("tooltip").trim(), "")

assert.match(color, /function inheritedPick\(section, key, baseSection, fallback\)/)
assert.match(color, /function inheritedAlpha\(section, key, baseSection, fallback\)/)
assert.match(color, /function inheritedComposed\(section, baseSection, colorKey, alphaKey, colorFallback, alphaFallback\)/)
assert.match(color, /readonly property QtObject cards:\s*QtObject\s*\{/)
assert.match(color, /readonly property QtObject barPanels:\s*QtObject\s*\{/)
assert.match(color, /inheritedComposed\("notifications",\s*"cards",\s*"background"/)
assert.match(color, /inheritedPick\("notifications",\s*"text",\s*"cards"/)
assert.match(color, /inheritedComposed\("tooltip",\s*"cards",\s*"background"/)
assert.match(color, /inheritedPick\("tooltip",\s*"text",\s*"cards"/)
assert.match(color, /property color secondaryText:\s*root\.pick\("cards\.text-secondary", root\.foreground\)/)
assert.match(color, /inheritedPick\("tooltip",\s*"text-secondary",\s*"cards",\s*root\.foreground\)/)
assert.match(color, /inheritedComposed\("bar-panels",\s*"cards",\s*"background"/)
assert.match(color, /inheritedPick\("bar-panels",\s*"text",\s*"cards"/)
assert.match(color, /inheritedPick\("bar-panels",\s*"text-secondary",\s*"cards",\s*root\.foreground\)/)
assert.match(color, /inheritedPick\("notifications",\s*"text-secondary",\s*"cards",\s*root\.foreground\)/)

assert.match(border, /function surfaceBase\(section\)/)
assert.match(cardStyleSource, /section === "notifications" \|\| section === "tooltip" \|\| section === "bar-panels"/)
assert.match(border, /function surfaceValue\(section, key\)/)
assert.match(border, /function surfaceValueOr\(section, keys\)/)
assert.match(border, /function surfaceAlpha\(section, key, fallback\)/)
assert.match(border, /surfaceValueOr\(section, token === "border"/)
assert.match(border, /surfaceAlpha\(section, alphaKey \|\| token \+ "-alpha", 1\.0\)/)
assert.match(border, /resolveValueRef\(surfaceValue\(section, token\)\)/)
assert.match(border, /surfaceValue\("notifications", "border"\)/)
assert.match(border, /surfaceAlpha\("notifications", "border-alpha", opacity\)/)

const keyboardPanel = read("Ui/KeyboardPanel.qml")
const panelBase = read("Ui/Panel.qml")
const panelHero = read("Ui/PanelHero.qml")
const panelSectionHeader = read("Ui/PanelSectionHeader.qml")
const notificationCard = read("plugins/notifications/components/NotificationCard.qml")
const button = read("Ui/Button.qml")
const panelToolTip = read("Ui/PanelToolTip.qml")
const bar = read("plugins/bar/Bar.qml")
const tray = read("plugins/bar/widgets/Tray.qml")
const osd = read("plugins/osd/Osd.qml")
const popupCard = read("Ui/PopupCard.qml")

assert.match(keyboardPanel, /Color\.barPanels\.background/)
assert.match(keyboardPanel, /Border\.surfaceSpec\("bar-panels", "border", Color\.barPanels\.border/)
assert.doesNotMatch(keyboardPanel, /Color\.popups/)
assert.match(panelBase, /readonly property color panelForeground:\s*Color\.barPanels\.text/)
assert.match(panelBase, /readonly property color panelSecondary:\s*Color\.barPanels\.secondaryText/)
assert.match(panelHero, /property color secondaryForeground:\s*Color\.barPanels\.secondaryText/)
assert.match(panelHero, /id:\s*detailText[\s\S]*?color:\s*root\.secondaryForeground/)
assert.match(panelHero, /id:\s*metaText[\s\S]*?color:\s*root\.secondaryForeground/)
assert.match(panelSectionHeader, /property color secondaryForeground:\s*Color\.barPanels\.secondaryText/)
assert.match(panelSectionHeader, /color:\s*secondaryForeground/)
assert.match(notificationCard, /readonly property color bodyColor:\s*Color\.notifications\.secondaryText/)
assert.match(notificationCard, /readonly property color dimColor:\s*Qt\.darker\(Color\.notifications\.text, 1\.4\)/,
  "notification close affordance keeps interactive dimming")
assert.match(notificationCard, /Color\.notifications\.(?:critical|low)/,
  "notification urgency colors remain semantic")
assert.match(button, /ToolTip\s*\{[\s\S]*?radius:\s*Style\.cornerRadius/)
assert.match(panelToolTip, /Color\.tooltip\.(?:text|background|border)/)
assert.match(bar, /Color\.tooltip\.(?:text|background|border)/)
assert.match(osd, /Color\.popups\.(?:text|background|border)/)
assert.doesNotMatch(osd, /Color\.barPanels/)
assert.match(popupCard, /Color\.popups\.(?:background|border)/)
assert.match(tray, /\.display\(anchorItem\.QsWindow\.window, point\.x, point\.y\)/)

const panelForegroundContracts = [
  ["plugins/agents/Panel.qml", /readonly property color foreground:\s*panelForeground/],
  ["plugins/panels/audio/Panel.qml", /readonly property color foreground:\s*panelForeground/],
  ["plugins/panels/bluetooth/Panel.qml", /readonly property color foreground:\s*panelForeground/],
  ["plugins/panels/clock/Panel.qml", /readonly property color contentForeground:\s*panelForeground/],
  ["plugins/panels/monitor/Panel.qml", /readonly property color foreground:\s*panelForeground/],
  ["plugins/panels/network/Panel.qml", /readonly property color foreground:\s*panelForeground/],
  ["plugins/panels/power/Panel.qml", /readonly property color foreground:\s*panelForeground/],
  ["plugins/panels/tailscale/Panel.qml", /readonly property color foreground:\s*panelForeground/],
  ["plugins/panels/vm/Panel.qml", /readonly property color foreground:\s*panelForeground/],
]
for (const [relative, contract] of panelForegroundContracts) assert.match(read(relative), contract, relative)

const agents = read("plugins/agents/Panel.qml")
const tailscale = read("plugins/panels/tailscale/Panel.qml")
assert.match(agents, /readonly property color surface:\s*Color\.barPanels\.background/)
assert.match(tailscale, /readonly property color barIconForeground:\s*bar \? bar\.foreground : Color\.foreground/)
assert.match(tailscale, /foreground:\s*tailscale\.active \? root\.barIconForeground : root\.barIconDim/)

console.log("card-style-test: shared card theme contract verified")
