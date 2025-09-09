vim.env.LAZY_STDPATH = ".repro_copilotlua"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

local plugins = {
	{
		dir = "~/AppData/Local/nvim-data/lazy/copilot.lua",
		config = function()
			require("copilot").setup({
				suggestion = {
					enabled = true,
					auto_trigger = true,
				},
				panel = { enabled = false },
				filetypes = {
					["*"] = true,
				},
			})
		end,
	},
}

require("lazy.minit").repro({ spec = plugins })
