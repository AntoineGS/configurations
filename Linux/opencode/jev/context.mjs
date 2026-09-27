import { contextQuestions, rubricVersion } from "./questions.mjs";

function textPart(result) {
  if (typeof result.content === "string") return {text:result.content,replace:text=>({...result,content:text})};
  if (!Array.isArray(result.content)) return;
  const parts = result.content.filter(p=>p.type==="text");
  if (parts.length!==1 || typeof parts[0].text!=="string") return;
  return {text:parts[0].text,replace:text=>({...result,content:result.content.map(p=>p===parts[0]?{...p,text}:p)})};
}
function lines(text,start=0,end=text.length) {
  const spans=[];let at=start;
  while(at<end) {const newline=text.indexOf("\n",at);const next=newline<0?end:Math.min(newline+1,end);spans.push({start:at,end:next,text:text.slice(at,next)});at=next;}
  return spans;
}
function group(spans) {
  const groups=[];
  for (const span of spans) {
    const last=groups.at(-1);
    if(last && last.end===span.start && last.source===span.source && last.text.length+span.text.length<=1800) {
      last.end=span.end;last.text+=span.text;last.entries.push(...(span.entries??[]));
    } else groups.push({...span,entries:[...(span.entries??[])]});
  }
  return groups.map((c,i)=>({...c,id:`c${i}`}));
}

export function segmentResult({tool,input,result}) {
  if (!["grep","webfetch","shell"].includes(tool) || result.metadata?.jev) return;
  const part=textPart(result);if(!part)return;
  const {text}=part;let spans;const protectedSpans=[];
  if (tool==="grep" && Array.isArray(result.output)) {
    // Verified V2.0.14: grep returns the same matches as structured output and
    // human-readable content. Only transform when every row maps exactly.
    let cursor=0;spans=[];
    for(const entry of result.output) {
      if(typeof entry.text!=="string" || typeof entry.entry?.path!=="string" || !Number.isInteger(entry.line))return;
      const needle=`  Line ${entry.line}: ${entry.text.trimEnd()}\n`;
      const match=text.indexOf(needle,cursor);if(match<0)return;
      const gap=text.slice(cursor,match);
      const start=gap.trim()?match:cursor;
      if(start>cursor)protectedSpans.push({start:cursor,end:start,text:text.slice(cursor,start)});
      const end=match+needle.length;
      spans.push({start,end,text:text.slice(start,end),source:entry.entry.path,entries:[entry]});cursor=end;
    }
    if(cursor<text.length)protectedSpans.push({start:cursor,end:text.length,text:text.slice(cursor)});
  } else {
    if(result.output!==undefined)return;
    spans=lines(text).map(span=>({...span,source:input?.url ?? input?.path ?? tool}));
    if(tool==="shell") {
      const command=input?.command ?? "";
      if(!/^(node --test|python3? -m pytest|pytest|cargo test|go test|npx tsc|tsc)(\s|$)/.test(command) || /[;&|]/.test(command))return;
      if(!/(^TAP version |^ℹ tests |test result:|test session starts|error TS\d+:)/m.test(text))return;
      // Keep the full failure/diagnostic tail, not just isolated error lines.
      const first=spans.findIndex(s=>/not ok|error|warning|fail|panic|Traceback/i.test(s.text));
      if(first>=0)protectedSpans.push(...spans.splice(Math.max(0,first-2)));
    }
    spans=spans.filter(span=>{
      if(/truncat|omitted|coverage|exit (code|status)/i.test(span.text)){protectedSpans.push(span);return false;}return true;
    });
  }
  return {...part,candidates:group(spans),protectedSpans,structured:tool==="grep" && Array.isArray(result.output)};
}

export async function filterContext({client,archive,sessions,task,event,config}) {
  const original=event.result;
  if(event.status!=="completed" || !sessions.current(task))return original;
  const segmented=segmentResult(event);
  if(!segmented || segmented.text.length<config.contextThresholdChars || !segmented.candidates.length)return original;
  const state=await sessions.get(task.sessionID);
  if(!state.context?.request)return original;
  const deadlineAt=Date.now()+config.deadlineMs;const scored=[];
  // Independent batches share one total deadline and never truncate requirements.
  for(let index=0;index<segmented.candidates.length;index+=8) {
    const candidates=segmented.candidates.slice(index,index+8).map(({id,text,source,start,end})=>({id,text,source,start,end}));
    const result=await client.evaluate({task,kind:"context",state:{request:state.context.request,candidates},
      questions:contextQuestions(candidates),rubricVersion,deadlineAt});
    if(result.status!=="ok" || !sessions.current(task))return original;
    for(const candidate of segmented.candidates.slice(index,index+8)) {
      const score=result.answers[candidate.id]?.noul;
      if(!Number.isFinite(score))return original;
      scored.push({...candidate,score});
    }
  }
  const selected=[];let length=segmented.protectedSpans.reduce((n,s)=>n+s.text.length,0);
  for(const candidate of scored.sort((a,b)=>b.score-a.score)) {
    if(candidate.score<config.contextKeepProbability)continue;
    if(selected.length && length+candidate.text.length>config.contextTargetChars)continue;
    selected.push(candidate);length+=candidate.text.length;
  }
  if(!selected.length || length>=segmented.text.length || !sessions.current(task))return original;
  let recovery;
  try {recovery=await archive.save({sessionID:task.sessionID,text:segmented.text});}catch{return original;}
  if(!sessions.current(task))return original;
  const spans=[...selected,...segmented.protectedSpans].sort((a,b)=>a.start-b.start);
  const header=`[Jev selected ${length}/${segmented.text.length} characters; partial coverage. Full text: jev_context_read id=${recovery.id}; expires ${new Date(recovery.expiresAt).toISOString()}. Offsets below are original UTF-16 character offsets.]\n`;
  const content=header+spans.map(s=>`${s.id?`\n[${s.source}; offsets ${s.start}–${s.end}]\n`:""}${s.text}`).join("");
  const replacement=segmented.replace(content);
  if(segmented.structured)replacement.output=selected.sort((a,b)=>a.start-b.start).flatMap(s=>s.entries);
  replacement.metadata={...original.metadata,jev:{callID:event.id,originalChars:segmented.text.length,selectedChars:length,recovery}};
  return replacement;
}
