-- vim.opt.termguicolors = true

return {
  "akinsho/bufferline.nvim",
  lazy = false,
  version = "*",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    require("bufferline").setup {
      options = {
        -- separator_style = "slope",
        hover = {
          enabled = true,
          delay = 200,
          reveal = { "close" },
        },
      },
      highlights = {
        fill = {
          bg = "NONE",
        },
        background = {
          bg = "NONE",
        },
        buffer_visible = {
          bg = "NONE",
          italic = true,
        },
        buffer_selected = {
          fb = "#A6A6B8",
          bg = "#434256",
          bold = true,
          italic = false,
        },
        separator = {
          fg = "NONE",
          bg = "NONE",
        },
        separator_visible = {
          fg = "NONE",
          bg = "NONE",
        },
        separator_selected = {
          fg = "NONE",
          bg = "NONE",
        },
        close_button = {
          bg = "NONE",
        },
        close_button_visible = {
          bg = "NONE",
        },
        close_button_selected = {
          bg = "#434256",
        },
        modified = {
          bg = "NONE",
        },
        modified_visible = {
          bg = "NONE",
        },
        modified_selected = {
          bg = "#434256",
        },
        offset_separator = {
          bg = "NONE",
        },
      },
    }
  end,
}
