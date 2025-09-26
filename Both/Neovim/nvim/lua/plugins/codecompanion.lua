local wk = require "which-key"
wk.add {
  { "<leader>cc", group = "Code Companion" },
  { "<leader>ccc", "<cmd>CodeCompanionChat<CR>", desc = "Chat" },
  { "<leader>cct", "<cmd>CodeCompanionChat Toggle<CR>", desc = "Toggle Chat" },
}

return {
  "olimorris/codecompanion.nvim",
  --lazy = false,
  cmd = "CodeCompanionChat",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    { "nvim-lua/plenary.nvim", branch = "master" },
  },
  config = true,
  opts = {
    adapters = {
      http = {
        copilot = function()
          return require("codecompanion.adapters").extend("copilot", {
            -- schema = {
            -- model = {
            -- https://github.com/CopilotC-Nvim/CopilotChat.nvim?tab=readme-ov-file#models
            -- gpt-4o, claude-3.5-sonnet, claude-3.7-sonnet, o1-preview, o1-mini
            -- default = "claude-3.7-sonnet",
            -- },
            -- },
          })
        end,
      },
    },
    strategies = {
      chat = {
        adapter = "copilot",
      },
      inline = {
        adapter = "copilot",
      },
    },
  },
}
