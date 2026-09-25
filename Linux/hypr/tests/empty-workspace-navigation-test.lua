local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*)/")
package.path = directory .. "/../?.lua;" .. package.path

local function dispatcher_namespace(name)
  return setmetatable({}, {
    __index = function(_, method)
      return function(args)
        return { name = name .. "." .. method, args = args }
      end
    end,
  })
end

local bindings = {}
local dispatched = {}
local active_window
local dsp = dispatcher_namespace("dsp")
dsp.window = dispatcher_namespace("window")
dsp.workspace = dispatcher_namespace("workspace")

hl = {
  dsp = dsp,
  bind = function(keys, action)
    bindings[keys] = action
  end,
  define_submap = function() end,
  get_active_window = function()
    return active_window
  end,
  dispatch = function(action)
    dispatched[#dispatched + 1] = action
  end,
}

dofile(directory .. "/../bindings/tiling.lua")

-- No active window must still switch workspaces for navigation, but not for window movement.
bindings["SUPER + J"]()
assert(#dispatched == 1 and dispatched[1].name == "dsp.focus" and dispatched[1].args.workspace == "m+1")

bindings["SUPER + K"]()
assert(#dispatched == 2 and dispatched[2].name == "dsp.focus" and dispatched[2].args.workspace == "m-1")

bindings["SUPER + SHIFT + J"]()
bindings["SUPER + SHIFT + K"]()
assert(#dispatched == 2)

-- Horizontal navigation must cross to the adjacent monitor without an active window.
for _, binding in ipairs({ { "SUPER + H", "l" }, { "SUPER + L", "r" } }) do
  local action = bindings[binding[1]]
  if type(action) == "function" then
    action()
  end
  assert(#dispatched == 3 and dispatched[3].name == "dsp.focus" and dispatched[3].args.monitor == binding[2])
  dispatched[3] = nil
end

-- Existing horizontal focus and the RustDesk handoff stay in place with an active window.
active_window = {}
bindings["SUPER + L"]()
assert(dispatched[3].name == "dsp.focus" and dispatched[3].args.direction == "right")

bindings["SUPER + H"]()
local hostname_pipe = io.popen("hostname")
local hostname = hostname_pipe:read("*l")
hostname_pipe:close()
if hostname == "antoinews-linux" then
  assert(dispatched[4].name == "dsp.exec_cmd" and dispatched[4].args:find("rustdesk-focus-handoff.sh", 1, true))
else
  assert(dispatched[4].name == "dsp.focus" and dispatched[4].args.direction == "left")
end

print("empty workspace navigation passed")
