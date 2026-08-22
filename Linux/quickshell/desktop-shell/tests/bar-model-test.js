const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const model = require("../plugins/bar/BarModel.js")
const shellRoot = path.resolve(__dirname, "..")
const shellSource = fs.readFileSync(path.join(shellRoot, "shell.qml"), "utf8")
const barSource = fs.readFileSync(path.join(shellRoot, "plugins/bar/Bar.qml"), "utf8")
const workspacesSource = fs.readFileSync(path.join(shellRoot, "plugins/bar/widgets/Workspaces.qml"), "utf8")
const traySource = fs.readFileSync(path.join(shellRoot, "plugins/bar/widgets/Tray.qml"), "utf8")
const clockSource = fs.readFileSync(path.join(shellRoot, "plugins/panels/clock/BarWidget.qml"), "utf8")
const opticalGlyphSource = fs.readFileSync(path.join(shellRoot, "Ui/OpticalGlyph.qml"), "utf8")
const tailscalePanelSource = fs.readFileSync(path.join(shellRoot, "plugins/panels/tailscale/Panel.qml"), "utf8")
const tailscaleIconSource = fs.readFileSync(path.join(shellRoot, "plugins/panels/tailscale/TailscaleIcon.qml"), "utf8")
const tailscaleBarButtonSource = tailscalePanelSource.slice(
  tailscalePanelSource.indexOf("BarIconButton {"),
  tailscalePanelSource.indexOf("KeyboardPanel {")
)
const widgetButtonSource = fs.readFileSync(path.join(shellRoot, "Ui/WidgetButton.qml"), "utf8")
const barIconButtonSource = fs.readFileSync(path.join(shellRoot, "Ui/BarIconButton.qml"), "utf8")
const centerSource = barSource.slice(barSource.indexOf("component CenterModules"), barSource.indexOf("component ModuleList"))
const barVariantsSource = barSource.slice(barSource.indexOf("Variants {"), barSource.indexOf("component BarPanel"))
const barPanelSource = barSource.slice(barSource.indexOf("component BarPanel"), barSource.indexOf("component LeftModules"))

const failures = []
function contract(name, check) {
  try {
    check()
  } catch (error) {
    failures.push(`${name}: ${error.message}`)
  }
}

assert.deepStrictEqual(model.pinTrayToInner([
  { id: "desktop.audio" }, { id: "desktop.tray" }, { id: "cpu" }
], "right"), [
  { id: "desktop.tray" }, { id: "desktop.audio" }, { id: "cpu" }
])
assert.strictEqual(model.customModuleSafeName("../escape"), false)

contract("empty command JSON stays hidden", () => {
  assert.deepStrictEqual(model.commandModuleState(
    { text: "", tooltip: "", class: "" },
    '{"text":"","tooltip":"","class":""}',
    {}
  ), { text: "", tooltip: "", active: false, muted: false })
})

contract("muted command class reaches the widget", () => {
  assert.deepStrictEqual(model.commandModuleState(
    { text: "6%/3d12h", tooltip: "Codex quota", class: "muted" },
    "",
    {}
  ), { text: "6%/3d12h", tooltip: "Codex quota", active: false, muted: true })
})

contract("rich tooltip markup preserves line boundaries", () => {
  assert.equal(
    model.tooltipDisplayText("<span>Weekly</span>\r\n\r\n<span>Resets in 10h</span>"),
    "<span>Weekly</span><br><br><span>Resets in 10h</span>"
  )
  assert.equal(model.tooltipDisplayText("Weekly\nResets in 10h"), "Weekly\nResets in 10h")
})

