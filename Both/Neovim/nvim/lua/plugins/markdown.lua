return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" }, -- if you use the mini.nvim suite
  -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
  -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
  init = function()
    -- Define color variables
    local color1_bg = "#c678dd"
    local color2_bg = "#e06c75"
    local color3_bg = "#d19a66"
    local color4_bg = "#98c379"
    local color5_bg = "#61afef"
    local color6_bg = "#56b6c2"
    local color_fg = "#1e2127"

    -- Heading colors (when not hovered over), extends through the entire line
    vim.cmd(string.format([[highlight RenderMarkdownH1Bg guifg=%s guibg=%s]], color_fg, color1_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH2Bg guifg=%s guibg=%s]], color_fg, color2_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH3Bg guifg=%s guibg=%s]], color_fg, color3_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH4Bg guifg=%s guibg=%s]], color_fg, color4_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH5Bg guifg=%s guibg=%s]], color_fg, color5_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH6Bg guifg=%s guibg=%s]], color_fg, color6_bg))

    vim.cmd(string.format([[highlight RenderMarkdownH1 cterm=bold gui=bold guifg=%s]], color1_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH2 cterm=bold gui=bold guifg=%s]], color2_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH3 cterm=bold gui=bold guifg=%s]], color3_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH4 cterm=bold gui=bold guifg=%s]], color4_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH5 cterm=bold gui=bold guifg=%s]], color5_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH6 cterm=bold gui=bold guifg=%s]], color6_bg))
  end,
  opts = {},
  ft = "markdown",
}
