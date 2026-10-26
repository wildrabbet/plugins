local M = {}

local floor, abs, max = math.floor, math.abs, math.max

M.DEFAULTS = {countdown = false, blink = false, catch_secs = 60, warn_secs = 30, danger_secs = 15, flash_secs = 5, collapsed_ttl_ms = 180000,
  forget_ms = 1800000, far_tiles = 64, near_tiles = 15, max_traps = 5, lay_secs = 1.8}
M.ROLES = {'set', 'caught', 'warn', 'danger', 'collapsed', 'text', 'backing', 'slot_ready', 'slot_busy', 'slot_full', 'unknown'}
M.PRESETS = {
  dusk = {'68A9FF', '5CE0C3', 'F1C66A', 'FF8A80', 'FF4D40', 'F8FAFC', '111827', '5CE0C3', 'F1C66A', '94A3B8', 'CBD5E1'},
  red_green = {'56B4E9', '0072B2', 'E69F00', 'F0E442', 'CC79A7', 'FFFFFF', '111827', '56B4E9', 'E69F00', 'CCCCCC', 'CCCCCC'},
  blue_yellow = {'7DD3C7', 'F2A3BD', 'FFFFFF', 'E86A91', 'B7BAC5', 'FFFFFF', '101318', '7DD3C7', 'F2A3BD', 'B7BAC5', 'FFFFFF'},
  high_contrast = {'FFFFFF', 'FFFFFF', 'FFFFFF', 'FFFFFF', 'FFFFFF', 'FFFFFF', '000000', 'FFFFFF', 'FFFFFF', 'FFFFFF', 'FFFFFF'},
  classic = {'4D9EFF', '59FF73', 'FF9E26', 'FF4D40', 'FF4D40', 'FFFFFF', '111111', '59FF73', 'FF9E26', 'AAAAAA', 'AAAAAA'},
}

function M.color(colorText)
  if type(colorText) ~= 'string' or #colorText > 7 then return nil end
  colorText = colorText:gsub('^#', '')
  if #colorText ~= 6 or colorText:find('[^%x]') then return nil end
  return {tonumber(colorText:sub(1, 2), 16) / 255, tonumber(colorText:sub(3, 4), 16) / 255, tonumber(colorText:sub(5, 6), 16) / 255}
end

function M.colorText(color)
  return string.format('%02X%02X%02X', floor(color[1] * 255 + .5), floor(color[2] * 255 + .5), floor(color[3] * 255 + .5))
end

function M.palette(name)
  local p = M.PRESETS[name]
  if not p then return nil end
  local out = {}
  for i, role in ipairs(M.ROLES) do out[role] = M.color(p[i]) end
  return out
end

M.COLORS = M.palette('dusk')
M.LABELS = {set = 'Set', caught = 'Caught', warn = 'Low', danger = 'Urgent', collapsed = 'Reset trap', unknown = 'Unknown state'}

local LAY1, LAY2 = 'you begin setting up the trap', 'you begin setting the'
local DISMANTLE = 'you dismantle the trap'
local COLLAPSE = 'trap that you laid has collapsed'
local FALLEN_SNARE = 'snare that you placed has fallen over'
local LOG_MAX, LAY_MAX = 300, 10
local TRAP_MAX, ID_MAX = 64, 128

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function learn(ids, id)
  if ids[id] or count(ids) < ID_MAX then ids[id] = true end
end

local function key(x, z, plane) return x .. ',' .. z .. ',' .. (plane or 0) end
local function dist(ax, az, bx, bz) return max(abs(ax - bx), abs(az - bz)) end
local function idOf(id) return (tostring(id):sub(1, 96):gsub('[,=\n\r]', '_')) end
local function since(now, at) return at and now - at or nil end

local T = {}
T.__index = T

