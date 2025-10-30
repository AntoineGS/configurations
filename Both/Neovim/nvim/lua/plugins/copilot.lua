local logger_conf = {}
local src = {}
local os = vim.loop.os_uname()

if vim.fn.hostname() == "DESKTOP-E07VTRN" then
  logger_conf = {
    file_log_level = vim.log.levels.TRACE,
    print_log_level = vim.log.levels.WARN,
    trace_lsp = "verbose",
    log_lsp_messages = true,
    trace_lsp_progress = true,
  }
end

if os.sysname == "Windows_NT" then
  src = {
    dir = "C:/Gits/copilot.lua",
    dependencies = {
      dir = "C:/Gits/copilot-lsp",
    },
  }
else
  src = {
    "zbirenbaum/copilot.lua",
    dependencies = {
      "copilotlsp-nvim/copilot-lsp",
    },
  }
end

return vim.tbl_deep_extend("force", src, {
  cmd = "Copilot",
  event = "InsertEnter",
  config = function()
    require("copilot").setup {
      trace = "verbose",
      -- copilot_model = "gpt-4o-copilot",
      logger = logger_conf,
      -- panel = {
      --   enabled = true,
      --   auto_refresh = true,
      --   keymap = {
      --     open = false,
      --   },
      -- },
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = "<C-p>",
          accept_word = "<M-p>",
          accept_line = "<M-P>",
          -- accept = "<TAB>",
          next = "<M-]>",
          prev = "<M-[>",
          -- dismiss = "<C-c>",
        },
      },
      nes = {
        enabled = false,
        auto_trigger = true,
        keymap = {
          -- accept_and_goto = false,
          -- accept = "<leader>p",
          accept_and_goto = "<leader>p",
          accept = false,
          dismiss = "<Esc>",
        },
      },
      filetypes = {
        ["*"] = true,
      },
      should_attach = function(_, bufname)
        local logger = require "copilot.logger"

        if string.match(bufname, ".*copilot-lua\\.log") then
          logger.debug("not attaching, buffer name is " .. bufname)
          return false
        end

        if not vim.bo.buflisted then
          logger.debug "not attaching, buffer is not 'buflisted'"
          return false
        end

        if vim.bo.buftype ~= "" then
          logger.debug("not attaching, buffer 'buftype' is " .. vim.bo.buftype)
          return false
        end

        return true
      end,
      server = {
        -- type = "nodejs",
        type = "binary",
        -- custom_server_filepath = "C:\\Users\\antoi\\AppData\\Local\\nvim-data\\lazy\\copilot.lua\\copilot\\js_2\\language-server.js",
      },
      -- auth_provider_url = "https://someurl.com",
      -- lsp_binary = "C:\\Users\\antoi\\AppData\\Local\\nvim-data\\lazy\\copilot.lua\\copilot\\copilot-language-server.exe",
    }
  end,

  -- stylua: ignore
  keys = { { "<leader>cp", function() require("copilot.panel").toggle() end, mode = "n", desc = "Toggle the Copilot panel", }, },
})
