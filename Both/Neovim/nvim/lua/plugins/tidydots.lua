local wk = require "which-key"

wk.add {
  { "<leader>tp", "<cmd>TidydotsPreview<cr>", desc = "Preview Tidydots" },
}

return {
  dir = "~/gits/tidydots.nvim",
  cmd = "TidydotsPreview",
  opts = {
    cmd = "~/gits/tidydots/tidydots",
  },
}
