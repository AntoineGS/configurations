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
const centerSource = barSource.slice(barSource.indexOf("component CenterModules"), barSource.indexOf("component ModuleList"))

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

contract("fixed bar model has no drag or position helpers", () => {
  assert.strictEqual(model.nearestDropTarget, undefined)
  assert.strictEqual(model.normalizePosition, undefined)
  assert.doesNotMatch(barSource, /function normalizePosition/)
})

assert.strictEqual(failures.length, 0, failures.join("\n"))

console.log("bar-model-test: neutral and review-fix contracts verified")
