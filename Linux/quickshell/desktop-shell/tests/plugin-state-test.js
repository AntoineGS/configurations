const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const State = require("../services/PluginState.js")

const qmlContext = {}
vm.runInNewContext(fs.readFileSync(require.resolve("../services/PluginState.js"), "utf8"), qmlContext)
assert.equal(qmlContext.emptyState().version, 1)

const defaults = {
  version: 1,
  bar: {
    id: "desktop.bar",
    layout: {
      left: [{ id: "desktop.menu" }],
      center: [{ id: "desktop.clock" }],
      right: [{ id: "desktop.tray" }],
    },
  },
  plugins: [],
}

assert.deepEqual(State.emptyState(), { version: 1 })
assert.equal(State.parseState("").valid, true)
assert.equal(State.parseState("{").valid, false)
assert.equal(State.parseState(JSON.stringify({
  version: 1,
  enabledPlugins: [{ id: "desktop.notifications" }],
})).valid, false)

const parsed = State.parseState(JSON.stringify({
  version: 1,
  enabledPlugins: [{ id: "acme.panel" }],
  barWidgets: [{ id: "acme.weather", section: "right", index: 0, settings: { units: "c" } }],
  barPluginId: "acme.bar",
}))
assert.equal(parsed.valid, true)

const effective = State.mergeConfig(defaults, parsed.state)
assert.deepEqual(effective.plugins, [{ id: "acme.panel" }])
assert.equal(effective.bar.id, "acme.bar")
assert.deepEqual(effective.bar.layout.right, [
  { id: "acme.weather", units: "c" },
  { id: "desktop.tray" },
])
assert.deepEqual(defaults.bar.layout.right, [{ id: "desktop.tray" }])

const changedDefaults = structuredClone(defaults)
changedDefaults.bar.layout.right.push({ id: "desktop.power" })
assert.deepEqual(State.mergeConfig(changedDefaults, parsed.state).bar.layout.right, [
  { id: "acme.weather", units: "c" },
  { id: "desktop.tray" },
  { id: "desktop.power" },
])

const emptySettingsState = State.setEnabled(State.emptyState(), {
  id: "acme.empty-widget",
  kinds: ["bar-widget"],
  barWidget: { defaultSection: "right" },
}, true, {}, defaults).state
assert.equal(emptySettingsState.barWidgets[0].settings, undefined)
assert.equal(State.parseState(JSON.stringify(emptySettingsState)).valid, true)
assert.equal(State.parseState(JSON.stringify(parsed.state)).valid, true)
assert.equal(State.parseState(JSON.stringify(State.parseState(JSON.stringify({
  version: 1,
  barWidgets: [{ id: "acme.empty", section: "left", index: 0, settings: {} }],
})).state)).valid, true)

assert.equal(State.parseState(JSON.stringify({
  version: 1,
  enabledPlugins: [{ id: "acme.one" }, { id: "acme.one" }],
})).valid, false)
assert.equal(State.parseState(JSON.stringify({ version: 1, extra: true })).valid, false)
assert.equal(State.parseState(JSON.stringify({
  version: 1,
  barWidgets: [{ id: "acme.one", section: "invalid", index: 0, settings: {} }],
})).valid, false)
assert.equal(State.parseState(JSON.stringify({
  version: 1,
  barWidgets: [{ id: "acme.one", section: "right", index: -1, settings: {} }],
})).valid, false)
assert.equal(State.parseState(JSON.stringify({
  version: 1,
  barWidgets: [{ id: "acme.one", section: "right", index: 1.5, settings: {} }],
})).valid, false)
assert.equal(State.parseState(JSON.stringify({
  version: 1,
  barWidgets: [{ id: "acme.one", section: "right", index: 0, settings: [] }],
})).valid, false)
for (const id of ["desktop.one", "omarchy.one", "acme/one", "acme..one"]) {
  assert.equal(State.parseState(JSON.stringify({ version: 1, enabledPlugins: [{ id }] })).valid, false)
}

