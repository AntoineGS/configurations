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
const elevatedSurface = read("Ui/ElevatedSurface.qml")

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
assert.equal(cardStyle.inheritedPick({
  "notifications.text-secondary": "#own",
  "cards.text-secondary": "#cards",
}, "notifications", "text-secondary", "cards", "#caller"), "#own")
assert.equal(cardStyle.inheritedPick({
  "cards.text-secondary": "#cards",
}, "notifications", "text-secondary", "cards", "#caller"), "#cards")
assert.equal(cardStyle.inheritedPick({}, "notifications", "text-secondary", "cards", "#caller"), "#caller")
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
assert.match(cards, /^background\s*=\s*"#303143"$/m)
assert.match(cards, /^background-alpha\s*=\s*1\.0$/m)
assert.match(cards, /^text\s*=\s*"#f8f5ff"$/m)
assert.match(cards, /^text-secondary\s*=\s*"#b8c9ff"$/m)
assert.match(cards, /^border\s*=\s*"#303143"$/m)
assert.match(cards, /^border-alpha\s*=\s*1\.0$/m)
assert.match(cards, /^border-width\s*=\s*2$/m)

const cardBackground = hexToken(cards, "background")
assert.ok(contrastRatio(cardBackground, hexToken(cards, "text")) >= 4.5,
  "primary card text meets WCAG AA contrast")
assert.ok(contrastRatio(cardBackground, hexToken(cards, "text-secondary")) >= 4.5,
  "secondary card text meets WCAG AA contrast")

const notifications = section("notifications")
assert.match(notifications, /^background\s*=\s*"#b4befe"$/m)
assert.match(notifications, /^background-alpha\s*=\s*1\.0$/m)
assert.match(notifications, /^text\s*=\s*"#11111b"$/m)
assert.match(notifications, /^text-secondary\s*=\s*"#11111b"$/m)
assert.match(notifications, /^border\s*=\s*"transparent"$/m)
assert.match(notifications, /^border-alpha\s*=\s*0\.0$/m)
assert.match(notifications, /^border-width\s*=\s*0$/m)
assert.match(notifications, /^countdown\s*=\s*"#11111b"$/m)
assert.match(notifications, /^low\s*=\s*"#89dceb"$/m)
assert.match(notifications, /^critical\s*=\s*"#f38ba8"$/m)
for (const surface of ["#89dceb", "#b4befe", "#f38ba8"]) {
  assert.ok(contrastRatio(surface, "#11111b") >= 7,
    `${surface} notification surface meets WCAG AAA with crust ink`)
}
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

