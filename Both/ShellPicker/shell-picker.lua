local source = debug.getinfo(1, "S").source
local directory = source:sub(2):match("^(.*)[/\\][^/\\]+$")
local core = dofile(directory .. "/shell-picker-core.lua")
local transport_counter = 0

local function home_directory()
  local userprofile = os.getenv("USERPROFILE")
  if userprofile and userprofile ~= "" then
    return userprofile
  end

  local home = os.getenv("HOME")
  if home and home ~= "" then
    return home
  end

  local drive = os.getenv("HOMEDRIVE")
  local path = os.getenv("HOMEPATH")
  if drive and path and drive ~= "" and path ~= "" then
    return drive .. path
  end
  return nil
end

local function command_succeeded(first, second, third)
  if first == true then
    return third == nil or (second == "exit" and third == 0)
  end
  if first == 0 then
    return true
  end
  return second == "exit" and third == 0
end

local function transport_names()
  local used = {}
  for _, name in ipairs(os.getenvnames()) do
    used[name:upper()] = true
  end

  while true do
    transport_counter = transport_counter + 1
    local suffix = tostring(transport_counter)
    local cwd_name = "SHELL_PICKER_TRANSPORT_CWD_" .. suffix
    local home_name = "SHELL_PICKER_TRANSPORT_HOME_" .. suffix
    if not used[cwd_name] and not used[home_name] then
      return cwd_name, home_name
    end
  end
end

local function environment_reference(name)
  return '"%' .. name .. '%"'
end

local function normalize_transport_path(path)
  local drive = path:match("^([%a]:)[/\\]+$")
  if drive then
    return drive .. "\\."
  end

  local server, share = path:match("^\\\\([^/\\]+)[/\\]([^/\\]+)[/\\]+$")
  if server and share then
    return "\\\\" .. server .. "\\" .. share .. "\\."
  end
  return path
end

local function picker_command(operation, cwd_name, home_name)
  return table.concat({
    "shell-picker.exe",
    operation,
    "--cwd",
    environment_reference(cwd_name),
    "--home",
    environment_reference(home_name),
    "--output",
    "nul",
  }, " ")
end

local function restore_environment(saved)
  local ok = true
  for index = #saved, 1, -1 do
    local entry = saved[index]
    local restored, result = pcall(os.setenv, entry.name, entry.value)
    if not restored or not result then
      ok = false
    end
  end
  return ok
end

local function run_picker(operation, cwd, home)
  if not core.validate_paths("cd", { cwd }) or not core.validate_paths("cd", { home }) then
    return nil
  end

  local saved = {}
  local ok, data = pcall(function()
    local cwd_name, home_name = transport_names()
    saved[1] = { name = cwd_name, value = os.getenv(cwd_name) }
    saved[2] = { name = home_name, value = os.getenv(home_name) }
    assert(os.setenv(cwd_name, normalize_transport_path(cwd)))
    assert(os.setenv(home_name, normalize_transport_path(home)))

    -- Clink redirects read-mode io.popen to popenyield in coroutine contexts.
    local stream, close = io.popen(picker_command(operation, cwd_name, home_name), "rb")
    if not stream then
      return nil
    end

    local read_ok, output = pcall(function()
      return stream:read("*a")
    end)
    local close_ok, first, second, third = pcall(function()
      if close then
        return close()
      end
      return stream:close()
    end)
    if not read_ok or not close_ok or not output or
        not command_succeeded(first, second, third) then
      return nil
    end
    return output
  end)
  if not restore_environment(saved) or not ok then
    return nil
  end
  return data
end

local function replace_line(rl_buffer, buffer, cursor)
  local length = rl_buffer:getlength()
  if length > 0 then
    rl_buffer:remove(1, length + 1)
  end
  if buffer ~= "" then
    rl_buffer:insert(buffer)
  end
  rl_buffer:setcursor(cursor)
end

local function restore_line(rl_buffer, buffer, cursor)
  replace_line(rl_buffer, buffer, cursor)
  rl_buffer:refreshline()
end

function shell_picker_space(rl_buffer, line_state)
  local before = rl_buffer:getbuffer()
  local before_cursor = rl_buffer:getcursor() - 1

  rl_buffer:insert(" ")
  local after = rl_buffer:getbuffer()
  local after_cursor = rl_buffer:getcursor()
  local operation = core.operation_for(before, before_cursor)
  if not operation then
    return
  end

  local cwd = os.getcwd()
  local home = home_directory()
  rl_buffer:beginoutput()
  local output = run_picker(operation, cwd, home)
  local paths = output and core.split_nul(output) or nil
  if not paths or not core.validate_paths(operation, paths) then
    restore_line(rl_buffer, after, after_cursor)
    return
  end

  local command
  if operation == "cd" then
    command = core.cd_command(paths[1])
  else
    command = core.cp_command(paths)
  end
  if not command then
    restore_line(rl_buffer, after, after_cursor)
    return
  end

  replace_line(rl_buffer, command, #command + 1)
  rl_buffer:refreshline()
end
