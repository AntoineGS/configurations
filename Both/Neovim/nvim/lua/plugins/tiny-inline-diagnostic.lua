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
        overflow = {
          mode = "wrap", -- "wrap": split into lines, "none": no truncation, "oneline": keep single line
          padding = 0, -- Extra characters to trigger wrapping earlier
        },
      },
    }
  end,
}
