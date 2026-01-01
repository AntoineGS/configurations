local languages = {
  "bash",
  "c",
  "c_sharp",
  "comment",
  "cpp",
  "css",
  "dockerfile",
  "go",
  "html",
  "ini",
  "java",
  "javascript",
  "json",
  "lua",
  "luadoc",
  "markdown",
  "markdown_inline",
  "nginx",
  "nu",
  "pascal",
  "php",
  "printf",
  "python",
  "rust",
  "sql",
  "toml",
  "typescript",
  "vim",
  "vimdoc",
  "yaml",
  "zsh",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    lazy = false,
  },
  {
    "MeanderingProgrammer/treesitter-modules.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    lazy = false,
    opts = {
      ensure_installed = languages,
      fold = { enable = true },
      highlight = { enable = true },
      indent = { enable = true },
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = "gnn",
          node_incremental = "gnn",
          node_decremental = "gnd",
          scope_incremental = false,
        },
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    lazy = false,
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    init = function()
      -- Disable entire built-in ftplugin mappings to avoid conflicts.
      -- See https://github.com/neovim/neovim/tree/master/runtime/ftplugin for built-in ftplugins.
      vim.g.no_plugin_maps = true

      -- Or, disable per filetype (add as you like)
      -- vim.g.no_python_maps = true
      -- vim.g.no_ruby_maps = true
      -- vim.g.no_rust_maps = true
      -- vim.g.no_go_maps = true
    end,
    config = function()
      require("nvim-treesitter-textobjects").setup {
        select = {
          -- Automatically jump forward to textobj, similar to targets.vim
          lookahead = true,
          -- You can choose the select mode (default is charwise 'v')
          --
          -- Can also be a function which gets passed a table with the keys
          -- * query_string: eg '@function.inner'
          -- * method: eg 'v' or 'o'
          -- and should return the mode ('v', 'V', or '<c-v>') or a table
          -- mapping query_strings to modes.
          selection_modes = {
            ["@parameter.outer"] = "v", -- charwise
            ["@function.outer"] = "V", -- linewise
            -- ['@class.outer'] = '<c-v>', -- blockwise
          },
          -- If you set this to `true` (default is `false`) then any textobject is
          -- extended to include preceding or succeeding whitespace. Succeeding
          -- whitespace has priority in order to act similarly to eg the built-in
          -- `ap`.
          --
          -- Can also be a function which gets passed a table with the keys
          -- * query_string: eg '@function.inner'
          -- * selection_mode: eg 'v'
          -- and should return true of false
          include_surrounding_whitespace = false,
        },
      }

      -- keymaps handled by mini.ai
      -- vim.keymap.set({ "x", "o" }, "af", function()
      --   require("nvim-treesitter-textobjects.select").select_textobject("@function.outer", "textobjects")
      -- end)
      -- vim.keymap.set({ "x", "o" }, "if", function()
      --   require("nvim-treesitter-textobjects.select").select_textobject("@function.inner", "textobjects")
      -- end)
      -- vim.keymap.set({ "x", "o" }, "ac", function()
      --   require("nvim-treesitter-textobjects.select").select_textobject("@class.outer", "textobjects")
      -- end)
      -- vim.keymap.set({ "x", "o" }, "ic", function()
      --   require("nvim-treesitter-textobjects.select").select_textobject("@class.inner", "textobjects")
      -- end)
      -- You can also use captures from other query groups like `locals.scm`
      -- vim.keymap.set({ "x", "o" }, "as", function()
      --   require("nvim-treesitter-textobjects.select").select_textobject("@local.scope", "locals")
      -- end)
    end,
  },
}
