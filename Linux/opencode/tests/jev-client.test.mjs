import test from "node:test";
import assert from "node:assert/strict";
import { createJevClient, validateAnswers } from "../jev/client.mjs";
import { createRequestCache } from "../jev/request-cache.mjs";
import { createUsage } from "../jev/usage.mjs";
import { loadConfig } from "../jev/config.mjs";

const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const questions = { relevant: { type: "noul", instructions: "Is this about a build failure?" } };
const good = () => ({ model: "jev-1.13.0", answers: { relevant: { type: "noul", noul: 0.9 } }, usage: { input_tokens: 100, output_tokens: 20 } });
const request = (sessionID = "one", state = "build") => ({ task: { sessionID, taskID: "task", epoch: 1, signal: new AbortController().signal }, kind: "test", state, questions, rubricVersion: "1" });
function fixture(fetchImpl, options = {}, now = Date.now) {
  const data = new Map();
  const usage = createUsage({ storage: { get: async k => data.get(k), set: async (k,v) => { data.set(k,v); } }, now });
  let key = "one";
  const ctx = { integration: { connection: { active: async id => id === "typesafe" ? { type: "env" } : undefined, resolve: async () => ({ type: "key", key }) } } };
  return { usage, rotate: () => { key = "two"; }, client: createJevClient({ ctx, usage, config: loadConfig(options), fetchImpl, now }) };
}

test("one subscriber cancellation preserves shared transport; all cancellations abort it", async () => {
  const cache = createRequestCache({ maxEntries: 2, ttlMs: 1000, now: Date.now });
  const gate = deferred(); let calls = 0; let transport;
  const run = async signal => { calls++; transport = signal; await gate.promise; return { value: 7 }; };
  const a = new AbortController(); const b = new AbortController();
  const first = cache.subscribe("same", run, { signal: a.signal, deadlineAt: Date.now()+1000 });
  const rejected = assert.rejects(first, { name: "AbortError" });
  const second = cache.subscribe("same", run, { signal: b.signal, deadlineAt: Date.now()+1000 });
  await Promise.resolve(); a.abort(); assert.equal(transport.aborted, false); gate.resolve();
  await rejected; assert.deepEqual(await second, { value: 7 }); assert.equal(calls, 1);
  const c = new AbortController(); const wait = deferred();
  const third = cache.subscribe("other", async signal => { transport = signal; await wait.promise; }, { signal: c.signal });
  const cancelled = assert.rejects(third, { name: "AbortError" });
  await Promise.resolve(); c.abort(); await cancelled; assert.equal(transport.aborted, true); wait.resolve(); cache.clear();
});

test("cache expiry and LRU eviction do not retain failed results", async () => {
  let now = 0; let calls = 0;
  const cache = createRequestCache({ maxEntries: 1, ttlMs: 10, now: () => now });
  const run = async () => ++calls;
  assert.equal(await cache.subscribe("a", run), 1);
  assert.equal(await cache.subscribe("a", run), 1);
  await cache.subscribe("b", run); assert.equal(await cache.subscribe("a", run), 3);
  now = 11; assert.equal(await cache.subscribe("a", run), 4);
  await cache.subscribe("bad", async () => ({ status: "fallback" }));
  assert.equal(await cache.subscribe("bad", run), 5);
});

test("identical sessions share one bill, while rubric and credentials invalidate cache", async () => {
  let calls = 0; const gate = deferred();
  const f = fixture(async (url, options) => {
    calls++; assert.equal(url,"https://api.typesafe.ai/v1/systemone");
    assert.equal(JSON.parse(options.body).model,"jev-1.13.0");
    assert.equal(options.headers.Authorization,`Bearer ${calls===3?"two":"one"}`);
    assert.equal(options.redirect, "error"); await gate.promise; return Response.json(good());
  });
  const first = f.client.evaluate(request("one")); const second = f.client.evaluate(request("two")); gate.resolve();
  const results = await Promise.all([first,second]);
  assert.ok(results.every(r => r.status === "ok")); assert.equal(calls,1);
  const firstUsage=await f.usage.snapshot("one"),secondUsage=await f.usage.snapshot("two");
  assert.equal(firstUsage.costUSD+secondUsage.costUSD,0);
  assert.equal(firstUsage.unknownCostRequests+secondUsage.unknownCostRequests,1);
  assert.ok(Math.abs(firstUsage.estimatedCostUSD+secondUsage.estimatedCostUSD-0.0000042)<1e-12);
  assert.equal((await f.client.evaluate(request())).status,"ok"); assert.equal(calls,1);
  assert.equal((await f.client.evaluate({ ...request(), rubricVersion: "2" })).status,"ok"); assert.equal(calls,2);
  f.rotate(); assert.equal((await f.client.evaluate(request())).status,"ok"); assert.equal(calls,3);
});

