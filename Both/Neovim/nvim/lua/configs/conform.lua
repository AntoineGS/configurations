return {
  formatters_by_ft = {
    lua = { "stylua" },
    css = { "prettierd" },
    html = { "prettierd" },
    javascript = { "prettierd" },
    json = { "prettierd" },
    markdown = { "prettierd" },
    scss = { "prettierd" },
    typescript = { "prettierd" },
    yaml = { "prettierd" },
    vue = { "prettierd" },
    angular = { "prettierd" },
    flow = { "prettierd" },
    graphql = { "prettierd" },
    less = { "prettierd" },
    jsx = { "prettierd" },
    bash = { "shfmt" },
    sh = { "shfmt" },
    zsh = { "shfmt" },
    sql = { "sqlfmt" },
    toml = { "prettierd" },
    nu = { "prettierd" },
    clang = { "clang-format" },
  },

  format_on_save = {
    -- These options will be passed to conform.format()
    timeout_ms = 500,
    lsp_fallback = true,
  },
}
