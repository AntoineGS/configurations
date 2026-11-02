local wk = require "which-key"
wk.add {
  { "<leader>o", group = "opencode" },
  { "<leader>oa", group = "send" },
}

local opencode_cmd = "opencode"

---@type snacks.terminal.Opts
local terminal_opts = {
  win = {
    position = "right",
    enter = false,
  },
}

-- Reveal the opencode terminal when execution starts
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:session.execution.started",
  callback = function()
    local win = require("snacks.terminal").get(opencode_cmd, { create = false })
    if win then
      win:show()
    end
  end,
})

return {
  "nickjvandyke/opencode.nvim",
  branch = "main", -- V2 support; stable releases target OpenCode V1
  version = false,
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
    { "<leader>oar", function() return require("opencode").operator("@this") end, mode = { "n", "x" }, expr = true, desc = "Send range to OpenCode" },
    { "<leader>oal", function() return require("opencode").operator("@this") .. "_" end, expr = true, desc = "Send line to OpenCode" },
  },
}
