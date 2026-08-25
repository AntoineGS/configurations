const assert = require("node:assert/strict")
const history = require("../plugins/clipboard/ClipboardHistory.js")

assert.deepEqual(history.parseHistoryResult("{"), { valid: false, history: [] })
assert.deepEqual(history.parseHistoryResult('{"type":"text"}'), { valid: false, history: [] })
assert.deepEqual(history.parseHistoryResult('["one",{"type":"text","text":"two"}]'), {
  valid: true,
  history: [{ type: "text", text: "one" }, { type: "text", text: "two" }],
})
assert.deepEqual(history.parseHistoryResult(JSON.stringify([" ", { type: "text", text: "\t" }])), { valid: true, history: [] })

const imageRoot = "/state/clipboard-images"
const hashedImage = `${imageRoot}/${"a".repeat(64)}.png`
assert.deepEqual(history.parseHistoryResult(JSON.stringify([{ type: "image", path: hashedImage, mime: "image/png" }]), imageRoot), {
  valid: true,
  history: [{ type: "image", path: hashedImage, mime: "image/png" }],
})
assert.deepEqual(history.parseHistoryResult(JSON.stringify([{ type: "image", path: "/tmp/outside.png", mime: "image/png" }]), imageRoot), {
  valid: true,
  history: [],
})
assert.deepEqual(history.parseHistoryResult(JSON.stringify([{ type: "image", path: `${imageRoot}/nested/a.png`, mime: "image/png" }]), imageRoot), {
  valid: true,
  history: [],
})

const oversized = Array.from({ length: 501 }, (_, index) => `entry-${index}`)
assert.equal(history.parseHistoryResult(JSON.stringify(oversized)).history.length, 500)

assert.deepEqual(history.addEntry([
  { type: "text", text: "old" },
  { type: "text", text: "new" },
], { type: "text", text: "new" }, 500), [
  { type: "text", text: "new" },
  { type: "text", text: "old" },
])
assert.equal(history.addEntry([], { type: "text", text: "new" }, 0).length, 0)

const entries = [
  { type: "text", text: "old" },
  { type: "image", path: "/state/a.png", mime: "image/png", capturedAt: "Friday 14:42" },
]
assert.deepEqual(history.removeEntryAt(entries, 0), [entries[1]])
assert.deepEqual(history.removeEntryAt(entries, 10), entries)
assert.deepEqual(history.imagePaths(entries), ["/state/a.png"])

const imageRow = history.displayRows(entries, "image", 50)[0]
assert.equal(imageRow.entryType, "image")
assert.equal(imageRow.previewText, "Screenshot from Friday 14:42")
assert.equal(imageRow.index, 1)

const fileRow = history.displayRows([{ type: "text", text: "file:///tmp/demo%20image.png\n" }], "demo", 50)[0]
assert.equal(fileRow.entryType, "file")
assert.equal(fileRow.fullText, "/tmp/demo image.png")
assert.equal(fileRow.previewText, "demo image.png")
assert.equal(fileRow.previewImage, "/tmp/demo image.png")

const filesRow = history.displayRows([{ type: "text", text: "file:///tmp/one.txt\nfile:///tmp/two.txt\n" }], "", 50)[0]
assert.equal(filesRow.previewText, "2 files")
assert.equal(history.displayRows([{ type: "text", text: "file:///tmp/demo.mp4\n" }], "", 50)[0].previewImage, "")
assert.deepEqual(history.displayRows(entries, "", 0), [])

const hugeRow = history.displayRows([{ type: "text", text: "x".repeat(100000) }], "", 50)[0]
assert.equal(hugeRow.fullText.length, 8192)
assert.equal(hugeRow.previewText.length, 8192)
assert.deepEqual(history.displayRows([{ type: "text", text: "x".repeat(8192) + "needle" }], "needle", 50), [])
