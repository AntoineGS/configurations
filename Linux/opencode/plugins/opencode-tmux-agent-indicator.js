// tmux-agent-indicator plugin for OpenCode.
// Install to ~/.config/opencode/plugins/ or .opencode/plugins/ (project-level).
// Tracks session state and calls agent-state.sh to update tmux pane visuals.

export const TmuxAgentIndicator = async ({ $, client }) => {
  const dir = process.env.TMUX_AGENT_INDICATOR_DIR
    || `${process.env.HOME}/.tmux/plugins/tmux-agent-indicator`;
  const script = `${dir}/scripts/agent-state.sh`;

  let lastState = "off";
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

  const setState = async (state) => {
    if (state === lastState) return;
    lastState = state;
    try {
      if (state === "running") {
        await $`bash ${script} --agent opencode --state off`;
      }
      await $`bash ${script} --agent opencode --state ${state}`;
    } catch {
      // non-fatal: tmux may not be available
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
