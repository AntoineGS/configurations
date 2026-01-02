-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(
-- The file name is hardcoded through nvchad/ui

---@type ChadrcConfig
local M = {}

-- For some reason these get changed back to defaults, so we set them but defer it
vim.schedule(function()
  vim.api.nvim_set_hl(0, "DiffAdd", { fg = "#98c379", bg = "#2a3231" })
  vim.api.nvim_set_hl(0, "DiffChange", { fg = "#6f737b", bg = "#262a32" })
  vim.api.nvim_set_hl(0, "DiffDelete", { fg = "#e06c75", bg = "#312931", strikethrough = true })
  vim.api.nvim_set_hl(0, "DiffText", { fg = "#abb2bf", bg = "#252931" })
end)

M.base46 = {
  theme = "onedark",
  transparency = true,
}

M.ui = {
  tabufline = {
    enabled = false,
  },
  statusline = {
    modules = {
      cursor = function()
        local sep_l = require("nvchad.stl.utils").separators["round"]["left"]
        return "%#St_pos_sep#" .. sep_l .. "%#St_pos_icon# %#St_pos_text# %l/%L:%v "
      end,
      file = function()
        local sep_r = require("nvchad.stl.utils").separators["round"]["right"]
        local x = require("nvchad.stl.utils").file()
        local modified = vim.bo.modified and " " or ""
        local name = " " .. x[2] .. modified .. " "
        return "%#St_file# " .. x[1] .. name .. "%#St_file_sep#" .. sep_r
      end,
    },
  },
}

M.mason = {
  pkgs = {
    "eslint-lsp",
    "prettierd",
    "powershell-editor-services",
    "pyright",
    --    "sqls",
    "docker-compose-language-service",
    --    "ltex-ls",
    "spectral-language-server",
    "sonarlint-language-server",
    "shfmt",
    --    "sqlfmt",
    "markdownlint-cli2",
    "markdown-toc",
    "marksman",
    "mdformat",
    "clangd",
    "clang-format",
    "cpplint",
    "bash-language-server",
    "gopls",
    "goimports",
    "vtsls",
    "black",
    "tex-fmt",
  },
}

return M
