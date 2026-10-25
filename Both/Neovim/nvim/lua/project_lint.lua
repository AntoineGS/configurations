local M = {}

-- Directories the Go tool ignores, plus vendored and JS dependencies.
local function skip_go_dir(dir)
  local name = vim.fs.basename(dir)
  return not (name == "vendor" or name == "testdata" or name == "node_modules" or name:match "^[._]")
end

local function go_files(root)
  local files = {}
  for name, type in vim.fs.dir(root, { depth = math.huge, skip = skip_go_dir }) do
    if type == "file" and name:match "%.go$" then
      files[#files + 1] = vim.fs.joinpath(root, name)
    end
  end
  return files
end

-- Project-wide linters keyed by filetype; every linter of a filetype runs in parallel and their results are
-- merged into one quickfix list. Output is parsed with `errorformat`; relative paths are resolved against the
-- linter's root. `tag` is appended to messages that don't name their source, and `clean` normalizes messages
-- before duplicates are dropped.
local linters = {
  go = {
    {
      title = "golangci-lint",
      root_markers = { "go.mod", ".git" },
      cmd = function()
        return {
          "golangci-lint",
          "run",
          "--path-mode=abs",
          "--output.text.print-issued-lines=false",
          "--output.text.colors=false",
          "--show-stats=false",
          "./...",
        }
      end,
      -- Build failures add a "file:1: : # package" header line before the typecheck issues.
      errorformat = "%-G%f:%l: : # %.%#,%f:%l:%c: %m,%f:%l: %m",
      -- golangci-lint exits with 1 when it reports issues.
      ok_codes = { 0, 1 },
    },
    {
      -- gopls only analyzes packages with an open file; `gopls check` covers the rest of the project.
      title = "gopls",
      tag = "gopls",
      root_markers = { "go.mod", ".git" },
      cmd = function(root)
        return vim.list_extend({ "gopls", "check", "-severity=hint" }, go_files(root))
      end,
      errorformat = "%f:%l:%c-%e:%k: %m,%f:%l:%c-%k: %m,%f:%l:%c: %m",
      ok_codes = { 0 },
      -- gopls repeats a diagnostic for each build configuration, suffixing the copies with "[GOOS]".
      clean = function(text)
        return (text:gsub("%s*%[%w+%]$", ""))
      end,
    },
  },
}

local function parse(linter, root, stdout)
  local lines = vim.split(stdout or "", "\n", { trimempty = true })
  for i, line in ipairs(lines) do
    -- golangci-lint ignores --path-mode=abs for typecheck issues; quickfix would resolve them against the cwd.
    local file = line:match "^([^:%s][^:]*):%d+:"
    if file and vim.fn.isabsolutepath(file) == 0 then
      lines[i] = vim.fs.joinpath(root, line)
    end
  end
  local items = vim.fn.getqflist({ lines = lines, efm = linter.errorformat }).items
  local issues, seen = {}, {}
  for _, item in ipairs(items) do
    if item.valid == 1 then
      if linter.clean then
        item.text = linter.clean(item.text)
      end
      if linter.tag then
        item.text = item.text .. " (" .. linter.tag .. ")"
      end
      local key = table.concat({ item.bufnr, item.lnum, item.col, item.text }, ":")
      if not seen[key] then
        seen[key] = true
        issues[#issues + 1] = item
      end
    end
  end
  return issues
end

-- Shows the issues in the Snacks quickfix picker, or in the location list of `loclist_win` when it is set.
local function show(title, issues, loclist_win)
  if #issues == 0 then
    vim.notify(title .. ": no issues")
    return
  end
  table.sort(issues, function(a, b)
    local a_name, b_name = vim.api.nvim_buf_get_name(a.bufnr), vim.api.nvim_buf_get_name(b.bufnr)
    if a_name ~= b_name then
      return a_name < b_name
    end
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return a.col < b.col
  end)
  if loclist_win then
    if not vim.api.nvim_win_is_valid(loclist_win) then
      loclist_win = vim.api.nvim_get_current_win()
    end
    vim.fn.setloclist(loclist_win, {}, " ", { title = title, items = issues })
    vim.api.nvim_win_call(loclist_win, function()
      vim.cmd.lopen()
    end)
    return
  end
  vim.fn.setqflist({}, " ", { title = title, items = issues })
  Snacks.picker.qflist()
end

-- opts.loclist: show the results in the current window's location list instead of the picker.
function M.run(opts)
  opts = opts or {}
  local loclist_win = opts.loclist and vim.api.nvim_get_current_win() or nil
  local filetype = vim.bo.filetype
  local available = {}
  for _, linter in ipairs(linters[filetype] or {}) do
    local root = vim.fs.root(0, linter.root_markers) or vim.fn.getcwd()
    local cmd = linter.cmd(root)
    if vim.fn.executable(cmd[1]) == 1 then
      available[#available + 1] = { linter = linter, root = root, cmd = cmd }
    else
      vim.notify(cmd[1] .. " is not installed", vim.log.levels.WARN)
    end
  end
  if #available == 0 then
    vim.notify("No project linter available for filetype '" .. filetype .. "'", vim.log.levels.WARN)
    return
  end

  local titles = vim.tbl_map(function(run)
    return run.linter.title
  end, available)
  local title = table.concat(titles, ", ")
  vim.notify(title .. " running in " .. available[1].root)

  local issues = {}
  local pending = #available
  for _, run in ipairs(available) do
    vim.system(run.cmd, { cwd = run.root, text = true }, function(result)
      vim.schedule(function()
        if vim.tbl_contains(run.linter.ok_codes, result.code) then
          vim.list_extend(issues, parse(run.linter, run.root, result.stdout))
        else
          vim.notify(
            run.linter.title .. " failed (exit " .. result.code .. "):\n" .. (result.stderr or ""),
            vim.log.levels.ERROR
          )
        end
        pending = pending - 1
        if pending == 0 then
          show(title, issues, loclist_win)
        end
      end)
    end)
  end
end

return M
