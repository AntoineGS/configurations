const empty = () => ({ requests: 0, costUSD: 0, estimatedCostUSD: 0, unknownCostRequests: 0, cacheHits: 0, fallbacks: 0, history: [] });

export function createUsage({ storage, now = Date.now }) {
  let tail = Promise.resolve();
  return {
    record(record) {
      const work = tail.then(async () => {
        const key = `usage/${record.sessionID}`;
        const state = await storage.get(key) ?? empty();
        if (record.transport) {
          state.requests++;
          if (record.costUSD !== undefined) state.costUSD += record.costUSD;
          else { state.unknownCostRequests++; state.estimatedCostUSD += record.estimatedCostUSD ?? 0; }
        }
        if (record.cached) state.cacheHits++;
        if (record.status === "fallback") state.fallbacks++;
        // Only locally curated scalar metadata enters this ledger.
        const allowed = ["kind","taskID","requestID","model","status","reason","cached","transport","costUSD","estimatedCostUSD","inputTokens","latencyMs","inputHash","originalChars","selectedChars","selectedIDs","signals"];
        state.history.push({ time: now(), ...Object.fromEntries(allowed.filter(k => record[k] !== undefined).map(k => [k,record[k]])) });
        state.history = state.history.slice(-100);
        await storage.set(key, state);
      });
      tail = work.catch(() => {});
      return work;
    },
    async snapshot(sessionID) { await tail; return await storage.get(`usage/${sessionID}`) ?? empty(); },
  };
}
