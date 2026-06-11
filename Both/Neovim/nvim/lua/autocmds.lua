local autocmd = vim.api.nvim_create_autocmd

-- Backups: timestamp 'backupext' before each write so saves don't overwrite the previous backup.
-- Companion to the backup config in options.lua.
autocmd("BufWritePre", {
  callback = function()
    vim.opt.backupext = "~" .. os.date "%Y-%m-%d_%H-%M-%S"
  end,
})

-- Prune backups older than 14 days. Runs once per session, deferred so it doesn't slow startup.
autocmd("VimEnter", {
  callback = function()
    vim.schedule(function()
      local dir = vim.fn.stdpath "state" .. "/backup"
      local cutoff = os.time() - 14 * 24 * 60 * 60
      local handle = vim.uv.fs_scandir(dir)
      if not handle then return end
      while true do
        local name, ftype = vim.uv.fs_scandir_next(handle)
        if not name then break end
        if ftype == "file" then
          local path = dir .. "/" .. name
          local stat = vim.uv.fs_stat(path)
          if stat and stat.mtime.sec < cutoff then
            vim.uv.fs_unlink(path)
          end
        end
      end
    end)
  end,
})

-- Handle OneDrive (or other sync tools) touching file timestamps without changing content.
-- Track file state ourselves since checktime is blocked inside autocommands (autocmd_busy).
local function track_file_state(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename == "" then return end
  local stat = vim.uv.fs_stat(filename)
  if stat then
    vim.b[bufnr]._file_stat = { mtime_s = stat.mtime.sec, size = stat.size }
  end
end

autocmd("BufReadPost", {
  callback = function(args) track_file_state(args.buf) end,
})

autocmd("FileChangedShell", {
  callback = function(args)
    local reason = vim.v.fcs_reason
    if reason == "time" then
      -- "reload" updates Neovim's internal mtime; content is identical so this is
      -- safe for unmodified buffers. For modified buffers keep "nothing" to preserve edits.
      vim.v.fcs_choice = vim.bo[args.buf].modified and "nothing" or "reload"
    elseif reason == "changed" then
      vim.v.fcs_choice = "reload"
    end
  end,
})

-- Before writing, if a sync tool only changed the timestamp (same size, different mtime),
-- re-read the file so Neovim's internal mtime matches the disk. This prevents the
-- "WARNING: The file has been changed since reading it!!!" prompt.
autocmd("BufWritePre", {
  callback = function(args)
    local bufnr = args.buf
    local filename = vim.api.nvim_buf_get_name(bufnr)
    if filename == "" or vim.fn.filereadable(filename) ~= 1 then return end

    local stat = vim.uv.fs_stat(filename)
    if not stat then return end
    local last = vim.b[bufnr]._file_stat
    if not last then return end

    -- Same mtime → nothing changed on disk
    if stat.mtime.sec == last.mtime_s then return end
    -- Size changed → real content change, let Neovim warn normally
    if stat.size ~= last.size then return end

    -- Only timestamp changed: re-read the file to update Neovim's internal mtime,
    -- then restore the buffer content the user was about to save.
    if vim.bo[bufnr].modified then
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local cursor = vim.api.nvim_win_get_cursor(0)
      vim.cmd("silent! edit!")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      pcall(vim.api.nvim_win_set_cursor, 0, cursor)
    else
      vim.cmd("silent! edit")
    end
    track_file_state(bufnr)
  end,
})

-- After saving, schedule a checktime to catch sync tool changes that happen
-- right after the write. This runs outside autocmd context so it actually works.
autocmd("BufWritePost", {
  callback = function(args)
    local bufnr = args.buf
    track_file_state(bufnr)
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) and not vim.bo[bufnr].modified then
        vim.cmd("silent! checktime " .. bufnr)
      end
    end, 500)
  end,
})

-- Spellcheck: enable for normal file buffers. Treesitter @spell captures scope
-- checking to comments/strings in code; prose filetypes (markdown, text) get
-- full-buffer checking since their whole content is prose.
autocmd("FileType", {
  callback = function(args)
    if vim.bo[args.buf].buftype == "" then
      vim.opt_local.spell = true
    end
  end,
})

-- Exclude tokens from spellcheck via extmarks:
--   * version-like tokens (e.g. v1, 1.2.3)
--   * all-uppercase words / acronyms (e.g. API, UTF8, S3) — assumed to be
--     special lingo, not misspellings
-- A legacy `syntax match` would work but flips the buffer into syntax-enabled
-- mode, which breaks Treesitter's @spell scoping and causes every identifier
-- to be spellchecked. Extmarks override TS spell captures without that
-- side-effect.
local spell_ns = vim.api.nvim_create_namespace("spell_exclusions")
local spell_exclusion_regexes = {
  vim.regex([[\v<v?\d+(\.\d+)*>]]),
  -- run starting with an uppercase letter, 2+ chars, only uppercase + digits.
  -- Bounded by lowercase lookarounds rather than \< \> keyword boundaries, so
  -- separators like `.` and `_` split it (SV1020.ACCSEC_USERS -> SV1020,
  -- ACCSEC, USERS) while genuine camelCase (OAuth) is left to spelloptions.
  -- The leading \l@<! / trailing \l@! also peel acronyms out of camelCase
  -- (HTTPResponse -> HTTP excluded, Response still checked).
  vim.regex([[\v\l@<!\u%(\u|\d)+\l@!]]),
}

local function update_spell_marks(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if vim.bo[bufnr].buftype ~= "" then return end
  vim.api.nvim_buf_clear_namespace(bufnr, spell_ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for lnum, line in ipairs(lines) do
    for _, regex in ipairs(spell_exclusion_regexes) do
      local offset = 0
      while offset < #line do
        local s, e = regex:match_str(line:sub(offset + 1))
        if not s then break end
        vim.api.nvim_buf_set_extmark(bufnr, spell_ns, lnum - 1, offset + s, {
          end_col = offset + e,
          spell = false,
          priority = 200,
        })
        offset = offset + e
      end
    end
  end
end

autocmd({ "BufReadPost", "TextChanged", "InsertLeave" }, {
  callback = function(args) update_spell_marks(args.buf) end,
})

-- user event that loads after UIEnter + only if file buf is there
autocmd({ "UIEnter", "BufReadPost", "BufNewFile" }, {
  group = vim.api.nvim_create_augroup("NvFilePost", { clear = true }),
  callback = function(args)
    local file = vim.api.nvim_buf_get_name(args.buf)
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = args.buf })

    if not vim.g.ui_entered and args.event == "UIEnter" then
      vim.g.ui_entered = true
    end

    if file ~= "" and buftype ~= "nofile" and vim.g.ui_entered then
      vim.api.nvim_exec_autocmds("User", { pattern = "FilePost", modeline = false })
      vim.api.nvim_del_augroup_by_name "NvFilePost"

      vim.schedule(function()
        vim.api.nvim_exec_autocmds("FileType", {})

        if vim.g.editorconfig then
          require("editorconfig").config(args.buf)
        end
      end)
    end
  end,
})
