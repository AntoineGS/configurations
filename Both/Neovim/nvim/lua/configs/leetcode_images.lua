local M = {}

local function draw_images(description)
  local buf = description.bufnr
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  local image = require("snacks").image
  -- LeetCode clears all extmarks on redraw, so recreate the placements too.
  image.placement.clean(buf)
  if not (image.supports_terminal() and image.terminal.env().placeholders) then
    return
  end

  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local offset = 1
    while true do
      local first, last, src = line:find("%[[^%]]*%]%((https?://[^%s%)]+)%)", offset)
      if not first then
        break
      end
      if image.supports_file((src:gsub("[?#].*$", ""))) then
        image.placement.new(buf, src, {
          pos = { row, first - 1 },
          range = { row, first - 1, row, last },
          inline = true,
          max_width = image.config.doc.max_width,
          max_height = image.config.doc.max_height,
        })
      end
      offset = last + 1
    end
  end
end

function M.attach(question)
  local description = question.description
  if description.draw_imgs == draw_images then
    return
  end

  -- Use LeetCode's redraw lifecycle, including resizing and toggling stats.
  description.draw_imgs = draw_images
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = description.bufnr,
    callback = function()
      vim.schedule(function()
        draw_images(description)
      end)
    end,
  })
  -- Snacks cleans up placements automatically when the buffer is deleted.
  draw_images(description)
end

return M
