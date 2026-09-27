const aborted = () => new DOMException("Decision cancelled", "AbortError");

// Each subscriber owns its deadline. Transport is cancelled only when nobody
// remains; settled entries contain answers only, keyed by a hash of all inputs.
export function createRequestCache({ maxEntries, ttlMs, now = Date.now }) {
  const cached = new Map();
  const pending = new Map();
  function subscribe(key, run, { signal, deadlineAt = Infinity } = {}) {
    if (signal?.aborted || deadlineAt <= now()) return Promise.reject(aborted());
    const hit = cached.get(key);
    if (hit && hit.expires > now()) {
      cached.delete(key); cached.set(key, hit);
      return Promise.resolve(structuredClone(hit.value));
    }
    cached.delete(key);
    let entry = pending.get(key);
    if (!entry) {
      entry = { abort: new AbortController(), subscribers: new Set() };
      pending.set(key, entry);
      Promise.resolve().then(() => run(entry.abort.signal)).then(value => finish(null, value), error => finish(error));
      function finish(error, value) {
        if (pending.get(key) === entry) pending.delete(key);
        if (!error && !entry.abort.signal.aborted && value?.status !== "fallback") {
          cached.set(key, { value: structuredClone(value), expires: now() + ttlMs });
          while (cached.size > maxEntries) cached.delete(cached.keys().next().value);
        }
        for (const sub of [...entry.subscribers]) sub.finish(error, value);
      }
    }
    return new Promise((resolve,reject) => {
      let timer;
      const sub = { finish(error, value) {
        clearTimeout(timer); signal?.removeEventListener("abort", cancel); entry.subscribers.delete(sub);
        if (error) reject(error); else resolve(structuredClone(value));
      } };
      const cancel = () => {
        sub.finish(aborted());
        if (!entry.subscribers.size) {
          if (pending.get(key) === entry) pending.delete(key);
          entry.abort.abort();
        }
      };
      entry.subscribers.add(sub);
      signal?.addEventListener("abort", cancel, { once: true });
      if (Number.isFinite(deadlineAt)) timer = setTimeout(cancel, Math.max(0, deadlineAt-now()));
    });
  }
  return { subscribe, clear() {
    cached.clear();
    for (const entry of pending.values()) {
      entry.abort.abort();
      for (const sub of [...entry.subscribers]) sub.finish(aborted());
    }
    pending.clear();
  } };
}
