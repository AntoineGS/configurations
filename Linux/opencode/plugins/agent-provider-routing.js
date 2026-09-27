// Routes every agent through a tier table so the whole roster can follow one
// provider, switched live with `/provider`.
//
// agent-routing.json maps each agent to a tier (reasoning / coding / light),
// and each tier to one model per provider. The active provider lives in plugin
// storage, so it survives restarts. Agent `.md` files carry no model/variant
// frontmatter: this plugin is the only thing that assigns them.

import { loadManifest, resolveCatalog, providersFor, modelFor } from "../jev/routing.mjs";
const STORAGE_KEY = "provider";

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

      // Synthetic messages schedule a model turn by default; these are status
      // notes for the user, so admit them without resuming the session.
      const notify = (sessionID, text) => ctx.session.synthetic({ sessionID, text, resume: false });

      const switchProvider = async (sessionID, requested) => {
        state.manifest = await loadManifest();
        const available = await refresh();

        if (!requested) {
          await notify(sessionID, status());
          return;
        }

        const next = requested === "toggle" ? [...available].find((provider) => provider !== state.provider) : requested;

        if (!next || !available.has(next)) {
          await notify(sessionID, `Provider ${requested} is not available here. Available: ${[...available].join(", ")}`);
          return;
        }

        state.provider = next;
        await ctx.storage.set(STORAGE_KEY, next);
        await ctx.agent.reload();
        await notify(sessionID, status());
      };

      await ctx.command.transform((editor) => {
        editor.add({
          name: "provider",
          description: "Switch every agent between openai and anthropic tiers",
          execute: ({ sessionID, prompt }) => switchProvider(sessionID, (prompt?.text ?? "").trim().toLowerCase()),
        });
        for (const provider of ["openai", "anthropic"]) {
          editor.add({
            name: provider,
            description: `Switch every agent to ${provider} tiers`,
            execute: ({ sessionID }) => switchProvider(sessionID, provider),
          });
        }
      });
    } catch (error) {
      console.error("agent-provider-routing setup failed:", error?.stack ?? error);
    }
  },
};
