return {
  "nvim-neotest/neotest",
  ft = "go",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
    "fredrikaverpil/neotest-golang",
  },
  config = function()
    require("neotest").setup {
      adapters = {
        require "neotest-golang" {
          go_test_args = { "-v", "-count=1" },
        },
      },
    }
  end,
  -- stylua: ignore
  keys = {
    { "<leader>tt", function() require("neotest").run.run() end, desc = "Run nearest test" },
    { "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run file tests" },
    { "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug nearest test" },
    { "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Toggle test summary" },
    { "<leader>to", function() require("neotest").output.open({ enter = true }) end, desc = "Show test output" },
    { "<leader>tO", function() require("neotest").output_panel.toggle() end, desc = "Toggle output panel" },
    { "<leader>tS", function() require("neotest").run.stop() end, desc = "Stop test" },
  },
}
