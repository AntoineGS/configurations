local g = vim.g
local o = vim.o
local opt = vim.opt

o.icm = "split"
o.cursorlineopt = "both"
opt.relativenumber = true
opt.foldmethod = "expr"
opt.foldexpr = "nvim_treesitter#foldexpr()"
opt.foldlevelstart = 99
--opt.foldtext = "getline(v:foldstart) .. v:lua.nvim_treesitter#foldtext()"

o.laststatus = 3
o.showmode = false
o.splitkeep = "screen"

o.clipboard = "unnamedplus"
o.cursorline = true
o.cursorlineopt = "number"

-- Indenting
o.expandtab = true
o.shiftwidth = 2
o.smartindent = true
o.tabstop = 2
o.softtabstop = 2

opt.fillchars = { eob = " " }
o.ignorecase = true
o.smartcase = true
o.mouse = "a"

-- Numbers
o.number = true
o.numberwidth = 2
o.ruler = false

-- disable nvim intro
opt.shortmess:append "sI"

o.signcolumn = "yes"
o.splitbelow = true
o.splitright = true
o.timeoutlen = 400
o.undofile = true
o.autoread = true

-- Backups: keep timestamped copies in stdpath('state')/backup; pruned after 14 days (see autocmds.lua).
-- Trailing '//' encodes the source file's full path into the backup name so files with the same
-- basename in different directories don't collide.
do
  local backup_dir = vim.fn.stdpath "state" .. "/backup"
  vim.fn.mkdir(backup_dir, "p")
  o.backup = true
  o.writebackup = true
  opt.backupdir = backup_dir .. "//"
end

opt.spelllang = { "en_us" }
opt.spelloptions:append "camel"

-- interval for writing swap file to disk, also used by gitsigns
o.updatetime = 250

-- go to previous/next line with h,l,left arrow and right arrow
-- when cursor reaches end/beginning of line
opt.whichwrap:append "<>[]hl"

-- disable some default providers
g.loaded_node_provider = 0
g.loaded_python3_provider = 0
g.loaded_perl_provider = 0
g.loaded_ruby_provider = 0

-- add binaries installed by mason.nvim to path
local is_windows = vim.fn.has "win32" ~= 0
local sep = is_windows and "\\" or "/"
local delim = is_windows and ";" or ":"
vim.env.PATH = table.concat({ vim.fn.stdpath "data", "mason", "bin" }, sep) .. delim .. vim.env.PATH
