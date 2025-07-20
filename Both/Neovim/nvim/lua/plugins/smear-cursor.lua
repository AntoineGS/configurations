if vim.g.neovide then
  return {}
else
  return {
    "sphamba/smear-cursor.nvim",
    lazy = false,
    opts = { -- Default  Range
      stiffness = 1, -- 0.6      [0, 1]
      trailing_stiffness = 0.4, -- 0.4      [0, 1]
      stiffness_insert_mode = 0.6, -- 0.4      [0, 1]
      trailing_stiffness_insert_mode = 0.6, -- 0.4      [0, 1]
      distance_stop_animating = 0.5, -- 0.1      > 0
    },
  }
end
