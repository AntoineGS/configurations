local wk = require "which-key"
wk.add {
  { "-", "<cmd>Oil<cr>", desc = "Oil (parent dir)" },
  { "<leader>_", "<cmd>Oil --float<cr>", desc = "Oil (float)" },
}

return {
  "stevearc/oil.nvim",
  lazy = true,
  cmd = "Oil",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  opts = {
    default_file_explorer = false,
    view_options = {
      show_hidden = true,
    },
  },
}