test("bad answers fail closed but billed invalid responses still count", async () => {
  for (const answer of [undefined, { type: "choice", choice: "x" }, { type: "noul", noul: 2 }, { type: "noul", noul: null }]) {
    const f = fixture(async () => Response.json({ ...good(), answers: { relevant: answer } }));
    assert.equal((await f.client.evaluate(request())).reason, "invalid-response");
    assert.equal((await f.client.evaluate(request())).reason, "invalid-response");
    assert.equal((await f.usage.snapshot("one")).requests, 2);
    assert.ok(Math.abs((await f.usage.snapshot("one")).estimatedCostUSD-0.0000084)<1e-12);
  }
  const q = { x: { type: "choice", instructions: "Choose", criteria: { a:"A", b:"B" } } };
  for (const a of [
    { type:"choice",choice:"z",confidence:1,probabilities:{a:1,b:0} },
    { type:"choice",choice:"a",confidence:1,probabilities:{a:1} },
    { type:"choice",choice:"a",confidence:2,probabilities:{a:1,b:0} },
    { type:"choice",choice:"a",confidence:1,probabilities:{a:0.2,b:0.2} },
  ]) assert.equal(validateAnswers({ x:a },q),false);
  assert.equal(validateAnswers({ x: { type:"score",score:2,confidence:1,probabilities:{0:0,1:1} } },
    {x:{type:"score",instructions:"Rate",criteria:["low","high"]}}),false);
});

test("an OpenRouter-only connection cannot supply a direct TypeSafe request",async()=>{
  let calls=0;
  const client=createJevClient({config:loadConfig(),usage:{record:async()=>{}},fetchImpl:async()=>{calls++;return Response.json(good());},
    ctx:{integration:{connection:{active:async id=>id==="openrouter"?{type:"credential",id:"old"}:undefined,
      resolve:async()=>({type:"key",key:"old-router-key"})}}}});
  assert.equal((await client.evaluate(request())).reason,"credentials-unavailable");
  assert.equal(calls,0);
});

test("cooldown after three failures, doctor bypass and success reset", async () => {
  let calls = 0; let fail = true;
  const f = fixture(async () => { calls++; if (fail) throw Error("secret backend body"); return Response.json(good()); });
  for (let i=0;i<3;i++) assert.equal((await f.client.evaluate(request())).reason,"network");
  assert.equal((await f.client.evaluate(request())).reason,"cooldown"); assert.equal(calls,3);
  fail = false; assert.equal((await f.client.evaluate({...request(), bypassCooldown:true})).status,"ok");
  assert.equal(f.client.status().failures,0);
});

test("concurrency is bounded and expired queued requests never dispatch", async () => {
  const gates = [deferred(),deferred()]; const started = deferred(); let calls = 0;
  const f = fixture(async () => { const n = calls++; if (calls===2) started.resolve(); await gates[n].promise; return Response.json(good()); });
  const a = f.client.evaluate(request("a","a")); const b = f.client.evaluate(request("b","b"));
  await started.promise;
  const c = await f.client.evaluate({...request("c","c"),deadlineAt:Date.now()+15});
  assert.equal(c.status,"fallback"); assert.equal(calls,2);
  gates.forEach(g => g.resolve()); await Promise.all([a,b]); assert.equal(calls,2);
});

test("size bounds, missing credential, and unknown billed cost", async () => {
  let calls = 0;
  const f = fixture(async () => {calls++; return Response.json({...good(),usage:{input_tokens:100}});}, {maxRequestBytes:1000});
  assert.equal((await f.client.evaluate(request("one","x".repeat(2000)))).reason,"request-too-large");
  assert.equal(calls,0);
  await f.client.evaluate(request());
  const usage = await f.usage.snapshot("one"); assert.equal(usage.costUSD,0); assert.equal(usage.unknownCostRequests,1);
  assert.ok(Math.abs(usage.estimatedCostUSD-0.0000042) < 1e-12);
  const tiny = fixture(async () => Response.json(good()),{maxResponseBytes:10});
  assert.equal((await tiny.client.evaluate(request())).reason,"response-too-large");
  const client = createJevClient({ctx:{integration:{connection:{active:async()=>undefined}}},config:loadConfig(),usage:f.usage});
  assert.equal((await client.evaluate(request())).reason,"credentials-unavailable");
  const denied = fixture(async () => new Response("private error body",{status:403}));
  const result = await denied.client.evaluate(request());
  assert.equal(result.httpStatus,403); assert.equal(result.reason,"authentication");
  assert.equal(JSON.stringify(result).includes("private"),false);
});
