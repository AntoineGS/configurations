import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(new URL("./opencode-tmux-agent-indicator.js", import.meta.url), "utf8")
const { TmuxAgentIndicator } = await import(`data:text/javascript,${encodeURIComponent(source)}`)

async function createHarness(sessions = {}) {
  const states = []
  const lookups = []
  const $ = (strings, ...values) => {
    const command = strings.reduce((result, part, index) => result + part + (values[index] ?? ""), "")
    states.push(command.match(/--state (\S+)/)[1])
    return Promise.resolve()
  }
  const client = {
    session: {
      get: async ({ sessionID }) => {
        lookups.push(sessionID)
        const value = sessions[sessionID]
        if (value instanceof Error) throw value
        return { data: value }
      },
    },
  }
  const hooks = await TmuxAgentIndicator({ $, client })
  return { hooks, lookups, states }
}

test("ignores child session idle while root idle marks done", async () => {
  const { hooks, states } = await createHarness({
    child: { parentID: "root" },
    root: {},
  })

  await hooks.event({ event: { type: "session.idle", properties: { sessionID: "child" } } })
  assert.deepEqual(states, [])

  await hooks.event({ event: { type: "session.idle", properties: { sessionID: "root" } } })
  assert.deepEqual(states, ["done"])
})

test("ignores child busy, permission, and question signals", async () => {
  const { hooks, states } = await createHarness({ child: { parentID: "root" } })

  await hooks.event({
    event: { type: "session.status", properties: { sessionID: "child", status: { type: "busy" } } },
  })
  await hooks.event({
    event: { type: "permission.asked", properties: { sessionID: "child" } },
  })
  await hooks["permission.ask"]({ sessionID: "child" })
  await hooks["tool.execute.before"]({ tool: "question", sessionID: "child" })

  assert.deepEqual(states, [])
})

test("preserves root busy, permission, and question signals", async () => {
  const busy = await createHarness({ root: {} })
  await busy.hooks.event({
    event: { type: "session.status", properties: { sessionID: "root", status: { type: "busy" } } },
  })
  assert.deepEqual(busy.states, ["off", "running"])

  const permission = await createHarness({ root: {} })
  await permission.hooks["permission.ask"]({ sessionID: "root" })
  assert.deepEqual(permission.states, ["needs-input"])

  const question = await createHarness({ root: {} })
  await question.hooks["tool.execute.before"]({ tool: "question", sessionID: "root" })
  assert.deepEqual(question.states, ["needs-input"])
})

test("ignores missing and failed session lookups", async () => {
  const missing = await createHarness({})
  await missing.hooks.event({ event: { type: "session.idle", properties: { sessionID: "missing" } } })
  assert.deepEqual(missing.states, [])

  const failed = await createHarness({ failed: new Error("lookup failed") })
  await failed.hooks.event({ event: { type: "session.idle", properties: { sessionID: "failed" } } })
  assert.deepEqual(failed.states, [])
})

test("caches session lineage", async () => {
  const { hooks, lookups, states } = await createHarness({ root: {} })

  await hooks.event({
    event: { type: "session.status", properties: { sessionID: "root", status: { type: "busy" } } },
  })
  await hooks.event({ event: { type: "session.idle", properties: { sessionID: "root" } } })

  assert.deepEqual(lookups, ["root"])
  assert.deepEqual(states, ["off", "running", "done"])
})

test("preserves session-less errors", async () => {
  const { hooks, lookups, states } = await createHarness()

  await hooks.event({ event: { type: "session.error", properties: {} } })

  assert.deepEqual(lookups, [])
  assert.deepEqual(states, ["done"])
})
