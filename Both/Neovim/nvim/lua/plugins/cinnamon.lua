return {
  "declancm/cinnamon.nvim",
  version = "*", -- use latest release
  opts = {
    -- change default options here
  },
  lazy = false,
  cond = not vim.g.vscode,
  config = function()
    require("cinnamon").setup({
        keymaps = {
        basic = true,
        extra = true,
        },
    })
  end,
}
