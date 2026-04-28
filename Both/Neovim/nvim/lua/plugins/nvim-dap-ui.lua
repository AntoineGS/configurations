return {
  "rcarriga/nvim-dap-ui",
  dependencies = {
    "mfussenegger/nvim-dap",
    "nvim-neotest/nvim-nio",
  },
  config = function()
    local dap, dapui = require "dap", require "dapui"
    dapui.setup()

    dap.listeners.before.attach.dapui_config = function() dapui.open() end
    dap.listeners.before.launch.dapui_config = function() dapui.open() end
    dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
    dap.listeners.before.event_exited.dapui_config = function() dapui.close() end

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
