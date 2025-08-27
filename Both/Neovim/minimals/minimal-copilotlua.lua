vim.env.LAZY_STDPATH = ".repro"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

local plugins = {
	{
		"zbirenbaum/copilot.lua",
		event = "InsertEnter",
		opts = {
			logger = {
				file_log_level = vim.log.levels.TRACE,
			},
		},
	},
}

require("lazy.minit").repro({ spec = plugins })