contract("empty workspaces dispatch through Hyprland", () => {
  assert.match(workspacesSource, /function focusWorkspace\(id\) \{[\s\S]*?var workspace = root\.workspaceById\(id\)[\s\S]*?workspace\.activate\(\)[\s\S]*?Hyprland\.dispatch\("workspace " \+ String\(id\)\)/)
  assert.doesNotMatch(workspacesSource, /root\.bar\.run|hyprctl/)
})

contract("tray menu-bearing items use native display", () => {
  const openTrayMenu = traySource.slice(traySource.indexOf("function openTrayMenu"))
  assert.match(openTrayMenu, /item\.display\(/)
  assert.doesNotMatch(openTrayMenu, /item\.menu/)
  assert.match(traySource, /modelData\.onlyMenu \|\| trayItemRoot\.modelData\.menu/)
  assert.doesNotMatch(traySource, /PopupCard|QsMenuOpener/)
})

contract("tray items reuse shared hover states without tinting full-color icons", () => {
  assert.match(traySource, /component TrayItem: BorderSurface/)
  assert.match(traySource, /readonly property bool hot: mouseArea\.containsMouse/)
  assert.match(traySource,
    /Style\.hoverFillFor\(root\.foreground, Color\.accent\)/)
  assert.match(traySource,
    /Border\.controlSpec\("hover-cursor", root\.foreground, Color\.accent\)/)
  assert.match(traySource,
    /property color tint: root\.foreground[\s\S]*?colorizationColor: trayIconRoot\.tint/)
  assert.match(traySource,
    /tint: mouseArea\.pressed[\s\S]*?Style\.pressedStateColor\(root\.foreground, Color\.accent\)[\s\S]*?trayItemRoot\.hot[\s\S]*?Style\.hoverStateColor\(root\.foreground, Color\.accent\)[\s\S]*?: root\.foreground/)
  assert.match(traySource, /visible: !trayIconRoot\.symbolic/)
  assert.match(traySource,
    /MultiEffect \{[\s\S]*?visible: trayIconRoot\.symbolic[\s\S]*?colorizationColor: trayIconRoot\.tint/)
})

contract("native tray display has QApplication shell mode", () => {
  assert.match(shellSource, /^\/\/\@ pragma UseQApplication\r?\n/)
  assert.match(traySource, /function openTrayMenu[\s\S]*?item\.display\(/)
})

contract("clock updates at seconds precision", () => {
  assert.match(clockSource, /precision: SystemClock\.Seconds/)
})

contract("custom glyph colors animate smoothly", () => {
  assert.match(opticalGlyphSource, /Behavior on color \{\s*ColorAnimation \{ duration: 160 \}/)
  assert.match(tailscaleIconSource, /Behavior on color \{\s*ColorAnimation \{ duration: 160 \}/)
})

contract("tailscale bar icon preserves idle dim and uses button content color", () => {
  assert.match(tailscaleBarButtonSource, /foreground: tailscale\.active \? root\.barIconForeground : root\.barIconDim/)
  assert.match(tailscaleBarButtonSource, /TailscaleIcon \{[\s\S]*?color: button\.contentColor/)
  assert.match(tailscalePanelSource, /iconSize: Style\.font\.display[\s\S]*?color: tailscale\.active \? root\.panelSecondary : root\.dim/)
})

contract("tailscale warning badges use their host surface", () => {
  assert.match(tailscaleIconSource, /property color badgeBackground: Color\.bar\.background/)
  assert.match(tailscaleIconSource, /borderSpec: Border\.flat\(root\.badgeBackground, 1\)/)
  assert.match(tailscaleBarButtonSource, /TailscaleIcon \{[\s\S]*?badgeBackground: Color\.bar\.background/)
  const panelIconSource = tailscalePanelSource.slice(tailscalePanelSource.indexOf("iconComponent: Component"))
  assert.match(panelIconSource, /TailscaleIcon \{[\s\S]*?badgeBackground: Color\.barPanels\.background/)
})

contract("tailscale bar icon applies its measured optical correction", () => {
  assert.match(tailscaleBarButtonSource,
    /TailscaleIcon \{[\s\S]*?anchors\.horizontalCenterOffset: Style\.space\(2\)[\s\S]*?anchors\.verticalCenterOffset: Style\.space\(2\)/)
})

contract("center anchor boundaries use one module gap", () => {
  assert.match(centerSource, /anchors\.rightMargin: root\.moduleGap/)
  assert.match(centerSource, /anchors\.leftMargin: root\.moduleGap/)
})

contract("bar variants bind each screen in the delegate", () => {
  assert.match(barVariantsSource, /BarPanel \{[\s\S]*?required property var modelData[\s\S]*?screen: modelData/)
  assert.doesNotMatch(barPanelSource, /required property var modelData|screen: modelData/)
})

contract("command modules provide their loader component", () => {
  assert.match(barSource, /Component \{\s*id: customCommandModuleComponent\s*CustomCommandModule \{ entry: slot\.entry \}\s*\}/)
  assert.match(barSource, /function injectProps\(\) \{[\s\S]*?if \(slot\.commandCustom\) return/)
})

contract("bar typography and icons use shared sizing contracts", () => {
  assert.match(barSource, /property real fontSize: 14/)
  assert.match(barSource, /property int fontWeight: Font\.Bold/)
  assert.match(widgetButtonSource, /fontSize: bar && bar\.fontSize \? bar\.fontSize : Style\.font\.body/)
  assert.match(widgetButtonSource, /font\.weight: root\.fontWeight/)
  assert.match(barIconButtonSource, /fontSize: bar && bar\.iconFontSize \? bar\.iconFontSize : Style\.bar\.iconFont/)
  assert.match(traySource, /width: Style\.space\(16\)[\s\S]*height: Style\.space\(16\)/)
})

contract("workspaces are monitor-local labeled buttons", () => {
  assert.match(workspacesSource, /import Quickshell\n/)
  assert.doesNotMatch(workspacesSource, /var ids = \[1, 2, 3, 4, 5\]/)
  assert.match(workspacesSource, /workspace\.monitor\.name !== root\.screenName/)
  assert.match(workspacesSource, /root\.setting\("labels", \(\{\}\)\)/)
  assert.match(workspacesSource, /text: displayName/)
  assert.match(workspacesSource, /active: focused/)
  assert.doesNotMatch(workspacesSource, /focused \? "\\uDB85\\uDCFB"/)
})

contract("bar buttons reuse shared hover states", () => {
  assert.match(widgetButtonSource,
    /readonly property bool hot: visible && interactive && !concealed && mouseArea\.containsMouse/)
  assert.match(widgetButtonSource,
    /readonly property color contentColor: mouseArea\.pressed[\s\S]*?Style\.pressedStateColor\(foreground, accent\)[\s\S]*?hot[\s\S]*?Style\.hoverStateColor\(foreground, accent\)[\s\S]*?active && useActiveColor/)
  assert.match(widgetButtonSource,
    /mouseArea\.pressed[\s\S]*?Style\.pressedFillFor\(root\.foreground, root\.accent\)/)
  assert.match(widgetButtonSource,
    /root\.hot[\s\S]*?Style\.hoverFillFor\(root\.foreground, root\.accent\)/)
  assert.match(widgetButtonSource,
    /Border\.controlSpec\("hover-cursor", root\.foreground, root\.accent\)/)
  assert.match(barIconButtonSource, /color: root\.contentColor/)
  assert.match(clockSource, /color: button\.contentColor/)
})

contract("fixed bar model has no drag or position helpers", () => {
  assert.strictEqual(model.nearestDropTarget, undefined)
  assert.strictEqual(model.normalizePosition, undefined)
  assert.doesNotMatch(barSource, /function normalizePosition/)
})

assert.strictEqual(failures.length, 0, failures.join("\n"))

console.log("bar-model-test: neutral and review-fix contracts verified")
