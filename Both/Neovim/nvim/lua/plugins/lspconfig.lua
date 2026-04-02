local M = {}
local map = vim.keymap.set

-- export on_attach & capabilities
M.on_attach = function(_, bufnr)
  local function opts(desc)
    return { buffer = bufnr, desc = "LSP " .. desc }
  end

  map("n", "gD", vim.lsp.buf.declaration, opts "Go to declaration")
  map("n", "gd", vim.lsp.buf.definition, opts "Go to definition")
  map("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts "Add workspace folder")
  map("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts "Remove workspace folder")

  map("n", "<leader>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, opts "List workspace folders")

  map("n", "<leader>D", vim.lsp.buf.type_definition, opts "Go to type definition")
  map("n", "<leader>ra", require "nvchad.lsp.renamer", opts "NvRenamer")
end

M.capabilities = vim.lsp.protocol.make_client_capabilities()

M.capabilities.textDocument.completion.completionItem = {
  documentationFormat = { "markdown", "plaintext" },
  snippetSupport = true,
  preselectSupport = true,
  insertReplaceSupport = true,
  labelDetailsSupport = true,
  deprecatedSupport = true,
  commitCharactersSupport = true,
  tagSupport = { valueSet = { 1 } },
  resolveSupport = {
    properties = {
      "documentation",
      "detail",
      "additionalTextEdits",
    },
  },
}

M.defaults = function()
  dofile(vim.g.base46_cache .. "lsp")
  local x = vim.diagnostic.severity

  vim.diagnostic.config {
    virtual_text = false,
    virtual_lines = true,
    signs = { text = { [x.ERROR] = "󰅙", [x.WARN] = "", [x.INFO] = "󰋼", [x.HINT] = "󰌵" } },
    underline = true,
    float = { border = "single" },
  }

  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
      M.on_attach(_, args.buf)
    end,
  })

  local lua_lsp_settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      workspace = {
        library = {
          vim.fn.expand "$VIMRUNTIME/lua",
          vim.fn.expand "$VIMRUNTIME/lua/vim/lsp",
          vim.fn.stdpath "data" .. "/lazy/ui/nvchad_types",
          vim.fn.stdpath "data" .. "/lazy/lazy.nvim/lua/lazy",
          "${3rd}/luv/library",
          "./deps",
        },
        maxPreload = 100000,
        preloadFileSize = 10000,
      },
      diagnostics = {
        globals = { "vim" },
      },
    },
  }

  -- vim.lsp.config("*", { capabilities = M.capabilities, on_init = M.on_init })
  vim.lsp.config("*", { capabilities = M.capabilities })
  vim.lsp.config("lua_ls", { settings = lua_lsp_settings })
  vim.lsp.enable "lua_ls"
  vim.lsp.enable "pyright"
  vim.lsp.enable "html"
  vim.lsp.enable "cssls"
  vim.lsp.enable "powershell_es"
  vim.lsp.enable "docker_compose_language_service"
  vim.lsp.enable "bash-language-server"
  vim.lsp.enable "spectral"
  vim.lsp.enable "marksman"
  vim.lsp.enable "clangd"
  vim.lsp.enable "gopls"
  vim.lsp.enable "rust_analyzer"
  vim.lsp.enable "vtsls"
  vim.lsp.enable "sqls"
  vim.lsp.enable "intelephense"

  -- Delphi LSP (bundled with RAD Studio 13 Florence)
  vim.lsp.config("delphi_ls", {
    cmd = { "C:/Program Files (x86)/Embarcadero/Studio/37.0/bin/DelphiLSP.exe" },
    filetypes = { "pascal" },
    root_markers = { "*.dpr" },
    single_file_support = false,
    on_attach = function(client)
      local lsp_config = vim.fs.find(function(name)
        return name:match ".*%.delphilsp%.json$"
      end, { type = "file", path = client.config.root_dir, upward = false })[1]

      if lsp_config then
        client.config.settings = { settingsFile = lsp_config }
        client.notify("workspace/didChangeConfiguration", { settings = client.config.settings })
      else
        vim.notify_once(
          "delphi_ls: '*.delphilsp.json' config file not found in " .. client.config.root_dir,
          vim.log.levels.WARN
        )
      end
    end,
  })
  vim.lsp.enable "delphi_ls"
end

return {
  "neovim/nvim-lspconfig",
  event = "User FilePost",
  config = function()
    M.defaults()
  end,
}
