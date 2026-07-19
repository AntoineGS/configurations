local wk = require "which-key"
wk.add {
  { "<leader>o", group = "opencode" },
  { "<leader>oa", group = "append" },
}

local opencode_cmd = "opencode-v --port" -- symlink to ocv; name must match the plugin's `pgrep -f "opencode.*--port"` discovery

---@type snacks.terminal.Opts
local terminal_opts = {
  win = {
    position = "right",
    enter = false,
  },
}

-- Reveal the opencode terminal when a prompt is submitted
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:tui.command.execute",
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    if event.properties.command == "prompt.submit" then
      local win = require("snacks.terminal").get(opencode_cmd, { create = false })
      if win then
        win:show()
      end
    end
  end,
})

return {
  "nickjvandyke/opencode.nvim",
  version = "*",
  dependencies = { "folke/snacks.nvim" },
  init = function()
    vim.o.autoread = true -- Required for vim.g.opencode_opts.events.reload
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      server = {
        start = function()
          require("snacks.terminal").open(opencode_cmd, terminal_opts)
        end,
      },
    }
  end,
  -- stylua: ignore
  keys = {
    { "<leader>oa", function() require("opencode").ask("@this: ") end, mode = { "n", "x" }, desc = "Ask OpenCode" },
    { "<leader>os", function() require("opencode").select() end, mode = { "n", "x" }, desc = "Select OpenCode" },
    { "<leader>ot", function() require("snacks.terminal").toggle(opencode_cmd, terminal_opts) end, desc = "Toggle OpenCode" },
    { "<leader>oar", function() return require("opencode").operator("@this ") end, mode = { "n", "x" }, expr = true, desc = "Append range to OpenCode" },
    { "<leader>oal", function() return require("opencode").operator("@this ") .. "_" end, expr = true, desc = "Append line to OpenCode" },
    { "<S-C-u>", function() require("opencode").command("session.half.page.up") end, desc = "Scroll OpenCode up" },
    { "<S-C-d>", function() require("opencode").command("session.half.page.down") end, desc = "Scroll OpenCode down" },
  },
}
