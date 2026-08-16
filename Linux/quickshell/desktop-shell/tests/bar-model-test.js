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

contract("native tray display has QApplication shell mode", () => {
  assert.match(shellSource, /^\/\/\@ pragma UseQApplication\r?\n/)
  assert.match(traySource, /function openTrayMenu[\s\S]*?item\.display\(/)
})

contract("clock updates at seconds precision", () => {
  assert.match(clockSource, /precision: SystemClock\.Seconds/)
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

contract("bar matches Waybar density", () => {
  assert.match(barSource, /readonly property int barSize: 32/)
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

contract("fixed bar model has no drag or position helpers", () => {
  assert.strictEqual(model.nearestDropTarget, undefined)
  assert.strictEqual(model.normalizePosition, undefined)
  assert.doesNotMatch(barSource, /function normalizePosition/)
})

assert.strictEqual(failures.length, 0, failures.join("\n"))

console.log("bar-model-test: neutral and review-fix contracts verified")
