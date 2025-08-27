vim.env.LAZY_STDPATH = ".repro"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

require("lazy.minit").repro({
	spec = {
		"zbirenbaum/copilot.lua",
		opts = {
			suggestion = {
				enabled = true,
				-- auto_trigger = false,
				auto_trigger = true,
				keymap = {
					-- accept = "<C-p>",
					accept = "<M-CR>", -- does not work
					-- accept = "<TAB>",
					-- accept_word = "<M-p>",
					-- accept_line = "<M-P>",
					-- next = "<M-]>",
					-- prev = "<M-[>",
					-- dismiss = "<M-)>",
				},
			},
			filetypes = {
				["*"] = true,
			},
		},
	},
})
