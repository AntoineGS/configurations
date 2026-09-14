return {
  "folke/which-key.nvim",
  keys = { "<leader>", "<c-w>", '"', "'", "`", "c", "v", "g", "d" },
  cmd = "WhichKey",
  opts = function()
    dofile(vim.g.base46_cache .. "whichkey")
    return {
      layout = { width = { min = 20, max = 50 } },
      spec = {
        { "gx", desc = "Open file or URL", mode = { "n", "x" } },
      },
    }
  end,
}
