return {
  "nvchad/base46",
  lazy = false,
  build = function()
    require("base46").load_all_highlights()
  end,
  config = function()
    -- Apply transparency after base46 loads
    vim.schedule(function()
      local transparent_groups = {
        "Normal",
        "NormalNC",
        -- "SignColumn",
        "EndOfBuffer",
        "LineNr",
        "Folded",
        "FoldColumn",
        "VertSplit",
        "StatusLine",
        "StatusLineNC",
        "CursorLine",
        "CursorLineNr",
        -- "TabLine",
        -- "TabLineFill",
        "NormalFloat",
        "ColorColumn",
      }

      for _, group in ipairs(transparent_groups) do
        vim.api.nvim_set_hl(0, group, { bg = "NONE", ctermbg = "NONE" })
      end

      -- Set active tab with colored background
      -- vim.api.nvim_set_hl(0, "TabLineSel", { bg = "#434256" })

      -- Make NvChad statusline base background transparent (keep colored sections)
      -- Groups with #22262e background (base/separator background)
      local statusline_bg_groups = {
        "StatusLine",
        "St_LspInfo",
        "St_LspHints",
        "St_lspWarning",
        "St_lspError",
        "St_cwd_sep",
        "St_file_sep",
        "St_LspMsg",
        "St_Lsp",
        "St_gitIcons",
      }

      for _, group in ipairs(statusline_bg_groups) do
        local hl = vim.api.nvim_get_hl(0, { name = group })
        if hl and hl.fg then
          hl.bg = nil
          hl.ctermbg = nil
          vim.api.nvim_set_hl(0, group, hl)
        elseif hl then
          vim.api.nvim_set_hl(0, group, { bg = "NONE", ctermbg = "NONE" })
        end
      end
    end)
  end,
}
