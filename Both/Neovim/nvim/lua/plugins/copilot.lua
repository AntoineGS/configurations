return {
  -- "zbirenbaum/copilot.lua",
  "AntoineGS/copilot.lua",
  branch = "master",
  cmd = "Copilot",
  event = "InsertEnter",
  -- config = function()
  --   require("copilot").setup {
  --     copilot_model = "gpt-4o-copilot",
  --     -- workspace_fodlers = {
  --     -- "C:\\Gits\\",
  --     --   "C:\\Dev\\",
  --     -- },
  --     logger = {
  --       file_log_level = vim.log.levels.TRACE,
  --       print_log_level = vim.log.levels.WARN,
  --       log_to_file = true,
  --       trace_lsp = "verbose",
  --     },
  --     filetypes = { ["*"] = true },
  --   }
  -- end,

  config = function()
    require("copilot").setup {
      copilot_model = "gpt-4o-copilot",
      logger = {
        file_log_level = vim.log.levels.TRACE,
        print_log_level = vim.log.levels.WARN,
        log_to_file = true,
        trace_lsp = "verbose",
      },
      panel = {
        enabled = true,
        keymap = {
          open = "<M-p>",
        },
      },
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = "<M-}>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-c>",
        },
      },
      filetypes = {
        ["*"] = true,
      },
    }
  end,
}
