import { createHash } from "node:crypto";

// Verified on V2.0.14: prompt-time switches precede context, selection messages
// are model-switched/agent-switched, collections may be wrapped in {data}.
// Same-model switchModel is silent: /jev pin is the explicit ownership override.
// The plugin's session API lacks active(); infer busy conservatively from history.
export const unwrap = value => value && typeof value === "object" && "data" in value ? value.data : value;
export const hash = value => createHash("sha256").update(JSON.stringify(value, (_key,item) =>
  item && typeof item === "object" && !Array.isArray(item)
    ? Object.fromEntries(Object.keys(item).sort().map(key=>[key,item[key]])) : item) ?? "undefined").digest("hex");

export async function resolveOpenRouter(ctx) {
  const connection = await ctx.integration.connection.active("openrouter");
  if (!connection) return undefined;
  const value = await ctx.integration.connection.resolve(connection);
  if (value?.type !== "key" || typeof value.key !== "string" || !value.key.trim()) return undefined;
  return { identity: hash([connection, value.key]), apiKey: value.key };
}

export async function readSessionView(ctx, sessionID) {
  const [raw, context] = await Promise.all([
    ctx.session.get({ sessionID }), ctx.session.context({ sessionID }),
  ]);
  const info = unwrap(raw);
  const messages = unwrap(context);
  if (!info?.location?.directory || !Array.isArray(messages)) throw new Error("runtime-shape");
  const last = messages.findLast(message => ["user", "assistant", "idle"].includes(message.type));
  return { sessionID, parentID: info.parentID, directory: info.location.directory,
    agent: info.agent, model: info.model, messages,
    selectionEvents: messages.filter(message => ["model-switched", "agent-switched"].includes(message.type)),
    busy: !!last && last.type !== "idle" };
}

export async function readCatalogs(ctx, directory) {
  const location = { directory };
  const values = await Promise.all([ctx.agent.list({ location }), ctx.model.list({ location }), ctx.skill.list({ location })]);
  const [agents, models, skills] = values.map(unwrap);
  if (![agents, models, skills].every(Array.isArray)) throw new Error("catalog-shape");
  return { agents, models, skills };
}

export const textResult = (text, metadata = {}) => ({ content: [{ type: "text", text }], metadata });
export const notify = (ctx, sessionID, text) => ctx.session.synthetic({ sessionID, text, resume: false });
