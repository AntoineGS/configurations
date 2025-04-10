require "nvchad.mappings"

local wk = require "which-key"
wk.add {
  { "<leader><space>", "<cmd>lua Snacks.picker.smart()<CR>", desc = "Smart Find Files" },
  { '<leader>"', "<cmd>lua Snacks.picker.buffers()<CR>", desc = "Buffers" },
  { "<leader>/", "<cmd>lua Snacks.picker.grep()<CR>", desc = "Grep" },
  { "<leader>:", "<cmd>lua Snacks.picker.command_history()<CR>", desc = "Command History" },
  { "<leader>n", "<cmd>lua Snacks.picker.notifications()<CR>", desc = "Notification History" },
  { "<leader>e", "<cmd>lua Snacks.explorer()<CR>", desc = "File Explorer" },
  -- find
  { "<leader>fb", "<cmd>lua Snacks.picker.buffers()<CR>", desc = "Buffers" },
  { "<leader>fc", '<cmd>lua Snacks.picker.files({ cwd = vim.fn.stdpath("config") })<CR>', desc = "Find Config File" },
  { "<leader>ff", "<cmd>lua Snacks.picker.files()<CR>", desc = "Find Files" },
  { "<leader>fg", "<cmd>lua Snacks.picker.git_files()<CR>", desc = "Find Git Files" },
  { "<leader>fp", "<cmd>lua Snacks.picker.projects()<CR>", desc = "Projects" },
  { "<leader>fr", "<cmd>lua Snacks.picker.recent()<CR>", desc = "Recent" },
  -- git
  { "<leader>gb", "<cmd>lua Snacks.picker.git_branches()<CR>", desc = "Git Branches" },
  { "<leader>gl", "<cmd>lua Snacks.picker.git_log()<CR>", desc = "Git Log" },
  { "<leader>gL", "<cmd>lua Snacks.picker.git_log_line()<CR>", desc = "Git Log Line" },
  { "<leader>gs", "<cmd>lua Snacks.picker.git_status()<CR>", desc = "Git Status" },
  { "<leader>gS", "<cmd>lua Snacks.picker.git_stash()<CR>", desc = "Git Stash" },
  { "<leader>gd", "<cmd>lua Snacks.picker.git_diff()<CR>", desc = "Git Diff (Hunks)" },
  { "<leader>gf", "<cmd>lua Snacks.picker.git_log_file()<CR>", desc = "Git Log File" },
  -- Grep
  { "<leader>sb", "<cmd>lua Snacks.picker.lines()<CR>", desc = "Buffer Lines" },
  { "<leader>sB", "<cmd>lua Snacks.picker.grep_buffers()<CR>", desc = "Grep Open Buffers" },
  { "<leader>sg", "<cmd>lua Snacks.picker.grep()<CR>", desc = "Grep" },
  { "<leader>sw", "<cmd>lua Snacks.picker.grep_word()<CR>", desc = "Visual selection or word", mode = { "n", "x" } },
  -- search
  { '<leader>s"', "<cmd>lua Snacks.picker.registers()<CR>", desc = "Registers" },
  { "<leader>s/", "<cmd>lua Snacks.picker.search_history()<CR>", desc = "Search History" },
  { "<leader>sa", "<cmd>lua Snacks.picker.autocmds()<CR>", desc = "Autocmds" },
  { "<leader>sb", "<cmd>lua Snacks.picker.lines()<CR>", desc = "Buffer Lines" },
  { "<leader>sc", "<cmd>lua Snacks.picker.command_history()<CR>", desc = "Command History" },
  { "<leader>sC", "<cmd>lua Snacks.picker.commands()<CR>", desc = "Commands" },
  { "<leader>sd", "<cmd>lua Snacks.picker.diagnostics()<CR>", desc = "Diagnostics" },
  { "<leader>sD", "<cmd>lua Snacks.picker.diagnostics_buffer()<CR>", desc = "Buffer Diagnostics" },
  { "<leader>sh", "<cmd>lua Snacks.picker.help()<CR>", desc = "Help Pages" },
  { "<leader>sH", "<cmd>lua Snacks.picker.highlights()<CR>", desc = "Highlights" },
  { "<leader>si", "<cmd>lua Snacks.picker.icons()<CR>", desc = "Icons" },
  { "<leader>sj", "<cmd>lua Snacks.picker.jumps()<CR>", desc = "Jumps" },
  { "<leader>sk", "<cmd>lua Snacks.picker.keymaps()<CR>", desc = "Keymaps" },
  { "<leader>sl", "<cmd>lua Snacks.picker.loclist()<CR>", desc = "Location List" },
  { "<leader>sm", "<cmd>lua Snacks.picker.marks()<CR>", desc = "Marks" },
  { "<leader>sM", "<cmd>lua Snacks.picker.man()<CR>", desc = "Man Pages" },
  { "<leader>sp", "<cmd>lua Snacks.picker.lazy()<CR>", desc = "Search for Plugin Spec" },
  { "<leader>sq", "<cmd>lua Snacks.picker.qflist()<CR>", desc = "Quickfix List" },
  { "<leader>sR", "<cmd>lua Snacks.picker.resume()<CR>", desc = "Resume" },
  { "<leader>su", "<cmd>lua Snacks.picker.undo()<CR>", desc = "Undo History" },
  { "<leader>uC", "<cmd>lua Snacks.picker.colorschemes()<CR>", desc = "Colorschemes" },
  -- LSP
  { "gd", "<cmd>lua Snacks.picker.lsp_definitions()<CR>", desc = "Goto Definition" },
  { "gD", "<cmd>lua Snacks.picker.lsp_declarations()<CR>", desc = "Goto Declaration" },
  { "gR", "<cmd>lua Snacks.picker.lsp_references()<CR>", nowait = true, desc = "References" },
  { "gI", "<cmd>lua Snacks.picker.lsp_implementations()<CR>", desc = "Goto Implementation" },
  { "gy", "<cmd>lua Snacks.picker.lsp_type_definitions()<CR>", desc = "Goto T[y]pe Definition" },
  { "<leader>ss", "<cmd>lua Snacks.picker.lsp_symbols()<CR>", desc = "LSP Symbols" },
  { "<leader>sS", "<cmd>lua Snacks.picker.lsp_workspace_symbols()<CR>", desc = "LSP Workspace Symbols" },
}

return {
  "folke/snacks.nvim",
  lazy = false,
  opts = {
    explorer = {
      replace_netrw = true,
    },
    picker = {
      sources = {
        explorer = {
          hidden = true,
        },
      },
    },
  },
}
