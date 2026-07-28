import { expect, test } from "bun:test"
import { ContextUsagePlugin } from "./context-usage.ts"

test("counts tokens with js-tiktoken", async () => {
  const client = {
    session: {
      messages: async () => ({
        data: [
          {
            info: { id: "user", role: "user", modelID: "gpt-4o", providerID: "openai" },
            parts: [{ type: "text", text: "hello" }],
          },
          {
            info: {
              id: "assistant",
              role: "assistant",
              modelID: "gpt-4o",
              providerID: "openai",
              system: ["OpenCode CLI system prompt"],
            },
            parts: [{ type: "text", text: "hi" }],
          },
        ],
      }),
    },
  }

  const hooks = await ContextUsagePlugin({ client })
  const output = await hooks.tool.context_usage.execute({}, { sessionID: "test" })

  expect(output).toContain("Context Analysis: Session test")
  expect(output).toContain("Total:")
})
