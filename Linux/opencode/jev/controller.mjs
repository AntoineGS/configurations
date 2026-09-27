import { loadConfig } from "./config.mjs";
import { createJevClient } from "./client.mjs";
import { createUsage } from "./usage.mjs";
import { createSessions } from "./sessions.mjs";
import { hash, notify, readSessionView, resolveOpenRouter, unwrap, textResult } from "./runtime.mjs";
import { classifyTask, workflowMode } from "./tasks.mjs";
import { applyRoute, canRoute, selectRoute } from "./routes.mjs";
import { readRouting } from "./routing.mjs";
import { suggestSkills, renderSkillHint, skillCatalogHash } from "./skills.mjs";
import { createArchive } from "./archive.mjs";
import { filterContext } from "./context.mjs";
import { collectReviewScope, selectReview, renderReviewAssignment } from "./reviews.mjs";

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
  const archive = createArchive({retentionMs:config.archiveRetentionDays*86400000});
  const toolTasks = new Map();
  void archive.prune().catch(()=>{});
  const pruneTimer = setInterval(()=>void archive.prune().catch(()=>{}),86400000);
  pruneTimer.unref?.();
  const guard = fn => async (...args) => {
    try { return await fn(...args); } catch { console.error("jev: operation-fallback"); }
  };
  const runReview = async (sessionID,input,signal) => {
    const state=await sessions.get(sessionID);
    if(!state.enabled || !config.features.review)return {status:"fallback",reason:"review-disabled"};
    const policy={...input.policy,mode:state.workflow==="none"?"none":state.workflow==="full"?"full":input.policy.mode};
    const task=state.task ?? await sessions.beginTask(sessionID,`review-${Date.now()}`);
    const requestTask=signal?{...task,signal:AbortSignal.any([task.signal,signal])}:task;
    const scope=await collectReviewScope({ctx,sessionID,scope:input.scope});
    const agents=unwrap(await ctx.agent.list({location:{directory:scope.directory}}));
    const result=await selectReview({client,task:requestTask,scope,requirements:input.requirements,policy,agents,config});
    const fresh=await collectReviewScope({ctx,sessionID,scope:input.scope});
    await sessions.get(sessionID);
    if(!sessions.current(task) || requestTask.signal.aborted || fresh.hash!==scope.hash) return {...result,status:"fallback",reason:"stale-review-scope",selection:undefined};
    await usage.record({sessionID,taskID:task.taskID,kind:"review-selected",status:result.status,reason:result.reason,
      selectedIDs:result.selection?.selectedAgents,signals:result.signals});
    return result;
  };
  registrations.push(await ctx.tool.transform(editor=>{
    editor.add({name:"context_read",description:"Recover complete text omitted by Jev. Uses current session only; offsets are UTF-16 characters.",
      options:{namespace:"jev",codemode:true},input:{type:"object",properties:{id:{type:"string"},offset:{type:"integer",minimum:0},limit:{type:"integer",minimum:1,maximum:16000}},required:["id"],additionalProperties:false},
      execute:async (input,toolContext)=>{
        try {return textResult(JSON.stringify(await archive.read({...input,sessionID:toolContext.sessionID})));}
        catch {return textResult("Recovery unavailable: invalid reference, expired record, or invalid offset/limit. The original command was not rerun.");}
      }});
    editor.add({name:"review_select",description:"Select review dimensions from the current diff. Supply repository/user policy explicitly; selection is not a correctness verdict.",
      options:{namespace:"jev",codemode:true},input:{type:"object",properties:{requirements:{type:"string"},
        scope:{type:"object",properties:{mode:{enum:["working","branch","committed"]},base:{type:"string"},files:{type:"array",items:{type:"string"}}},required:["mode"],additionalProperties:false},
        policy:{type:"object",properties:{mode:{enum:["adaptive","full","none"]},delegationAllowed:{type:"boolean"},baselineRequired:{type:"boolean"},requiredAgents:{type:"array",items:{type:"string"}}},required:["mode","delegationAllowed","baselineRequired","requiredAgents"],additionalProperties:false}},
        required:["requirements","scope","policy"],additionalProperties:false},
      execute:async(input,toolContext)=>{
        try{return textResult(renderReviewAssignment(await runReview(toolContext.sessionID,input,toolContext.signal)));}
        catch{return textResult("Jev review selection failed. Use the ordinary review policy, preserving mandatory reviews and delegation restrictions; this is not an all-clear.");}
      }});
  }));
  registrations.push(await ctx.tool.hook("execute.before",guard(async event=>{
    if (!config.features.context || !["grep","webfetch","shell"].includes(event.tool)) return;
    const state = await sessions.get(event.sessionID);
    if (state.task && sessions.current(state.task)) toolTasks.set(`${event.sessionID}/${event.id}`,state.task);
    while (toolTasks.size>512) toolTasks.delete(toolTasks.keys().next().value);
  })));
  registrations.push(await ctx.tool.hook("execute.after",guard(async event=>{
    const key=`${event.sessionID}/${event.id}`;const task=toolTasks.get(key);toolTasks.delete(key);
    if (!task || event.status!=="completed" || !sessions.current(task)) return;
    const result=await filterContext({client,archive,sessions,task,event,config});
    await sessions.get(event.sessionID); // Revalidate a moved session after asynchronous I/O.
    if (sessions.current(task)) {
      event.result=result;
      if(result.metadata?.jev) await usage.record({sessionID:event.sessionID,taskID:task.taskID,kind:"context-selected",
        originalChars:result.metadata.jev.originalChars,selectedChars:result.metadata.jev.selectedChars});
    }
  })));
  registrations.push(await ctx.session.hook("prompt",guard(async event => {
    if (!Object.values(config.features).some(Boolean)) return;
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
      if(classified.kind === "new")state.specialist=undefined;
      state.context = classified.context;
      const mode = workflowMode(event.prompt.text);
      state.workflow = mode === "adaptive" && classified.kind !== "new" ? (state.workflow ?? mode) : mode;
      if (config.features.routing && !event.metadata?.jevReview && !busy && classified.kind === "new" && state.workflow === "adaptive"
        && canRoute({view,ownership:state.route})) {
        const routing = await readRouting(ctx,view.directory);
        const route = await selectRoute({client,task,view,context:state.context,routing,config,deadlineAt});
        if (route.status === "selected" && sessions.current(task)) {
          const result = await applyRoute({ctx,sessions,task,view,route});
          if(sessions.current(task))state.specialist=route.specialist;
          await usage.record({sessionID:event.sessionID,taskID:task.taskID,kind:"route-applied",status:result.status,
            reason:result.reason,signals:{confidence:route.confidence},selectedIDs:[route.agent,`${route.model.providerID}/${route.model.id}`]});
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
        if (sessions.current(task)) {
          state.hint = {...suggestion,taskID:task.taskID,explicitHash};
          if(!reuse)await usage.record({sessionID:event.sessionID,taskID:task.taskID,kind:"skill-suggested",status:suggestion.status,
            reason:suggestion.reason,selectedIDs:suggestion.suggestedIDs,signals:suggestion.signals});
        }
      }
    });
  })));
  registrations.push(await ctx.session.hook("context",guard(async event => {
    const state = await sessions.get(event.sessionID);
    state.awaitingAdmission = false;
    if (!state.enabled || !state.task || !sessions.current(state.task)) return;
    if(state.specialist && state.workflow==="adaptive") event.system.push({type:"text",text:
      `Jev advisory specialist fit: ${state.specialist}. Consider this through ordinary delegation only if the user and repository already permit it. This is not an instruction to spawn an agent.`});
    if(config.features.review && state.workflow!=="none" && state.workflow!=="full") event.system.push({type:"text",text:
      "When your ordinary workflow requires review, use jev_review_select at that review boundary with the actual scope, requirements, and repository/user policy. Keep mandatory correctness reviews. This adds no review phase where review is excluded, authorizes no delegation, and never narrows an explicitly requested full review. On fallback, use your ordinary review workflow."});
    if (state.hint) {
      const catalog = unwrap(await ctx.skill.list({location:{directory:state.directory}}));
      if (state.hint.catalogHash !== skillCatalogHash(catalog)) state.hint = undefined;
      const text = renderSkillHint(state.hint);
      if (text && sessions.current(state.task)) event.system.push({type:"text",text});
    }
  })));
  const onEvent=guard(async event=>{
      const sessionID = event.data?.sessionID;
      if (!sessionID || (event.location?.directory !== ctx.location.directory && !sessions.has(sessionID))) return;
      if (["session.model.selected","session.agent.selected"].includes(event.type)) {
        const state = await sessions.get(sessionID);
        const view = await readSessionView(ctx,sessionID);
        if (!state.applying && !canRoute({view:{...view,busy:false},ownership:state.route})) await sessions.pin(sessionID);
      } else if (["session.moved","session.execution.interrupted","session.inbox.cancelled"].includes(event.type)) {
        sessions.invalidate(sessionID);
        if(sessions.has(sessionID))(await sessions.get(sessionID)).awaitingAdmission=false;
      } else if (["session.execution.succeeded","session.execution.failed"].includes(event.type) && sessions.has(sessionID)) {
        (await sessions.get(sessionID)).awaitingAdmission=false;
      }
  });
  void (async () => {
    for await (const event of ctx.event.subscribe({signal:abort.signal})) await onEvent(event);
  })().catch(()=>{});
  registrations.push(await ctx.command.transform(editor=>editor.add({name:"review-adaptive",description:"Select relevant reviews for the current working diff",execute:guard(async({sessionID,prompt,delivery})=>{
    const view=await readSessionView(ctx,sessionID);
    if(view.busy){await notify(ctx,sessionID,"Run /review-adaptive at an idle review boundary.");return;}
    const requirements=prompt?.text?.trim() || "Review the current working-tree changes.";
    const state=await sessions.get(sessionID);
    if(state.enabled){await sessions.beginTask(sessionID,`review-${Date.now()}`);state.workflow="adaptive";}
    // Repository policy is semantic: the coordinator confirms delegation before
    // launching anyone. Direct command preselection conservatively forbids it.
    const input={requirements,scope:{mode:"working"},policy:{mode:"adaptive",delegationAllowed:false,baselineRequired:true,requiredAgents:[]}};
    let result;
    try{result=await runReview(sessionID,input,abort.signal);}catch{result={status:"fallback",reason:"scope-unavailable"};}
    await ctx.session.prompt({...prompt,sessionID,delivery,metadata:{jevReview:true},
      text:`${requirements}\n\n${renderReviewAssignment(result)}\nConfirm applicable repository/user policy. If delegation is allowed and needed, call jev_review_select with that confirmed policy before assigning specialists.`});
  })})));
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
    abort.abort(); clearInterval(pruneTimer); toolTasks.clear(); sessions.close(); client.close();
    await Promise.all(registrations.map(registration=>registration.dispose()));
  };
}
