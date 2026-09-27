import { hash, readSessionView } from "./runtime.mjs";
import { modelFor, readRouting } from "./routing.mjs";
import { rubricVersion, routeQuestions } from "./questions.mjs";

export function canRoute({view,ownership,selectionEvents = view.selectionEvents ?? []}) {
  if (view.busy || ownership?.mode === "pinned") return false;
  if (ownership?.mode !== "auto") return !view.model && !view.agent && !selectionEvents.length
    && !(view.messages ?? []).some(m=>m.type==="user");
  if (selectionEvents.some(e=>!ownership.eventIDs?.includes(e.id))) return false;
  return hash(view.model) === hash(ownership.model) && view.agent === ownership.agent;
}

const intents = [
  {key:"direct",agent:"build",tier:"coding",description:"Bounded implementation or straightforward debugging by one coding worker"},
  {key:"discovery",agent:"build",tier:"light",description:"Simple read-only lookup, explanation, or repository navigation"},
  {key:"coordinate",agent:"orchestrator",tier:"orchestration",description:"Multi-part implementation requiring specialist coordination"},
  {key:"reason",agent:"build",tier:"reasoning",description:"Complex causal investigation or difficult design reasoning by one worker"},
];
export async function selectRoute({client,task,view,context,routing,config,deadlineAt}) {
  const no = reason => ({status:"fallback",reason});
  if (context.files?.length || context.explicitAgents?.length || !routing.provider || context.request.length > 12000) return no("route-ineligible");
  const candidates = intents.flatMap(intent => {
    const agent = view.parentID ? view.agent : intent.agent;
    const definition = routing.agents.find(a=>a.id===agent);
    if (!definition || definition.hidden || (!view.parentID && !["primary","all"].includes(definition.mode))) return [];
    const model = modelFor(routing.manifest,routing.catalog,routing.provider,intent.tier);
    const info = model && routing.models.find(m=>m.providerID===model.providerID && m.id===model.id);
    if (!info || info.capabilities?.tools === false || !info.limit?.context || info.limit.context < context.request.length + 16000) return [];
    return [{...intent,agent,model}];
  });
  if (!candidates.length) return no("no-candidates");
  const result = await client.evaluate({task,kind:"route",state:context,questions:routeQuestions(candidates),rubricVersion,deadlineAt});
  if (result.status !== "ok") return result;
  const answer = result.answers.route;
  const chosen = candidates.find(c=>c.key===answer.choice);
  if (!chosen || answer.confidence < config.routeConfidence) return no("uncertain-route");
  return {status:"selected",agent:chosen.agent,model:chosen.model,provider:routing.provider,confidence:answer.confidence};
}

export async function applyRoute({ctx,sessions,task,route}) {
  if (!sessions.current(task)) return {status:"bypassed"};
  const state = await sessions.get(task.sessionID);
  let view = await readSessionView(ctx,task.sessionID);
  if (!sessions.current(task) || view.directory !== task.directory || !canRoute({view,ownership:state.route})
    || (view.parentID && route.agent !== view.agent)) return {status:"bypassed"};
  const routing = await readRouting(ctx,view.directory);
  if (routing.provider !== route.provider || !routing.catalog.has(`${route.model.providerID}/${route.model.id}`)) return {status:"bypassed"};
  let ownership = {...state.route,mode:"auto",agent:view.agent,model:view.model,eventIDs:view.selectionEvents.map(e=>e.id)};
  state.applying = true;
  try {
    for (const [field,method] of [["agent","switchAgent"],["model","switchModel"]]) {
      view = await readSessionView(ctx,task.sessionID);
      if (!sessions.current(task) || view.directory !== task.directory || !canRoute({view,ownership})) throw new Error("stale-route");
      if (hash(view[field]) === hash(route[field])) continue;
      await ctx.session[method]({sessionID:task.sessionID,[field]:route[field]});
      const after = await readSessionView(ctx,task.sessionID);
      const added = after.selectionEvents.filter(e=>!ownership.eventIDs.includes(e.id));
      if (added.length !== 1 || added[0].type !== `${field}-switched` || hash(added[0][field]) !== hash(route[field])) throw new Error("external-selection");
      ownership = {...ownership,[field]:route[field],eventIDs:after.selectionEvents.map(e=>e.id)};
      if (!sessions.current(task)) throw new Error("stale-route");
      await sessions.saveRoute(task.sessionID,ownership);
    }
    await sessions.saveRoute(task.sessionID,{...ownership,taskID:task.taskID});
    return {status:"applied"};
  } catch {
    // Never roll back over a concurrent user choice. Partial state becomes pinned.
    await sessions.pin(task.sessionID);
    return {status:"fallback",reason:"partial-or-stale-route"};
  } finally {state.applying = false;}
}