function M.new(opts)
  local o = {}
  for k, v in pairs(M.DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do
    if M.DEFAULTS[k] ~= nil and type(v) == type(M.DEFAULTS[k]) then o[k] = v end
  end
  return setmetatable({opts = o, theme = 'dusk', colors = M.palette('dusk'), traps = {}, ids = {set = {}, caught = {}, collapsed = {}}, lay = {}, max_seen = o.max_traps,
    log = {}, dirty = false}, T)
end

function T:setTheme(name)
  local colors = M.palette(name)
  if not colors then return false end
  self.colors, self.theme = colors, name
  return true
end

function T:setColor(role, colorText)
  local color = M.color(colorText)
  if not self.colors[role] or not color then return false end
  self.colors[role] = color
  return true
end

function T:setTimes(values)
  if type(values) ~= 'table' then return false end
  local next = {}
  for _, key in ipairs({'catch_secs', 'warn_secs', 'danger_secs', 'flash_secs'}) do
    local n = values[key] == nil and self.opts[key] or tonumber(values[key])
    if not n or n ~= n or n ~= floor(n) or n < 0 or n > 600 then return false end
    next[key] = n
  end
  if next.catch_secs < 5 or next.warn_secs > next.catch_secs or next.danger_secs > next.warn_secs or next.flash_secs > next.danger_secs then return false end
  for k, v in pairs(next) do self.opts[k] = v end
  return true
end

function T:note(now, s)
  self.log[#self.log + 1] = string.format('%.1f %s', (now or 0) / 1000, s)
  while #self.log > LOG_MAX do table.remove(self.log, 1) end
end

function T:lay_secs()
  local n, sum = #self.lay, 0
  for _, v in ipairs(self.lay) do sum = sum + v end
  return n > 0 and sum / n or self.opts.lay_secs
end

-- a collapsed trap: red on its own tile until it is laid again, picked up, or 3 minutes pass
function T:collapse(k, t, x, z, plane, now)
  t = t or {x = x, z = z, plane = plane}
  t.state, t.at, t.caught_at = 'collapsed', now, nil
  self.traps[k] = t
end

function T:chat(line, now, tile)
  if type(line) ~= 'string' or type(now) ~= 'number' then return end
  local l = (line:sub(1, 4096):lower():gsub('<[^>]*>', ''))
  if l:find(LAY1, 1, true) or l:find(LAY2, 1, true) then
    if tile and type(tile.x) == 'number' and type(tile.z) == 'number' then
      self.pend = {x = tile.x, z = tile.z, plane = tile.plane or 0, at = now}
      self:note(now, 'lay at ' .. tile.x .. ',' .. tile.z)
    end
    self.lay_at = now
  elseif l:find(DISMANTLE, 1, true) then
    self.dismantle_at = now   -- the player's own check: the trap taken off in the next ~2 s is no collapse
  elseif l:find(COLLAPSE, 1, true) or l:find(FALLEN_SNARE, 1, true) then
    local r = self.last_removed
    if r and now - r.at < 1000 then   -- the trap went first, the words came after
      self:collapse(r.k, r.t, r.x, r.z, r.plane, now)
      self.last_removed = nil
      self:note(now, 'trap ' .. r.k .. ' collapsed (message after removal)')
    else
      self.collapse_at = now
      self:note(now, 'collapsed (message)')
    end
  end
end

-- Native hosts supply an observed state. They must establish ownership separately; IDs cannot establish it.
function T:observe(row, now, owned)
  if type(row)~='table' or type(row.x)~='number' or type(row.z)~='number' or type(now)~='number' then return false end
  if owned~=true or (row.state~='set' and row.state~='caught' and row.state~='collapsed' and row.state~='unknown') then return false end
  local k=key(row.x,row.z,row.plane)
  local t=self.traps[k]
  if not t and count(self.traps)>=TRAP_MAX then return false end
  t=t or {x=row.x,z=row.z,plane=row.plane or 0}
  if row.state=='caught' and t.state~='caught' then t.caught_at=now
  elseif row.state~='caught' then t.caught_at=nil end
  t.state,t.id,t.at=row.state,row.id,now
  t.species,t.family,t.detail=row.species,row.family,row.detail
  self.traps[k]=t
  return true
end

function T:object(x, z, plane, id, now)
  if type(x) ~= 'number' or type(z) ~= 'number' or id == nil or type(now) ~= 'number' then return end
  plane = plane or 0
  id = idOf(id)
  local k = key(x, z, plane)
  local t, P, ids = self.traps[k], self.pend, self.ids
  -- a new trap (or one laid again on a red tile): the first object near where the player laid one, within 4 s, that
  -- isn't a known catch or collapse
  if not t or (t.state == 'collapsed' and P and not ids.caught[id] and not ids.collapsed[id]) then
    if P and now - P.at < 4000 and P.plane == plane and dist(x, z, P.x, P.z) <= 2 and not ids.caught[id] and not ids.collapsed[id] then
      if not t and count(self.traps) >= TRAP_MAX then return end
      self.traps[k] = {x = x, z = z, plane = plane, state = 'set', id = id, at = now}
      if not ids.set[id] then learn(ids.set, id); self.dirty = true end
      self:note(now, 'trap ' .. k .. ' set ' .. id .. ' (stood ' .. P.x .. ',' .. P.z .. ')')
      local d = (now - P.at) / 1000
      if d > 0.3 and d < 5 then
        self.lay[#self.lay + 1] = floor(d * 100 + 0.5) / 100
        while #self.lay > LAY_MAX do table.remove(self.lay, 1) end
        self.dirty = true
      end
      self.pend = nil
    end
    return
  end
  local state
  if ids.set[id] then state = 'set'
  elseif ids.collapsed[id] then state = 'collapsed'
  elseif ids.caught[id] then state = 'caught'
  elseif since(now, self.collapse_at) and now - self.collapse_at < 2500 then
    state = 'collapsed'; learn(ids.collapsed, id); self.dirty = true; self.collapse_at = nil
  else state = 'caught'; learn(ids.caught, id); self.dirty = true end
  if state ~= t.state then self:note(now, 'trap ' .. k .. ' ' .. t.state .. ' -> ' .. state .. ' (' .. id .. ')') end
  if state == 'caught' and t.state ~= 'caught' then t.caught_at = now elseif state ~= 'caught' then t.caught_at = nil end
  t.state, t.id, t.at = state, id, now
end

-- a collapsing trap is taken off its tile (it drops as an item to lay again): taken off within 2 s of the collapse words
-- = red until laid again; within 2.5 s of the player's own dismantle = gone; else gone, but the words may still follow
function T:removed(x, z, plane, now, tile)
  if type(x) ~= 'number' or type(z) ~= 'number' or type(now) ~= 'number' then return end
  plane = plane or 0
  local k = key(x, z, plane)
  local t = self.traps[k]
  if since(now, self.collapse_at) and now - self.collapse_at < 2000 then
    -- Proximity cannot establish ownership of an object removed near another hunter.
    if t then
      self:collapse(k, t, x, z, plane, now)
      self.collapse_at = nil
      self:note(now, 'trap ' .. k .. ' collapsed (removed)')
    end
  elseif since(now, self.dismantle_at) and now - self.dismantle_at < 2500 then
    if t then self:note(now, 'trap ' .. k .. ' removed'); self.traps[k] = nil end
    self.last_removed = nil
  else
    if t then self:note(now, 'trap ' .. k .. ' removed'); self.traps[k] = nil end
    if t then self.last_removed = {k = k, t = t, x = x, z = z, plane = plane, at = now} end
  end
end

-- the player picked up a collapsed trap: an item into the backpack while they stand within 2 tiles of a red one, and
-- not right after their own check or a lay
function T:item_added(now, tile)
  if type(now) ~= 'number' or not tile or type(tile.x) ~= 'number' then return end
  if since(now, self.dismantle_at) and now - self.dismantle_at < 3000 then return end
  if since(now, self.lay_at) and now - self.lay_at < 2000 then return end
  local best, bd = nil, 3
  for k, t in pairs(self.traps) do
    if t.state == 'collapsed' and (t.plane or 0) == (tile.plane or 0) then
      local d = dist(t.x, t.z, tile.x, tile.z)
      if d < bd then best, bd = k, d end
    end
  end
  if best then self:note(now, 'trap ' .. best .. ' picked up (red box cleared)'); self.traps[best] = nil end
end

function T:forget(now, tile)
  local o = self.opts
  for k, t in pairs(self.traps) do
    local far = tile and type(tile.x) == 'number' and ((tile.plane or 0) ~= (t.plane or 0) or dist(t.x, t.z, tile.x, tile.z) > o.far_tiles)
    if far or now - t.at > o.forget_ms or (t.state == 'collapsed' and now - t.at > o.collapsed_ttl_ms) then self.traps[k] = nil end
  end
end

function T:view(now, tile)
  local o, out = self.opts, {}
  self:forget(now, tile)
  for _, t in pairs(self.traps) do
    local item = {x = t.x, z = t.z, plane = t.plane or 0, state = t.state, color = self.colors[t.state] or self.colors.set,
      label = t.detail and t.detail~='' and t.detail or M.LABELS[t.state], flash = false, text_color = self.colors.text, backing_color = self.colors.backing}
    if o.countdown and t.state == 'caught' and t.caught_at then
      local left = max(0, o.catch_secs - (now - t.caught_at) / 1000)
      -- Words remain distinct even with a monochrome palette.
      if left <= o.danger_secs then item.color = self.colors.danger; item.label = M.LABELS.danger
      elseif left <= o.warn_secs then item.color = self.colors.warn; item.label = M.LABELS.warn end
      item.flash = o.blink and left <= o.flash_secs
      item.left = left
      item.label = item.label .. string.format('  %d:%02d', floor(left / 60), floor(left % 60))
    end
    if t.state=='caught' and t.species then item.label=item.label .. ': ' .. t.species end
    item.species,item.family=t.species,t.family
    out[#out + 1] = item
  end
  table.sort(out, function(a, b) if a.x ~= b.x then return a.x < b.x end; if a.z ~= b.z then return a.z < b.z end; return a.plane < b.plane end)
  return out
end

function T:slot(now)
  local standing = 0
  for _, t in pairs(self.traps) do if t.state ~= 'collapsed' then standing = standing + 1 end end
  if standing > self.max_seen then self.max_seen = standing; self.dirty = true end
  local dur = self:lay_secs() * 1000
  local busy = since(now, self.lay_at) ~= nil and now - self.lay_at < dur
  local left = busy and (dur - (now - self.lay_at)) / 1000 or 0
  return {standing = standing, max = self.max_seen, busy = busy, ready = not busy and standing < self.max_seen,
    left_s = left, frac = busy and left / (dur / 1000) or 0}
end

function T:counts()
  local c = {set = 0, caught = 0, collapsed = 0}
  for _, t in pairs(self.traps) do c[t.state] = (c[t.state] or 0) + 1 end
  return c
end

------------------------------------------------------------ the learned parts, as key=value lines
local function keys(set)
  local out = {}
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return table.concat(out, ',')
end
function M.encode(tr)
  local lay = {}
  for i, v in ipairs(tr.lay) do lay[i] = string.format('%.2f', v) end
  return table.concat({'max=' .. tr.max_seen, 'lay=' .. table.concat(lay, ','), 'set=' .. keys(tr.ids.set),
    'caught=' .. keys(tr.ids.caught), 'collapsed=' .. keys(tr.ids.collapsed)}, '\n')
end
function M.decode(tr, s)
  for line in tostring(s or ''):sub(1, 32768):gmatch('[^\n]+') do
    local k, v = line:match('^(%a+)=(.*)$')
    if k == 'max' and tonumber(v) then tr.max_seen = math.min(TRAP_MAX, max(tr.max_seen, floor(tonumber(v))))
    elseif k == 'lay' then
      tr.lay = {}
      for n in v:gmatch('[^,]+') do if tonumber(n) and #tr.lay < LAY_MAX then tr.lay[#tr.lay + 1] = tonumber(n) end end
    elseif k == 'set' or k == 'caught' or k == 'collapsed' then
      for id in v:gmatch('[^,]+') do learn(tr.ids[k], idOf(id)) end
    end
  end
  return tr
end

return M
