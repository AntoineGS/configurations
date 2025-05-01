return {
  "saghen/blink.cmp",
  dependencies = {
    "rafamadriz/friendly-snippets",
    -- "fang2hou/blink-copilot",
  },
  version = "*",

  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    -- 'default' (recommended) for mappings similar to built-in completions (C-y to accept, C-n/C-p for up/down)
    -- 'super-tab' for mappings similar to vscode (tab to accept, arrow keys for up/down)
    -- 'enter' for mappings similar to 'super-tab' but with 'enter' to accept
    --
    -- All presets have the following mappings:
    -- C-space: Open menu or open docs if already open
    -- C-e: Hide menu
    -- C-k: Toggle signature help
    --
    -- See the full "keymap" documentation for information on defining your own keymap.
    keymap = {
      preset = "none",
      ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
      ["<C-e>"] = { "hide" },
      -- ["<M-p>"] = { "select_and_accept" },

      ["<Up>"] = { "select_prev", "fallback" },
      ["<Down>"] = { "select_next", "fallback" },
      -- ["<C-p>"] = { "select_prev", "fallback_to_mappings" },
      -- ["<C-n>"] = { "select_next", "fallback_to_mappings" },

      ["<C-b>"] = { "scroll_documentation_up", "fallback" },
      ["<C-f>"] = { "scroll_documentation_down", "fallback" },

      ["<Tab>"] = { "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },

      ["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
    },

    appearance = {
      -- Sets the fallback highlight groups to nvim-cmp's highlight groups
      -- Useful for when your theme doesn't support blink.cmp
      -- Will be removed in a future release
      use_nvim_cmp_as_default = true,
      -- Set to 'mono' for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
      -- Adjusts spacing to ensure icons are aligned
      nerd_font_variant = "mono",
    },

    -- Default list of enabled providers defined so that you can extend it
    -- elsewhere in your config, without redefining it, due to `opts_extend`
    -- sources = {
    --   default = { "copilot", "lsp", "path", "snippets", "buffer" },
    --   providers = {
    --     copilot = {
    --       name = "copilot",
    --       module = "blink-copilot",
    --       score_offset = 100,
    --       async = true,
    --     },
    --   },
    -- },
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
    },
    fuzzy = { implementation = "prefer_rust_with_warning" },
    completion = {
      menu = {
        direction_priority = { "n", "s" },
      },
      list = {
        selection = {
          preselect = false,
        },
      },
    },
  },
  opts_extend = { "sources.default" },
}
