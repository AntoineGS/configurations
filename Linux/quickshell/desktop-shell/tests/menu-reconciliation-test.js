const assert = require("node:assert/strict")
const model = require("../plugins/menu/MenuModel.js")

function applyOperations(rows, operations) {
  const work = rows.map(row => ({ ...row }))
  for (const operation of operations) {
    if (operation.type === "remove") {
      work.splice(operation.index, 1)
    } else if (operation.type === "move") {
      const moved = work.splice(operation.from, 1)
      work.splice(operation.to, 0, moved[0])
    } else if (operation.type === "insert") {
      work.splice(operation.index, 0, { ...operation.row })
    } else if (operation.type === "set") {
      work[operation.index] = { ...operation.row }
    } else {
      assert.fail(`unknown operation: ${operation.type}`)
    }
  }
  return work
}

const current = [
  { itemId: "a", label: "A old", disabled: false },
  { itemId: "b", label: "B", disabled: false },
  { itemId: "c", label: "C old", disabled: false },
]
const next = [
  { itemId: "c", label: "C new", disabled: true },
  { itemId: "a", label: "A new", disabled: false },
  { itemId: "d", label: "D", disabled: false },
]

const operations = model.planRowReconciliation(current, next)

assert.deepEqual(operations.map(operation => ({
  type: operation.type,
  index: operation.index,
  from: operation.from,
  to: operation.to,
})), [
  { type: "remove", index: 1, from: undefined, to: undefined },
  { type: "move", index: undefined, from: 1, to: 0 },
  { type: "set", index: 0, from: undefined, to: undefined },
  { type: "set", index: 1, from: undefined, to: undefined },
  { type: "insert", index: 2, from: undefined, to: undefined },
])
assert.deepEqual(applyOperations(current, operations), next)
assert.deepEqual(applyOperations([], model.planRowReconciliation([], next)), next)
assert.deepEqual(applyOperations(current, model.planRowReconciliation(current, [])), [])

const unchanged = [{ itemId: "same", label: "Same", disabled: false }]
assert.deepEqual(model.planRowReconciliation(unchanged, unchanged), [])

const duplicateCurrent = [
  { itemId: "duplicate", label: "First", disabled: false },
  { itemId: "duplicate", label: "Second", disabled: false },
]
const duplicateNext = [{ itemId: "duplicate", label: "Only", disabled: true }]
assert.deepEqual(
  applyOperations(duplicateCurrent, model.planRowReconciliation(duplicateCurrent, duplicateNext)),
  duplicateNext,
)
