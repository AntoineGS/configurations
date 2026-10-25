vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

vim.filetype.add { extension = { dpk = "pascal" } }

-- Use the local InterBase SQL parser and queries before plugins load SQL.
local sql_parser_root = vim.fn.expand "~/gits/tree-sitter-sql"
local sql_parser_setup = sql_parser_root .. "/contrib/neovim/preview.lua"
if vim.fn.filereadable(sql_parser_setup) == 1 and vim.fn.filereadable(sql_parser_root .. "/sql.so") == 1 then
  dofile(sql_parser_setup)
end

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
