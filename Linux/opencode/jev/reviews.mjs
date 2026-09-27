import { hash, unwrap } from "./runtime.mjs";
import { rubricVersion, reviewQuestions } from "./questions.mjs";

export const reviewAgents = {
  baseline:"comprehensive-review__code-reviewer",architecture:"comprehensive-review__architect-review",
  security:"security-scanning__security-auditor",database:"database-design__sql-pro",
  performance:"performance-testing-review__performance-engineer",deployment:"deployment-strategies__deployment-engineer",
  tests:"unit-testing__test-automator",documentation:"code-documentation__docs-architect",accessibility:"ui-design__accessibility-expert",
};
export function chooseReviewers({answers={},policy,agents,complete,config}) {
  if(policy.mode==="none")return {status:"skipped",selectedAgents:[],missingRequired:[],dimensions:[]};
  const dimensions=[];let invalid=false;
  for(const dimension of Object.keys(reviewAgents).filter(k=>k!=="baseline")) {
    const value=answers[dimension]?.noul;
    if(!Number.isFinite(value)||value<0||value>1)invalid=true;
    if(policy.mode==="full" || !Number.isFinite(value) || value>=config.reviewOmitProbability)dimensions.push(dimension);
  }
  const required=[...new Set([...(policy.requiredAgents??[]),...(policy.baselineRequired?[reviewAgents.baseline]:[])])];
  const available=new Set(agents.filter(a=>!a.hidden && a.mode!=="primary").map(a=>a.id));
  const missingRequired=required.filter(id=>!available.has(id));
  const requested=[...new Set([...required,...dimensions.map(d=>reviewAgents[d])])];
  const missingRelevant=requested.filter(id=>!available.has(id));
  const incomplete=!complete || missingRelevant.length>0;
  return {status:incomplete?"fallback":policy.mode==="full"?"full":invalid?"fallback":"selected",
    selectedAgents:policy.delegationAllowed?requested.filter(id=>available.has(id)):[],missingRequired,missingRelevant,
    dimensions,delegationAllowed:policy.delegationAllowed,baselineRequired:policy.baselineRequired};
}
export async function collectReviewScope({ctx,sessionID,scope={mode:"working"}}) {
  const info=unwrap(await ctx.session.get({sessionID}));const directory=info.location.directory;
  if(!["working","branch","committed"].includes(scope.mode??"working"))throw new Error("invalid-review-scope");
  const [diffResult,statusResult]=await Promise.all([
    ctx.vcs.diff({location:{directory},mode:scope.mode??"working",...(scope.base?{base:scope.base}:{}),context:5}),
    ctx.vcs.status({location:{directory}}),
  ]);
  const all=unwrap(diffResult);const status=unwrap(statusResult);
  if(!Array.isArray(all)||!Array.isArray(status))throw new Error("invalid-vcs-result");
  const diff=scope.files?.length?all.filter(d=>scope.files.includes(d.file)):all;
  const paths=diff.map(d=>d.file);
  const expected=scope.files?.length?scope.files:scope.mode==="working"||!scope.mode?status.map(s=>s.file):paths;
  const missing=expected.filter(file=>!paths.includes(file));
  const incomplete=diff.filter(d=>{
    if(typeof d.patch!=="string"||!d.patch||/^(\[[^\n]*truncat|Binary files|GIT binary patch)/im.test(d.patch))return true;
    let hunk=false;let additions=0;let deletions=0;
    for(const line of d.patch.split("\n")) {
      if(line.startsWith("@@")){hunk=true;continue;}
      if(hunk && line.startsWith("+"))additions++;
      if(hunk && line.startsWith("-"))deletions++;
    }
    return additions!==d.additions || deletions!==d.deletions;
  }).map(d=>d.file);
  const complete=diff.length>0 && !missing.length && !incomplete.length;
  return {directory,diff,paths,missing,incomplete,complete,hash:hash({directory,scope,diff,missing,incomplete})};
}
export async function selectReview({client,task,scope,requirements,policy,agents,config}) {
  const base={scopeHash:scope.hash,coverage:{complete:scope.complete,paths:scope.paths,missing:scope.missing,incomplete:scope.incomplete},policy,launchedReviewers:null};
  if(policy.mode==="none"||policy.mode==="full") {
    const selection=chooseReviewers({policy,agents,complete:scope.complete,config});
    return {...base,status:selection.status,selection};
  }
  if(!scope.complete) return {...base,status:"fallback",reason:"incomplete-scope",selection:chooseReviewers({policy,agents,complete:false,config})};
  const result=await client.evaluate({task,kind:"review",state:{requirements,diff:scope.diff},questions:reviewQuestions(),rubricVersion});
  const selection=chooseReviewers({answers:result.status==="ok"?result.answers:{},policy,agents,complete:scope.complete,config});
  return {...base,status:result.status==="ok"?selection.status:"fallback",reason:result.reason,selection,
    signals:result.status==="ok"?Object.fromEntries(Object.entries(result.answers).map(([k,v])=>[k,v.noul])):undefined};
}
export function renderReviewAssignment(result) {
  return `Review selection (not a correctness verdict):\n${JSON.stringify(result,null,2)}\n`
    + "Recheck the current diff against scopeHash before launching reviewers. Enforce the user's and repository's mandatory review and delegation policy. "
    + "If scope changed, selection failed, or required reviewers are missing, use the ordinary review workflow and disclose coverage gaps. "
    + "Full mode preserves every requested comprehensive-review phase. No-delegation mode means perform relevant checks yourself. "
    + "Never interpret an empty list as an all-clear. Consolidate actual findings and report which reviewers actually ran.";
}