assert.match(elevatedSurface, /import QtQuick\.Effects/)
assert.match(elevatedSurface, /BorderSurface\s*\{/)
assert.match(elevatedSurface, /property bool revealed:\s*false/)
assert.match(elevatedSurface, /property real entranceX:\s*0/)
assert.match(elevatedSurface, /property real entranceY:\s*0/)
assert.match(elevatedSurface, /property real concealedScale:\s*0\.97/)
assert.match(elevatedSurface, /property int motionDuration:\s*140/)
assert.match(elevatedSurface, /property int shadowBlurMax:\s*24/)
assert.match(elevatedSurface, /property real shadowBlurAmount:\s*0\.7/)
assert.match(elevatedSurface, /property real shadowOpacityAmount:\s*0\.38/)
assert.match(elevatedSurface, /property real shadowOffsetY:\s*4/)
assert.match(elevatedSurface, /property real shadowScaleAmount:\s*1\.0/)
assert.match(elevatedSurface, /property rect effectPaddingRect:\s*Qt\.rect\(0, 0, 0, 0\)/)
assert.match(elevatedSurface, /blurMax:\s*root\.shadowBlurMax/)
assert.match(elevatedSurface, /shadowBlur:\s*root\.shadowBlurAmount/)
assert.match(elevatedSurface, /shadowOpacity:\s*root\.shadowOpacityAmount/)
assert.match(elevatedSurface, /shadowVerticalOffset:\s*root\.shadowOffsetY/)
assert.match(elevatedSurface, /shadowScale:\s*root\.shadowScaleAmount/)
assert.match(elevatedSurface, /paddingRect:\s*root\.effectPaddingRect/)
assert.match(elevatedSurface, /duration:\s*root\.motionDuration/)
assert.match(elevatedSurface, /easing\.type:\s*Easing\.OutCubic/)

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
assert.match(notificationCard, /readonly property color surfaceColor:\s*urgency === 0/)
assert.match(notificationCard, /Color\.notifications\.low[\s\S]*Color\.notifications\.critical[\s\S]*Color\.notifications\.background/)
assert.match(notificationCard, /readonly property color inkColor:\s*Color\.notifications\.text/)
assert.match(notificationCard, /readonly property string urgencyLabel:/)
assert.match(notificationCard, /readonly property string sourceLabel:/)
assert.match(notificationCard, /function formatTime\(value\)/)
assert.match(notificationCard, /radius:\s*0/)
assert.match(notificationCard, /borderSpec:\s*Border\.none\(\)/)
assert.match(notificationCard, /concealedScale:\s*1\.0/)
assert.match(notificationCard, /motionDuration:\s*160/)
assert.match(notificationCard, /entranceX:\s*Style\.space\(12\)/)
assert.match(notificationCard, /shadowBlurMax:\s*48/)
assert.match(notificationCard, /shadowOpacityAmount:\s*0\.78/)
assert.match(notificationCard, /shadowOffsetY:\s*14/)
assert.match(notificationCard, /shadowScaleAmount:\s*1\.03/)
assert.match(notificationCard, /effectPaddingRect:\s*Qt\.rect\(-8, -8, 16, 30\)/)
assert.doesNotMatch(notificationCard, /id:\s*smallIconSlot/)
assert.match(notificationCard, /id:\s*metadataRule[\s\S]*height:\s*Style\.space\(2\)/)
assert.match(notificationCard, /id:\s*actionRule[\s\S]*height:\s*Math\.max\(1, Style\.space\(1\)\)/)
assert.match(notificationCard, /font\.pixelSize:\s*Style\.font\.title/)
assert.match(notificationCard, /font\.pixelSize:\s*Style\.font\.bodySmall/)
assert.match(notificationCard, /lineHeight:\s*1\.45/)
assert.match(notificationCard, /borderSpec:\s*Border\.flat\(root\.inkColor[\s\S]*radius:\s*0/)
assert.match(notificationCard, /Flow\s*\{[\s\S]*layoutDirection:\s*Qt\.RightToLeft/)
assert.match(notificationCard, /maximumWidth:\s*Style\.space\(140\)/)
assert.match(notificationCard, /Quickshell\.iconPath\(value, true\)/)
assert.match(button, /property real maximumWidth:\s*-1/)
assert.match(button, /elide:\s*root\.maximumWidth > 0 \? Text\.ElideRight : Text\.ElideNone/)
assert.match(button, /PanelToolTip\s*\{/)
assert.match(panelToolTip, /Color\.tooltip\.(?:text|background|border)/)
assert.match(bar, /Color\.tooltip\.(?:text|background|border)/)
assert.match(osd, /Color\.popups\.(?:text|background|border)/)
assert.doesNotMatch(osd, /Color\.barPanels/)
assert.match(popupCard, /Color\.popups\.(?:background|border)/)
assert.match(tray, /\.display\(anchorItem\.QsWindow\.window, point\.x, point\.y\)/)
assert.match(popupCard, /property int elevationInset:\s*Style\.space\(24\)/)
assert.match(popupCard, /mask:\s*Region\s*\{\s*item:\s*card\s*\}/)
assert.match(popupCard, /ElevatedSurface\s*\{[\s\S]*?revealed:\s*root\.open/)
assert.match(bar, /property int elevationInset:\s*Style\.space\(24\)/)
assert.match(bar, /property int hoverSafeInset:\s*Style\.space\(6\)/)
assert.match(bar, /implicitHeight:[^\n]*hoverSafeInset \+ elevationInset/)
assert.match(bar, /y:\s*tooltipWindow\.hoverSafeInset/)
assert.match(bar, /target\.height \+ 6 - tooltipWindow\.hoverSafeInset/)
assert.doesNotMatch(bar, /target\.height \+ 6 - tooltipWindow\.elevationInset/)
assert.match(bar, /ElevatedSurface\s*\{[\s\S]*?id:\s*tooltipBubble/)
assert.match(panelToolTip, /background:\s*ElevatedSurface/)
assert.match(button, /PanelToolTip\s*\{/)
assert.doesNotMatch(button, /(?:^|\s)ToolTip\s*\{/)
assert.match(keyboardPanel, /ElevatedSurface\s*\{[\s\S]*?id:\s*card/)
assert.match(keyboardPanel, /revealed:\s*root\.open\s*\|\|\s*root\.popoutSwitching/)
assert.match(notificationCard, /^ElevatedSurface\s*\{/m)
assert.match(notificationCard, /entranceX:\s*Style\.space\(12\)/)

const popupAvailability = popupCard.slice(
  popupCard.indexOf("readonly property real availableCardWidth"),
  popupCard.indexOf("readonly property real verticalContentInset"))
assert.doesNotMatch(popupAvailability, /elevationInset/,
  "shadow padding does not reduce visible popup card capacity")
assert.match(keyboardPanel, /property int elevationInset:\s*Style\.space\(24\)/)
assert.match(keyboardPanel, /shadowInsetX:[\s\S]*barPos === "top" \|\| barPos === "bottom"/)
assert.match(keyboardPanel, /shadowInsetY:[\s\S]*barPos === "left" \|\| barPos === "right"/)
assert.match(popupCard, /function clampParallelOrigin\(value, popupExtent, cardExtent, availableExtent\)/)
assert.equal((popupCard.match(/root\.clampParallelOrigin\(/g) || []).length, 4,
  "popup anchoring uses shadow-aware clamping in centered and anchored paths")

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
const audio = read("plugins/panels/audio/Panel.qml")
const bluetooth = read("plugins/panels/bluetooth/Panel.qml")
const clockPanel = read("plugins/panels/clock/Panel.qml")
const monitor = read("plugins/panels/monitor/Panel.qml")
const network = read("plugins/panels/network/Panel.qml")
const tailscale = read("plugins/panels/tailscale/Panel.qml")
const vmPanel = read("plugins/panels/vm/Panel.qml")
assert.match(agents, /readonly property color surface:\s*Color\.barPanels\.background/)
assert.match(tailscale, /readonly property color barIconForeground:\s*bar \? bar\.foreground : Color\.foreground/)
assert.match(tailscale, /foreground:\s*tailscale\.active \? root\.barIconForeground : root\.barIconDim/)

assert.match(agents, /readonly property color dim:\s*Qt\.darker\(foreground, 1\.55\)/)
assert.match(agents, /readonly property color secondary:\s*panelSecondary/)
assert.match(agents, /text: "No AI coding subscriptions found\.[\s\S]*?\n\s+color:\s*root\.dim/,
  "empty Agents state remains dim")
assert.match(agents, /text: root\.statusText\(root\.provider\)[\s\S]*?\n\s+color:\s*root\.dim/,
  "Agents status and error content remains dim")
assert.match(agents, /text: root\.footerText\(\)\s*\n\s+color:\s*root\.secondary/,
  "Agents footer metadata uses secondary")
assert.match(agents, /id: resetText[\s\S]*?\n\s+color:\s*root\.secondary/,
  "limit reset metadata uses secondary")
assert.match(agents, /text: root\.dayLabel\(dayRow\.day \? dayRow\.day\.date : "", dayRow\.today\)\s*\n\s+color:\s*dayRow\.today \? root\.foreground : root\.secondary/,
  "non-today history labels use secondary")
assert.match(agents, /text: usage\.formatTokenCount\(dayRow\.day \? Number\(dayRow\.day\.messageCount \|\| 0\) : 0\)\s*\n\s+color:\s*dayRow\.today \? root\.foreground : root\.secondary/,
  "non-today history values use secondary")
assert.match(agents, /id: modelTokens[\s\S]*?\n\s+color:\s*root\.secondary/,
  "model token totals use secondary")

assert.match(audio, /id:\s*heroIcon[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(audio, /text:\s*root\.outputVolumeName[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(audio, /id:\s*outputPercent[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(audio, /text:\s*inputNode \? root\.sourceGlyph[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(audio, /id:\s*streamPercent[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(audio, /id:\s*heroIcon[\s\S]*?opacity:\s*root\.outputMuted \? 0\.5 : 1\.0/)

assert.match(bluetooth, /id:\s*heroIcon[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(bluetooth, /text:\s*root\.heroStatus\.toUpperCase\(\)[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(bluetooth, /text:\s*deviceRow\.connected[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(bluetooth, /text:\s*deviceRow\.statusText[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(bluetooth, /opacity:\s*root\.adapter && root\.adapter\.enabled \? 1\.0 : 0\.5/)
assert.match(bluetooth, /text:\s*!root\.adapter \? "No Bluetooth adapter"[\s\S]*?color:\s*Qt\.darker\(root\.foreground, 1\.5\)/)

assert.match(clockPanel, /readonly property color contentSecondary:\s*panelSecondary/)
assert.match(clockPanel, /id:\s*yearLabel[\s\S]*?color:\s*root\.contentSecondary/)
assert.match(clockPanel, /text:\s*root\.weekdayLabel[\s\S]*?color:\s*root\.contentSecondary/)
assert.match(clockPanel, /text:\s*modelData\.week[\s\S]*?color:\s*root\.contentSecondary/)
assert.match(clockPanel, /modelData\.weekend \? root\.contentSecondary : root\.contentForeground/)
assert.match(clockPanel, /id:\s*monthLabel[\s\S]*?color:\s*root\.contentSecondary/)
const weekStartTextStart = clockPanel.indexOf('text: "W"')
const weekStartTextEnd = clockPanel.indexOf("font.family", weekStartTextStart)
assert.ok(weekStartTextStart >= 0 && weekStartTextEnd > weekStartTextStart, "week-start control block exists")
assert.match(clockPanel.slice(weekStartTextStart, weekStartTextEnd),
  /color:\s*weekStartMouse\.containsMouse\s*\?\s*Style\.hoverStateColor\(root\.contentForeground, Color\.accent\)\s*:\s*Qt\.darker\(root\.contentForeground, 1\.9\)/,
  "week-start control preserves its idle dim and hover logic")
assert.match(clockPanel, /modelData\.inMonth[\s\S]*?Qt\.darker\(root\.contentForeground, 2\.2\)/,
  "out-of-month dates retain unavailable-state dimming")

assert.match(monitor, /Model\.displayIcon[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(monitor, /root\.brightnessPercent \+ "%"[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(monitor, /root\.keyboardBrightness\.percent \+ "%"[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(monitor, /id:\s*scaleLabel[\s\S]*?color:\s*root\.panelSecondary/)

assert.match(network, /id:\s*heroIcon[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(network, /Math\.round\(root\.signalStrength\)[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(network, /Model\.wifiIconFor[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(network, /text:\s*rowData && rowData\.connected[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(network, /text:\s*root\.wifiDevice \? "Scanning for networks\.\.\."[\s\S]*?color:\s*Qt\.darker\(root\.foreground, 1\.5\)/)

assert.match(tailscale, /tailscale\.active \? root\.panelSecondary : root\.dim/)
assert.match(tailscale, /tailscale\.lastError[^\n]*\? root\.urgent : root\.panelSecondary/)
const peerGlyphStart = tailscale.indexOf("text: Model.osIcon(modelData.os)")
const peerGlyphEnd = tailscale.indexOf("font.family", peerGlyphStart)
assert.ok(peerGlyphStart >= 0 && peerGlyphEnd > peerGlyphStart, "Tailscale peer glyph block exists")
assert.match(tailscale.slice(peerGlyphStart, peerGlyphEnd), /color:\s*root\.panelSecondary/,
  "Tailscale peer glyph uses semantic secondary styling")
assert.match(tailscale, /Model\.peerAddress[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(tailscale, /text:\s*"No peers found on this tailnet"[\s\S]*?color:\s*root\.dim/)

assert.match(vmPanel, /text:\s*""[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(vmPanel, /text:\s*"MEMORY"[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(vmPanel, /text:\s*"CPU"[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(vmPanel, /id:\s*minimumLabel[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(vmPanel, /id:\s*maximumLabel[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(vmPanel, /text:\s*"LIVE \+ NEXT BOOT"[\s\S]*?color:\s*root\.panelSecondary/)
assert.match(vmPanel, /root\.actionError !== "" \? Color\.urgent : root\.panelSecondary/)

console.log("card-style-test: shared card theme contract verified")
