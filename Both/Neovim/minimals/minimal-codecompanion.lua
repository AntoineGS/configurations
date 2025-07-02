vim.env.LAZY_STDPATH = ".repro_codecompanion"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

local plugins = {
	{
		"olimorris/codecompanion.nvim",
		opts = {
			adapters = {
				copilot = function()
					return require("codecompanion.adapters").extend("copilot", {})
				end,
			},
			strategies = {
				chat = {
					adapter = "copilot",
				},
				inline = {
					adapter = "copilot",
				},
			},
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
		},
	},
	{
		"zbirenbaum/copilot.lua",
		config = function()
			require("copilot").setup({})
		end,
	},
}

require("lazy.minit").repro({ spec = plugins })
