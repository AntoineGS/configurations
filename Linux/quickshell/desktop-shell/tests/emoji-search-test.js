const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const search = require("../plugins/emojis/EmojiSearch.js")

const raw = fs.readFileSync(path.join(__dirname, "../plugins/emojis/emojis.json"), "utf8")
const data = search.parseEmojis(raw)
assert.ok(data.length > 1000)
assert.deepEqual(search.parseEmojis("{"), [])
assert.deepEqual(search.parseEmojis('{"e":"nope"}'), [])

const fixture = [
  { e: "a", k: "grinning face smile happy" },
  { e: "b", k: "face with tears of joy joy tears" },
  { e: "c", k: "flag united states us america" },
]
assert.deepEqual(search.filterEmojis(fixture, "  JOY  ").map(item => item.e), ["b"])
assert.deepEqual(search.filterEmojis(fixture, "", 2).map(item => item.e), ["a", "b"])
assert.deepEqual(search.filterEmojis(fixture, "", 0), [])
assert.equal(search.filterEmojis(data, "face with tears")[0].e, "😂")

assert.deepEqual(search.parseRecentEmojis('["😂","😂","","👍",3]', 8), ["😂", "👍"])
assert.deepEqual(search.parseRecentEmojis("{", 8), [])

const recent = ["😂", "👍", "🔥", "❤️", "🎉", "✅", "👀", "🤔"]
assert.deepEqual(search.addRecentEmoji(recent, "🔥", 8), ["🔥", "😂", "👍", "❤️", "🎉", "✅", "👀", "🤔"])
assert.deepEqual(search.addRecentEmoji(recent, "🚀", 8), ["🚀", "😂", "👍", "🔥", "❤️", "🎉", "✅", "👀"])
assert.deepEqual(search.addRecentEmoji(recent, "", 8), recent)
