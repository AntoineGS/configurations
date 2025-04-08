return {
  "jbyuki/one-small-step-for-vimkind",
  dependencies = {
    "mfussenegger/nvim-dap",
  },
  opts = {}, -- for default options, refer to the configuration section for custom setup.
  config = function(_, _) end,
  keys = {
    {
      "<leader>dll",
      function()
        require("osv").launch { port = 8086 }
      end,
      desc = "Launch Lua DAP",
    },
  },
}
