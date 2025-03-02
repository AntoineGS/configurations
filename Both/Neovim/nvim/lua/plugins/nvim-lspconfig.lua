return {
  "neovim/nvim-lspconfig",
  dependencies = { "saghen/blink.cmp" },
  opts = {
    servers = {
      lua_ls = {},
      html = {},
      cssls = {},
      powershell_es = {},
      pyright = {},
      docker_compose_language_service = {},
      bashls = {},
      spectral = {},
      marksman = {},
    },
  },
  config = function(_, opts)
    local lspconfig = require "lspconfig"
    for server, config in pairs(opts.servers) do
      -- passing config.capabilities to blink.cmp merges with the capabilities in your
      -- `opts[server].capabilities, if you've defined it
      -- config.capabilities = require("blink.cmp").get_lsp_capabilities(config.capabilities)
      config.capabilities = require("blink.cmp").get_lsp_capabilities()
      lspconfig[server].setup(config)
    end
  end,
}
