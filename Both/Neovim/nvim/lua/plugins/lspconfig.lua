local M = {}
local map = vim.keymap.set
local pascal_project = require "pascal_project"

-- export on_attach & capabilities
M.on_attach = function(client, bufnr)
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

  if client and client.name == "sqls" then
    require("sqls_parameters").attach(client, bufnr)
    vim.api.nvim_buf_create_user_command(bufnr, "SqlsExplain", function(args)
      require("sqls.commands").exec(
        client.id,
        "explainQuery",
        args.smods,
        args.range ~= 0,
        nil,
        args.line1,
        args.line2,
        bufnr
      )
    end, { range = true, desc = "Explain SQL without executing it" })
    vim.api.nvim_buf_create_user_command(bufnr, "SqlsCancel", function()
      for id, request in pairs(client.requests) do
        if request.type == "pending" and request.method == "workspace/executeCommand" then
          client:cancel_request(id)
        end
      end
    end, { desc = "Cancel pending sqls commands" })

    require("which-key").add { { "<leader>S", group = "sqls", buffer = bufnr } }
    map("n", "<leader>Sq", "<cmd>SqlsExecuteQuery<cr>", opts "SQL execute buffer")
    map("x", "<leader>Sq", ":SqlsExecuteQuery<cr>", opts "SQL execute selected lines")
    map("n", "<leader>Sc", "<cmd>SqlsSwitchConnection<cr>", opts "SQL switch connection")
    map("n", "<leader>Sl", "<cmd>SqlsShowConnections<cr>", opts "SQL list connections")
    map("n", "<leader>St", "<cmd>SqlsShowTables<cr>", opts "SQL list tables")
    map("n", "<leader>Se", "<cmd>SqlsExplain<cr>", opts "SQL explain buffer")
    map("x", "<leader>Se", ":SqlsExplain<cr>", opts "SQL explain selected lines")
    map("n", "<leader>Sx", "<cmd>SqlsCancel<cr>", opts "SQL cancel")
    map("n", "<leader>Sk", vim.lsp.buf.signature_help, opts "SQL signature help")
  end
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
    virtual_lines = false,
    signs = { text = { [x.ERROR] = "󰅙", [x.WARN] = "", [x.INFO] = "󰋼", [x.HINT] = "󰌵" } },
    underline = true,
    float = { border = "single" },
  }

  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      M.on_attach(client, args.buf)
      if client and client.name == "pascal_lsp" then
        pascal_project.attach(client, args.buf)
      end
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
  vim.lsp.enable "golangci_lint_ls"
  vim.lsp.enable "rust_analyzer"
  vim.lsp.enable "vtsls"
  if vim.fn.has "linux" == 1 then
    -- Use the local InterBase-enabled build instead of Mason's sqls.
    vim.lsp.config("sqls", {
      cmd = {
        vim.fn.expand "~/gits/sqls/sqls",
        "--config",
        vim.fn.expand "~/.config/sqls/config.yml",
      },
      commands = {
        executeQuery = function(command, context)
          require("sqls_parameters").code_action(command, context)
        end,
        explainQuery = function(_, context)
          require("sqls.commands").exec(context.client_id, "explainQuery")
        end,
      },
      on_exit = function(_, _, client_id)
        require("sqls_parameters").clear(client_id)
      end,
    })
  end
  vim.lsp.enable "sqls"
  vim.lsp.enable "intelephense"

  -- Native Pascal LSP installed with cargo; independent of RAD Studio and PATH.
  local pascal_lsp = vim.fn.expand "~/.cargo/bin/pascal-lsp"
  if vim.fn.has "win32" == 1 then
    pascal_lsp = pascal_lsp .. ".exe"
  end
  vim.lsp.config("pascal_lsp", {
    cmd = { pascal_lsp, "--stdio" },
    filetypes = { "pascal" },
    root_markers = { ".lint4d.toml", ".git" },
  })
  vim.lsp.enable "pascal_lsp"
end

return {
  "neovim/nvim-lspconfig",
  dependencies = { "nanotee/sqls.nvim" },
  event = "User FilePost",
  config = function()
    M.defaults()
  end,
}
