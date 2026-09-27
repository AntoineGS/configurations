import test from "node:test";
import assert from "node:assert/strict";
import { createSessions } from "../jev/sessions.mjs";

function fixture() {
  const data = new Map(); let directory = "/project";
  const storage = { get: async k => structuredClone(data.get(k)), set: async (k,v) => {data.set(k,structuredClone(v));} };
  const readView = async id => ({ sessionID:id,parentID:id==="child"?"parent":undefined,directory,messages:[],selectionEvents:[],busy:false });
  return {data,storage,readView,move:()=>{directory="/moved";},create:()=>createSessions({storage,readView})};
}
test("off is durable and inherited once; child overrides are isolated", async () => {
  const f=fixture(); const s=f.create(); const task=await s.beginTask("parent","first");
  await s.setEnabled("parent",false); assert.equal(s.current(task),false);
  assert.equal((await s.get("child")).enabled,false);
  await s.setEnabled("child",true);
  assert.equal((await s.get("parent")).enabled,false);
  s.close(); const reloaded=f.create();
  assert.equal((await reloaded.get("child")).enabled,true);
  assert.equal((await reloaded.get("parent")).enabled,false);
});
test("pin holds route only and persists; on releases ownership explicitly", async () => {
  const f=fixture(); const s=f.create();
  await s.pin("parent"); assert.equal((await s.get("parent")).enabled,true);
  assert.equal((await f.create().get("parent")).route.mode,"pinned");
  await s.setEnabled("parent",true); assert.equal((await s.get("parent")).route.mode,"auto");
});
test("new revisions, moves, and shutdown invalidate stale results", async () => {
  const f=fixture(); const s=f.create();
  const first=await s.beginTask("parent","task","prompt-one");
  assert.equal(await s.beginTask("parent","task","prompt-one"),first);
  const next=await s.beginTask("parent","task","prompt-two");
  assert.equal(s.current(first),false); assert.equal(s.current(next),true);
  f.move(); await s.get("parent"); assert.equal(s.current(next),false);
  const moved=await s.beginTask("parent","new"); s.close(); assert.equal(s.current(moved),false);
});
test("per-session queues serialize routing without delaying off", async () => {
  const s=fixture().create(); let release; const order=[];
  const first=s.serial("parent",async()=>{order.push(1);await new Promise(r=>{release=r;});order.push(2);});
  const second=s.serial("parent",async()=>{order.push(3);});
  await new Promise(r=>setImmediate(r));
  await s.setEnabled("parent",false); assert.equal((await s.get("parent")).enabled,false);
  release(); await Promise.all([first,second]); assert.deepEqual(order,[1,2,3]);
});
