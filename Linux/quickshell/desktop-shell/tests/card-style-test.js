#!/usr/bin/env node
"use strict"

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const shellRoot = path.resolve(__dirname, "..")
const read = relative => fs.readFileSync(path.join(shellRoot, relative), "utf8")
const theme = read("config/shell.toml")
const color = read("Commons/Color.qml")
const border = read("Commons/Border.qml")

function section(name) {
  const marker = `[${name}]\n`
  const start = theme.indexOf(marker)
  if (start < 0) return ""
  const rest = theme.slice(start + marker.length)
  const next = rest.search(/^\[/m)
  return next < 0 ? rest : rest.slice(0, next)
}

const cards = section("cards")
assert.match(cards, /^background\s*=\s*"#52476a"$/m)
assert.match(cards, /^background-alpha\s*=\s*1\.0$/m)
assert.match(cards, /^text\s*=\s*"#cdd6f4"$/m)
assert.match(cards, /^border\s*=\s*"#52476a"$/m)
assert.match(cards, /^border-alpha\s*=\s*1\.0$/m)
assert.match(cards, /^border-width\s*=\s*2$/m)

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
assert.match(color, /inheritedComposed\("bar-panels",\s*"cards",\s*"background"/)
assert.match(color, /inheritedPick\("bar-panels",\s*"text",\s*"cards"/)

assert.match(border, /function surfaceBase\(section\)/)
assert.match(border, /section === "notifications" \|\| section === "tooltip" \|\| section === "bar-panels"/)
assert.match(border, /function surfaceValue\(section, key\)/)
assert.match(border, /function surfaceValueOr\(section, keys\)/)
assert.match(border, /function surfaceAlpha\(section, key, fallback\)/)
assert.match(border, /surfaceValueOr\(section, token === "border"/)
assert.match(border, /surfaceAlpha\(section, alphaKey \|\| token \+ "-alpha", 1\.0\)/)
assert.match(border, /resolveValueRef\(surfaceValue\(section, token\)\)/)
assert.match(border, /surfaceValue\("notifications", "border"\)/)
assert.match(border, /surfaceAlpha\("notifications", "border-alpha", opacity\)/)

console.log("card-style-test: shared card theme contract verified")
