local M = {}

local function is_continuation(byte)
  return byte and byte >= 0x80 and byte <= 0xbf
end

local function decode_utf8(value, index)
  local first = value:byte(index)
  if not first then
    return nil
  end
  if first <= 0x7f then
    return first, index + 1
  end

  local second = value:byte(index + 1)
  local third = value:byte(index + 2)
  local fourth = value:byte(index + 3)
  if first >= 0xc2 and first <= 0xdf and is_continuation(second) then
    return (first - 0xc0) * 0x40 + second - 0x80, index + 2
  end
  if first == 0xe0 and second and second >= 0xa0 and second <= 0xbf and is_continuation(third) then
    return (first - 0xe0) * 0x1000 + (second - 0x80) * 0x40 + third - 0x80, index + 3
  end
  if first >= 0xe1 and first <= 0xec and is_continuation(second) and is_continuation(third) then
    return (first - 0xe0) * 0x1000 + (second - 0x80) * 0x40 + third - 0x80, index + 3
  end
  if first == 0xed and second and second >= 0x80 and second <= 0x9f and is_continuation(third) then
    return (first - 0xe0) * 0x1000 + (second - 0x80) * 0x40 + third - 0x80, index + 3
  end
  if first >= 0xee and first <= 0xef and is_continuation(second) and is_continuation(third) then
    return (first - 0xe0) * 0x1000 + (second - 0x80) * 0x40 + third - 0x80, index + 3
  end
  if first == 0xf0 and second and second >= 0x90 and second <= 0xbf and
      is_continuation(third) and is_continuation(fourth) then
    return (first - 0xf0) * 0x40000 + (second - 0x80) * 0x1000 + (third - 0x80) * 0x40 + fourth - 0x80, index + 4
  end
  if first >= 0xf1 and first <= 0xf3 and is_continuation(second) and is_continuation(third) and
      is_continuation(fourth) then
    return (first - 0xf0) * 0x40000 + (second - 0x80) * 0x1000 + (third - 0x80) * 0x40 + fourth - 0x80, index + 4
  end
  if first == 0xf4 and second and second >= 0x80 and second <= 0x8f and
      is_continuation(third) and is_continuation(fourth) then
    return (first - 0xf0) * 0x40000 + (second - 0x80) * 0x1000 + (third - 0x80) * 0x40 + fourth - 0x80, index + 4
  end
  return nil
end

local function valid_text(value)
  if type(value) ~= "string" then
    return false
  end
  local index = 1
  while index <= #value do
    local codepoint, next_index = decode_utf8(value, index)
    if not codepoint then
      return false
    end
    if codepoint < 0x20 or (codepoint >= 0x7f and codepoint <= 0x9f) or
        codepoint == 0x2028 or codepoint == 0x2029 then
      return false
    end
    if codepoint == 0x22 then
      return false
    end
    index = next_index
  end
  return true
end

local function is_absolute_windows(path)
  if path:match("^%a:[/\\]") then
    return true
  end
  return path:match("^[/\\][/\\][^/\\]+[/\\][^/\\]+") ~= nil
end

local function valid_component(component)
  if component == "." or component == ".." then
    return true
  end
  if component == "" or component:sub(-1) == "." or component:sub(-1) == " " then
    return false
  end

  local name = component:match("^([^%.]*)"):upper()
  if name == "CON" or name == "PRN" or name == "AUX" or name == "NUL" then
    return false
  end
  if name:match("^COM[1-9]$") or name:match("^LPT[1-9]$") then
    return false
  end
  return true
end

local function valid_windows_path(path, require_absolute)
  if type(path) ~= "string" or path == "" or not valid_text(path) then
    return false
  end
  if path:find("[*?<>|]", 1) or path:find(":", 3, true) then
    return false
  end
  if path:match("^[%a]:") and not path:match("^[%a]:[/\\]") then
    return false
  end
  if path:find(":", 1, true) and not path:match("^[%a]:[/\\]") then
    return false
  end
  if path:match("^[/\\]") and not path:match("^[/\\][/\\]") then
    return false
  end
  if path:match("^[/\\][/\\][?.][/\\]") then
    return false
  end
  if require_absolute and not is_absolute_windows(path) then
    return false
  end

  local component_index = 0
  for component in path:gmatch("[^/\\]+") do
    component_index = component_index + 1
    local drive = path:match("^[%a]:[/\\]")
    local unc = path:match("^[/\\][/\\]")
    if (drive and component_index == 1) or (unc and component_index <= 2) then
      if not valid_component(component:gsub(":$", "")) then
        return false
      end
    elseif not valid_component(component) then
      return false
    end
  end
  return true
