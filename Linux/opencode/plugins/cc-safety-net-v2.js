// OpenCode v2 adapter for cc-safety-net.
//
// The published package (2.4.x) only ships a v1 plugin function, which v2
// rejects at load time. This wraps that function and re-registers its hooks
// through the v2 plugin context. Temporary until upstream ships a v2 entry:
// https://github.com/kenryu42/cc-safety-net
//
// Requires `cc-safety-net` in ~/.config/opencode/node_modules (package.json).

import { CCSafetyNetPlugin } from "cc-safety-net";

// v2 renamed the shell tool; cc-safety-net only inspects commands for `bash`.
const TOOL_ALIASES = new Map([["shell", "bash"]]);

export default {
  id: "cc-safety-net-v2",
  async setup(ctx) {
    if (!ctx?.tool?.hook || !ctx?.location?.directory) return;

    const v1 = await CCSafetyNetPlugin({ directory: ctx.location.directory });

    // The v1 config hook records the configured shell and contributes the
    // `/cc-safety-net` command template. Feed it an empty config to collect both.
    const config = {};
    if (typeof v1.config === "function") await v1.config(config);

    const before = v1["tool.execute.before"];
    if (typeof before === "function") {
      await ctx.tool.hook("execute.before", async (event) => {
        const tool = TOOL_ALIASES.get(event.tool) ?? event.tool;
        // Throwing here denies the tool call, same as the v1 hook contract.
        await before({ tool, sessionID: event.sessionID }, { args: event.input });
      });
    }

    const command = config.command?.["cc-safety-net"];
    if (command?.template && typeof ctx.command?.transform === "function") {
      await ctx.command.transform((editor) => {
        editor.add({
          name: "cc-safety-net",
          description: command.description,
          execute: async ({ sessionID, prompt, delivery }) => {
            const text = [command.template, prompt?.text].filter(Boolean).join("\n\n");
            await ctx.session.prompt({ ...prompt, sessionID, text, delivery });
          },
        });
      });
    }
  },
};
