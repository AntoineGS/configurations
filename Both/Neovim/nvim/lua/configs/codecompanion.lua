return {
  adapters = {
    copilot = function()
      return require("codecompanion.adapters").extend("copilot", {
        schema = {
          model = {
            -- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#models
            -- gpt-4o, claude-3.5-sonnet, o1-preview, o1-mini
            default = "claude-3.5-sonnet",
          },
        },
      })
    end,
  },
  strategies = {
    chat = {
      adapter = "copilot",
    },
    inline = {
      adapter = "copilot",
    },
  },
}
