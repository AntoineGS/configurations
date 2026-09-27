import { loadConfig } from "./config.mjs";
import { createJevClient } from "./client.mjs";
import { createUsage } from "./usage.mjs";
import { createSessions } from "./sessions.mjs";
import { hash, notify, readSessionView, resolveOpenRouter, unwrap } from "./runtime.mjs";
import { classifyTask, workflowMode } from "./tasks.mjs";
import { applyRoute, canRoute, selectRoute } from "./routes.mjs";
import { readRouting } from "./routing.mjs";
import { suggestSkills, renderSkillHint, skillCatalogHash } from "./skills.mjs";

export const doctorQuestions = {
  build: {type:"noul",instructions:"Does the state describe a compiler failure?"},
  category: {type:"choice",instructions:"Classify the state.",criteria:{build:"Compiler error",other:"Unrelated message"}},
  detail: {type:"score",instructions:"How specific is the diagnostic?",criteria:["No diagnostic detail","Names a source file and line"]},
};

export async function setupJev(ctx) {
  let config;
  try { config = loadConfig(ctx.options ?? {}); }
  catch { console.error("jev: invalid-configuration"); return; }
  const usage = createUsage({storage:ctx.storage});
  const client = createJevClient({ctx,config,usage});
  const sessions = createSessions({storage:ctx.storage,readView:id=>readSessionView(ctx,id),enabled:config.enabled});
  const registrations = []; const abort = new AbortController();
  const guard = fn => async (...args) => {
    try { return await fn(...args); } catch { console.error("jev: operation-fallback"); }
  };
  registrations.push(await ctx.session.hook("prompt",guard(async event => {
    const state = await sessions.get(event.sessionID);
    if (!state.enabled) return;
    if (state.revision === event.messageID) return;
    const oldTaskID = state.task?.taskID;
    const oldHint = state.hint;
    // Invalidate pending older decisions before joining the admission queue.
    const task = await sessions.beginTask(event.sessionID,oldTaskID ?? event.messageID,event.messageID);
    await sessions.serial(event.sessionID,async () => {
      if (!sessions.current(task)) return;
      const view = await readSessionView(ctx,event.sessionID);
      const busy = view.busy || state.awaitingAdmission;
      const deadlineAt = Date.now()+config.deadlineMs;
      const classified = await classifyTask({client,task,view:{...view,busy},prompt:event.prompt,previous:state.context,deadlineAt});
      if (!sessions.current(task)) return;
      if (classified.kind === "new" && !busy) task.taskID = event.messageID;
      state.context = classified.context;
      const mode = workflowMode(event.prompt.text);
      state.workflow = mode === "adaptive" && classified.kind !== "new" ? (state.workflow ?? mode) : mode;
      if (config.features.routing && !busy && classified.kind === "new" && state.workflow === "adaptive"
        && canRoute({view,ownership:state.route})) {
        const routing = await readRouting(ctx,view.directory);
        const route = await selectRoute({client,task,view,context:state.context,routing,config,deadlineAt});
        if (route.status === "selected" && sessions.current(task)) {
          const result = await applyRoute({ctx,sessions,task,view,route});
          await usage.record({sessionID:event.sessionID,taskID:task.taskID,kind:"route-applied",status:result.status,
            reason:result.reason,selectedIDs:[route.agent,`${route.model.providerID}/${route.model.id}`]});
        }
      }
      state.awaitingAdmission = true;
      if (config.features.skills && sessions.current(task)) {
        const catalog = unwrap(await ctx.skill.list({location:{directory:task.directory}}));
        const explicitIDs = (event.prompt.skills ?? []).map(s=>s.id ?? s.name);
        const explicitHash = hash(explicitIDs);
        const reuse = classified.kind !== "new" && /^(continue|yes|ok(?:ay)?|go ahead|keep going)[.!\s]*$/i.test(event.prompt.text)
          && oldHint?.catalogHash === skillCatalogHash(catalog) && oldHint.explicitHash === explicitHash;
        const suggestion = reuse ? oldHint : await suggestSkills({client,task,context:state.context,catalog,explicitIDs,config});
        if (sessions.current(task)) state.hint = {...suggestion,taskID:task.taskID,explicitHash};
      }
    });
  })));
  registrations.push(await ctx.session.hook("context",guard(async event => {
    const state = await sessions.get(event.sessionID);
    state.awaitingAdmission = false;
    if (!state.enabled || !state.task || !sessions.current(state.task)) return;
    if (state.hint) {
      const catalog = unwrap(await ctx.skill.list({location:{directory:state.directory}}));
      if (state.hint.catalogHash !== skillCatalogHash(catalog)) state.hint = undefined;
      const text = renderSkillHint(state.hint);
      if (text && sessions.current(state.task)) event.system.push({type:"text",text});
    }
  })));
  void (async () => {
    for await (const event of ctx.event.subscribe({signal:abort.signal})) {
      const sessionID = event.data?.sessionID;
      if (!sessionID || event.location?.directory !== ctx.location.directory) continue;
      if (["session.model.selected","session.agent.selected"].includes(event.type)) {
        const state = await sessions.get(sessionID);
        const view = await readSessionView(ctx,sessionID);
        if (!state.applying && !canRoute({view:{...view,busy:false},ownership:state.route})) await sessions.pin(sessionID);
      } else if (event.type === "session.location.switched" || event.type === "session.interrupted") {
        sessions.invalidate(sessionID);
      }
    }
  })().catch(()=>{});
  registrations.push(await ctx.command.transform(editor => editor.add({
    name:"jev",description:"Jev status, on, off, pin, or doctor",
    execute:guard(async ({sessionID,prompt}) => {
      const command = (prompt?.text ?? "").trim() || "status";
      if (command === "on" || command === "off") await sessions.setEnabled(sessionID,command === "on");
      else if (command === "pin") await sessions.pin(sessionID);
      else if (command === "doctor") {
        const view = await readSessionView(ctx,sessionID); const start = Date.now();
        const result = await client.evaluate({task:{sessionID,taskID:"doctor",directory:view.directory,signal:abort.signal},
          kind:"doctor",rubricVersion:"doctor-1",bypassCooldown:true,state:"Compiler error in example.ts:12: missing semicolon.",questions:doctorQuestions});
        await notify(ctx,sessionID,JSON.stringify({status:result.status,reason:result.reason,httpStatus:result.httpStatus,model:result.model,
          latencyMs:Date.now()-start,usage:result.usage,cached:result.cached},null,2));
        return;
      } else if (command !== "status") {
        await notify(ctx,sessionID,"Usage: /jev status | on | off | pin | doctor"); return;
      }
      const state = await sessions.get(sessionID);
      const credential = await resolveOpenRouter(ctx).catch(()=>undefined);
      await notify(ctx,sessionID,JSON.stringify({enabled:state.enabled,features:config.features,backend:"OpenRouter",model:config.model,
        credentialAvailable:!!credential,routing:state.route.mode,client:client.status(),usage:await usage.snapshot(sessionID)},null,2));
    }),
  })));
  return async () => {
    abort.abort(); sessions.close(); client.close();
    await Promise.all(registrations.map(registration=>registration.dispose()));
  };
}
