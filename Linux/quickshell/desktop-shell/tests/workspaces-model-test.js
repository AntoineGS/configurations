const assert = require("assert")
const Model = require("../plugins/bar/widgets/WorkspacesModel.js")

const objectModel = {
  0: { id: 1 },
  1: { id: 4 },
  length: 2
}

assert.deepEqual(Model.objectModelValues(objectModel).map(workspace => workspace.id), [1, 4])
assert.deepEqual(Model.objectModelValues([{ id: 2 }]).map(workspace => workspace.id), [2])
assert.equal(Model.activeWorkspaceId([
  { name: "eDP-1", activeWorkspace: { id: 4 } },
  { name: "DP-1", activeWorkspace: { id: 7 } }
], "eDP-1"), 4)
assert.equal(Model.activeWorkspaceId([], "eDP-1"), -1)
assert.equal(Model.activeWorkspaceId([{ name: "eDP-1", activeWorkspace: null }], "eDP-1"), -1)
assert.equal(Model.confirmedActiveWorkspaceId(4, [], "eDP-1"), 4)
assert.equal(Model.confirmedActiveWorkspaceId(4, [
  { name: "eDP-1", activeWorkspace: { id: 2 } }
], "eDP-1"), 2)
