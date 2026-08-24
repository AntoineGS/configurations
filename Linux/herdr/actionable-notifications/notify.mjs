import { execFile } from "node:child_process"
import { readFile } from "node:fs/promises"
import net from "node:net"
import { promisify } from "node:util"
import { pathToFileURL } from "node:url"

import {
  paneFocusRequest,
  inspectAgentEvent,
  resolveNotification,
  selectGhosttyTarget,
  sessionFromSocketPath,
} from "./notification-policy.mjs"

const execFileAsync = promisify(execFile)
const SETTLE_DELAY_MS = 1000

/**
 * Orchestrates policy validation, notification display, and focus actions.
 * @param {string} raw Serialized Herdr plugin event.
 * @param {object} dependencies Injectable side-effect adapters.
 * @returns {Promise<"ignored" | "suppressed" | "dismissed" | "focused">}
 */
export async function handleEvent(raw, dependencies) {
  const parsed = inspectAgentEvent(raw)
  if (parsed.malformed) {
    await diagnose(dependencies, "malformed Herdr event")
    return "ignored"
  }
  const event = parsed.event
  if (!event) return "ignored"

  await dependencies.sleep(SETTLE_DELAY_MS)
  const notification = resolveNotification(event, await dependencies.snapshot())
  if (!notification) return "suppressed"

  const lookup = dependencies.ghosttyTarget || dependencies.ghosttyAddress
  let target = null
  try {
    target = await lookup()
  } catch {
    await diagnose(dependencies, "ghostty lookup failed")
  }
  if (!await dependencies.notify(notification)) return "dismissed"

  await dependencies.focusPane(notification.paneId)
  if (target) {
    let current
    try {
      current = await lookup()
    } catch {
      await diagnose(dependencies, "ghostty lookup failed")
      return "focused"
    }
    if (!sameTarget(target, current)) {
      await diagnose(dependencies, "ghostty target changed")
      return "focused"
    }
    try {
      await dependencies.focusWindow(targetAddress(target))
    } catch {
      await diagnose(dependencies, "ghostty focus failed")
    }
  }
  return "focused"
}

function targetAddress(target) {
  return typeof target === "string" ? target : target?.address
}

function sameTarget(left, right) {
  if (typeof left === "string" || typeof right === "string") return left === right
  return left?.address === right?.address
    && left?.ghosttyPid === right?.ghosttyPid
    && left?.ghosttyStartTime === right?.ghosttyStartTime
    && left?.herdrPid === right?.herdrPid
    && left?.herdrStartTime === right?.herdrStartTime
    && left?.session === right?.session
}

async function diagnose(dependencies, message) {
  if (typeof dependencies.diagnose === "function") return dependencies.diagnose(message)
}

const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds))

async function commandJson(command, args) {
  const { stdout } = await execFileAsync(command, args, {
    encoding: "utf8",
    timeout: 3000,
    maxBuffer: 1024 * 1024,
  })
  return JSON.parse(stdout)
}

async function processIdentity(pid, read) {
  const raw = await read(`/proc/${pid}/stat`, "utf8")
  const stat = String(raw)
  const closingParen = stat.lastIndexOf(")")
  if (closingParen < 0) throw new Error("invalid process stat")
  const fields = stat.slice(closingParen + 2).trim().split(/\s+/)
  const ppid = Number(fields[1])
  const startTime = fields[19]
  if (!Number.isInteger(ppid) || !startTime) throw new Error("invalid process identity")
  return { pid, ppid, startTime }
}

function sameProcessIdentity(left, right) {
  return left?.pid === right?.pid
    && left?.ppid === right?.ppid
    && left?.startTime === right?.startTime
}

/**
 * Reads a process tree only when every process remains the same descendant
 * throughout traversal. A null result is a fail-closed inconsistent tree.
 * @param {number|string} rootPid Ghostty process identifier.
 * @param {Function} read Injectable `/proc` reader for testing.
 * @returns {Promise<Array|null>}
 */
