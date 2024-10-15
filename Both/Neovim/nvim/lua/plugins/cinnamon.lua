return {
  "declancm/cinnamon.nvim",
  version = "*", -- use latest release
  opts = {
    -- change default options here
  },
  lazy = false,
  config = function()
    require("cinnamon").setup({
        keymaps = {
        basic = true,
        extra = true,
        },
    })
  end,
}
