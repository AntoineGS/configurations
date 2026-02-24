local wk = require "which-key"
wk.add {
  { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "DiffviewOpen" },
  { "<leader>gc", "<cmd>DiffviewClose<cr>", desc = "DiffviewClose" },
  { "<leader>gt", "<cmd>DiffviewToggle<cr>", desc = "DiffviewToggle" },
  { "<leader>gi", "<cmd>DiffviewFocusFiles<cr>", desc = "DiffviewFocusFiles" },
}

return {
  "dlyongemallo/diffview.nvim",
  lazy = true,
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggle", "DiffviewFocusFiles" },
}
