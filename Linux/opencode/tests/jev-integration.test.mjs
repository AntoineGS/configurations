import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { setupJev } from "../jev/controller.mjs";
import { reviewAgents } from "../jev/reviews.mjs";

const deferred=()=>{let resolve;const promise=new Promise(r=>{resolve=r;});return{promise,resolve};};
function host(options={}) {
  const hooks=new Map(),toolHooks=new Map(),commands=new Map(),tools=new Map(),storage=new Map(),records=new Map();
  const calls=[];const notes=[];let switches=0;let sequence=0;
  const events=[];let wake=deferred();
  let patch="--- a/db.sql\n+++ b/db.sql\n@@ -1 +1 @@\n-old\n+new\n";
  const record=id=>{if(!records.has(id))records.set(id,{id,location:{directory:"/fixture"},messages:[]});return records.get(id);};
  const hook=map=>async(name,fn)=>{map.set(name,fn);return{dispose:async()=>map.delete(name)};};
  const transform=map=>async fn=>{fn({add:value=>map.set(value.options?.namespace?`${value.options.namespace}_${value.name}`:value.name,value)});return{dispose:async()=>map.clear()};};
  const models=["gpt-6-luna","gpt-6-sol"].map(id=>({id,providerID:"openai",enabled:true,variants:[{id:"high"},{id:"medium"}],limit:{context:128000},capabilities:{tools:true}}));
  const agents=[{id:"build",mode:"primary"},{id:"orchestrator",mode:"primary",model:{providerID:"openai",id:"gpt-6-sol"}},
    ...Object.values(reviewAgents).map(id=>({id,mode:"subagent",hidden:false,description:"Specialist review"}))];
  const skills=[{id:"sql",description:"SQL query optimization",content:"Review SQL plans"},{id:"css",description:"CSS layout",content:"Review styles"}];
  const ctx={options,location:{directory:"/fixture"},storage:{get:async k=>structuredClone(storage.get(k)),set:async(k,v)=>storage.set(k,structuredClone(v))},
    session:{hook:hook(hooks),get:async({sessionID})=>{const {messages,...info}=record(sessionID);return structuredClone(info);},
      context:async({sessionID})=>structuredClone(record(sessionID).messages),
      switchAgent:async({sessionID,agent})=>{switches++;const r=record(sessionID);r.agent=agent;r.messages.push({id:`m${++sequence}`,type:"agent-switched",agent});},
      switchModel:async({sessionID,model})=>{switches++;const r=record(sessionID);r.model=structuredClone(model);r.messages.push({id:`m${++sequence}`,type:"model-switched",model});},
      synthetic:async data=>notes.push(data),prompt:async data=>{calls.push({syntheticPrompt:data});}},
    agent:{list:async()=>({data:agents})},model:{list:async()=>({data:models})},skill:{list:async()=>({data:skills})},
    command:{transform:transform(commands)},tool:{transform:transform(tools),hook:hook(toolHooks)},
    integration:{connection:{active:async()=>({type:"credential",id:"fixture"}),resolve:async()=>({type:"key",key:"fixture-key"})}},
    event:{async *subscribe({signal}){signal.addEventListener("abort",()=>wake.resolve(),{once:true});while(!signal.aborted){if(!events.length)await wake.promise;while(events.length)yield events.shift();wake=deferred();}}},
    vcs:{diff:async()=>({data:[{file:"db.sql",patch,additions:1,deletions:1,status:"modified"}]}),status:async()=>({data:[{file:"db.sql"}]})},
  };
  const fetch=async(_url,options)=>{
    const body=JSON.parse(options.body);calls.push(body);
    const answers=Object.fromEntries(Object.entries(body.questions).map(([id,q])=>{
      if(q.type==="noul")return[id,{type:"noul",noul:id==="independent"?Number(body.state.currentRequest.includes("new task")):
        body.state.candidates?.[0]?.text!==undefined?Number(body.state.candidates.find(c=>c.id===id).text.includes("RELEVANT")):id==="css"?0.01:0.9}];
      const keys=Object.keys(q.criteria);const choice=keys.includes("direct")?"direct":keys.includes("sql")?"sql":keys[0];
      return[id,{type:"choice",choice,confidence:1,probabilities:Object.fromEntries(keys.map(k=>[k,k===choice?1:0]))}];
    }));
    return Response.json({model:"typesafe/jev-1.13",answers,usage:{input_tokens:100,cost:0.0000042}});
  };
  async function prompt(id,text,{finish=true,delivery="steer"}={}) {
    const messageID=`u${++sequence}`;await hooks.get("prompt")({sessionID:id,messageID,prompt:{text},delivery});
    record(id).messages.push({id:messageID,type:"user",text});
    const event={sessionID:id,system:[],model:record(id).model,agent:record(id).agent};
    await hooks.get("context")(event);
    if(finish)record(id).messages.push({id:`i${++sequence}`,type:"idle"});return event;
  }
  return{ctx,hooks,toolHooks,commands,tools,storage,calls,notes,record,fetch,prompt,switches:()=>switches,changeDiff:()=>{patch=patch.replace("+new","+newer");},
    emit:async event=>{events.push(event);wake.resolve();await new Promise(r=>setImmediate(r));},
    command:(id,text)=>commands.get("jev").execute({sessionID:id,prompt:{text}})};
}

