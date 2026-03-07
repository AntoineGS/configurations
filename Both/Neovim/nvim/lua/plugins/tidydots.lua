local wk = require "which-key"

wk.add {
  { "<leader>tp", "<cmd>TidydotsPreview<cr>", desc = "Preview Tidydots" },
}

-- if local dir exists use it, otherwise use the one from github
if vim.fn.isdirectory "~/gits/tidydots.nvim" == 0 then
  return {
    "AntoineGS/tidydots.nvim",
    event = "BufReadPre *.tmpl",
    opts = {
      cmd = "tidydots",
      auto_open = true,
      debug = true,
    },
  }
end

return {
  dir = "~/gits/tidydots.nvim",
  event = "BufReadPre *.tmpl",
  opts = {
    cmd = "~/gits/tidydots/tidydots",
    auto_open = true,
    debug = true,
  },
}
