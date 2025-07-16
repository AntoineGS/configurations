-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "onedark",

  -- hl_override = {
  -- 	Comment = { italic = true },
  -- 	["@comment"] = { italic = true },
  -- },
}

M.mason = {
  pkgs = {
    "eslint-lsp",
    "prettierd",
    "powershell-editor-services",
    "pyright",
    --    "sqls",
    "docker-compose-language-service",
    "bash-language-server",
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
  },
}

return M