test("route once per task; continuations and tool iterations reuse decisions; pin survives reload",async t=>{
  const h=host();t.mock.method(globalThis,"fetch",h.fetch);let cleanup=await setupJev(h.ctx);
  try {
    const first=await h.prompt("s","Fix the SQL query");assert.equal(h.record("s").model.id,"gpt-6-luna");assert.equal(h.switches(),2);
    assert.ok(first.system.some(s=>s.text.includes("sql")));
    const count=h.calls.length;
    await h.hooks.get("context")({sessionID:"s",system:[]});await h.prompt("s","continue");
    assert.equal(h.calls.length,count);assert.equal(h.switches(),2);
    await h.command("s","pin");await cleanup();cleanup=await setupJev(h.ctx);
    await h.prompt("s","new task: inspect CSS layout");assert.equal(h.switches(),2);
    assert.equal(h.storage.get("session/s").route.mode,"pinned");
    await h.command("s","off");const before=h.calls.length;await h.prompt("s","new task: fix build");assert.equal(h.calls.length,before);
    await h.prompt("other","Fix a separate SQL query");assert.equal(h.switches(),4);
  } finally {await cleanup();}
});

test("off during inference prevents late switches and persists across restart",async t=>{
  const h=host({features:{skills:false}});const entered=deferred(),release=deferred();
  t.mock.method(globalThis,"fetch",async(...args)=>{entered.resolve();await release.promise;return h.fetch(...args);});
  let cleanup=await setupJev(h.ctx);
  try {
    const pending=h.prompt("s","Fix SQL");await entered.promise;await h.command("s","off");release.resolve();await pending;
    assert.equal(h.switches(),0);await cleanup();cleanup=await setupJev(h.ctx);
    const before=h.calls.length;await h.prompt("s","Fix SQL");assert.equal(h.calls.length,before);
  } finally {release.resolve();await cleanup();}
});

