import { hash } from "./runtime.mjs";
import { rubricVersion, skillRankQuestions, skillFitQuestions } from "./questions.mjs";

const processSkills = new Set(["using-superpowers","brainstorming","writing-plans","executing-plans","test-driven-development",
  "systematic-debugging","using-git-worktrees","subagent-driven-development","dispatching-parallel-agents",
  "requesting-code-review","receiving-code-review","verification-before-completion","finishing-a-development-branch"]);
export const skillCatalogHash = catalog => hash(catalog.map(s=>[s.id,s.description,s.content]));
export async function suggestSkills({client,task,context,catalog,explicitIDs=[],config,deadlineAt=Date.now()+config.deadlineMs}) {
  const catalogHash = skillCatalogHash(catalog);
  const none = reason => ({status:"fallback",reason,suggestedIDs:[],catalogHash});
  const candidates = catalog.filter(s=>!explicitIDs.includes(s.id) && !processSkills.has(s.id.replace(/^.*[:/]/,"")));
  if (!candidates.length) return {status:"ok",suggestedIDs:[],catalogHash};
  async function rank(group) {
    if (group.length === 1) return group;
    const r = await client.evaluate({task,kind:"skill-rank",state:{request:context.request},questions:skillRankQuestions(group),rubricVersion,deadlineAt});
    if (r.status !== "ok" || task.signal.aborted) return undefined;
    return [...group].sort((a,b)=>(r.answers.rank.probabilities[b.id]??0)-(r.answers.rank.probabilities[a.id]??0)).slice(0,6);
  }
  let finalists = [];
  for (let i=0;i<candidates.length;i+=255) {
    const ranked = await rank(candidates.slice(i,i+255));
    if (!ranked) return none("ranking-failed");
    finalists.push(...ranked);
  }
  if (finalists.length > 255) return none("catalog-too-large");
  if (finalists.length > 6) finalists = await rank(finalists);
  if (!finalists) return none("ranking-failed");
  const excerpts = finalists.map(s=>({id:s.id,description:s.description,excerpt:(s.content??"").slice(0,700)}));
  const fit = await client.evaluate({task,kind:"skill-fit",state:{request:context.request,candidates:excerpts},
    questions:skillFitQuestions(finalists),rubricVersion,deadlineAt});
  if (fit.status !== "ok" || task.signal.aborted) return none("fit-failed");
  return {status:"ok",catalogHash,suggestedIDs:finalists.filter(s=>fit.answers[s.id]?.noul>=config.skillFitProbability)
    .sort((a,b)=>fit.answers[b.id].noul-fit.answers[a.id].noul).slice(0,config.skillLimit).map(s=>s.id)};
}
export function renderSkillHint(result) {
  return result?.suggestedIDs?.length ? `Jev advisory domain-skill suggestions: ${result.suggestedIDs.join(", ")}. Check applicability before loading. Mandatory process skills and explicit skill choices still take precedence.` : "";
}
