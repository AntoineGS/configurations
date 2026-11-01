return {
  "dazui-py/leetcode.nvim",
  lazy = vim.fn.argv(0, -1) ~= "leetcode.nvim",
  cmd = "Leet",
  keys = {
    { "<leader>lm", "<cmd>Leet<CR>", desc = "LeetCode menu" },
    { "<leader>ll", "<cmd>Leet list<CR>", desc = "List problems" },
    { "<leader>ld", "<cmd>Leet daily<CR>", desc = "Daily problem" },
    { "<leader>lR", "<cmd>Leet random<CR>", desc = "Random problem" },
    { "<leader>lr", "<cmd>Leet run<CR>", desc = "Run test cases" },
    { "<leader>ls", "<cmd>Leet submit<CR>", desc = "Submit solution" },
    { "<leader>lc", "<cmd>Leet console<CR>", desc = "Open console" },
    { "<leader>lv", "<cmd>Leet desc<CR>", desc = "Toggle description" },
    { "<leader>lp", "<cmd>Leet lc<CR>", desc = "Resume last problem" },
    { "<leader>lq", "<cmd>Leet exit<CR>", desc = "Exit LeetCode" },
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "folke/snacks.nvim",
  },
  opts = {
    lang = "golang",
    picker = { provider = "snacks-picker" },
    plugins = { non_standalone = true },
  },
}
