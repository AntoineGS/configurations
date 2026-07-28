local opts = {
  -- Auto-detects tmux / zellij / wezterm / kitty from $TMUX, $ZELLIJ, etc.
  multiplexer_integration = nil,
  at_edge = "wrap",
  -- match the zellij-side Ctrl+h/l binds (move_focus_or_tab): when both
  -- nvim and zellij are at the left/right edge, switch zellij tabs
  zellij_move_focus_or_tab = true,
}

local in_herdr = vim.env.HERDR_ENV == "1" and vim.env.HERDR_PANE_ID ~= nil

if in_herdr then
  opts.multiplexer_integration = false
  opts.at_edge = function(ctx)
    vim.system { "herdr", "pane", "focus", "--pane", vim.env.HERDR_PANE_ID, "--direction", ctx.direction }
  end
end

return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  init = function()
    if in_herdr then
      vim.g.smart_splits_multiplexer_integration = false
    end
  end,
  opts = opts,
}
