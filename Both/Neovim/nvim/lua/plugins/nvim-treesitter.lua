return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
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
    },
  },
  -- might be optional
  dependencies = {
    { "nushell/tree-sitter-nu", build = ":TSUpdate" },
  },
}
