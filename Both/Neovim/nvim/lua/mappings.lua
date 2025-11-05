local wk = require "which-key"
local map = vim.keymap.set

wk.add {
  { "<leader>y", '"+y', desc = "Yank to +" },
  { "<leader>y", '"+y', desc = "Yank to +", mode = "v" },
  { "<leader>Y", '"+Y', desc = "Yank rest of line to +" },
}

map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("i", "<C-b>", "<ESC>^i", { desc = "move beginning of line" })
map("i", "<C-e>", "<End>", { desc = "move end of line" })
map("i", "<C-h>", "<Left>", { desc = "move left" })
map("i", "<C-l>", "<Right>", { desc = "move right" })
map("i", "<C-j>", "<Down>", { desc = "move down" })
map("i", "<C-k>", "<Up>", { desc = "move up" })

-- map("n", "<C-h>", "<C-w>h", { desc = "switch window left" })
-- map("n", "<C-l>", "<C-w>l", { desc = "switch window right" })
-- map("n", "<C-j>", "<C-w>j", { desc = "switch window down" })
-- map("n", "<C-k>", "<C-w>k", { desc = "switch window up" })
map("n", "<C-h>", "<cmd> TmuxNavigateLeft<CR>", { desc = "switch window left" })
map("n", "<C-l>", "<cmd> TmuxNavigateRight<CR>", { desc = "switch window right" })
map("n", "<C-j>", "<cmd> TmuxNavigateDown<CR>", { desc = "switch window down" })
map("n", "<C-k>", "<cmd> TmuxNavigateUp<CR>", { desc = "switch window up" })

map("n", "<Esc>", "<cmd>noh<CR>", { desc = "general clear highlights" })

map("n", "<leader>n", "<cmd>set nu!<CR>", { desc = "toggle line number" })
map("n", "<leader>rn", "<cmd>set rnu!<CR>", { desc = "toggle relative number" })
map("n", "<leader>ch", "<cmd>NvCheatsheet<CR>", { desc = "toggle nvcheatsheet" })

map({ "n", "x" }, "<leader>fm", function()
  require("conform").format { lsp_fallback = true }
end, { desc = "general format file" })

-- global lsp mappings
map("n", "<leader>ds", vim.diagnostic.setloclist, { desc = "LSP diagnostic loclist" })

-- tabufline
map("n", "<leader>b", "<cmd>enew<CR>", { desc = "buffer new" })

map("n", "<tab>", "<cmd>BufferLineCycleNext<CR>", { desc = "buffer goto next" })

map("n", "<S-tab>", "<cmd>BufferLineCyclePrev<CR>", { desc = "buffer goto prev" })

map("n", "<leader>x", function()
  require("nvchad.tabufline").close_buffer()
end, { desc = "buffer close" })

map("n", "<leader>th", function()
  require("nvchad.themes").open()
end, { desc = "telescope nvchad themes" })

-- terminal
map("t", "<C-x>", "<C-\\><C-N>", { desc = "terminal escape terminal mode" })

-- new terminals
map("n", "<leader>h", function()
  require("nvchad.term").new { pos = "sp" }
end, { desc = "terminal new horizontal term" })

map("n", "<leader>v", function()
  require("nvchad.term").new { pos = "vsp" }
end, { desc = "terminal new vertical term" })

-- toggleable
map({ "n", "t" }, "<A-v>", function()
  require("nvchad.term").toggle { pos = "vsp", id = "vtoggleTerm" }
end, { desc = "terminal toggleable vertical term" })

map({ "n", "t" }, "<A-h>", function()
  require("nvchad.term").toggle { pos = "sp", id = "htoggleTerm" }
end, { desc = "terminal toggleable horizontal term" })

map({ "n", "t" }, "<A-i>", function()
  require("nvchad.term").toggle { pos = "float", id = "floatTerm" }
end, { desc = "terminal toggle floating term" })

-- whichkey
map("n", "<leader>wK", "<cmd>WhichKey <CR>", { desc = "whichkey all keymaps" })

map("n", "<leader>wk", function()
  vim.cmd("WhichKey " .. vim.fn.input "WhichKey: ")
end, { desc = "whichkey query lookup" })
