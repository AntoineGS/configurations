local autocmd = vim.api.nvim_create_autocmd

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
      vim.cmd([[syntax match NoSpellVersion /\v<v?\d+(\.\d+)*>/ contains=@NoSpell containedin=ALL transparent]])
    end
  end,
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
