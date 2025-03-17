return {
  -- "zbirenbaum/copilot.lua",
  "AntoineGS/copilot.lua",
  branch = "master",
  cmd = "Copilot",
  event = "InsertEnter",
  config = function()
    require("copilot").setup {
      copilot_model = "gpt-4o-copilot",
    }
  end,
}
