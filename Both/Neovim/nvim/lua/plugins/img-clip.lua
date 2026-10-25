local function is_markdown()
  return vim.bo.filetype == "markdown"
end

return {
  "HakonHarnes/img-clip.nvim",
  -- Load with markdown so its vim.paste hook catches image paths pasted by herdr's remote image bridge
  ft = "markdown",
  cmd = "PasteImage",
  keys = {
    -- Ghostty only forwards ctrl+shift+v when the clipboard holds no text, i.e. an image
    {
      "<C-S-v>",
      "<cmd>PasteImage<cr>",
      mode = { "n", "i" },
      ft = "markdown",
      desc = "Paste Image From Clipboard",
    },
  },
  opts = {
    default = {
      -- Save next to the current file as <file>-<timestamp>.<ext>
      dir_path = ".",
      relative_to_current_file = true,
      prompt_for_file_name = false,
      file_name = function()
        local base = vim.fn.expand "%:t:r"
        if base == "" then
          base = "image"
        end
        -- img-clip only appends the extension when the name has none, and passes the name through os.date
        return base:gsub("%.", "_"):gsub("%%", "%%%%") .. "-%Y%m%d-%H%M%S"
      end,
      -- Copy pasted image paths (e.g. herdr's /tmp staging files) instead of linking them
      copy_images = true,
      drag_and_drop = {
        enabled = is_markdown,
        insert_mode = true,
        -- Plain text pastes fall through to the normal handler; don't warn "Content is not an image."
        verbose = false,
      },
    },
  },
}
