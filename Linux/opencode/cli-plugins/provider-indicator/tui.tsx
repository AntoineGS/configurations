/** @jsxImportSource @opentui/solid */
import { Plugin } from "@opencode/plugin/tui";
import { createSignal, Show } from "solid-js";

export default Plugin.define({
  id: "agent-provider-indicator",
  setup(context) {
    const [provider, setProvider] = createSignal<string>();

    const refresh = async () => {
      const location = context.location ?? context.data.location.default();
      await context.data.location.agent.sync(location);
      const agent = context.data.location.agent.list(location)?.find((item) => item.id === "orchestrator");
      const active = agent?.model?.providerID;
      setProvider(active === "openai" ? "OpenAI" : active === "anthropic" ? "Anthropic" : undefined);
    };

    void refresh().catch(() => setProvider(undefined));
    const stop = context.data.on("agent.updated", () => void refresh().catch(() => setProvider(undefined)));
    const remove = context.ui.slot({
      append: "prompt.footer.status",
      render: () => (
        <Show when={provider()}>
          {(active) => <text fg={context.theme.text.base}>Rte: {active()}</text>}
        </Show>
      ),
    });

    return () => {
      stop();
      remove();
    };
  },
});
