import { rubricVersion, taskQuestions } from "./questions.mjs";

// V2.0.14 command admission exposes expanded text, not command identity.
export function workflowMode(text = "") {
  if (text.startsWith("Treat this as a one-shot task. I explicitly request")) return "none";
  if (/^(You are a subagent spawned by another session\.\n)?# Comprehensive Code Review Orchestrator/.test(text)) return "full";
  return "adaptive";
}
export async function classifyTask({client,task,view,prompt,previous,deadlineAt}) {
  const request = prompt.text ?? "";
  const tail = [];
  let length = 0;
  for (const message of [...view.messages].reverse()) {
    if (message.type !== "user" || typeof message.text !== "string") continue;
    if (length + message.text.length > 8000) break;
    length += message.text.length; tail.unshift(message.text);
  }
  const context = {request,initialRequest:request,followups:[],omittedFollowups:0,
    files:prompt.files ?? [],explicitAgents:prompt.agents ?? [],explicitSkills:prompt.skills ?? [],tail};
  if (!previous) return {kind:view.messages.some(m=>m.type==="user")?"unknown":"new",context};
  let kind = "continue";
  if (!view.busy && !/^(continue|yes|ok(?:ay)?|go ahead|keep going)[.!\s]*$/i.test(request)) {
    const result = await client.evaluate({task,kind:"task",state:{currentRequest:request,previousRequest:previous.request},
      questions:taskQuestions(),rubricVersion,deadlineAt});
    if (result.status === "ok" && result.answers.independent.noul >= 0.8) kind = "new";
  }
  if (kind === "continue") {
    context.initialRequest=previous.initialRequest ?? previous.request;
    context.followups=[...(previous.followups ?? []),request];
    context.omittedFollowups=previous.omittedFollowups ?? 0;
    // Keep complete messages and always keep the current request intact. Never
    // append an already-rendered previous window into the new window.
    let size=context.followups.reduce((n,message)=>n+message.length+2,0);
    while(context.followups.length>1 && size>8000) {
      size-=context.followups.shift().length+2;context.omittedFollowups++;
    }
    context.request=`${context.initialRequest}\n\nRecent follow-ups (${context.omittedFollowups} earlier omitted):\n${context.followups.join("\n\n")}`;
  } else context.tail=[];
  return {kind,context};
}
