if not vim.g.vscode then
  require "nvchad.mappings"

  local cinnamon = require "cinnamon"
  vim.keymap.set("n", "<C-U>", function()
    cinnamon.scroll "<C-U>zz"
  end)
  vim.keymap.set("n", "<C-D>", function()
    cinnamon.scroll "<C-D>zz"
  end)
end

--[[ local map = vim.keymap.set
map("n", "<leader>y", '"+y')
map("v", "<leader>y", '"+y')
map("n", "<leader>yy", '"+yy')
map("n", "<leader>Y", '"+Y')
map("n", "<leader>p", '"+p')
map("n", "<leader>P", '"+P') ]]

-- map("n", ";", ":", { desc = "CMD enter command mode" })
-- map("i", "jk", "<ESC>")
-- map({ "n)", "i", "v" }, "<C-s>", "<cmd> w <cr>")
