-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()
require("lspconfig").nushell.setup {}

local lspconfig = require "lspconfig"

local servers = {
  "html",
  "cssls",
  "powershell_es",
  "pyright",
  "docker_compose_language_service",
  "bashls",
  -- "ltex",
  "spectral",
  "marksman",
}
local nvlsp = require "nvchad.configs.lspconfig"

-- lsps with default config
for _, lsp in ipairs(servers) do
  lspconfig[lsp].setup {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  }
end

-- configuring single server, example: typescript
-- lspconfig.ts_ls.setup {
--   on_attach = nvlsp.on_attach,
--   on_init = nvlsp.on_init,
--   capabilities = nvlsp.capabilities,
-- }
