local M = {}

-- Project-wide linters keyed by filetype. Output is parsed into the quickfix list with `errorformat`,
-- so file paths must be absolute or the parsed entries point at the wrong files.
local linters = {
  go = {
    title = "golangci-lint",
    root_markers = { "go.mod", ".git" },
    cmd = {
      "golangci-lint",
      "run",
      "--path-mode=abs",
      "--output.text.print-issued-lines=false",
      "--output.text.colors=false",
      "--show-stats=false",
      "./...",
    },
    errorformat = "%f:%l:%c: %m,%f:%l: %m",
    -- golangci-lint exits with 1 when it reports issues.
    ok_codes = { 0, 1 },
  },
}

function M.run()
  local filetype = vim.bo.filetype
  local linter = linters[filetype]
  if not linter then
    vim.notify("No project linter configured for filetype '" .. filetype .. "'", vim.log.levels.WARN)
    return
  end
  if vim.fn.executable(linter.cmd[1]) == 0 then
    vim.notify(linter.cmd[1] .. " is not installed", vim.log.levels.ERROR)
    return
  end

  local root = vim.fs.root(0, linter.root_markers) or vim.fn.getcwd()
  vim.notify(linter.title .. " running in " .. root)
  vim.system(linter.cmd, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if not vim.tbl_contains(linter.ok_codes, result.code) then
        vim.notify(
          linter.title .. " failed (exit " .. result.code .. "):\n" .. (result.stderr or ""),
          vim.log.levels.ERROR
        )
        return
      end

      local lines = vim.split(result.stdout or "", "\n", { trimempty = true })
      vim.fn.setqflist({}, " ", { title = linter.title, lines = lines, efm = linter.errorformat })
      local issues = vim.tbl_filter(function(item)
        return item.valid == 1
      end, vim.fn.getqflist())
      if #issues == 0 then
        vim.notify(linter.title .. ": no issues")
        return
      end
      Snacks.picker.qflist()
    end)
  end)
end

return M
