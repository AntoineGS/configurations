// tmux-agent-indicator plugin for OpenCode.
// Install to ~/.config/opencode/plugins/ or .opencode/plugins/ (project-level).
// Tracks session state and calls agent-state.sh to update tmux pane visuals.

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

const scriptPath = () => {
  const dir = process.env.TMUX_AGENT_INDICATOR_DIR
    || `${process.env.HOME}/.tmux/plugins/tmux-agent-indicator`;
  return `${dir}/scripts/agent-state.sh`;
};

const makeStateReporter = (script) => {
  let lastState = "off";
  return async (state) => {
    if (state === lastState) return;
    lastState = state;
    try {
      if (state === "running") {
        await run("bash", [script, "--agent", "opencode", "--state", "off"]);
      }
      await run("bash", [script, "--agent", "opencode", "--state", state]);
    } catch {
      // non-fatal: tmux may not be available
    }
  };
};

// V1 entrypoint (OpenCode 1.x). Kept so the same file works on both versions.
export const TmuxAgentIndicator = async ({ client }) => {
  if (!process.env.TMUX) return {};

  const script = scriptPath();
  const setState = makeStateReporter(script);
  let idleAt = 0;
  const rootSessions = new Map();

  const isRootSession = async (sessionID) => {
    if (!sessionID) return true;
    if (rootSessions.has(sessionID)) return rootSessions.get(sessionID);

    try {
      const result = await client.session.get({ path: { id: sessionID } });
      if (!result.data) return false;
      const root = !result.data.parentID;
      rootSessions.set(sessionID, root);
      return root;
    } catch {
      return false;
    }
  };

  return {
    event: async ({ event }) => {
      const sessionEvent = event.type === "session.status"
        || event.type === "session.idle"
        || event.type === "session.error"
        || event.type === "permission.updated"
        || event.type === "permission.asked";
      if (sessionEvent && !(await isRootSession(event.properties.sessionID))) return;

      if (event.type === "session.status"
          && event.properties.status.type === "busy") {
        // Guard: don't override done/error if idle fired recently (race condition)
        if (Date.now() - idleAt < 2000) return;
        await setState("running");
      }

      if (event.type === "permission.updated"
          || event.type === "permission.asked") {
        await setState("needs-input");
      }

      if (event.type === "session.idle") {
        idleAt = Date.now();
        await setState("done");
      }

      if (event.type === "session.error") {
        idleAt = Date.now();
        await setState("done");
      }
    },
    "permission.ask": async (input) => {
      if (!(await isRootSession(input.sessionID))) return;
      await setState("needs-input");
    },
    "tool.execute.before": async (input) => {
      if (input.tool === "question" && await isRootSession(input.sessionID)) {
        await setState("needs-input");
      }
    },
  };
};

// V2 entrypoint. The shared background service owns this plugin, so
// process.env.TMUX is the service's environment, not the pane that started
// a given session.
const setup = async (ctx) => {
  if (!process.env.TMUX) return;

  const script = scriptPath();
  const setState = makeStateReporter(script);
  let idleAt = 0;
  const rootSessions = new Map();

  const isRootSession = async (sessionID) => {
    if (!sessionID) return true;
    if (rootSessions.has(sessionID)) return rootSessions.get(sessionID);

    try {
      const session = await ctx.session.get({ sessionID });
      if (!session) return false;
      const root = !session.parentID;
      rootSessions.set(sessionID, root);
      return root;
    } catch {
      return false;
    }
  };

  await ctx.permission.hook("evaluate", async (event) => {
    if (event.effect !== "ask") return;
    if (!(await isRootSession(event.sessionID))) return;
    await setState("needs-input");
  });

  await ctx.tool.hook("execute.before", async (event) => {
    if (event.tool === "question" && await isRootSession(event.sessionID)) {
      await setState("needs-input");
    }
  });

  const controller = new AbortController();

  void (async () => {
    try {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        const sessionID = event?.data?.sessionID ?? event?.data?.form?.sessionID;

        switch (event.type) {
          case "session.status": {
            if (!(await isRootSession(sessionID))) break;
            if (event.data.status?.type !== "busy") break;
            // Guard: don't override done/error if idle fired recently (race condition)
            if (Date.now() - idleAt < 2000) break;
            await setState("running");
            break;
          }
          case "permission.asked":
          case "form.created":
            if (!(await isRootSession(sessionID))) break;
            await setState("needs-input");
            break;
          case "session.idle":
          case "session.execution.failed":
          case "session.execution.interrupted":
            if (!(await isRootSession(sessionID))) break;
            idleAt = Date.now();
            await setState("done");
            break;
          default:
            break;
        }
      }
    } catch {
      // stream closed or aborted during plugin unload
    }
  })();

  return () => controller.abort();
};

export default {
  id: "tmux-agent-indicator",
  server: TmuxAgentIndicator,
  setup,
};
