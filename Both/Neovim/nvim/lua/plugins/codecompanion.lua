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
  opts = require "configs.codecompanion",
}
