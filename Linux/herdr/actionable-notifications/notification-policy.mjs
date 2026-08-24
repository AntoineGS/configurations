import { basename } from "node:path"

const ACTIONABLE_STATUSES = new Set(["done", "blocked"])

export function parseAgentEvent(raw) {
  return inspectAgentEvent(raw).event
}

export function inspectAgentEvent(raw) {
  try {
    const parsed = JSON.parse(String(raw || ""))
    const envelope = parsed?.event !== undefined
    if (envelope && parsed.event !== "pane_agent_status_changed") {
      return { event: null, malformed: true }
    }
    const event = envelope ? parsed.data : parsed
    if (envelope && (!event || typeof event !== "object" || Array.isArray(event)
      || event.type !== "pane_agent_status_changed")) {
      return { event: null, malformed: true }
    }
    if (event?.type !== "pane_agent_status_changed") return { event: null, malformed: false }
    if (typeof event.pane_id !== "string" || event.pane_id.length === 0
      || typeof event.workspace_id !== "string" || event.workspace_id.length === 0
      || typeof event.agent_status !== "string") {
      return { event: null, malformed: true }
    }
    if (!ACTIONABLE_STATUSES.has(event.agent_status)) return { event: null, malformed: false }
    return { event, malformed: false }
  } catch {
    return { event: null, malformed: true }
  }
}

function snapshotFrom(envelope) {
  return envelope?.result?.snapshot ?? envelope?.snapshot ?? envelope
}

export function resolveNotification(event, envelope) {
  const snapshot = snapshotFrom(envelope)
  if (!snapshot || !Array.isArray(snapshot.panes)) return null

  const pane = snapshot.panes.find(candidate => candidate?.pane_id === event.pane_id)
  if (!pane || pane.agent_status !== event.agent_status) return null

  const tab = Array.isArray(snapshot.tabs)
    ? snapshot.tabs.find(candidate => candidate?.tab_id === pane.tab_id)
    : null
  if (!tab || snapshot.focused_tab_id === tab.tab_id || tab.focused === true) return null

  const workspace = Array.isArray(snapshot.workspaces)
    ? snapshot.workspaces.find(candidate => candidate?.workspace_id === pane.workspace_id)
    : null
  if (!workspace) return null

  const agent = String(event.display_agent || event.agent || pane.agent || "Agent").slice(0, 80)
  const eventText = event.agent_status === "blocked" ? "needs attention" : "finished"
  const context = [String(workspace.label || workspace.workspace_id), String(workspace.number || "")]
  if (Number(workspace.tab_count) > 1) context.push(String(tab.label || tab.number || tab.tab_id))

  return {
    paneId: event.pane_id,
    title: `${agent} ${eventText}`.slice(0, 160),
    body: context.filter(Boolean).join(" · ").slice(0, 512),
  }
}

export function sessionFromSocketPath(socketPath) {
  const path = String(socketPath || "")
  const named = path.match(/(?:^|\/)sessions\/([^/]+)\/herdr\.sock$/)
  return named ? named[1] : path.endsWith("/herdr.sock") ? "default" : null
}

function herdrSession(process) {
  const argv = process?.argv
  if (process?.comm !== "herdr" || !Array.isArray(argv) || basename(argv[0] || "") !== "herdr") return null
  if (argv.length === 1) return "default"
  if (argv.length === 2 && argv[1].startsWith("--session=")) return argv[1].slice(10) || null
  if (argv.length === 3 && argv[1] === "--session") return argv[2] || null
  if (argv.length === 4 && argv[1] === "session" && argv[2] === "attach") return argv[3] || null
  return null
}

function isHerdrClient(process) {
  return herdrSession(process) !== null
}

function isGhostty(client) {
  return String(client?.class || "").toLowerCase() === "com.mitchellh.ghostty"
}

export function selectGhosttyTarget(clients, processTrees, session) {
  const matches = (Array.isArray(clients) ? clients : []).flatMap(client => {
    if (!isGhostty(client)) return []
    const tree = processTrees?.[String(client.pid)]
    const herdr = Array.isArray(tree)
      ? tree.filter(process => herdrSession(process) === session)
      : []
    const ghostty = tree?.find(process => process.pid === Number(client.pid))
    if (herdr.length !== 1 || !ghostty?.identity || !herdr[0].identity) return []
    return [{
      address: String(client.address || "") || null,
      ghosttyPid: ghostty.pid,
      ghosttyStartTime: ghostty.identity.startTime,
      herdrPid: herdr[0].pid,
      herdrStartTime: herdr[0].identity.startTime,
      session,
    }]
  })
  return matches.length === 1 && matches[0].address ? matches[0] : null
}

export function selectGhosttyAddress(clients, processTrees) {
  const matches = (Array.isArray(clients) ? clients : []).filter(client => {
    if (!isGhostty(client)) return false
    const tree = processTrees?.[String(client.pid)]
    return Array.isArray(tree) && tree.some(isHerdrClient)
  })
  return matches.length === 1 ? String(matches[0].address || "") || null : null
}

export function paneFocusRequest(paneId, requestId) {
  return {
    id: requestId,
    method: "pane.focus",
    params: { pane_id: paneId },
  }
}
