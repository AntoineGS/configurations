local wk = require "which-key"
wk.add {
  { "<leader>mt", group = "MiniTest" },
  { "<leader>mtr", "<cmd>lua MiniTest.run()<CR>", desc = "Run" },
  { "<leader>mtf", "<cmd>lua MiniTest.run_file()<CR>", desc = "Run File" },
  { "<leader>mtl", "<cmd>lua MiniTest.run_at_location()<CR>", desc = "Run At Location" },
}
return {
  "echasnovski/mini.nvim",
  version = false,
  require("mini.test").setup(),
}
