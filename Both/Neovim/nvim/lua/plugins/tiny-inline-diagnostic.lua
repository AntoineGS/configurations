return {
  "rachartier/tiny-inline-diagnostic.nvim",
  event = "VeryLazy",
  priority = 1000,
  opts = {},
  config = function()
    require("tiny-inline-diagnostic").setup {
      options = {
        multilines = {
          enabled = true,
        },
        show_diags_only_under_cursor = false,
      },
    }
  end,
}
