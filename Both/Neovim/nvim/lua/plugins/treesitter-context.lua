-- if local dir exists use it, otherwise use the one from github
local local_dir = vim.fn.expand "~/gits/nvim-treesitter-context"
local src = vim.fn.isdirectory(local_dir) == 1 and { dir = local_dir } or { "AntoineGS/nvim-treesitter-context" }

return vim.tbl_extend("force", src, {
  event = { "BufReadPost", "BufNewFile" },
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  opts = {
    mode = "topline",
  },
  config = function(_, opts)
    require("treesitter-context").setup(opts)

    -- Default links to NormalFloat, which is transparent here and blends with the buffer
    local colors = require("base46").get_theme_tb "base_30"
    vim.api.nvim_set_hl(0, "TreesitterContext", { bg = colors.one_bg })
    vim.api.nvim_set_hl(0, "TreesitterContextLineNumber", { fg = colors.light_grey, bg = colors.one_bg })
    vim.api.nvim_set_hl(0, "TreesitterContextBottom", { underline = true, sp = colors.grey_fg2 })
    vim.api.nvim_set_hl(0, "TreesitterContextLineNumberBottom", { underline = true, sp = colors.grey_fg2 })
  end,
  keys = {
    -- [c is kept for diff hunks
    {
      "[x",
      function()
        require("treesitter-context").go_to_context(vim.v.count1)
      end,
      desc = "Go to treesitter context",
    },
    { "<leader>tc", "<cmd>TSContext toggle<cr>", desc = "Toggle treesitter context" },
  },
})
