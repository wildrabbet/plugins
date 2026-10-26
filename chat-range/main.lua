-- Chat Range 1.0.2
-- See a range overlay around your character, with adjustable display colours.

local R = require('range')
local ok, saved = pcall(function() return PersistentDB:Get('settings') end)
local settings = R.settings(ok and saved or nil)
local hub = require('settings').new('rangeVisibility', {{'visible', 'Show range', settings.visible}},
  'Local display settings only. The 10/13-tile guides remain approximate.')
local rings, palette, field, hint = {}, nil, nil, nil
local lastTile, dirty, stopped, lastError = nil, false, false, nil

local function clearRings()
  for _, ring in ipairs(rings) do if ring.isValid then ring:Destroy() end end
  rings, lastTile = {}, nil
end
local function clearPalette()
  if palette then pcall(function() palette:Destroy() end) end
  palette, field, hint = nil, nil, nil
end
local function showHint(content)
  -- The game may have closed the cog since the last save attempt.
  if hint then pcall(function() hint.content = content end) end
end
local function save()
  local success, result = pcall(function() return PersistentDB:Set('settings', settings) end)
  dirty = not (success and result == true)
  showHint(dirty and 'Save failed; retrying.' or 'Six colour digits, e.g. 6EE8FF.')
end
local function chooseColour(text)
  local colour = R.colour(text)
  if not colour then showHint('Enter six colour digits.'); return end
  settings.colour = colour; if field then field.content = colour end; lastTile = nil; save()
end
local function text(parent, content, x, y, w)
  local item = ui.Text.new(parent)
  item:SetPos(x, y); item:SetSize(w, 20)
  item.font = id.Font.MUSEO_SANS_15PT_REGULAR; item.content = content
  item.clickthrough = true
  return item
end
local function button(parent, label, x, y, w, action)
  local item = ui.Button.new(parent)
  item:SetPos(x, y); item:SetSize(w, 24)
  item.stylesheetID = id.StyleSheet.BUTTON_DEFAULT; item.label = label
  item:Subscribe(ui.Hook.ONBUTTONPRESSED, function() if not stopped then action() end end)
  return item
end
Event.SettingsLayerReady.Subscribe('range-colours', function(event)
  if stopped then return end
  clearPalette()
  palette = ui.Layer.new(event.component)
  palette:SetPos(8, 90); palette:SetSize(320, 140)
  text(palette, 'Range colour', 0, 0, 280)
  for i, label in ipairs({'Cyan', 'Amber', 'Violet', 'White'}) do
    local colour = R.presets[i]
    button(palette, label, ((i - 1) % 2) * 126, 24 + math.floor((i - 1) / 2) * 28, 120,
      function() chooseColour(colour) end)
  end
  field = ui.InputField.new(palette)
  field:SetPos(0, 84); field:SetSize(120, 24)
  field.stylesheetID = id.StyleSheet.INPUT_DEFAULT
  field:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.ALPHANUMERIC, 6)
  field.text.font = id.Font.MUSEO_SANS_15PT_REGULAR; field.content = settings.colour
  button(palette, 'Apply colour', 126, 84, 120, function() chooseColour(field.content) end)
  hint = text(palette, 'Six colour digits, e.g. 6EE8FF.', 0, 112, 310)
end)
local function shape(tile, radius)
  local points = R.outline(tile.x, tile.z, radius)
  if not points then return nil end
  local data, positions, heights = ShapeData.new(), {}, {}
  for i, point in ipairs(points) do
    local x, z = point[1] * 512, point[2] * 512
    -- Base terrain omits raised scenery such as steps and platforms.
    local height, loaded = World.GetGroundHeight(tile.level, x, z, HeightOffsetType.LOCATION)
    if not loaded or height < 0 then return nil end
    heights[i] = height
    positions[i] = Vector3.new(x, height + 24, z)
  end
  local lines = R.links(heights)
  if #lines == 0 then return nil end
  data.positions, data.lines = positions, lines
  return data
end
local function update()
  if stopped then return end
  if hub.visible ~= settings.visible then
    settings.visible = hub.visible
    clearRings(); save()
  end
  if not Player.IsAvailable() or not World.IsAvailable() then clearRings(); return end
  if dirty then save() end
  if not settings.visible then return end
  local player = Player.GetEntity()
  if not player or not player.isValid then clearRings(); return end
  local tile = player.coordGrid
  local key = tile.level .. ':' .. tile.x .. ':' .. tile.z .. ':' .. settings.colour
  if key == lastTile and #rings == 2 and rings[1].isValid and rings[2].isValid then return end
  -- Build both before changing the display, so an unloaded edge cannot leave half a range.
  local shapes = {shape(tile, 10), shape(tile, 13)}
  if not shapes[1] or not shapes[2] then
    clearRings(); return
  end
  clearRings()
  for i, data in ipairs(shapes) do
    local ring = assert(ShapeList.CreateInstance('range-' .. i), 'Could not create range outline')
    rings[#rings + 1] = ring
    assert(ring:SetShapeData(data), 'Could not set range outline')
    ring.colour = R.rgba(settings.colour, i == 1 and 0.9 or 0.4)
    ring.lineWidth = 2; ring.ignoreDepth = false
  end
  lastTile = key
end
local function tick()
  local success, reason = pcall(update)
  if not success then
    clearRings()
    if reason ~= lastError then log('Chat Range: {}', tostring(reason)); lastError = reason end
  end
end
Event.ServerLogic.Subscribe('chat-range-update', tick)
Event.GameStateChanged.Subscribe('chat-range-context', function()
  if not stopped then clearRings() end
end)
tick()
return {stop = function()
  stopped = true; clearRings(); clearPalette()
  Event.ServerLogic.Unsubscribe('chat-range-update')
  Event.GameStateChanged.Unsubscribe('chat-range-context')
  Event.SettingsLayerReady.Unsubscribe('rangeVisibility')
  Event.SettingsLayerReady.Unsubscribe('range-colours')
end}
