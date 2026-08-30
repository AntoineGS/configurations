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
