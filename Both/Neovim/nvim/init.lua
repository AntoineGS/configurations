vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- load theme before plugins so treesitter has highlight groups defined
local base46_files = { "defaults", "statusline", "syntax", "treesitter" }
for _, file in ipairs(base46_files) do
  local path = vim.g.base46_cache .. file
  if vim.uv.fs_stat(path) then
    dofile(path)
  end
end

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  { import = "plugins.which-key" },
  { import = "plugins" },
}, lazy_config)

require "options"
require "autocmds"
require "marks"

vim.schedule(function()
  require "mappings"
end)
