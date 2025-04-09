local wk = require "which-key"
wk.add {
  { "<leader>rr", "<cmd>GrugFar<CR>", desc = "Find & Replace" },
  { "<leader>rw", "<cmd>GrugFarWithin<CR>", desc = "Find & Replace Within" },
}

return {
  "MagicDuck/grug-far.nvim",
  cmd = { "GrugFar", "GrugFarWithin" },
  config = function()
    -- optional setup call to override plugin options
    -- alternatively you can set options with vim.g.grug_far = { ... }
    require("grug-far").setup {}
  end,
}
