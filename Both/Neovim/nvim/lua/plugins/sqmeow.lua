local wk = require "which-key"
wk.add {
  { "<leader>Q", group = "database" },
}

return {
  "2giosangmitom/sqmeow.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
  version = "*",
  build = function()
    require("sqmeow").install()
  end,
  cmd = "Sqmeow",
  keys = {
    { "<leader>Qq", "<cmd>Sqmeow toggle<cr>", desc = "Toggle drawer & results" },
    { "<leader>Qs", "<cmd>Sqmeow scratch<cr>", desc = "New scratchpad" },
    { "<leader>Qu", "<cmd>Sqmeow use<cr>", desc = "Use connection" },
    { "<leader>Qa", "<cmd>Sqmeow add<cr>", desc = "Add connection" },
    { "<leader>Ql", "<cmd>Sqmeow log<cr>", desc = "Query log" },
    { "<leader>Qc", "<cmd>Sqmeow cancel<cr>", desc = "Cancel query" },
  },
  opts = {},
}
