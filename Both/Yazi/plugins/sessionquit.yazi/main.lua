return {
	entry = function()
		if os.getenv("YAZI_AUTOSESSION") == "1" then
			require("autosession"):entry({ args = { "save-and-quit" } })
		else
			ya.emit("quit", {})
		end
	end,
}