const ordered = State.parseState(JSON.stringify({
  version: 1,
  barWidgets: [
    { id: "acme.first", section: "left", index: 0, settings: {} },
    { id: "acme.second", section: "left", index: 0, settings: {} },
  ],
})).state
assert.deepEqual(State.mergeConfig(defaults, ordered).bar.layout.left.slice(0, 2), [
  { id: "acme.first" },
  { id: "acme.second" },
])

const panel = { id: "acme.panel", kinds: ["panel"] }
const widget = {
  id: "acme.weather",
  kinds: ["bar-widget"],
  barWidget: { defaultSection: "right" },
}
const keepLoadedWidget = {
  id: "acme.marketplace",
  kinds: ["bar-widget"],
  keepLoaded: true,
  barWidget: { defaultSection: "right" },
}
const widgetWithoutDefault = { id: "weather", kinds: ["bar-widget"] }
const hybrid = { id: "acme.hybrid", kinds: ["panel", "bar-widget"] }
const fullBar = { id: "acme.bar", kinds: ["bar"] }
let state = State.emptyState()
let result = State.setEnabled(state, panel, true, {}, defaults)
assert.equal(result.ok, true)
assert.deepEqual(result.state.enabledPlugins, [{ id: "acme.panel" }])
assert.deepEqual(state, { version: 1 })

const fallbackResult = State.setEnabled(State.emptyState(), widgetWithoutDefault, true, {}, defaults)
assert.equal(fallbackResult.ok, true)
assert.deepEqual(fallbackResult.state.barWidgets[0], { id: "weather", section: "center", index: 0 })

result = State.setEnabled(result.state, widget, true, { section: "right", index: 0 }, defaults)
assert.equal(result.ok, true)
assert.equal(State.inBar(result.state, "acme.weather"), true)
result = State.setWidget(result.state, "acme.weather", "units", "c")
assert.deepEqual(result.state.barWidgets[0].settings, { units: "c" })
result = State.setEnabled(result.state, widget, true, { section: "right", index: 0 }, defaults)
assert.deepEqual(result.state.barWidgets.find((item) => item.id === "acme.weather").settings, { units: "c" })

let equalIndexState = State.emptyState()
equalIndexState = State.setEnabled(equalIndexState, {
  id: "acme.first",
  kinds: ["bar-widget"],
  barWidget: { defaultSection: "left" },
}, true, { section: "left", index: 0 }, defaults).state
equalIndexState = State.setEnabled(equalIndexState, {
  id: "acme.second",
  kinds: ["bar-widget"],
  barWidget: { defaultSection: "left" },
}, true, { section: "left", index: 0 }, defaults).state
const equalIndexBefore = structuredClone(equalIndexState)
const equalIndexAfter = State.setEnabled(equalIndexState, {
  id: "acme.first",
  kinds: ["bar-widget"],
  barWidget: { defaultSection: "left" },
}, true, { section: "left", index: 0 }, defaults)
assert.deepEqual(equalIndexAfter.state, equalIndexBefore)
assert.deepEqual(State.mergeConfig(defaults, equalIndexAfter.state).bar.layout.left.slice(0, 2), [
  { id: "acme.first" },
  { id: "acme.second" },
])
result = State.setEnabled(result.state, fullBar, true, {}, defaults)
assert.equal(result.state.barPluginId, "acme.bar")
result = State.setEnabled(result.state, { id: "desktop.bar", kinds: ["bar"], __isFirstParty: true }, true, {}, defaults)
assert.equal(result.ok, true)
assert.equal(result.state.barPluginId, undefined)
result = State.setEnabled(result.state, { id: "desktop.clock", kinds: ["bar-widget"], __isFirstParty: true }, false)
assert.equal(result.ok, false)

let headless = State.setEnabled(State.emptyState(), keepLoadedWidget, true, { headless: true }, defaults)
assert.equal(headless.ok, true)
assert.deepEqual(headless.state.enabledPlugins, [{ id: "acme.marketplace" }])
assert.equal(State.inBar(headless.state, "acme.marketplace"), false)

