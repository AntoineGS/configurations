return {
  "rcarriga/nvim-dap-ui",
  dependencies = {
    "mfussenegger/nvim-dap",
    "nvim-neotest/nvim-nio",
  },
  config = function()
    local dap, dapui = require "dap", require "dapui"
    dapui.setup()

    local saved_layout
    local function open_ui()
      if not saved_layout then
        saved_layout = {
          win = vim.api.nvim_get_current_win(),
          windows = vim.api.nvim_tabpage_list_wins(0),
          restore = vim.fn.winrestcmd(),
        }
      end
      dapui.open()
    end

    local function close_ui()
      dapui.close()
      local layout = saved_layout
      saved_layout = nil -- Both exited and terminated may fire for one session.
      if layout and vim.api.nvim_win_is_valid(layout.win) then
        vim.api.nvim_win_call(layout.win, function()
          -- Window numbers in winrestcmd are only safe for the original layout.
          if vim.deep_equal(layout.windows, vim.api.nvim_tabpage_list_wins(0)) then
            vim.cmd(layout.restore)
          end
        end)
      end
    end

    dap.listeners.before.attach.dapui_config = open_ui
    dap.listeners.before.launch.dapui_config = open_ui
    dap.listeners.before.event_terminated.dapui_config = close_ui
    dap.listeners.before.event_exited.dapui_config = close_ui

    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "dapui_scopes", "dapui_stacks", "dapui_watches", "dapui_breakpoints" },
      callback = function(args)
        vim.keymap.set("n", "<CR>", "o", { buffer = args.buf, remap = true, silent = true })
      end,
    })
  end,
  -- stylua: ignore
  keys = {
    { "<leader>du", function() require("dapui").toggle() end, desc = "Toggle DAP UI" },
    { "<leader>de", function() require("dapui").eval() end, desc = "Eval expression", mode = { "n", "v" } },
  },
}
