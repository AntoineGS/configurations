return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = {
    -- auto-detects tmux / zellij / wezterm / kitty from $TMUX, $ZELLIJ, etc.
    multiplexer_integration = nil,
    at_edge = "wrap",
    -- match the zellij-side Ctrl+h/l binds (move_focus_or_tab): when both
    -- nvim and zellij are at the left/right edge, switch zellij tabs
    zellij_move_focus_or_tab = true,
  },
}
