import assert from "node:assert/strict"
import test from "node:test"

import {
  paneFocusRequest,
  parseAgentEvent,
  resolveNotification,
  selectGhosttyTarget,
  selectGhosttyAddress,
  sessionFromSocketPath,
} from "./notification-policy.mjs"
import { handleEvent, processTree } from "./notify.mjs"

const event = {
  type: "pane_agent_status_changed",
  pane_id: "w1G:p1",
  workspace_id: "w1G",
  agent: "opencode",
  display_agent: "OpenCode",
  agent_status: "done",
  state_labels: {},
}

const snapshot = {
  result: {
    snapshot: {
      focused_tab_id: "w1F:t1",
      panes: [{ pane_id: "w1G:p1", tab_id: "w1G:t2", workspace_id: "w1G", agent: "opencode", agent_status: "done" }],
      tabs: [{ tab_id: "w1G:t2", workspace_id: "w1G", focused: false, label: "review", number: 2 }],
      workspaces: [{ workspace_id: "w1G", label: "configurations", number: 3, tab_count: 2 }],
    },
  },
}

test("accepts only actionable Herdr pane events", () => {
  assert.deepEqual(parseAgentEvent(JSON.stringify(event)), event)
  const envelopeEvent = {
    type: "pane_agent_status_changed",
    pane_id: "w1M:p1",
    workspace_id: "w1M",
    agent_status: "done",
    agent: "opencode",
  }
  assert.deepEqual(parseAgentEvent(JSON.stringify({
    event: "pane_agent_status_changed",
    data: envelopeEvent,
  })), envelopeEvent)
  assert.equal(parseAgentEvent(JSON.stringify({ event: "other", data: envelopeEvent })), null)
  assert.equal(parseAgentEvent(JSON.stringify({ ...event, agent_status: "working" })), null)
  assert.equal(parseAgentEvent("{"), null)
  assert.equal(parseAgentEvent(JSON.stringify({ ...event, pane_id: "" })), null)
})

test("revalidates status and suppresses the active tab", () => {
  assert.deepEqual(resolveNotification(event, snapshot), {
    paneId: "w1G:p1",
    title: "OpenCode finished",
    body: "configurations · 3 · review",
  })
  assert.equal(resolveNotification({ ...event, agent_status: "blocked" }, snapshot), null)
  assert.equal(resolveNotification(event, {
    result: { snapshot: { ...snapshot.result.snapshot, focused_tab_id: "w1G:t2" } },
  }), null)
})

test("selects only one Ghostty tree containing a Herdr client", () => {
  const clients = [
    { address: "0xremote", class: "com.mitchellh.ghostty", pid: 10 },
    { address: "0xlocal", class: "com.mitchellh.ghostty", pid: 20 },
  ]
  assert.equal(selectGhosttyAddress(clients, {
    "10": [{ comm: "waypipe", argv: ["waypipe", "ssh"] }],
    "20": [{ comm: "herdr", argv: ["herdr"] }],
  }), "0xlocal")
  assert.equal(selectGhosttyAddress(clients, {
    "10": [{ comm: "herdr", argv: ["herdr", "--session", "other"] }],
    "20": [{ comm: "herdr", argv: ["herdr"] }],
  }), null)
})

test("matches only the Herdr session derived from the socket path", () => {
  const clients = [{ address: "0xlocal", class: "com.mitchellh.ghostty", pid: 20 }]
  const treeFor = argv => ({
    "20": [
      { pid: 20, comm: "ghostty", argv: ["ghostty"], identity: { pid: 20, startTime: "1" } },
      { pid: 21, comm: "herdr", argv, identity: { pid: 21, startTime: "2" } },
    ],
  })
  assert.equal(sessionFromSocketPath("/run/user/1000/herdr.sock"), "default")
  assert.equal(sessionFromSocketPath("/run/user/1000/sessions/work/herdr.sock"), "work")
  assert.equal(selectGhosttyTarget(clients, treeFor(["herdr"]), "default").session, "default")
  for (const executable of ["/home/user/.local/bin/herdr", "/usr/bin/herdr", "./herdr"]) {
    assert.equal(selectGhosttyTarget(clients, treeFor([executable]), "default").session, "default")
    assert.equal(selectGhosttyTarget(clients, treeFor([executable, "--session", "work"]), "work").session, "work")
  }
  assert.equal(selectGhosttyTarget(clients, treeFor(["/usr/bin/not-herdr"]), "default"), null)
  assert.equal(selectGhosttyTarget(clients, treeFor(["herdr", "--session", "work"]), "work").session, "work")
  assert.equal(selectGhosttyTarget(clients, treeFor(["herdr", "--session=work"]), "work").session, "work")
  assert.equal(selectGhosttyTarget(clients, treeFor(["herdr", "session", "attach", "work"]), "work").session, "work")
  assert.equal(selectGhosttyTarget(clients, treeFor(["herdr", "--session", "server"]), "server").session, "server")
  for (const argv of [
    ["herdr", "update"],
    ["herdr", "plugin", "install"],
    ["herdr", "integration", "status"],
    ["herdr", "--remote=host"],
    ["herdr", "--no-session"],
    ["herdr", "--session"],
    ["herdr", "session", "attach"],
    ["herdr", "--session", "work", "extra"],
  ]) assert.equal(selectGhosttyTarget(clients, treeFor(argv), "default"), null)
})

