th.git = th.git or {}
th.git.unknown_sign = "  "
th.git.clean_sign = "  "

if os.getenv("YAZI_AUTOSESSION") == "1" then
	require("autosession"):setup()
end
require("git"):setup({
	order = 1500,
})

function Linemode:size_and_mtime()
	local time = math.floor(self._file.cha.mtime or 0)
	if time == 0 then
		time = ""
	elseif os.date("%Y", time) == os.date("%Y") then
		time = os.date("%b %d %H:%M", time)
	else
		time = os.date("%b %d  %Y", time)
	end

	local size = self._file:size()
	return string.format("%s %s", size and ya.readable_size(size) or "-", time)
end
