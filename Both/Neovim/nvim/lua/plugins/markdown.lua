return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" }, -- if you use the mini.nvim suite
  -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
  -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
  init = function()
    -- Catppuccin Mocha colors
    local color1_bg = "#cba6f7" -- mauve
    local color2_bg = "#f38ba8" -- red
    local color3_bg = "#fab387" -- peach
    local color4_bg = "#a6e3a1" -- green
    local color5_bg = "#89b4fa" -- blue
    local color6_bg = "#94e2d5" -- teal
    local color_fg = "#1e1e2e" -- base

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
  opts = {
    file_types = { "markdown", "Avante" },
    render_modes = { "n", "i", "c", "t" },
    preset = "lazy",
  },
  ft = { "markdown", "Avante" },
}