end

function M.split_nul(data)
  if type(data) ~= "string" then
    return nil
  end

  local paths = {}
  if data == "" then
    return paths
  end

  local start = 1
  while true do
    local finish = data:find("\0", start, true)
    if not finish or finish == start then
      return nil
    end
    paths[#paths + 1] = data:sub(start, finish - 1)
    start = finish + 1
    if start > #data then
      return paths
    end
  end
end

function M.operation_for(buffer, cursor)
  if cursor ~= 2 then
    return nil
  end
  if buffer == "cd" or buffer == "cp" then
    return buffer
  end
  return nil
end

function M.quote_cmd_arg(value)
  if not valid_text(value) then
    return nil
  end
  if value == "" then
    return [[""]]
  end

  local output = { [["]] }
  local quoted = true
  local trailing_backslashes = 0

  local function close_quote()
    if not quoted then
      return
    end
    if trailing_backslashes > 0 then
      output[#output + 1] = string.rep("\\", trailing_backslashes)
    end
    output[#output + 1] = [["]]
    quoted = false
    trailing_backslashes = 0
  end

  local function open_quote()
    if not quoted then
      output[#output + 1] = [["]]
      quoted = true
    end
  end

  for index = 1, #value do
    local character = value:sub(index, index)
    if character == "\\" and quoted then
      output[#output + 1] = "\\"
      trailing_backslashes = trailing_backslashes + 1
    elseif character == "%" then
      close_quote()
      output[#output + 1] = "^%"
      open_quote()
    else
      open_quote()
      output[#output + 1] = character
      trailing_backslashes = 0
    end
  end

  local needs_empty_segment = not quoted
  close_quote()
  if needs_empty_segment then
    output[#output + 1] = [["]]
    output[#output + 1] = [["]]
  end
  return table.concat(output)
end

function M.quote_process_arg(value)
  if not valid_text(value) then
    return nil
  end
  if value == "" then
    return [[""]]
  end

  local output = { [["]] }
  local trailing_backslashes = 0
  for index = 1, #value do
    local character = value:sub(index, index)
    if character == "\\" then
      output[#output + 1] = "\\"
      trailing_backslashes = trailing_backslashes + 1
    else
      output[#output + 1] = character
      trailing_backslashes = 0
    end
  end
  if trailing_backslashes > 0 then
    output[#output + 1] = string.rep("\\", trailing_backslashes)
  end
  output[#output + 1] = [["]]
  return table.concat(output)
end

local function escape_cd_arg(value)
  if not valid_text(value) then
    return nil
  end

  local output = {}
  for index = 1, #value do
    local character = value:sub(index, index)
    if character == " " or character == "&" or character == "(" or character == ")" or
        character == "^" or character == "!" or character == "%" or character == "|" or
        character == "<" or character == ">" then
      output[#output + 1] = "^"
    end
    output[#output + 1] = character
  end
  return table.concat(output)
end

local function delayed_expansion_guard(command)
  -- Commands containing ! require standard CMD delayed expansion to remain off.
  return 'if not "!"=="^!" ' .. command
end

function M.validate_paths(operation, paths)
  if type(paths) ~= "table" then
    return false
  end
  if operation == "cd" and #paths ~= 1 then
    return false
  end
  if operation == "cp" and #paths == 0 then
    return false
  end
  if operation ~= "cd" and operation ~= "cp" then
    return false
  end

  for index = 1, #paths do
    if not valid_windows_path(paths[index], operation == "cd") then
      return false
    end
  end
  return true
end

function M.cd_command(path)
  if not M.validate_paths("cd", { path }) then
    return nil
  end
  local quoted = path:find("%", 1, true) and escape_cd_arg(path) or M.quote_cmd_arg(path)
  if not quoted then
    return nil
  end
  local command = "cd /d " .. quoted
  if path:find("!", 1, true) then
    return delayed_expansion_guard(command)
  end
  return command
end

function M.cp_command(paths)
  if not M.validate_paths("cp", paths) then
    return nil
  end

  local quoted = {}
  for index = 1, #paths do
    local argument = M.quote_cmd_arg(paths[index])
    if not argument then
      return nil
    end
    quoted[index] = argument
  end
  local command = "cp.exe -- " .. table.concat(quoted, " ") .. " "
  for index = 1, #paths do
    if paths[index]:find("!", 1, true) then
      return delayed_expansion_guard(command)
    end
  end
  return command
end

return M
