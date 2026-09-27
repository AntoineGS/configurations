import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, symlink, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { createArchive } from "../jev/archive.mjs";
import { filterContext } from "../jev/context.mjs";
import { hash } from "../jev/runtime.mjs";
import { loadConfig } from "../jev/config.mjs";

test("archive recovery is verbatim, session-bound, bounded and expiring", async () => {
  const root=await mkdtemp("/tmp/opencode/jev-archive-test-");let now=1000;
  try {
    const archive=createArchive({root,retentionMs:1000,now:()=>now});
    const original="compiler error\nUnicode: café 🐛\n";
    const ref=await archive.save({sessionID:"one",text:original});
    assert.equal((await archive.read({sessionID:"one",id:ref.id,offset:0,limit:1000})).text,original);
    for(const args of [{sessionID:"two",id:ref.id},{sessionID:"one",id:"../escape"},{sessionID:"one",id:ref.id,offset:-1},{sessionID:"one",id:ref.id,limit:1000000}]) {
      await assert.rejects(archive.read(args));
    }
    now=2001;await assert.rejects(archive.read({sessionID:"one",id:ref.id}));await archive.prune();
    await assert.rejects(archive.read({sessionID:"one",id:ref.id}));
    await mkdir(join(root,"outside"));await symlink(join(root,"outside"),join(root,hash("symlink")));
    await assert.rejects(archive.save({sessionID:"symlink",text:"private"}));
  } finally {await rm(root,{recursive:true,force:true});}
});
const task=()=>({sessionID:"s",taskID:"t",epoch:1,directory:"/p",signal:new AbortController().signal});
const config=loadConfig();
const big=()=>Array.from({length:100},(_,i)=>`Section ${i}: ${i===40?"RELEVANT":"background"} ${"x".repeat(220)}\n`).join("");
function args(result={content:big(),metadata:{source:"fixture"}}) {
  let original;
  return {task:task(),config,event:{tool:"webfetch",input:{url:"https://example.com"},id:"call",status:"completed",result},
    sessions:{current:()=>true,get:async()=>({context:{request:"Find RELEVANT"}})},
    archive:{save:async ({text})=>{original=text;return{id:"ref",expiresAt:42,characters:text.length};}},
    client:{evaluate:async r=>({status:"ok",answers:Object.fromEntries(r.state.candidates.map(c=>[c.id,{type:"noul",noul:c.text.includes("RELEVANT")?0.99:0.01}]))})},
    original:()=>original};
}
test("selection keeps verbatim excerpts and non-text content with complete recovery", async () => {
  const text=big();const file={type:"file",mediaType:"image/png",url:"fixture"};
  const a=args({content:[{type:"text",text},file],metadata:{exitCode:1}});
  const result=await filterContext(a);
  assert.notEqual(result,a.event.result);assert.equal(a.original(),text);
  assert.deepEqual(result.content[1],file);assert.equal(result.metadata.exitCode,1);
  assert.ok(result.content[0].text.includes(text.split("\n")[40]));
  assert.ok(result.content[0].text.length<text.length);assert.equal(result.metadata.jev.recovery.id,"ref");
  assert.equal(await filterContext({...a,event:{...a.event,result}}),result);
});
test("unknown shapes, exact reads, diffs, mutations and small text bypass inference", async () => {
  for(const tool of ["read","patch","skill","unknown_mcp_tool","execute"]) {
    const a=args();a.event.tool=tool;a.client.evaluate=()=>{throw Error("must bypass");};
    assert.equal(await filterContext(a),a.event.result);
  }
  for(const result of [{content:"small"},{content:big(),output:{text:big()}}]) {
    const a=args(result);assert.equal(await filterContext(a),result);
  }
  const a=args();a.event.tool="shell";a.event.input={command:"git diff"};assert.equal(await filterContext(a),a.event.result);
});
test("failed archival, low relevance, late cancellation and moved sessions keep originals", async () => {
  for(const mode of ["archive","low","cancel","move"]) {
    const a=args();
    if(mode==="archive")a.archive.save=async()=>{throw Error("disk full");};
    if(mode==="low")a.client.evaluate=async r=>({status:"ok",answers:Object.fromEntries(r.state.candidates.map(c=>[c.id,{type:"noul",noul:0.01}]))});
    if(mode==="cancel"||mode==="move")a.archive.save=async()=>{a.sessions.current=()=>false;return{id:"ref"};};
    assert.equal(await filterContext(a),a.event.result);
  }
});
test("verified grep output and text are selected consistently", async () => {
  const output=Array.from({length:200},(_,i)=>({entry:{path:"fixture.txt",type:"file"},line:i+1,offset:i*120,
    text:`needle ${i}: ${i===80?"RELEVANT":"background"} ${"x".repeat(90)}\n`,submatches:[{text:"needle",start:0,end:6}]}));
  const content=`Found 200 matches\n/p/fixture.txt:\n${output.map(m=>`  Line ${m.line}: ${m.text}\n`).join("")}`;
  const a=args({content,output,metadata:{matches:200,truncated:false}});a.event.tool="grep";
  const result=await filterContext(a);
  assert.ok(result.output.length<200);assert.ok(result.output.some(m=>m.line===81));
  for(const match of result.output)assert.ok(result.content.includes(match.text.trimEnd()));
  assert.equal(a.original(),content);assert.equal(result.metadata.matches,200);
});
test("recognized failures and their full trailing diagnostics are protected above target", async () => {
  const a=args({content:`TAP version 13\n${big()}not ok 1 - compiler error\n${"  at fixture.js:1:2\n".repeat(1000)}`,metadata:{exitCode:1}});
  a.event.tool="shell";a.event.input={command:"node --test fixture.test.mjs"};
  const result=await filterContext(a);
  assert.ok(result.content.includes("not ok 1 - compiler error\n"+"  at fixture.js:1:2\n".repeat(1000)));
  assert.ok(result.metadata.jev.selectedChars>config.contextTargetChars);
});