test("constructs an exact pane focus request", () => {
  assert.deepEqual(paneFocusRequest("w1G:p1", "notification:42"), {
    id: "notification:42",
    method: "pane.focus",
    params: { pane_id: "w1G:p1" },
  })
})

function dependencies(overrides = {}) {
  const calls = []
  return {
    calls,
    values: {
      sleep: async milliseconds => calls.push(["sleep", milliseconds]),
      snapshot: async () => snapshot,
      ghosttyAddress: async () => "0xlocal",
      notify: async notification => { calls.push(["notify", notification]); return true },
      focusPane: async paneId => calls.push(["focusPane", paneId]),
      focusWindow: async address => calls.push(["focusWindow", address]),
      ...overrides,
    },
  }
}

test("focuses the exact pane before raising Ghostty", async () => {
  const fixture = dependencies()
  assert.equal(await handleEvent(JSON.stringify(event), fixture.values), "focused")
  assert.deepEqual(fixture.calls, [
    ["sleep", 1000],
    ["notify", { paneId: "w1G:p1", title: "OpenCode finished", body: "configurations · 3 · review" }],
    ["focusPane", "w1G:p1"],
    ["focusWindow", "0xlocal"],
  ])
})

test("does not focus when the notification is dismissed", async () => {
  const fixture = dependencies({ notify: async () => false })
  assert.equal(await handleEvent(JSON.stringify(event), fixture.values), "dismissed")
  assert.equal(fixture.calls.some(([name]) => name.startsWith("focus")), false)
})

test("still focuses Herdr when Ghostty cannot be selected safely", async () => {
  const fixture = dependencies({ ghosttyAddress: async () => null })
  assert.equal(await handleEvent(JSON.stringify(event), fixture.values), "focused")
  assert.deepEqual(fixture.calls.at(-1), ["focusPane", "w1G:p1"])
})

test("does not raise Ghostty after pane focus fails", async () => {
  const fixture = dependencies({
    focusPane: async () => { throw new Error("pane disappeared") },
  })
  await assert.rejects(handleEvent(JSON.stringify(event), fixture.values), /pane disappeared/)
  assert.equal(fixture.calls.some(([name]) => name === "focusWindow"), false)
})

test("keeps pane focus when initial Ghostty lookup rejects", async () => {
  const diagnostics = []
  const fixture = dependencies({
    ghosttyAddress: async () => { throw new Error("hyprctl unavailable") },
    diagnose: async message => diagnostics.push(message),
  })
  assert.equal(await handleEvent(JSON.stringify(event), { ...fixture.values, sleep: async () => {} }), "focused")
  assert.deepEqual(fixture.calls, [
    ["notify", { paneId: "w1G:p1", title: "OpenCode finished", body: "configurations · 3 · review" }],
    ["focusPane", "w1G:p1"],
  ])
  assert.deepEqual(diagnostics, ["ghostty lookup failed"])
})

test("keeps pane focus when post-click lookup rejects", async () => {
  const diagnostics = []
  let lookups = 0
  const fixture = dependencies({
    ghosttyAddress: async () => {
      lookups += 1
      if (lookups === 2) throw new Error("hyprctl timeout")
      return "0xlocal"
    },
    diagnose: async message => diagnostics.push(message),
  })
  assert.equal(await handleEvent(JSON.stringify(event), { ...fixture.values, sleep: async () => {} }), "focused")
  assert.deepEqual(fixture.calls.slice(-1), [["focusPane", "w1G:p1"]])
  assert.deepEqual(diagnostics, ["ghostty lookup failed"])
})