test("context keeps pairing across task changes and supports complete same-session recovery",async t=>{
  const root=await mkdtemp("/tmp/opencode/jev-integration-cache-");const previous=process.env.XDG_CACHE_HOME;
  process.env.XDG_CACHE_HOME=root;
  t.after(()=>{if(previous===undefined)delete process.env.XDG_CACHE_HOME;else process.env.XDG_CACHE_HOME=previous;});
  const h=host({features:{routing:false,skills:false}});t.mock.method(globalThis,"fetch",h.fetch);const cleanup=await setupJev(h.ctx);
  try {
    await h.prompt("s","Find RELEVANT");
    const text=Array.from({length:150},(_,i)=>`${i===30?"RELEVANT":"background"} ${"x".repeat(200)}\n`).join("");
    const event={sessionID:"s",tool:"webfetch",id:"tool-one",input:{url:"https://example.com"},status:"completed",result:{content:text,metadata:{source:"fixture"}}};
    await h.toolHooks.get("execute.before")(event);await h.toolHooks.get("execute.after")(event);
    assert.ok(event.result.metadata.jev);const ref=event.result.metadata.jev.recovery.id;
    const read=h.tools.get("jev_context_read").execute;
    const first=JSON.parse((await read({id:ref,offset:0,limit:16000},{sessionID:"s"})).content[0].text);
    const second=JSON.parse((await read({id:ref,offset:16000,limit:16000},{sessionID:"s"})).content[0].text);
    assert.equal(first.text+second.text,text);
    const foreign=await read({id:ref},{sessionID:"other"});assert.ok(!foreign.content[0].text.includes("RELEVANT"));
    const old={...event,id:"old",result:{content:text}};await h.toolHooks.get("execute.before")(old);
    await h.prompt("s","new task: something else");const original=old.result;await h.toolHooks.get("execute.after")(old);assert.equal(old.result,original);
  } finally {await cleanup();await rm(root,{recursive:true,force:true});}
});

test("review selection rechecks scope and reports stale coverage rather than reviewer assignments",async t=>{
  const h=host({features:{routing:false,skills:false}});
  t.mock.method(globalThis,"fetch",async(...args)=>{const result=await h.fetch(...args);h.changeDiff();return result;});
  const cleanup=await setupJev(h.ctx);
  try {
    await h.prompt("s","Review SQL changes");
    const result=await h.tools.get("jev_review_select").execute({requirements:"Review SQL",scope:{mode:"working"},policy:{mode:"adaptive",delegationAllowed:true,baselineRequired:true,requiredAgents:[]}},
      {sessionID:"s",signal:new AbortController().signal});
    const text=result.content[0].text;const value=JSON.parse(text.slice(text.indexOf("{"),text.lastIndexOf("}")+1));
    assert.equal(value.status,"fallback");assert.equal(value.reason,"stale-review-scope");assert.equal(value.selection,undefined);
  } finally {await cleanup();}
});

test("disabled automatic features make no classification calls",async t=>{
  const h=host({features:{routing:false,skills:false,context:false,review:false}});
  t.mock.method(globalThis,"fetch",h.fetch);const cleanup=await setupJev(h.ctx);
  try {await h.prompt("s","First request");await h.prompt("s","new task: second request");assert.equal(h.calls.length,0);}
  finally{await cleanup();}
});

test("verified V2 interruption events invalidate inference before dispatch",async t=>{
  const h=host({features:{skills:false}});const entered=deferred(),release=deferred();
  t.mock.method(globalThis,"fetch",async(...args)=>{entered.resolve();await release.promise;return h.fetch(...args);});
  const cleanup=await setupJev(h.ctx);
  try {
    const pending=h.prompt("s","Fix SQL");await entered.promise;
    await h.emit({type:"session.execution.interrupted",location:{directory:"/fixture"},data:{sessionID:"s"}});
    release.resolve();await pending;assert.equal(h.switches(),0);
  } finally {release.resolve();await cleanup();}
});

test("durable interruption boundary also invalidates work when a public event is absent",async t=>{
  const h=host({features:{skills:false}});const entered=deferred(),release=deferred();
  t.mock.method(globalThis,"fetch",async(...args)=>{entered.resolve();await release.promise;return h.fetch(...args);});
  const cleanup=await setupJev(h.ctx);
  try{
    const pending=h.prompt("s","Fix SQL");await entered.promise;
    h.record("s").messages.push({id:"interruption",type:"idle",outcome:"interrupted"});
    release.resolve();await pending;assert.equal(h.switches(),0);
  }finally{release.resolve();await cleanup();}
});
