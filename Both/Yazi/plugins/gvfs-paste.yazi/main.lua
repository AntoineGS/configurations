-- Paste with gio when the destination is a gvfs FUSE mount (~/Shares/md-ftp, ...).
-- gvfs FUSE shares one stream per path, so anything reading a file while it is
-- being written (Yazi's mime fetcher, a preview) breaks the copy on FTP with
-- "Operation not supported". gio talks to the gvfs backend directly instead.
--
-- Uploads land under a hidden temporary name and are renamed into place through
-- FUSE: nobody downloads a partial file, and the rename's inotify event is what
-- lets Yazi see the new entry (gio itself bypasses FUSE, so Yazi gets no event).

local get_state = ya.sync(function()
	local yanked = {}
	for _, file in pairs(cx.yanked) do
		yanked[#yanked + 1] = tostring(file.url)
	end
	return tostring(cx.active.current.cwd), yanked, cx.yanked.is_cut
end)

local function realpath(path)
	local output = Command("realpath"):arg({ "-e", "--", path }):output()
	if output and output.status.success then
		return (output.stdout:gsub("\n$", ""))
	end
end

-- /run/user/<uid>/gvfs/<mount>, or nil when the path is not on a gvfs mount
local function gvfs_mount(path)
	local root = "/run/user/" .. ya.uid() .. "/gvfs/"
	if path:sub(1, #root) == root then
		return root .. path:sub(#root + 1):match("^[^/]+")
	end
end

local function gio(args)
	local output, err = Command("gio"):arg(args):output()
	if not output then
		return "gio: " .. tostring(err)
	elseif not output.status.success then
		return (output.stderr:gsub("%s+$", ""))
	end
end

local function exists(path) return fs.cha(Url(path)) ~= nil end

local function remove(path, is_dir)
	local _, err = fs.remove(is_dir and "dir_all" or "file", Url(path))
	return err and tostring(err)
end

local function rename(from, to)
	local _, err = fs.rename(Url(from), Url(to))
	return err and tostring(err)
end

-- Same naming as Yazi's paste: file_1.ext for files, dir_1 for directories
local function unique(path, is_dir)
	if not exists(path) then
		return path
	end
	local dir, name = path:match("^(.*)/([^/]+)$")
	local stem, ext = name:match("^(.+)(%.[^.]+)$")
	if is_dir or not stem then
		stem, ext = name, ""
	end
	for i = 1, math.huge do
		local candidate = string.format("%s/%s_%d%s", dir, stem, i, ext)
		if not exists(candidate) then
			return candidate
		end
	end
end

local function temp_for(path)
	local dir, name = path:match("^(.*)/([^/]+)$")
	return string.format("%s/.%s.gvfs-paste", dir, name)
end

local function place(tmp, dst, is_dir)
	local err = rename(tmp, dst)
	if err and not is_dir and exists(dst) then
		-- Some FTP servers refuse RNTO onto an existing file
		err = remove(dst, false) or rename(tmp, dst)
	end
	if err then
		remove(tmp, is_dir)
	end
	return err
end

-- staged: `to` is inside a temporary directory that is renamed into place afterwards
local function copy_file(from, to, staged)
	if staged then
		return gio({ "copy", "-T", "--", from, to })
	end
	local tmp = temp_for(to)
	local err = gio({ "copy", "-T", "--", from, tmp })
	if err then
		remove(tmp, false)
		return err
	end
	return place(tmp, to, false)
end

-- gio copy does not recurse, so walk directories ourselves
local function copy_tree(from, to, staged)
	if not staged and not exists(to) then
		local tmp = temp_for(to)
		local err = copy_tree(from, tmp, true)
		if err then
			remove(tmp, true)
			return err
		end
		return place(tmp, to, true)
	end

	local err = not exists(to) and gio({ "mkdir", "--", to })
	if err then
		return err
	end
	local files, read_err = fs.read_dir(Url(from), { resolve = true })
	if not files then
		return tostring(read_err)
	end
	for _, file in ipairs(files) do
		local src, dst = from .. "/" .. file.name, to .. "/" .. file.name
		if file.cha.is_dir then
			err = copy_tree(src, dst, staged)
		else
			err = copy_file(src, dst, staged)
		end
		if err then
			return err
		end
	end
end

local function paste(src, dst, is_dir, is_cut, same_mount)
	if is_cut and same_mount and not exists(dst) then
		-- A FUSE rename is a server-side RNFR/RNTO
		return rename(src, dst)
	end
	local err
	if is_dir then
		err = copy_tree(src, dst, false)
	else
		err = copy_file(src, dst, false)
	end
	return err or (is_cut and remove(src, is_dir))
end

return {
	entry = function(_, job)
		local force = job.args.force
		local cwd, yanked, is_cut = get_state()
		local dest = realpath(cwd)
		local mount = dest and gvfs_mount(dest)
		if not mount or #yanked == 0 then
			return ya.emit("paste", { force = force })
		end

		ya.notify { title = "gvfs paste", content = string.format("Pasting %d item(s) with gio…", #yanked), timeout = 3 }

		local failures = {}
		for _, url in ipairs(yanked) do
			local name = url:match("([^/]+)/*$")
			local src = realpath(url)
			local err
			if not src then
				err = "source no longer exists"
			else
				local is_dir = (fs.cha(Url(src), true) or {}).is_dir
				local dst = dest .. "/" .. name
				if not force then
					dst = unique(dst, is_dir)
				end
				if src == dst then
					err = "source and destination are the same"
				else
					err = paste(src, dst, is_dir, is_cut, gvfs_mount(src) == mount)
				end
			end
			if err then
				failures[#failures + 1] = name .. ": " .. err
			end
		end

		if is_cut and #failures == 0 then
			ya.emit("unyank", {})
		end
		if #failures > 0 then
			ya.notify { title = "gvfs paste failed", content = table.concat(failures, "\n"), timeout = 10, level = "error" }
		else
			ya.notify { title = "gvfs paste", content = string.format("Pasted %d item(s)", #yanked), timeout = 3 }
		end
	end,
}
