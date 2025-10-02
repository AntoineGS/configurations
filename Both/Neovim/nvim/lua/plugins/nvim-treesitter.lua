pcall(function()
  dofile(vim.g.base46_cache .. "syntax")
  dofile(vim.g.base46_cache .. "treesitter")
end)

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  dependencies = {
    { "nushell/tree-sitter-nu", build = ":TSUpdate" },
  },
  event = { "BufReadPost", "BufNewFile" },
  cmd = { "TSInstall", "TSBufEnable", "TSBufDisable", "TSModuleInfo" },
  build = ":TSUpdate",
  opts = {
    ensure_installed = { "lua", "luadoc", "printf", "vim", "vimdoc" },

    highlight = {
      enable = true,
      use_languagetree = true,
    },

    indent = { enable = true },
  },
  config = {
    ensure_installed = {
      "vim",
      "lua",
      "vimdoc",
      "html",
      "css",
      "bash",
      "json",
      "yaml",
      "toml",
      "nu",
      "ini",
      "dockerfile",
      "markdown",
      "markdown_inline",
      "cpp",
      "go",
      -- "latex",
      "pascal",
      "php",
      "rust",
      "sql",
      "lua",
      "javascript",
      "typescript",
      "nginx",
      "python",
      "java",
      "c",
      "c_sharp",
      "comment",
    },
  },
}
