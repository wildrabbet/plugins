-- Chat Range's colour, settings and square outlines. Client-side only.
local M = {presets = {'6EE8FF', 'FFBD69', 'B8A1FF', 'FFFFFF'}}
function M.colour(text)
  if type(text) ~= 'string' or #text > 7 then return nil end
  text = text:gsub('^#', ''):upper()
  return #text == 6 and text:match('^%x+$') and text or nil
end
function M.settings(saved)
  saved = type(saved) == 'table' and saved or {}
  return {visible = saved.visible ~= false, colour = M.colour(saved.colour) or M.presets[1]}
end
function M.rgba(colour, alpha)
  return assert(tonumber(M.colour(colour), 16)) * 256 + math.floor(alpha * 255 + 0.5)
end
function M.nextColour(colour)
  for i, value in ipairs(M.presets) do if value == colour then return M.presets[i % #M.presets + 1] end end
  return M.presets[1]
end
function M.outline(x, z, radius)
  if radius ~= 10 and radius ~= 13 then return nil end
  if type(x) ~= 'number' or type(z) ~= 'number' or x ~= math.floor(x) or z ~= math.floor(z)
    or x < 0 or z < 0 or x > 12799 or z > 12799 then return nil end
  local lowX, lowZ, side, points = x - radius, z - radius, radius * 2 + 1, {}
  -- Quarter-tile samples follow short ramps and stair surfaces more closely.
  for i = 0, side * 4 - 1 do points[#points + 1] = {lowX + i / 4, lowZ} end
  for i = 0, side * 4 - 1 do points[#points + 1] = {lowX + side, lowZ + i / 4} end
  for i = 0, side * 4 - 1 do points[#points + 1] = {lowX + side - i / 4, lowZ + side} end
  for i = 0, side * 4 - 1 do points[#points + 1] = {lowX, lowZ + side - i / 4} end
  return points
end
function M.links(heights)
  local lines = {}
  for i, height in ipairs(heights) do
    local nextIndex = i % #heights + 1
    -- Break at cliffs instead of drawing diagonal fences through open space.
    if math.abs(height - heights[nextIndex]) <= 256 then
      lines[#lines + 1] = i - 1; lines[#lines + 1] = nextIndex - 1
    end
  end
  return lines
end
return M