export async function processTree(rootPid, read = readFile) {
  const queue = [{ pid: Number(rootPid), parent: null }]
  const seen = new Set()
  const result = []

  while (queue.length > 0) {
    const { pid, parent } = queue.shift()
    if (!Number.isInteger(pid) || pid <= 0 || seen.has(pid)) return null
    seen.add(pid)
    try {
      const identityBefore = await processIdentity(pid, read)
      if (parent) {
        const parentBefore = await processIdentity(parent.pid, read)
        if (!sameProcessIdentity(parentBefore, parent) || identityBefore.ppid !== parent.pid) return null
      }
      const [children, comm, cmdline] = await Promise.all([
        read(`/proc/${pid}/task/${pid}/children`, "utf8"),
        read(`/proc/${pid}/comm`, "utf8"),
        read(`/proc/${pid}/cmdline`),
      ])
      const identityAfter = await processIdentity(pid, read)
      if (!sameProcessIdentity(identityBefore, identityAfter)) return null
      if (parent && !sameProcessIdentity(await processIdentity(parent.pid, read), parent)) return null
      const argv = cmdline.toString("utf8").split("\0").filter(Boolean)
      result.push({ pid, comm: String(comm).trim(), argv, identity: identityBefore })
      for (const child of String(children).trim().split(/\s+/).filter(Boolean)) {
        queue.push({ pid: Number(child), parent: identityBefore })
      }
    } catch {
      return null
    }
  }
  return result
}

async function ghosttyTarget(session) {
  const clients = await commandJson("hyprctl", ["clients", "-j"])
  const processTrees = {}
  for (const client of clients) {
    if (String(client?.class || "").toLowerCase() !== "com.mitchellh.ghostty") continue
    processTrees[String(client.pid)] = await processTree(client.pid)
  }
  return selectGhosttyTarget(clients, processTrees, session)
}

async function showNotification(notification) {
  const { stdout } = await execFileAsync("notify-send", [
    "--app-name", "Herdr",
    "--expire-time", "8000",
    "--action", "default=Open",
    notification.title,
    notification.body,
  ], { encoding: "utf8", timeout: 35000, maxBuffer: 4096 })
  return stdout.trim() === "default"
}

async function socketRequest(socketPath, request) {
  return await new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath)
    let buffer = ""
    let settled = false
    const settle = (callback, value) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      callback(value)
    }
    const timer = setTimeout(() => {
      settle(reject, new Error("Herdr request timed out"))
      socket.destroy()
    }, 2000)

    socket.setEncoding("utf8")
    socket.on("connect", () => socket.write(`${JSON.stringify(request)}\n`))
    socket.on("data", chunk => {
      buffer += chunk
      const newline = buffer.indexOf("\n")
      if (newline < 0) return
      socket.end()
      try {
        const response = JSON.parse(buffer.slice(0, newline))
        if (response.error) {
          settle(reject, new Error(response.error.message || response.error.code || "Herdr request failed"))
        } else {
          settle(resolve, response)
        }
      } catch (error) {
        settle(reject, error)
      }
    })
    socket.on("error", error => settle(reject, error))
    socket.on("end", () => {
      if (!buffer.includes("\n")) settle(reject, new Error("Herdr closed without a response"))
    })
  })
}

async function main() {
  const socketPath = process.env.HERDR_SOCKET_PATH
  if (!socketPath) throw new Error("HERDR_SOCKET_PATH is unavailable")
  const session = sessionFromSocketPath(socketPath)
  if (!session) throw new Error("HERDR_SOCKET_PATH has no valid session")
  const requestId = `actionable-notification:${process.pid}:${Date.now()}`

  await handleEvent(process.env.HERDR_PLUGIN_EVENT_JSON, {
    sleep,
    snapshot: () => commandJson(process.env.HERDR_BIN_PATH || "herdr", ["api", "snapshot"]),
    ghosttyTarget: () => ghosttyTarget(session),
    diagnose: message => console.error(`actionable-notifications: ${message}`),
    notify: showNotification,
    focusPane: paneId => socketRequest(socketPath, paneFocusRequest(paneId, requestId)),
    focusWindow: address => execFileAsync("hyprctl", ["dispatch", "focuswindow", `address:${address}`], {
      encoding: "utf8",
      timeout: 3000,
    }),
  })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => {
    console.error(`actionable-notifications: ${error.message}`)
    process.exitCode = 1
  })
}
