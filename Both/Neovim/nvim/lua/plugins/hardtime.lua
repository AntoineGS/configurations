return {
  "m4xshen/hardtime.nvim",
  lazy = true,
  dependencies = { "MunifTanjim/nui.nvim" },
  opts = {},
  config = function()
    require("hardtime").setup()
  end,
}
