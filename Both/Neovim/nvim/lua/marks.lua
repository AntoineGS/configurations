--- Custom mark API.
--- Implementation slightly inspired by https://github.com/chentoast/marks.nvim, but this is
--- much simpler.

--- Map of mark information per buffer.
---@type table<integer, table<string, {line: integer, id: integer}>>
local marks = {}

--- Namespace for extmarks
local ns_id = vim.api.nvim_create_namespace("marks_signs")

--- The autocommand group name.
local sign_group_name = "mariasolos/marks_signs"

---@param mark string
---@return boolean
local function is_lowercase_mark(mark)
  return 97 <= mark:byte() and mark:byte() <= 122
end

---@param mark string
---@return boolean
local function is_uppercase_mark(mark)
  return 65 <= mark:byte() and mark:byte() <= 90
end

---@param mark string
---@return boolean
local function is_letter_mark(mark)
  return is_lowercase_mark(mark) or is_uppercase_mark(mark)
end

---@param mark string
---@param bufnr integer
local function delete_mark(mark, bufnr)
  local buffer_marks = marks[bufnr]
  if not buffer_marks or not buffer_marks[mark] then
    return
  end

  -- Remove the extmark.
  vim.api.nvim_buf_del_extmark(bufnr, ns_id, buffer_marks[mark].id)
  buffer_marks[mark] = nil

  -- Remove the mark.
  vim.cmd("delmarks " .. mark)
end

---@param mark string
---@param bufnr integer
---@param line? integer
local function register_mark(mark, bufnr, line)
  if not marks[bufnr] then
    marks[bufnr] = {}
  end
  local buffer_marks = marks[bufnr]

  if buffer_marks[mark] then
    -- Mark already exists, remove it first.
    delete_mark(mark, bufnr)
  end

  line = line or vim.api.nvim_win_get_cursor(0)[1]

  -- Create the extmark with sign.
  local id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line - 1, 0, {
    sign_text = mark,
    sign_hl_group = "DiagnosticOk",
    priority = 10,
  })

  buffer_marks[mark] = { line = line, id = id }
end

---@param bufnr integer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "m", "", {
    desc = "Add mark",
    callback = function()
      local ok, mark = pcall(function()
        return vim.fn.getcharstr()
      end)
      if not ok or not is_letter_mark(mark) then
        return
      end

      register_mark(mark, bufnr)
      vim.cmd("normal! m" .. mark)
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "dm", "", {
    desc = "Delete mark",
    callback = function()
      local ok, mark = pcall(function()
        return vim.fn.getcharstr()
      end)
      if not ok or not is_letter_mark(mark) then
        return
      end

      delete_mark(mark, bufnr)
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "dm-", "", {
    desc = "Delete all buffer marks",
    callback = function()
      marks[bufnr] = {}
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      vim.cmd "delmarks!"
    end,
  })
end

-- Set up autocommands to refresh the signs.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup(sign_group_name, { clear = true }),
  callback = function(args)
    local bufnr = args.buf
    -- Only handle normal buffers.
    if vim.bo[bufnr].bt ~= "" then
      return
    end

    -- Set custom mappings.
    set_keymaps(bufnr)

    if not marks[bufnr] then
      marks[bufnr] = {}
    end

    -- Remove all marks that were deleted.
    for mark, _ in pairs(marks[bufnr]) do
      if vim.api.nvim_buf_get_mark(bufnr, mark)[1] == 0 then
        delete_mark(mark, bufnr)
      end
    end

    -- Register the letter marks.
    for _, data in ipairs(vim.fn.getmarklist()) do
      local mark = data.mark:sub(2, 3)
      local mark_buf, mark_line = unpack(data.pos)
      local cached_mark = marks[bufnr][mark]

      if mark_buf == bufnr and is_uppercase_mark(mark) and (not cached_mark or mark_line ~= cached_mark.line) then
        register_mark(mark, bufnr, mark_line)
      end
    end
    for _, data in ipairs(vim.fn.getmarklist "%") do
      local mark = data.mark:sub(2, 3)
      local mark_line = data.pos[2]
      local cached_mark = marks[bufnr][mark]

      if is_lowercase_mark(mark) and (not cached_mark or mark_line ~= cached_mark.line) then
        register_mark(mark, bufnr, mark_line)
      end
    end
  end,
})

-- Set up keymaps for the current buffer on module load
vim.schedule(function()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].bt == "" then
    marks[bufnr] = {}
    set_keymaps(bufnr)
  end
end)
