local skip_query

-- Display heading text in uppercase without changing the buffer. Only runs of non-punctuation characters are
-- overlaid so concealed markup (emphasis, link brackets, escapes) stays aligned; code and link targets are skipped.
local function uppercase_headings(ctx)
  local marks = {}
  local start_row, start_col, end_row, end_col = ctx.root:range()
  local node = vim.treesitter.get_node { bufnr = ctx.buf, pos = { start_row, start_col }, lang = "markdown" }
  local parent = node and node:parent()
  if parent and parent:type() == "paragraph" then
    parent = parent:parent()
  end
  if not parent or (parent:type() ~= "atx_heading" and parent:type() ~= "setext_heading") then
    return marks
  end

  skip_query = skip_query
    or vim.treesitter.query.parse(
      "markdown_inline",
      [[[(code_span) (link_destination) (link_label) (uri_autolink) (email_autolink) (html_tag)
        (entity_reference) (numeric_character_reference) (latex_block)] @skip]]
    )
  local skipped = {}
  for _, skip in skip_query:iter_captures(ctx.root, ctx.buf, start_row, end_row + 1) do
    skipped[#skipped + 1] = { skip:range() }
  end

  local lines = vim.api.nvim_buf_get_lines(ctx.buf, start_row, end_row + 1, false)
  for i, line in ipairs(lines) do
    local row = start_row + i - 1
    local text = line:sub(1, row == end_row and end_col or #line)
    local function mask(from, to)
      to = math.min(to, #text)
      text = text:sub(1, from) .. ("\0"):rep(to - from) .. text:sub(to + 1)
    end
    if row == start_row then
      mask(0, start_col)
    end
    for _, range in ipairs(skipped) do
      if range[1] <= row and row <= range[3] then
        mask(range[1] == row and range[2] or 0, range[3] == row and range[4] or #text)
      end
    end
    for col, run in text:gmatch "()([^%p%z]+)" do
      local upper = vim.fn.toupper(run)
      if upper ~= run and vim.fn.strdisplaywidth(upper) == vim.fn.strdisplaywidth(run) then
        marks[#marks + 1] = {
          conceal = true,
          start_row = row,
          start_col = col - 1,
          opts = { virt_text = { { upper } }, virt_text_pos = "overlay", hl_mode = "combine" },
        }
      end
    end
  end
  return marks
end

return {
  "MeanderingProgrammer/render-markdown.nvim",
  -- Temporary performance worktree; remove this dir override to use the installed version.
  dir = vim.fn.expand "~/gits/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" }, -- if you use the mini.nvim suite
  -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
  -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
  init = function()
    -- Catppuccin Mocha colors
    local color1 = "#f38ba8" -- red
    local color2 = "#cba6f7" -- mauve
    local color3 = "#94e2d5" -- teal
    local color4 = "#a6e3a1" -- green
    local color5 = "#89b4fa" -- blue
    local color6 = "#f9e2af" -- yellow

    -- Each accent blended 15% over base (#1e1e2e)
    local color1_bg = "#3e2e40"
    local color2_bg = "#38324c"
    local color3_bg = "#303b47"
    local color4_bg = "#323c3f"
    local color5_bg = "#2e344d"
    local color6_bg = "#3f3b41"

    -- Heading colors (when not hovered over), extends through the entire line
    vim.cmd(string.format([[highlight RenderMarkdownH1Bg cterm=bold gui=bold guifg=%s guibg=%s]], color1, color1_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH2Bg cterm=bold gui=bold guifg=%s guibg=%s]], color2, color2_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH3Bg cterm=bold gui=bold guifg=%s guibg=%s]], color3, color3_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH4Bg cterm=bold gui=bold guifg=%s guibg=%s]], color4, color4_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH5Bg cterm=bold gui=bold guifg=%s guibg=%s]], color5, color5_bg))
    vim.cmd(string.format([[highlight RenderMarkdownH6Bg cterm=bold gui=bold guifg=%s guibg=%s]], color6, color6_bg))

    vim.cmd(string.format([[highlight RenderMarkdownH1 cterm=bold gui=bold guifg=%s]], color1))
    vim.cmd(string.format([[highlight RenderMarkdownH2 cterm=bold gui=bold guifg=%s]], color2))
    vim.cmd(string.format([[highlight RenderMarkdownH3 cterm=bold gui=bold guifg=%s]], color3))
    vim.cmd(string.format([[highlight RenderMarkdownH4 cterm=bold gui=bold guifg=%s]], color4))
    vim.cmd(string.format([[highlight RenderMarkdownH5 cterm=bold gui=bold guifg=%s]], color5))
    vim.cmd(string.format([[highlight RenderMarkdownH6 cterm=bold gui=bold guifg=%s]], color6))
  end,
  opts = {
    file_types = { "markdown", "Avante" },
    render_modes = { "n", "i", "c", "t" },
    preset = "lazy",
    heading = {
      -- Outline numbering starting at H2 (1, 1.1, 1.1.1, ...); H1 stays unnumbered
      icons = function(ctx)
        if ctx.level == 1 then
          return ""
        end
        return table.concat(ctx.sections, ".", 2) .. " "
      end,
      position = "inline",
      -- width = { "full", "full", "block" },
    },
    custom_handlers = {
      markdown_inline = { extends = true, parse = uppercase_headings },
    },
  },
  ft = { "markdown", "Avante" },
}
