import test from "node:test";
import assert from "node:assert/strict";
import { canRoute, selectRoute, applyRoute } from "../jev/routes.mjs";
import { resolveCatalog, modelFor } from "../jev/routing.mjs";
import { classifyTask, workflowMode } from "../jev/tasks.mjs";
import { loadConfig } from "../jev/config.mjs";

const model={providerID:"openai",id:"gpt-6-luna",variant:"high"};
test("explicit pins, unknown provenance, busy sessions and external selections block routing", () => {
  const view={sessionID:"s",model,agent:"build",busy:false};
  const ownership={mode:"auto",eventIDs:["own-switch"],model,agent:"build"};
  assert.equal(canRoute({view,ownership,selectionEvents:[{id:"manual-switch",type:"model-switched",model}]}),false);
  assert.equal(canRoute({view,ownership:{mode:"pinned"},selectionEvents:[]}),false);
  assert.equal(canRoute({view,ownership:{mode:"unknown"},selectionEvents:[]}),false);
  assert.equal(canRoute({view:{...view,busy:true},ownership,selectionEvents:[]}),false);
  assert.equal(canRoute({view,ownership,selectionEvents:[]}),true);
  assert.equal(canRoute({view:{...view,model:{id:model.id,variant:model.variant,providerID:model.providerID}},ownership,selectionEvents:[]}),true);
  assert.equal(canRoute({view:{sessionID:"new",busy:false,messages:[]},ownership:{mode:"unknown"},selectionEvents:[]}),true);
});

const routing = () => {
  const models=[{...model,enabled:true,limit:{context:128000},capabilities:{tools:true},variants:[{id:"high"}]}];
  return {provider:"openai",models,catalog:resolveCatalog(models),agents:[{id:"build",mode:"primary"}],
    manifest:{tiers:{coding:{openai:model},light:{openai:model},reasoning:{openai:model}}}};
};
const task = {sessionID:"s",taskID:"t",epoch:1,directory:"/p",signal:new AbortController().signal};
const choose = {evaluate:async()=>({status:"ok",answers:{route:{type:"choice",choice:"direct",confidence:0.95}}})};
test("selection rejects unsupported attachments, unavailable and subagent-only candidates", async () => {
  const args={client:choose,task,view:{},context:{request:"fix typo",files:[]},routing:routing(),config:loadConfig()};
  assert.equal((await selectRoute(args)).agent,"build");
  assert.equal((await selectRoute({...args,context:{...args.context,files:[{uri:"file:///photo"}]}})).status,"fallback");
  const r=routing(); r.agents[0].mode="subagent";
  assert.equal((await selectRoute({...args,routing:r})).status,"fallback");
  r.agents[0].mode="primary";r.agents[0].hidden=true;
  assert.equal((await selectRoute({...args,routing:r})).status,"fallback");
  assert.equal(modelFor(r.manifest,r.catalog,"missing","coding"),undefined);
  r.manifest.tiers.coding.openai={...model,variant:"unsupported"};
  assert.equal(modelFor(r.manifest,r.catalog,"openai","coding").variant,undefined);
});
test("child role is preserved and manual changes during inference cannot be overwritten", async () => {
  const view={sessionID:"s",directory:"/p",parentID:"parent",agent:"specialist",messages:[],selectionEvents:[],busy:false};
  let changes=0;
  const ctx={session:{get:async()=>({...view,id:"s",location:{directory:"/p"}}),context:async()=>[],switchAgent:async()=>{changes++;}}};
  const sessions={current:()=>true,get:async()=>({route:{mode:"auto",eventIDs:[],agent:"specialist"}}),saveRoute:async()=>{}};
  assert.equal((await applyRoute({ctx,sessions,task,view,route:{agent:"build",model}})).status,"bypassed");
  assert.equal(changes,0);
  sessions.current=()=>false;
  assert.equal((await applyRoute({ctx,sessions,task,view,route:{agent:"specialist",model}})).status,"bypassed");
});
test("task continuations and explicit workflow modes bypass expensive classification", async () => {
  const client={evaluate:()=>{throw Error("unexpected inference");}};
  const previous={request:"Fix build",files:[]};
  const r=await classifyTask({client,task,view:{messages:[]},prompt:{text:"continue"},previous});
  assert.equal(r.kind,"continue"); assert.ok(r.context.request.includes("Fix build"));
  assert.equal(workflowMode("Treat this as a one-shot task. I explicitly request that you skip brainstorming,"),"none");
  assert.equal(workflowMode("You are a subagent spawned by another session.\n# Comprehensive Code Review Orchestrator"),"full");
});
