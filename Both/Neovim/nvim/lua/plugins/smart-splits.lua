local opts = {
  move = {
    at_edge = "wrap",
  },
}

local in_herdr = vim.env.HERDR_ENV == "1" and vim.env.HERDR_PANE_ID ~= nil

if in_herdr then
  opts.move.at_edge = function(ctx)
    vim.system { "herdr", "pane", "focus", "--pane", vim.env.HERDR_PANE_ID, "--direction", ctx.direction }
  end
end

return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = opts,
}
