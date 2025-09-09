require "nvchad.options"

local o = vim.o
o.icm = "split"
o.cursorlineopt = "both"
local opt = vim.opt
opt.clipboard = ""
opt.relativenumber = true
opt.foldmethod = "expr"
opt.foldexpr = "nvim_treesitter#foldexpr()"
opt.foldlevelstart = 99
--opt.foldtext = "getline(v:foldstart) .. v:lua.nvim_treesitter#foldtext()"
