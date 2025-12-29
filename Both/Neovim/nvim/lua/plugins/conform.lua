return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre", -- uncomment for format on save
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        css = { "prettierd" },
        html = { "prettierd" },
        javascript = { "deno_fmt" },
        json = { "deno_fmt" },
        markdown = { "deno_fmt" },
        scss = { "prettierd" },
        typescript = { "deno_fmt" },
        yaml = { "prettierd" },
        vue = { "prettierd" },
        angular = { "prettierd" },
        flow = { "prettierd" },
        graphql = { "prettierd" },
        less = { "prettierd" },
        jsx = { "prettierd" },
        bash = { "shfmt" },
        sh = { "shfmt" },
        zsh = { "beautysh" },
        --sql = { "sqlfmt" },
        toml = { "prettierd" },
        nu = { "prettierd" },
        clang = { "clang-format" },
        go = { "gofmt", "goimports" },
        python = { "black" },
        tex = { "tex-fmt" },
      },

      format_on_save = {
        -- These options will be passed to conform.format()
        timeout_ms = 2000,
        lsp_fallback = true,
      },
    },
  },
}
