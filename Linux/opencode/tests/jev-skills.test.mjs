import test from "node:test";
import assert from "node:assert/strict";
import { suggestSkills, skillCatalogHash } from "../jev/skills.mjs";
import { loadConfig } from "../jev/config.mjs";
const task=()=>({sessionID:"s",epoch:1,taskID:"t",directory:"/p",signal:new AbortController().signal});
const catalog=[{id:"sql",description:"Query tuning",content:"Tune queries"},{id:"css",description:"Layout",content:"Style pages"}];
function client(fit) {return {evaluate:async r=>({status:"ok",answers:r.kind==="skill-rank"
  ? {rank:{type:"choice",choice:"sql",probabilities:Object.fromEntries(Object.keys(r.questions.rank.criteria).map((id,i)=>[id,i===0?0.9:0.1])),confidence:0.8}}
  : Object.fromEntries(Object.keys(r.questions).map(id=>[id,{type:"noul",noul:fit}]))})};}
test("ranking is independently verified and can produce none or multiple", async () => {
  const args={task:task(),context:{request:"Explain build error"},catalog,explicitIDs:[],config:loadConfig()};
  assert.deepEqual((await suggestSkills({...args,client:client(0.1)})).suggestedIDs,[]);
  assert.deepEqual((await suggestSkills({...args,client:client(0.9)})).suggestedIDs,["sql","css"]);
});
test("explicit/process skills and catalog remain untouched; hash includes instructions", async () => {
  const all=[...catalog,{id:"test-driven-development",description:"Process",content:"mandatory"}];
  const before=structuredClone(all);
  const result=await suggestSkills({client:client(0.9),task:task(),context:{request:"SQL"},catalog:all,explicitIDs:["sql"],config:loadConfig()});
  assert.deepEqual(result.suggestedIDs,["css"]); assert.deepEqual(all,before);
  all[2]={...all[2],content:"changed"};assert.notEqual(skillCatalogHash(all),skillCatalogHash(before));
});
test("large catalogs use bounded groups and one shared deadline", async () => {
  const all=Array.from({length:300},(_,i)=>({id:`s${i}`,description:`Domain ${i}`,content:"instructions"}));
  const deadlines=[]; const base=client(0.9);
  const result=await suggestSkills({client:{evaluate:async r=>{deadlines.push(r.deadlineAt);if(r.kind==="skill-rank")assert.ok(Object.keys(r.questions.rank.criteria).length<=255);return base.evaluate(r);}},
    task:task(),context:{request:"Task"},catalog:all,explicitIDs:[],config:loadConfig()});
  assert.equal(result.suggestedIDs.length,3); assert.equal(new Set(deadlines).size,1);
});
test("cancelled ranking never publishes suggestions", async () => {
  const abort=new AbortController();const t={...task(),signal:abort.signal};const base=client(0.9);
  const result=await suggestSkills({client:{evaluate:async r=>{abort.abort();return base.evaluate(r);}},task:t,context:{request:"SQL"},catalog,explicitIDs:[],config:loadConfig()});
  assert.deepEqual(result.suggestedIDs,[]); assert.equal(result.status,"fallback");
});
