-- Keymaps
local keymap = vim.keymap.set
keymap("n", "<leader>tf", "<cmd>Telescope find_files<cr>", { desc = "Find Files" })
keymap("n", "<leader>tg", "<cmd>Telescope live_grep<cr>", { desc = "Live Grep" })
keymap("n", "<leader>tb", "<cmd>Telescope buffers<cr>", { desc = "Find Buffers" })

return {
  "nvim-telescope/telescope.nvim",
  lazy = false,
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local telescope = require "telescope"
    local actions = require "telescope.actions"

    telescope.setup {
      defaults = {
        mappings = {
          i = {
            ["<C-u>"] = false,
            ["<C-d>"] = false,
            ["<C-j>"] = actions.move_selection_next,
            ["<C-k>"] = actions.move_selection_previous,
          },
        },
      },
    }
  end,
}
