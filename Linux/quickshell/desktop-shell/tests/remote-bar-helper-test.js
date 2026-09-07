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
  { pid: 2, ppid: 1, comm: "ssh", argv: ["ssh", "ssh://user@ANTOINEWS-LINUX"] },
], "antoinews-linux"), "ssh://user@ANTOINEWS-LINUX")
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

const targets = ["antoinews-linux", "DESKTOP-E07VTRN"]
const monitors = [
  { id: 0, name: "eDP-1", activeWorkspace: { id: 1 }, specialWorkspace: { id: -99 } },
  { id: 1, name: "DP-2", activeWorkspace: { id: 2 } },
  { id: 2, name: "DP-off", activeWorkspace: { id: 3 }, dpmsStatus: false },
  { id: 3, name: "DP-disabled", activeWorkspace: { id: 4 }, disabled: true },
]
const terminal = (pid, host, rank, extra = {}) => ({
  pid, title: `${host}: ~/work`, class: "com.mitchellh.ghostty",
  workspace: { id: 1 }, monitor: 0, focusHistoryID: rank, ...extra,
})
const older = terminal(10, targets[0], 5)
const recent = terminal(20, "desktop-e07vtrn", 1)
assert.deepEqual(Helper.selectRemoteWindows(monitors, [
  older, recent, terminal(30, targets[0], 0, { class: "chromium" }),
  terminal(40, "local", 0), terminal(50, "antoinews-linux-extra", 0),
], targets), [{ screen: "eDP-1", host: targets[1], pid: 20 }])
for (const extra of [
  { mapped: false }, { hidden: true }, { visible: false },
  { workspace: { id: 9 } }, { workspace: { id: 3 }, monitor: 2 },
  { workspace: { id: 4 }, monitor: 3 },
]) {
  assert.deepEqual(Helper.selectRemoteWindows(monitors, [older, { ...recent, ...extra }], targets),
    [{ screen: "eDP-1", host: targets[0], pid: 10 }])
}
assert.deepEqual(Helper.selectRemoteWindows(monitors, [
  older, recent, terminal(60, targets[0], 0, { workspace: { id: 2 }, monitor: 1 }),
], targets), [
  { screen: "DP-2", host: targets[0], pid: 60 },
  { screen: "eDP-1", host: targets[1], pid: 20 },
])
assert.deepEqual(Helper.selectRemoteWindows(monitors, [
  older, terminal(70, targets[1], 0, { workspace: { id: -99 } }),
], targets), [{ screen: "eDP-1", host: targets[1], pid: 70 }])
assert.deepEqual(Helper.selectRemoteWindows(monitors, [
  terminal(80, targets[1], 0, { pinned: true, workspace: { id: 1 }, monitor: 1 }),
  terminal(90, targets[0], 0, { pinned: true, monitor: 2 }),
], targets), [{ screen: "DP-2", host: targets[1], pid: 80 }])
const unranked = [terminal(20, targets[1], -1), terminal(10, targets[0], undefined)]
assert.deepEqual(Helper.selectRemoteWindows(monitors, [...unranked, terminal(30, targets[1], 9)], targets),
  [{ screen: "eDP-1", host: targets[1], pid: 30 }])
assert.deepEqual(Helper.selectRemoteWindows(monitors, unranked, targets),
  Helper.selectRemoteWindows(monitors, [...unranked].reverse(), targets))
const tied = [terminal(20, targets[1], 1), terminal(10, targets[0], 1)]
assert.deepEqual(Helper.selectRemoteWindows(monitors, tied, targets),
  [{ screen: "eDP-1", host: targets[0], pid: 10 }])
assert.deepEqual(Helper.selectRemoteWindows(monitors, [...tied].reverse(), targets),
  Helper.selectRemoteWindows(monitors, tied, targets))
assert.deepEqual(Helper.selectRemoteWindows(null, null, targets), [])

// Exercise CLI wiring and ancestry resolution without a live compositor or SSH connection.
async function testDetect() {
  const fs = require("node:fs/promises")
  const vm = require("node:vm")
  const source = await fs.readFile(require.resolve("../../../os/helpers/desktop-remote-bar"), "utf8")
  const calls = []
  let sessionReads = 0
  let output = ""
  const identities = new Map([[10, 0], [20, 0], [60, 0], [101, 10], [201, 20], [601, 60]])
  const sessions = [
    { pid: 101, startTime: "123", sshTarget: "wrong-user@DESKTOP-E07VTRN" },
    { pid: 201, startTime: "123", sshTarget: "ssh://user@desktop-e07vtrn" },
  ]
  const fakeFs = {
    async readdir(name) {
      if (name.endsWith("desktop-remote-bar-sessions")) {
        sessionReads += 1
        return sessions.map(session => `${session.pid}.json`)
      }
      return [name.split("/")[2]]
    },
    async readFile(name) {
      if (name.endsWith(".json")) return JSON.stringify(sessions.find(s => name.endsWith(`/${s.pid}.json`)))
      const pid = Number(name.split("/")[2])
      if (!identities.has(pid)) throw new Error("missing process")
      if (name.endsWith("/stat")) {
        const fields = Array(20).fill("0")
        fields[0] = "S"
        fields[1] = String(identities.get(pid))
        fields[19] = "123"
        return `${pid} (process) ${fields.join(" ")}`
      }
      if (name.endsWith("/comm")) return pid >= 100 ? "ssh" : "ghostty"
      if (name.endsWith("/children")) return pid === 60 ? "601" : ""
      if (name.endsWith("/cmdline")) return Buffer.from(pid === 601
        ? "ssh\0Multidev\\a.simard@ANTOINEWS-LINUX\0" : "ghostty\0")
      throw new Error(`unexpected read ${name}`)
    },
  }
  const sandbox = {
    module: { exports: {} }, Buffer, console,
    process: { env: { XDG_RUNTIME_DIR: "/runtime" }, stdout: { write(text) { output += text } } },
    require(name) {
      if (name === "node:fs/promises") return fakeFs
      if (name === "node:child_process") return {
        execFile(command, args, options, callback) {
          calls.push([command, ...args])
          callback(null, { stdout: JSON.stringify(args.includes("monitors") ? monitors : [
            older, recent, terminal(60, targets[0], 0, { workspace: { id: 2 }, monitor: 1 }),
          ]) })
        },
      }
      return require(name)
    },
  }
  vm.createContext(sandbox)
  vm.runInContext(source, sandbox)
  await vm.runInContext('main(["detect", "antoinews-linux", "DESKTOP-E07VTRN"])', sandbox)
  assert.deepEqual(JSON.parse(output), { screens: [
    { screen: "DP-2", host: targets[0], sshTarget: "Multidev\\a.simard@ANTOINEWS-LINUX" },
    { screen: "eDP-1", host: targets[1], sshTarget: "ssh://user@desktop-e07vtrn" },
  ] })
  assert.equal(sessionReads, 1)
  assert.deepEqual(calls, [["hyprctl", "-j", "monitors", "all"], ["hyprctl", "-j", "clients"]])
  identities.delete(201)
  output = ""
  // A selected terminal without a matching session/tree must use its canonical host,
  // never borrow the older terminal's credentials.
  fakeFs.rm = async () => {}
  await vm.runInContext('main(["detect", "antoinews-linux", "DESKTOP-E07VTRN"])', sandbox)
  assert.equal(JSON.parse(output).screens[1].sshTarget, targets[1])
  console.log("remote-bar-helper tests passed")
}
testDetect().catch(error => {
  console.error(error)
  process.exitCode = 1
})
