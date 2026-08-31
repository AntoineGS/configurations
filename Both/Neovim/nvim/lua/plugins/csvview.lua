return {
  "hat0uma/csvview.nvim",
  ft = { "csv", "tsv" },
  cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle", "CsvViewInfo" },
  opts = {
    view = {
      display_mode = "border",
    },
  },
  config = function(_, opts)
    local csvview = require "csvview"
    csvview.setup(opts)
    vim.api.nvim_set_hl(0, "CsvViewCursorLine", { bg = "#313244" })

    local cursorline_ns = vim.api.nvim_create_namespace "csvview.cursorline"
    local cursor_row
    vim.api.nvim_set_decoration_provider(cursorline_ns, {
      on_win = function(_, winid, bufnr)
        if not csvview.is_enabled(bufnr) then
          return false
        end

        cursor_row = vim.api.nvim_win_get_cursor(winid)[1] - 1
      end,
      on_line = function(_, _, bufnr, row)
        if row ~= cursor_row then
          return
        end

        vim.api.nvim_buf_set_extmark(bufnr, cursorline_ns, row, 0, {
          end_row = row + 1,
          ephemeral = true,
          hl_eol = true,
          hl_group = "CsvViewCursorLine",
          hl_mode = "combine",
          priority = 200,
        })
      end,
    })

    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "csv", "tsv" },
      callback = function(args)
        if not csvview.is_enabled(args.buf) then
          csvview.enable(args.buf)
        end
      end,
    })
  end,
}
