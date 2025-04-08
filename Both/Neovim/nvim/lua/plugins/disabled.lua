require "nvchad.mappings"
local nomap = vim.keymap.del
nomap("n", "<leader>fh")
nomap("n", "<leader>fa")
nomap("n", "<leader>fo")
nomap("n", "<leader>fw")
nomap("n", "<leader>fz")
nomap("n", "<leader>ma")
nomap("n", "<leader>cm")
nomap("n", "<leader>gt")
nomap("n", "<leader>pt")
nomap("n", "<leader>th")
nomap("n", "<C-n>")

return {
  {
    "hrsh7th/nvim-cmp",
    enabled = false,
  },
  {
    "nvim-tree/nvim-tree.lua",
    enabled = false,
  },
  {
    "nvim-telescope/telescope.nvim",
    enabled = false,
  },
}
