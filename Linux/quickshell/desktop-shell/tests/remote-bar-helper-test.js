const assert = require("node:assert/strict")
const Helper = require("../../../os/helpers/desktop-remote-bar")

assert.equal(Helper.sshDestination(["ssh", "antoinews-linux"]), "antoinews-linux")
assert.equal(Helper.sshDestination(["ssh", "-p", "22", "user@antoinews-linux"]), "user@antoinews-linux")
assert.equal(Helper.sshDestination([
  "ssh", "-t", "-R", "/tmp/server.sock:/tmp/client.sock", "Multidev\\a.simard@antoinews-linux",
  "--", "waypipe", "server",
]), "Multidev\\a.simard@antoinews-linux")
assert.equal(Helper.destinationHost("Multidev\\a.simard@antoinews-linux"), "antoinews-linux")
assert.equal(Helper.isSshConnection(["ssh", "antoinews-linux"]), true)
assert.equal(Helper.isSshConnection(["ssh", "-N", "antoinews-linux"]), true)
assert.equal(Helper.isSshConnection(["ssh", "-G", "antoinews-linux"]), false)
assert.equal(Helper.isSshConnection(["ssh", "-O", "check", "antoinews-linux"]), false)
assert.equal(Helper.isSshConnection(["ssh", "-V"]), false)
assert.equal(Helper.isTargetSsh({
  comm: "ssh",
  argv: ["ssh", "-t", "user@antoinews-linux", "command"],
}, "antoinews-linux"), true)
assert.equal(Helper.isTargetSsh({
  comm: "ssh",
  argv: ["ssh", "other-host", "antoinews-linux"],
}, "antoinews-linux"), false)
assert.equal(Helper.targetSshDestination([
  { pid: 1, ppid: 0, comm: "ghostty", argv: ["ghostty"] },
  { pid: 2, ppid: 1, comm: "waypipe", argv: ["waypipe"] },
  { pid: 3, ppid: 2, comm: "ssh", argv: ["ssh", "user@antoinews-linux"] },
], "antoinews-linux"), "user@antoinews-linux")
assert.equal(Helper.targetSshDestination([
  { pid: 1, ppid: 0, comm: "ghostty", argv: ["ghostty"] },
  { pid: 2, ppid: 1, comm: "tmux", argv: ["tmux"] },
  { pid: 3, ppid: 2, comm: "ssh", argv: ["ssh", "user@antoinews-linux"] },
], "antoinews-linux"), "")

assert.deepEqual(Array.from(Helper.visibleWorkspaceIds([
  { activeWorkspace: { id: 8 }, specialWorkspace: { id: 0 } },
  { activeWorkspace: { id: 3 }, specialWorkspace: { id: -99 } },
  { activeWorkspace: { id: 9 }, specialWorkspace: { id: 0 }, dpmsStatus: false },
])), [8, 3, -99])
assert.deepEqual(Array.from(Helper.visibleWorkspaceScreens([
  { name: "DP-3", activeWorkspace: { id: 8 }, specialWorkspace: { id: 0 } },
  { name: "DP-2", activeWorkspace: { id: 3 }, specialWorkspace: { id: 0 } },
])), [[8, "DP-3"], [3, "DP-2"]])