test("revalidates Ghostty after pane focus and skips a stale address", async () => {
  const calls = []
  const addresses = ["0xlocal", "0xnew"]
  const fixture = dependencies({
    ghosttyAddress: async () => {
      calls.push(["ghosttyAddress"])
      return addresses.shift()
    },
    notify: async notification => {
      calls.push(["notify", notification])
      return true
    },
    focusPane: async paneId => calls.push(["focusPane", paneId]),
    focusWindow: async address => calls.push(["focusWindow", address]),
  })

  assert.equal(await handleEvent(JSON.stringify(event), { ...fixture.values, sleep: async () => {} }), "focused")
  assert.deepEqual(calls.map(([name, value]) => [name, value]), [
    ["ghosttyAddress", undefined],
    ["notify", { paneId: "w1G:p1", title: "OpenCode finished", body: "configurations · 3 · review" }],
    ["focusPane", "w1G:p1"],
    ["ghosttyAddress", undefined],
  ])
})

test("rejects a process tree when a child has a different parent", async () => {
  const stat = (pid, ppid, startTime) => `${pid} (process) S ${ppid} ${Array(17).fill("0").join(" ")} ${startTime}`
  const files = new Map([
    ["/proc/10/stat", stat(10, 1, 100)],
    ["/proc/10/task/10/children", "11\n"],
    ["/proc/10/comm", "ghostty\n"],
    ["/proc/10/cmdline", Buffer.from("ghostty\0")],
    ["/proc/11/stat", stat(11, 99, 200)],
  ])

  await assert.doesNotReject(async () => {
    assert.equal(await processTree(10, async path => {
      if (!files.has(path)) throw new Error(`missing ${path}`)
      return files.get(path)
    }), null)
  })
})

test("rejects a process tree when a process start identity changes", async () => {
  const stat = (pid, ppid, startTime) => `${pid} (process) S ${ppid} ${Array(17).fill("0").join(" ")} ${startTime}`
  let statReads = 0
  const files = new Map([
    ["/proc/10/task/10/children", ""],
    ["/proc/10/comm", "ghostty\n"],
    ["/proc/10/cmdline", Buffer.from("ghostty\0")],
  ])

  assert.equal(await processTree(10, async path => {
    if (path === "/proc/10/stat") return stat(10, 1, statReads++ === 0 ? 100 : 101)
    if (!files.has(path)) throw new Error(`missing ${path}`)
    return files.get(path)
  }), null)
})

test("skips outer focus when the same address has a replacement identity", async () => {
  const calls = []
  const targets = [
    { address: "0xlocal", ghosttyPid: 20, ghosttyStartTime: "10", herdrPid: 21, herdrStartTime: "11", session: "default" },
    { address: "0xlocal", ghosttyPid: 20, ghosttyStartTime: "12", herdrPid: 22, herdrStartTime: "13", session: "default" },
  ]
  const fixture = dependencies({
    ghosttyTarget: async () => targets.shift(),
    diagnose: async message => calls.push(["diagnose", message]),
    notify: async notification => { calls.push(["notify", notification]); return true },
    focusPane: async paneId => calls.push(["focusPane", paneId]),
    focusWindow: async address => calls.push(["focusWindow", address]),
  })
  assert.equal(await handleEvent(JSON.stringify(event), { ...fixture.values, sleep: async () => {} }), "focused")
  assert.equal(calls.some(([name]) => name === "focusWindow"), false)
  assert.deepEqual(calls.filter(([name]) => name === "diagnose"), [["diagnose", "ghostty target changed"]])
})

test("diagnoses malformed events but stays quiet for valid irrelevant statuses", async () => {
  const diagnostics = []
  const dependencies = {
    diagnose: async message => diagnostics.push(message),
    sleep: async () => { throw new Error("irrelevant event should not sleep") },
  }
  assert.equal(await handleEvent(JSON.stringify({ event: "pane_agent_status_changed", data: { type: "pane_agent_status_changed" } }), dependencies), "ignored")
  assert.equal(await handleEvent(JSON.stringify({ event: "pane_agent_status_changed", data: {
    type: "pane_agent_status_changed", pane_id: "w1:p1", workspace_id: "w1", agent_status: "working",
  } }), dependencies), "ignored")
  assert.deepEqual(diagnostics, ["malformed Herdr event"])
})

test("diagnoses malformed matching envelopes with invalid data", async () => {
  const diagnostics = []
  const dependencies = { diagnose: async message => diagnostics.push(message) }
  for (const data of [undefined, null, "event", { type: "other" }, {}]) {
    assert.equal(await handleEvent(JSON.stringify({ event: "pane_agent_status_changed", data }), dependencies), "ignored")
  }
  assert.deepEqual(diagnostics, [
    "malformed Herdr event",
    "malformed Herdr event",
    "malformed Herdr event",
    "malformed Herdr event",
    "malformed Herdr event",
  ])
})
