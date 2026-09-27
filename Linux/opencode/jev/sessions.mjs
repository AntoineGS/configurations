import { randomUUID } from "node:crypto";

export function createSessions({ storage, readView, enabled = true }) {
  const states = new Map(); const loading = new Map(); const queues = new Map();
  let closed = false;
  const persist = state => storage.set(`session/${state.sessionID}`, {enabled:state.enabled,route:state.route});
  function invalidate(sessionID) {
    const state = states.get(sessionID);
    if (state) { state.abort?.abort(); state.epoch++; state.hint = undefined; state.task = undefined; }
  }
  async function get(sessionID) {
    if (closed) throw new Error("closed");
    const view = await readView(sessionID);
    if (!states.has(sessionID)) {
      if (!loading.has(sessionID)) {
        const promise = (async () => {
          const stored = await storage.get(`session/${sessionID}`);
          const inherited = stored ? undefined : view.parentID ? (await get(view.parentID)).enabled : enabled;
          const state = {sessionID,directory:view.directory,enabled:stored?.enabled ?? inherited,
            route:stored?.route ?? {mode:"unknown",eventIDs:[]},epoch:0};
          states.set(sessionID,state);
          if (!stored) await persist(state);
          // Eviction cancels transient work; durable controls reload on demand.
          while (states.size > 256) {
            const oldest = states.keys().next().value;
            invalidate(oldest); states.delete(oldest);
          }
        })();
        loading.set(sessionID,promise);
        promise.finally(() => loading.delete(sessionID)).catch(() => {});
      }
      await loading.get(sessionID);
    }
    const state = states.get(sessionID);
    if (state.directory !== view.directory) { invalidate(sessionID); state.directory = view.directory; state.context = undefined; }
    states.delete(sessionID); states.set(sessionID,state);
    return state;
  }
  return {
    get, invalidate,
    async setEnabled(sessionID,value) {
      const state = await get(sessionID); invalidate(sessionID); state.enabled = value;
      if (value) {
        const view = await readView(sessionID);
        state.route = {mode:"auto",eventIDs:view.selectionEvents.map(e=>e.id),agent:view.agent,model:view.model};
      }
      await persist(state);
    },
    async pin(sessionID) {
      const state = await get(sessionID); invalidate(sessionID);
      state.route = {...state.route,mode:"pinned"}; await persist(state);
    },
    async beginTask(sessionID,taskID,revision = randomUUID()) {
      const state = await get(sessionID);
      if (state.revision === revision && state.task && !state.task.signal.aborted) return state.task;
      invalidate(sessionID); state.revision = revision; state.abort = new AbortController();
      state.task = {sessionID,epoch:state.epoch,taskID,directory:state.directory,signal:state.abort.signal};
      return state.task;
    },
    current(task) {
      const state = states.get(task.sessionID);
      return !closed && !!state?.enabled && state.epoch === task.epoch && state.directory === task.directory && !task.signal.aborted;
    },
    async saveRoute(sessionID,route) { const state = await get(sessionID); state.route = route; await persist(state); },
    serial(sessionID,operation) {
      const next = (queues.get(sessionID) ?? Promise.resolve()).catch(()=>{}).then(operation);
      queues.set(sessionID,next);
      next.finally(()=>{if(queues.get(sessionID)===next)queues.delete(sessionID);}).catch(()=>{});
      return next;
    },
    close() { closed = true; for (const id of states.keys()) invalidate(id); states.clear(); },
  };
}