let placed = State.setEnabled(headless.state, keepLoadedWidget, true, { section: "right" }, defaults)
assert.equal(placed.state.enabledPlugins, undefined)
assert.equal(State.inBar(placed.state, "acme.marketplace"), true)

headless = State.setEnabled(placed.state, keepLoadedWidget, true, { headless: true }, defaults)
assert.deepEqual(headless.state.enabledPlugins, [{ id: "acme.marketplace" }])
assert.equal(State.inBar(headless.state, "acme.marketplace"), false)

const rejected = State.setEnabled(State.emptyState(), widget, true, { headless: true }, defaults)
assert.equal(rejected.ok, false)
assert.match(rejected.error, /keepLoaded/)

result = State.setEnabled(result.state, hybrid, true, { section: "left", index: 100 }, defaults)
assert.equal(result.ok, true)
assert.deepEqual(result.state.enabledPlugins, [{ id: "acme.panel" }])
assert.equal(State.inBar(result.state, "acme.hybrid"), true)
assert.equal(result.state.barWidgets.find((item) => item.id === "acme.hybrid").index, 1)
const moved = State.moveWidget(result.state, "acme.hybrid", { section: "center", index: 0 }, defaults)
assert.equal(moved.ok, true)
assert.deepEqual(moved.state.barWidgets.find((item) => item.id === "acme.hybrid"), {
  id: "acme.hybrid",
  section: "center",
  index: 0,
})
result = moved
assert.deepEqual(result.state.barWidgets.find((item) => item.id === "acme.weather").settings, { units: "c" })
const beforeInvalidPlacement = structuredClone(result.state)
const invalidPlacement = State.setEnabled(result.state, widget, true, { section: "bad" }, defaults)
assert.equal(invalidPlacement.ok, false)
assert.deepEqual(result.state, beforeInvalidPlacement)
const beforeMissingWidget = structuredClone(result.state)
assert.equal(State.setWidget(result.state, "missing", "x", 1).ok, false)
assert.deepEqual(result.state, beforeMissingWidget)
assert.deepEqual(State.setWidget(result.state, "acme.hybrid", "unused", undefined).state, result.state)

const beforeDisable = structuredClone(result.state)
result = State.setEnabled(result.state, widget, false, {}, defaults)
assert.equal(result.ok, true)
assert.equal(State.inBar(result.state, "acme.weather"), false)
assert.deepEqual(result.state.enabledPlugins, beforeDisable.enabledPlugins)
const clamped = State.setEnabled(result.state, widget, true, { section: "right", index: 999 }, defaults)
assert.equal(clamped.ok, true)
assert.equal(clamped.state.barWidgets.find((item) => item.id === "acme.weather").index, 1)
assert.equal(State.mergeConfig(defaults, clamped.state).bar.layout.right[1].id, "acme.weather")
const beforeMissingMove = structuredClone(result.state)
assert.equal(State.moveWidget(result.state, "missing", { section: "left", index: 0 }, defaults).ok, false)
assert.deepEqual(result.state, beforeMissingMove)

let cleanup = State.emptyState()
cleanup = State.setEnabled(cleanup, panel, true, {}, defaults).state
cleanup = State.setEnabled(cleanup, widget, true, { section: "right", index: 0 }, defaults).state
cleanup = State.setEnabled(cleanup, fullBar, true, {}, defaults).state
cleanup = State.setEnabled(cleanup, widget, false, {}, defaults).state
assert.equal(cleanup.barWidgets, undefined)
cleanup = State.setEnabled(cleanup, panel, false, {}, defaults).state
assert.equal(cleanup.enabledPlugins, undefined)
cleanup = State.setEnabled(cleanup, fullBar, false, {}, defaults).state
assert.equal(cleanup.barPluginId, undefined)

console.log("plugin state tests passed")
