vim.env.LAZY_STDPATH = ".repro_nvchadui"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

local plugins = {
	{
		"nvim-lua/plenary.nvim",
		{ "nvim-tree/nvim-web-devicons", lazy = true },

		{
			"nvchad/ui",
			config = function()
				require("nvchad")
			end,
		},

		{
			"nvchad/base46",
			lazy = true,
			build = function()
				require("base46").load_all_highlights()
			end,
		},
	},
}

require("lazy.minit").repro({ spec = plugins })
