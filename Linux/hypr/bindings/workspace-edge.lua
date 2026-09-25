-- Whether a tiled window can be reached vertically before leaving this workspace.
return function(active, windows, direction)
  local active_y = active.at.y + active.size.y / 2

  for _, window in ipairs(windows) do
    if window ~= active and window.mapped and not window.hidden and not window.floating then
      local y = window.at.y + window.size.y / 2
      if (direction == "down" and y > active_y) or (direction == "up" and y < active_y) then
        return true
      end
    end
  end

  return false
end
