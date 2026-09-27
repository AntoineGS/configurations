import { constants } from "node:fs";
import { mkdir, lstat, open, rename, readdir, unlink } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { randomUUID } from "node:crypto";
import { hash } from "./runtime.mjs";

export const archiveRoot = () => join(process.platform === "win32" ? (process.env.LOCALAPPDATA || join(homedir(),".cache"))
  : (process.env.XDG_CACHE_HOME || join(homedir(),".cache")),"opencode","jev");
const validID = id => typeof id === "string" && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id);
const MAX_BYTES = 16*1024*1024;
export function createArchive({root=archiveRoot(),retentionMs=30*86400000,now=Date.now} = {}) {
  async function directory(path,create=false) {
    if (create) await mkdir(path,{recursive:true,mode:0o700});
    const stat = await lstat(path);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error("invalid-archive-directory");
  }
  async function sessionPath(sessionID,create=false) {
    if (typeof sessionID !== "string" || !sessionID) throw new Error("invalid-session");
    await directory(root,create);
    const path = join(root,hash(sessionID)); await directory(path,create); return path;
  }
  async function readRecord(path) {
    const file = await open(path,constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
    try {
      const stat = await file.stat();
      if (!stat.isFile() || stat.size > MAX_BYTES) throw new Error("invalid-archive-file");
      const record = JSON.parse(await file.readFile("utf8"));
      if (typeof record.text !== "string" || !Number.isFinite(record.expiresAt)) throw new Error("invalid-archive-record");
      return record;
    } finally {await file.close();}
  }
  return {
    async save({sessionID,text}) {
      const path = await sessionPath(sessionID,true); const id = randomUUID();
      const expiresAt = now()+retentionMs;
      const data = JSON.stringify({expiresAt,text});
      if (Buffer.byteLength(data)>MAX_BYTES) throw new Error("archive-too-large");
      const temp = join(path,`${id}.tmp`); const target = join(path,`${id}.json`);
      try {
        const file = await open(temp,"wx",0o600);
        try { await file.writeFile(data,"utf8"); await file.sync(); } finally {await file.close();}
        await rename(temp,target);
      } catch (error) {await unlink(temp).catch(()=>{});throw error;}
      return {id,expiresAt,characters:text.length};
    },
    async read({sessionID,id,offset=0,limit=16000}) {
      if (!validID(id) || !Number.isInteger(offset) || offset<0 || !Number.isInteger(limit) || limit<1 || limit>16000) throw new Error("invalid-recovery-request");
      const record = await readRecord(join(await sessionPath(sessionID),`${id}.json`));
      if (record.expiresAt<=now()) throw new Error("recovery-expired");
      return {text:record.text.slice(offset,offset+limit),offset,next:Math.min(offset+limit,record.text.length),characters:record.text.length,expiresAt:record.expiresAt};
    },
    async prune() {
      try {await directory(root);} catch {return;}
      for (const entry of await readdir(root,{withFileTypes:true})) {
        if (!entry.isDirectory() || !/^[a-f0-9]{64}$/.test(entry.name)) continue;
        const path = join(root,entry.name);
        try {
          await directory(path);
          for (const file of await readdir(path,{withFileTypes:true})) {
            if (!file.isFile() || !file.name.endsWith(".json") || !validID(file.name.slice(0,-5))) continue;
            const target = join(path,file.name);
            try {if ((await readRecord(target)).expiresAt<=now()) await unlink(target);} catch { /* Unknown files are not ours to remove. */ }
          }
        } catch { /* Session cache may have disappeared concurrently. */ }
      }
    },
  };
}
