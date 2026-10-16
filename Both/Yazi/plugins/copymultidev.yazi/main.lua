local get_paths = ya.sync(function()
	local paths = {}
	for _, url in pairs(cx.active.selected) do
		paths[#paths + 1] = tostring(url)
	end
	if #paths == 0 and cx.active.current.hovered then
		paths[1] = tostring(cx.active.current.hovered.url)
	end
	return paths
end)

-- ~/Shares/O-applications/Tools -> O:/Tools
local function to_windows(path, prefix)
	if path:sub(1, #prefix) ~= prefix then
		return path
	end
	local letter, rest = path:sub(#prefix + 1):match("^(%a)%-[^/]+(.*)$")
	if not letter then
		return path
	end
	return letter:upper() .. ":" .. (rest == "" and "/" or rest)
end

return {
	entry = function()
		local prefix = os.getenv("HOME") .. "/Shares/"
		local paths = get_paths()
		for i, path in ipairs(paths) do
			paths[i] = to_windows(path, prefix)
		end
		ya.clipboard(table.concat(paths, "\n"))
	end,
}
