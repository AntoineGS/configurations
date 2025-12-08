return {
  "leoluz/nvim-dap-go",
  lazy = false,
  dependencies = { "mfussenegger/nvim-dap" },
  config = function()
    require("dap-go").setup {
      -- dap_configurations = {
      --   {
      --     type = "go",
      --     name = "Debug",
      --     request = "launch",
      --     program = "${workspaceFolder}/backend/cmd/api",
      --     cwd = "${workspaceFolder}/backend",
      --     buildFlags = "-gcflags='all=-N -l'",
      --   },
      --   {
      --     type = "go",
      --     name = "Debug Package",
      --     request = "launch",
      --     program = "${fileDirname}",
      --   },
      -- },
      -- -- delve configurations
      -- delve = {
      --   path = "dlv",
      --   initialize_timeout_sec = 20,
      --   port = "${port}",
      --   args = {},
      --   build_flags = "-gcflags='all=-N -l'",
      -- },
    }
  end,
}
