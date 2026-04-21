local wk = require "which-key"
wk.add {
  { "<leader>-", "<cmd>Yazi<cr>", desc = "Yazi (current file)", mode = { "n", "v" } },
  { "<leader>cw", "<cmd>Yazi cwd<cr>", desc = "Yazi (cwd)" },
  { "<c-up>", "<cmd>Yazi toggle<cr>", desc = "Yazi (resume last)" },
}

return {
  "mikavilpas/yazi.nvim",
  lazy = true,
  cmd = "Yazi",
  dependencies = {
    { "nvim-lua/plenary.nvim", lazy = true },
    { "folke/snacks.nvim", lazy = true },
  },
  opts = {
    open_for_directories = false,
    keymaps = {
      show_help = "<f1>",
    },
  },
}
