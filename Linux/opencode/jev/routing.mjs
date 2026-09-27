import { readFile } from "node:fs/promises";
import { readCatalogs, unwrap } from "./runtime.mjs";

export async function loadManifest(url = new URL("../agent-routing.json", import.meta.url)) {
  const manifest = JSON.parse(await readFile(url,"utf8"));
  if (!manifest?.tiers || !manifest?.agents) throw new Error("agent-routing.json: expected tiers and agents");
  for (const [agent,tier] of Object.entries(manifest.agents)) {
    if (!manifest.tiers[tier]) throw new Error(`agent-routing.json: ${agent} uses unknown tier ${tier}`);
  }
  return manifest;
}
export function resolveCatalog(models) {
  const catalog = new Map();
  for (const model of unwrap(models) ?? []) {
    if (model.enabled === false) continue;
    catalog.set(`${model.providerID}/${model.id}`,new Set((model.variants ?? []).map(variant=>variant.id)));
  }
  return catalog;
}
export function providersFor(manifest,catalog) {
  const providers = new Set();
  for (const tier of Object.values(manifest.tiers)) {
    for (const [provider,target] of Object.entries(tier)) {
      if (catalog.has(`${provider}/${target.id}`)) providers.add(provider);
    }
  }
  return providers;
}
export function modelFor(manifest,catalog,provider,tier) {
  const target = manifest.tiers[tier]?.[provider];
  if (!target) return undefined;
  const variants = catalog.get(`${provider}/${target.id}`);
  if (!variants) return undefined;
  const model = {providerID:provider,id:target.id};
  if (target.variant && variants.has(target.variant)) model.variant = target.variant;
  return model;
}
export async function readRouting(ctx,directory) {
  const [manifest,live] = await Promise.all([loadManifest(),readCatalogs(ctx,directory)]);
  return {...live,manifest,catalog:resolveCatalog(live.models),provider:live.agents.find(a=>a.id==="orchestrator")?.model?.providerID};
}
