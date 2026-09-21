// Routes every agent through a tier table so the whole roster can follow one
// provider, switched live with `/provider`.
//
// agent-routing.json maps each agent to a tier (reasoning / coding / light),
// and each tier to one model per provider. The active provider lives in plugin
// storage, so it survives restarts. Agent `.md` files carry no model/variant
// frontmatter: this plugin is the only thing that assigns them.

import { readFile } from "node:fs/promises";

const MANIFEST = new URL("../agent-routing.json", import.meta.url);
const STORAGE_KEY = "provider";

async function loadManifest() {
  const manifest = JSON.parse(await readFile(MANIFEST, "utf8"));
  if (!manifest?.tiers || !manifest?.agents) throw new Error("agent-routing.json: expected tiers and agents");
  for (const [agent, tier] of Object.entries(manifest.agents)) {
    if (!manifest.tiers[tier]) throw new Error(`agent-routing.json: ${agent} uses unknown tier ${tier}`);
  }
  return manifest;
}

// Context read methods mirror the HTTP client, which wraps collections in a
// `data` envelope. Older shapes return the array directly.
function asArray(result) {
  if (Array.isArray(result)) return result;
  if (Array.isArray(result?.data)) return result.data;
  return [];
}

// Providers a tier can actually reach right now. The anthropic provider is only
// configured on some hosts, so availability is checked against the live model
// list rather than assumed from the manifest.
function resolveCatalog(models) {
  const catalog = new Map();
  for (const model of asArray(models)) {
    if (model.enabled === false) continue;
    catalog.set(`${model.providerID}/${model.id}`, new Set((model.variants ?? []).map((variant) => variant.id)));
  }
  return catalog;
}

function providersFor(manifest, catalog) {
  const providers = new Set();
  for (const tier of Object.values(manifest.tiers)) {
    for (const [provider, target] of Object.entries(tier)) {
      if (catalog.has(`${provider}/${target.id}`)) providers.add(provider);
    }
  }
  return providers;
}

// A model that does not expose the requested variant still works at its own
// default, so drop the variant instead of failing the switch.
function modelFor(manifest, catalog, provider, tier) {
  const target = manifest.tiers[tier]?.[provider];
  if (!target) return undefined;
  const variants = catalog.get(`${provider}/${target.id}`);
  if (!variants) return undefined;
  const model = { providerID: provider, id: target.id };
  if (target.variant && variants.has(target.variant)) model.variant = target.variant;
  return model;
}

function describe(model) {
  return model.variant ? `${model.providerID}/${model.id}#${model.variant}` : `${model.providerID}/${model.id}`;
}

export default {
  id: "agent-provider-routing",
  async setup(ctx) {
    if (!ctx?.agent?.transform) return;
    // Routing is a convenience, not a dependency: a failure here must leave
    // OpenCode running on whatever models the config already resolves to.
    try {
      const state = { manifest: await loadManifest(), catalog: new Map(), provider: undefined };

      const refresh = async () => {
        state.catalog = resolveCatalog(await ctx.model.list());
        const available = providersFor(state.manifest, state.catalog);
        if (!available.has(state.provider)) {
          state.provider = available.has(state.manifest.default_provider)
            ? state.manifest.default_provider
            : [...available][0];
        }
        return available;
      };

      const stored = await ctx.storage.get(STORAGE_KEY);
      if (typeof stored === "string") state.provider = stored;
      await refresh();

      // Reads state.provider on every replay, so reload() re-routes the roster.
      // Agents absent at replay time are ignored by the editor.
      await ctx.agent.transform((editor) => {
        if (!state.provider) return;
        for (const [agent, tier] of Object.entries(state.manifest.agents)) {
          const model = modelFor(state.manifest, state.catalog, state.provider, tier);
          if (!model) continue;
          try {
            editor.update(agent, (draft) => void (draft.model = model));
          } catch {
            // Agent not present in this location.
          }
        }
      });

      const status = () => {
        const tiers = Object.keys(state.manifest.tiers)
          .map((tier) => {
            const model = modelFor(state.manifest, state.catalog, state.provider, tier);
            return `  ${tier}: ${model ? describe(model) : "unavailable"}`;
          })
          .join("\n");
        return `Agent provider: ${state.provider}\n${tiers}`;
      };

      await ctx.command.transform((editor) => {
        editor.add({
          name: "provider",
          description: "Switch every agent between openai and anthropic tiers",
          execute: async ({ sessionID, prompt }) => {
            const requested = (prompt?.text ?? "").trim().toLowerCase();
            state.manifest = await loadManifest();
            const available = await refresh();

            if (!requested) {
              await ctx.session.synthetic({ sessionID, text: status() });
              return;
            }

            const next =
              requested === "toggle" ? [...available].find((provider) => provider !== state.provider) : requested;

            if (!next || !available.has(next)) {
              const text = `Provider ${requested} is not available here. Available: ${[...available].join(", ")}`;
              await ctx.session.synthetic({ sessionID, text });
              return;
            }

            state.provider = next;
            await ctx.storage.set(STORAGE_KEY, next);
            await ctx.agent.reload();
            await ctx.session.synthetic({ sessionID, text: status() });
          },
        });
      });
    } catch (error) {
      console.error("agent-provider-routing setup failed:", error?.stack ?? error);
    }
  },
};
