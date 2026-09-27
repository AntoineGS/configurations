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
  const context = {request,files:prompt.files ?? [],explicitAgents:prompt.agents ?? [],explicitSkills:prompt.skills ?? [],tail};
  if (!previous) return {kind:view.messages.some(m=>m.type==="user")?"unknown":"new",context};
  let kind = "continue";
  if (!view.busy && !/^(continue|yes|ok(?:ay)?|go ahead|keep going)[.!\s]*$/i.test(request)) {
    const result = await client.evaluate({task,kind:"task",state:{currentRequest:request,previousRequest:previous.request},
      questions:taskQuestions(),rubricVersion,deadlineAt});
    if (result.status === "ok" && result.answers.independent.noul >= 0.8) kind = "new";
  }
  if (kind === "continue") context.request = `${previous.request}\n\nFollow-up: ${request}`;
  return {kind,context};
}
