import { randomUUID } from "node:crypto";
import { hash, resolveOpenRouter } from "./runtime.mjs";
import { createRequestCache } from "./request-cache.mjs";

const ENDPOINT = "https://openrouter.ai/api/v1/systemone";
const probability = value => Number.isFinite(value) && value >= 0 && value <= 1;
const keysEqual = (object, keys) => object && typeof object === "object" && !Array.isArray(object)
  && Object.keys(object).length === keys.length && keys.every(k => Object.hasOwn(object,k));
const fallback = reason => ({ status: "fallback", reason });

export function validateAnswers(answers, questions) {
  if (!keysEqual(answers,Object.keys(questions))) return false;
  return Object.entries(questions).every(([id,q]) => {
    const a = answers[id];
    if (!a || a.type !== q.type) return false;
    if (q.type === "noul") return probability(a.noul);
    const keys = q.type === "score" ? q.criteria.map((_,i) => String(i)) : Object.keys(q.criteria);
    if (!probability(a.confidence) || !keysEqual(a.probabilities,keys)) return false;
    const values = Object.values(a.probabilities);
    if (!values.every(probability) || Math.abs(values.reduce((a,b) => a+b,0)-1) > 0.02) return false;
    if (q.type === "choice") return keys.includes(a.choice);
    return Number.isFinite(a.score) && a.score >= 0 && a.score <= keys.length-1;
  });
}

function validQuestions(questions) {
  return questions && Object.keys(questions).length > 0 && Object.values(questions).every(q => {
    if (!q?.instructions || !["noul","choice","score"].includes(q.type)) return false;
    if (q.type === "noul") return true;
    if (q.type === "score") return Array.isArray(q.criteria) && q.criteria.length >= 2 && q.criteria.length <= 10;
    return q.criteria && !Array.isArray(q.criteria) && Object.keys(q.criteria).length >= 1 && Object.keys(q.criteria).length <= 255;
  });
}

async function readBody(response, limit) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error("invalid-response");
  let size = 0; const chunks = [];
  try {
    while (true) {
      const {done,value} = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > limit) throw new Error("response-too-large");
      chunks.push(value);
    }
    try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
    catch { throw new Error("invalid-response"); }
  } finally { await reader.cancel().catch(() => {}); }
}

// Cancellation-aware semaphore. Cancelled queue entries never become requests.
function semaphore(limit) {
  let active = 0; const queue = [];
  function drain() {
    while (active < limit && queue.length) {
      const item = queue.shift(); item.signal.removeEventListener("abort",item.cancel);
      if (item.signal.aborted) { item.reject(new Error("cancelled")); continue; }
      active++;
      item.resolve(() => { active--; drain(); });
    }
  }
  return signal => new Promise((resolve,reject) => {
    const item = { signal,resolve,reject,cancel() {
      const index = queue.indexOf(item); if (index >= 0) queue.splice(index,1);
      reject(new Error("cancelled"));
    } };
    if (signal.aborted) return reject(new Error("cancelled"));
    signal.addEventListener("abort",item.cancel,{once:true}); queue.push(item); drain();
  });
}

async function bounded(promise, signal, deadlineAt, now) {
  if (signal?.aborted || deadlineAt <= now()) throw new Error("cancelled");
  let timer; let cancel;
  try {
    return await Promise.race([promise, new Promise((_,reject) => {
      cancel = () => reject(new Error("cancelled"));
      signal?.addEventListener("abort",cancel,{once:true}); timer = setTimeout(cancel,deadlineAt-now());
    })]);
  } finally { clearTimeout(timer); signal?.removeEventListener("abort",cancel); }
}

export function createJevClient({ ctx, config, usage, fetchImpl = fetch, now = Date.now }) {
  const cache = createRequestCache({maxEntries:config.cacheEntries,ttlMs:config.cacheTtlMs,now});
  const acquire = semaphore(config.concurrency);
  let failures = 0; let cooldownUntil = 0; let closed = false;
  const record = value => usage.record(value).catch(() => {});
  return {
    status: () => ({ failures, cooldownUntil, closed }),
    close() { closed = true; cache.clear(); },
    async evaluate(request) {
      const start = now(); const deadlineAt = request.deadlineAt ?? start + config.deadlineMs;
      const base = {sessionID:request.task.sessionID,taskID:request.task.taskID,kind:request.kind};
      let result; let started = false;
      try {
        if (closed) throw new Error("closed");
        if (!request.bypassCooldown && cooldownUntil > now()) throw new Error("cooldown");
        if (!validQuestions(request.questions)) throw new Error("invalid-questions");
        const body = JSON.stringify({ model: config.model, state: request.state, questions: request.questions });
        if (Buffer.byteLength(body) > config.maxRequestBytes) throw new Error("request-too-large");
        const credential = await bounded(resolveOpenRouter(ctx),request.task.signal,deadlineAt,now);
        if (!credential) throw new Error("credentials-unavailable");
        const inputHash = hash([ENDPOINT,credential.identity,body,request.rubricVersion]);
        result = await cache.subscribe(inputHash, async signal => {
          const release = await acquire(signal);
          const requestID = randomUUID(); let counted = false; let cost = {}; let model;
          try {
            if (!request.bypassCooldown && cooldownUntil > now()) return fallback("cooldown");
            started = true; counted = true;
            const response = await fetchImpl(ENDPOINT, {method:"POST",redirect:"error",signal,
              headers:{Authorization:`Bearer ${credential.apiKey}`,"Content-Type":"application/json"},body});
            if (!response.ok) {
              await response.body?.cancel();
              throw new Error(response.status === 401 || response.status === 403 ? "authentication" : response.status === 429 ? "rate-limit" : "http");
            }
            const data = await readBody(response,config.maxResponseBytes);
            if (Number.isFinite(data.usage?.input_tokens) && data.usage.input_tokens >= 0) cost.inputTokens = data.usage.input_tokens;
            if (Number.isFinite(data.usage?.cost) && data.usage.cost >= 0) cost.costUSD = data.usage.cost;
            else if (cost.inputTokens !== undefined) cost.estimatedCostUSD = cost.inputTokens * 0.042 / 1e6;
            if (typeof data.model === "string" && data.model.startsWith("typesafe/") && data.model.length < 200) model = data.model;
            if (!model || !validateAnswers(data.answers,request.questions)) throw new Error("invalid-response");
            failures = 0; cooldownUntil = 0;
            return {status:"ok",answers:data.answers,model,requestID,usage:cost};
          } catch (error) {
            const allowed = ["authentication","rate-limit","http","invalid-response","response-too-large"];
            const reason = signal.aborted ? "cancelled" : allowed.includes(error?.message) ? error.message : "network";
            if (["authentication","rate-limit","http","network"].includes(reason)) {
              failures++; if (failures >= config.cooldownFailures) cooldownUntil = now()+config.cooldownMs;
            }
            return fallback(reason);
          } finally {
            release();
            if (counted) await record({...base,transport:true,requestID,model,...cost,inputHash,latencyMs:now()-start});
          }
        },{signal:request.task.signal,deadlineAt});
        result = {...result,cached:!started};
      } catch (error) {
        const allowed = ["closed","cooldown","invalid-questions","request-too-large","credentials-unavailable"];
        result = fallback(allowed.includes(error?.message) ? error.message : request.task.signal?.aborted ? "cancelled" : "deadline");
      }
      await record({...base,status:result.status,reason:result.reason,cached:result.cached,latencyMs:now()-start});
      return result;
    },
  };
}
