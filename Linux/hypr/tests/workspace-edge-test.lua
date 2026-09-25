local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*)/")
local has_window_beyond = dofile(directory .. "/../bindings/workspace-edge.lua")

local function window(x, y, options)
  options = options or {}
  return {
    at = { x = x, y = y },
    size = { x = 100, y = 100 },
    mapped = options.mapped ~= false,
    hidden = options.hidden or false,
    floating = options.floating or false,
  }
end

local active = window(0, 0)

-- A window farther down/up keeps the directional action inside this workspace.
assert(has_window_beyond(active, { active, window(0, 110) }, "down"))
assert(has_window_beyond(active, { active, window(0, -110) }, "up"))

-- Side-by-side windows, or windows in the opposite direction, are not a vertical destination.
assert(not has_window_beyond(active, { active, window(110, 0) }, "down"))
assert(not has_window_beyond(active, { active, window(0, -110) }, "down"))
assert(not has_window_beyond(active, { active, window(0, 110) }, "up"))

-- Hidden and floating windows must not prevent moving to the next workspace at an edge.
assert(not has_window_beyond(active, {
  active,
  window(0, 110, { hidden = true }),
  window(0, 220, { floating = true }),
  window(0, 330, { mapped = false }),
}, "down"))

print("workspace edge decisions passed")
