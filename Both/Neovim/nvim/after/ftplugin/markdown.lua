vim.opt_local.tabstop = 2
vim.opt_local.softtabstop = 2
vim.opt_local.shiftwidth = 2

-- gf on a markdown link opens the target file and jumps to the line.
-- Accepts `path#L12`, `path#L12-L20` and `path:12` targets. Relative paths
-- resolve from the markdown file's directory. Falls back to native gF when the
-- cursor line has no link.
local function follow_link()
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col "."
  local target

  -- Prefer the link under the cursor, otherwise the first link on the line.
  for s, t, e in line:gmatch "()%b[]%((.-)%)()" do
    if col >= s and col < e then
      target = t
      break
    end
    target = target or t
  end
  if not target then
    return vim.cmd "normal! gF"
  end

  local path, lnum = target:match "^(.-)#L(%d+)"
  if not path then
    path, lnum = target:match "^(.-):(%d+)$"
  end
  path = path or target

  local full = path
  if not path:match "^/" then
    full = vim.fn.fnamemodify(vim.fn.expand "%:p:h" .. "/" .. path, ":p")
  end
  if vim.fn.filereadable(full) == 0 then
    return vim.notify("Not found: " .. full, vim.log.levels.WARN)
  end

  vim.cmd.edit(vim.fn.fnameescape(full))
  if lnum then
    local n = math.min(tonumber(lnum), vim.api.nvim_buf_line_count(0))
    vim.api.nvim_win_set_cursor(0, { n, 0 })
    vim.cmd "normal! zz"
  end
end

vim.keymap.set("n", "gf", follow_link, { buffer = true, desc = "Follow markdown link to file and line" })
