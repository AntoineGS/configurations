local wk = require "which-key"

wk.add {
  { "<leader>tp", "<cmd>TidydotsPreview<cr>", desc = "Preview Tidydots" },
}

return {
  dir = "~/gits/tidydots.nvim",
  event = "BufReadPre *.tmpl",
  opts = {
    cmd = "~/gits/tidydots/tidydots",
    auto_open = true,
    debug = true,
  },
}
