import { loadConfig } from "./config.mjs";
import { createJevClient } from "./client.mjs";
import { createUsage } from "./usage.mjs";
import { createSessions } from "./sessions.mjs";
import { notify, readSessionView, resolveOpenRouter } from "./runtime.mjs";

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
