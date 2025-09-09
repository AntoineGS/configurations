vim.env.LAZY_STDPATH = ".repro_copilot-cmp"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

local plugins = {
	{
		"hrsh7th/nvim-cmp",
		dependencies = {
			-- cmp sources plugins
			{
				"zbirenbaum/copilot-cmp",
			},
			{
				-- snippet plugin
				"L3MON4D3/LuaSnip",
				dependencies = "rafamadriz/friendly-snippets",
				opts = { history = true, updateevents = "TextChanged,TextChangedI" },
				config = function(_, opts)
					require("luasnip").config.set_config(opts)
					-- require("nvchad.configs.luasnip")
				end,
			},
		},
		opts = {
			sources = {
				{ name = "copilot", priority = 600 },
			},
			-- experimental = {
			-- ghost_text = true,
			-- },
		},
	},
	{
		"zbirenbaum/copilot-cmp",
		config = function()
			require("copilot_cmp").setup()
		end,
	},
	{
		"zbirenbaum/copilot.lua",
		config = function()
			require("copilot").setup({
				suggestion = { enabled = false },
				panel = { enabled = false },
				filetypes = {
					["*"] = true,
				},
			})
		end,
	},
}

require("lazy.minit").repro({ spec = plugins })
