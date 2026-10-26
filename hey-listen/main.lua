-- Hey, Listen! 0.3.1
-- 3D arrows to track any NPC in the game.

local VERSION = "0.3.1"
local RetroUI = require("retro_ui")
local ListenUI = require("listen_ui")
local MAX_SHOWN = 30                 -- NPCs drawn at once (the nearest)
local RANGE = 40                     -- tiles
local LIFT = 700                     -- arrow height over the feet when the bounding box can't be used (world units)
local TILE = 512
local ADD, REMOVE = "Point at NPC", "Stop pointing"
local MAP_INTERFACES = { 1465, 1920, 1319 }   -- TOPLEVEL_V2_MINIMAP, ..._MINIMAP_LEGACY, ..._MINIMAP_CLASSIC (game data)
local MAP_PIECES = 150               -- component ids looked at in each
local PING_GAP = 100                 -- client ticks between two sounds for one NPC on the list (2 s)

local function get(fn)               -- read a game value; nil if it is not there
    local ok, value = pcall(fn)
    if ok then return value end
end

-- "Zanaris choir" and "zanaris_choir" are one NPC: names compare on letters and digits only
local function plain(s) return (tostring(s or ""):gsub("<[^>]*>", ""):lower():gsub("[^%w]", "")) end

-- Colours ------------------------------------------------------------------------------------------------------------
local COLOURS = { "rainbow", "green", "pink", "orange", "cyan", "yellow", "purple", "red", "blue", "white" }
local FIXED = { green = { 0.35, 1, 0.45 }, pink = { 1, 0.43, 0.78 }, orange = { 1, 0.63, 0.25 }, cyan = { 0.36, 1, 0.95 },
                yellow = { 1, 0.89, 0.36 }, purple = { 0.78, 0.49, 1 }, red = { 1, 0.3, 0.3 }, blue = { 0.27, 0.71, 1 },
                white = { 1, 1, 1 } }
local function hsv(h)                -- a fully bright, fully saturated colour at hue h (0-1)
    local i = math.floor(h * 6) % 6
    local f = h * 6 - math.floor(h * 6)
    local q, t = 1 - f, f
    if i == 0 then return { 1, t, 0 } elseif i == 1 then return { q, 1, 0 } elseif i == 2 then return { 0, 1, t }
    elseif i == 3 then return { 0, q, 1 } elseif i == 4 then return { t, 0, 1 } end
    return { 1, 0, q }
end
local function packed(c, alpha)      -- 0xRRGGBBAA for shapes
    local function b(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return ((b(c[1]) * 256 + b(c[2])) * 256 + b(c[3])) * 256 + (alpha or 255)
end

local SOUNDS = {
    { "popup", "Popup", "ARCH_INFO_POPUP" }, { "sparkle", "Sparkle", "LEVEL_UP_SPARKLE" },
    { "task", "Task done", "TASK_COMPLETE_01" }, { "coins", "Coins", "GE_COLLECT_COINS" }, { "bell", "Bell", "BELL_1" },
    { "church", "Church bell", "CHURCH_BELL" }, { "crier", "Town crier", "TOWN_CRIER_BELL_RING_1" },
    { "chime", "Chime", "TARDDIAD_SINGLE_CHIME_1" }, { "ding", "Ding", "MTXFEST17_CAROUSEL_DING_01" },
    { "whistle", "Whistle", "WHISTLE_CALL" }, { "horn", "Horn", "DOM_ARENA_BLOW_HORN" },
    { "fanfare", "Fanfare", "CLAN_THEATRE_MUSIC_FANFARE" },
}
local soundBy = {}
for _, s in ipairs(SOUNDS) do soundBy[s[1]] = s end
local missingSaid = {}
local function play(key)
    local s = soundBy[key]
    if not s then return end
    local n = get(function() return id.Sound[s[3]] end)
    if n == nil then
        if not missingSaid[key] then missingSaid[key] = true; log("Hey, Listen! - the game has no sound " .. s[3] .. "; playing Popup") end
        n = get(function() return id.Sound.ARCH_INFO_POPUP end)
    end
    if n == nil then return end
    local played = pcall(function()
        local p = audio.SoundPlaybackParams.new()
        p.type, p.audioBus, p.emitterShape = audio.SoundType.SCRIPT, audio.AudioBus.SFX, audio.EmitterShape.NONE
        audio.Play(n, p)
    end)
    if not played then pcall(audio.Play, n) end
end

-- Settings: saved as a table ------------------------------------------------------------------------------------------
-- list: { name, id (nil = every NPC of that name), colour, arrow, outline, dot, sound ("off" or a SOUNDS key) }
local prefs = { list = {}, outlines = true, arrows = true, ping = true, minimap = true, distance = true, compass = true,
                colour = "rainbow", scale = 4, piece = nil, win = { state = "small", x = 40, y = 220 } }
local validColour = {}
for _, c in ipairs(COLOURS) do validColour[c] = true end
local function cleanEntry(e)
    if type(e) ~= "table" or type(e.name) ~= "string" or plain(e.name) == "" then return nil end
    local idn = tonumber(e.id)
    return { name = e.name, id = (idn and idn >= 0 and idn == math.floor(idn)) and idn or nil,
             colour = validColour[e.colour] and e.colour or "rainbow", arrow = e.arrow ~= false, outline = e.outline ~= false,
             dot = e.dot ~= false, sound = (e.sound == "off" or soundBy[e.sound]) and e.sound or "popup" }
end
local saved = get(function() return PersistentDB:GetStructuredData("overHere") end)
if type(saved) == "table" then
    for k, v in pairs(saved) do
        if k ~= "list" and k ~= "win" and prefs[k] ~= nil and type(v) == type(prefs[k]) then prefs[k] = v end
        if k == "piece" and type(v) == "string" then prefs.piece = v end
    end
    if type(saved.list) == "table" then
        for _, e in ipairs(saved.list) do prefs.list[#prefs.list + 1] = cleanEntry(e) end
    elseif type(saved.names) == "string" then
        for entry in saved.names:gmatch("[^,]+") do
            local e = cleanEntry({ name = entry:gsub("^%s+", ""):gsub("%s+$", ""), colour = saved.colour,
                                   sound = saved.ping == false and "off" or "popup" })
            if e then prefs.list[#prefs.list + 1] = e end
        end
    end
    if type(saved.win) == "table" then
        local s = saved.win.state
        if s == "small" or s == "big" or s == "min" or s == "closed" then prefs.win.state = s end
        if tonumber(saved.win.x) then prefs.win.x = math.floor(tonumber(saved.win.x)) end
        if tonumber(saved.win.y) then prefs.win.y = math.floor(tonumber(saved.win.y)) end
    end
end
prefs.names = nil
if not validColour[prefs.colour] then prefs.colour = "rainbow" end
prefs.scale = math.max(1, math.min(16, tonumber(prefs.scale) or 4))
local function save() pcall(function() PersistentDB:SetStructuredData("overHere", prefs) end) end

-- The list ------------------------------------------------------------------------------------------------------------
local model = { ui = nil }           -- (one table: the main chunk stays well under Lua's 200 locals)
function model.label(e) return e.name .. (e.id and (" #" .. e.id) or "") end
function model.indexOf(name, idn)
    for i, e in ipairs(prefs.list) do
        if (idn and e.id == idn) or (not idn and not e.id and plain(e.name) == plain(name)) then return i end
    end
end
function model.changed()
    save()
    if model.ui then model.ui.Refresh() end
end
function model.add(name, idn)
    if plain(name) == "" or model.indexOf(name, idn) then return false end
    prefs.list[#prefs.list + 1] = cleanEntry({ name = name, id = idn, colour = prefs.colour })
    model.changed()
    log("Hey, Listen! - now pointing at " .. model.label(prefs.list[#prefs.list]))
    return true
end
function model.removeAt(i)
    local e = table.remove(prefs.list, i)
    if not e then return end
    model.changed()
    log("Hey, Listen! - stopped pointing at " .. model.label(e))
end
function model.cycleColour(i)
    local e = prefs.list[i]
    if not e then return end
    for k, c in ipairs(COLOURS) do
        if c == e.colour then e.colour = COLOURS[k % #COLOURS + 1] break end
    end
    model.changed()
end
function model.toggle(i, key)
    local e = prefs.list[i]
    if e and (key == "arrow" or key == "outline" or key == "dot") then e[key] = not e[key]; model.changed() end
end
function model.setSound(i, key)
    local e = prefs.list[i]
    if e and (key == "off" or soundBy[key]) then
        e.sound = key
        model.changed()
        if key ~= "off" then play(key) end
    end
end
function model.chip(e)               -- the colour chip: "rainbow" or 0xRRGGBBAA
    if e.colour == "rainbow" then return "rainbow" end
    return packed(FIXED[e.colour] or FIXED.green)
end
function model.soundLabel(key) return key == "off" and "off" or (soundBy[key] and soundBy[key][2] or "off") end
-- "Zanaris choir, Seren spirit, Lesser demon #82" -> the list, and back
function model.copyText()
    local parts = {}
    for _, e in ipairs(prefs.list) do parts[#parts + 1] = model.label(e) end
    return table.concat(parts, ", ")
end
function model.addTyped(text, nameOfId)
    local added = 0
    for item in tostring(text or ""):gmatch("[^,]+") do
        item = item:gsub("^%s+", ""):gsub("%s+$", "")
        local name, idn = item:match("^(.-)%s*#(%d+)$")
        if not idn and item:match("^%d+$") then name, idn = "", item end
        idn = tonumber(idn)
        if idn and (not name or name == "") then name = nameOfId and nameOfId(idn) or nil end
        if name and plain(name) ~= "" and model.add(name, idn) then added = added + 1 end
        if not idn and item ~= "" and model.add(item, nil) then added = added + 1 end
    end
    return added
end
function model.setMaster(key)
    if prefs[key] ~= nil and type(prefs[key]) == "boolean" then prefs[key] = not prefs[key]; model.changed() end
end

-- The right-click entries (NPC Tags' method: next to Cancel, Alt held) ----------------------------------------------
local function menuText(entry)
    local override = get(function() return entry.overrideText end)
    if override and override ~= "" then return override end
    return get(function() return entry.fullText end)
end
local function isOurs(entry, label)
    return get(function() return entry.actionEntryType == MiniMenuEntryType.PLUGIN end) == true and menuText(entry) == label
end
local function indexOf(menu, label)
    for i = 1, menu.entryCount do if isOurs(menu.entries[i], label) then return i end end
end
local function cancelIndex(menu)
    for i = 1, menu.entryCount do
        if get(function() return menu.entries[i].actionType == MiniMenuActionType.CANCEL end) then return i end
    end
end
local function placeLow(menu, label)
    for _ = 1, 64 do
        local cancel, at = cancelIndex(menu), indexOf(menu, label)
        if not cancel or not at then return end
        local target = cancel + (cancel <= menu.entryCount / 2 and 1 or -1)
        if at == target then return end
        menu:Swap(at, at + (target > at and 1 or -1))
    end
end
local function altHeld()             -- if the game can't say, treat it as held so the entry isn't lost
    if get(function() return Keyboard.IsAvailable() end) ~= true then return true end
    return get(function() return Keyboard.IsAltDown() end) == true
end
local function onMenu(event)
    local menu = event.miniMenu
    local count = menu.entryCount
    if count < 3 or count > 64 or not altHeld() then return end
    if indexOf(menu, ADD) or indexOf(menu, REMOVE) then return end
    local npc
    for i = count, 1, -1 do
        local data = get(function() return menu.entries[i].npcData end)
        npc = data and get(function() return data.entity end)
        if npc then break end
    end
    local name = npc and get(function() return npc.displayName end)
    if plain(name) == "" then return end
    name = tostring(name):gsub("<[^>]*>", "")
    if model.indexOf(name, nil) then
        menu:Add(REMOVE, function() local at = model.indexOf(name, nil); if at then model.removeAt(at) end end)
        placeLow(menu, REMOVE)
    else
        menu:Add(ADD, function() model.add(name, nil) end)
        placeLow(menu, ADD)
    end
end
local menuError = nil
Event.MiniMenuReady.Subscribe("overHereMenu", function(event)
    local ok, problem = pcall(onMenu, event)
    if not ok and problem ~= menuError then log("Hey, Listen! - menu: " .. tostring(problem)) end
    menuError = not ok and problem or nil
end)

-- Shapes: tile outlines, arrows and the compass, made once -----------------------------------------------------------
local function tileShape()
    local e = 240
    local shape = ShapeData.new()
    shape.positions = {
        Vector3.new(-e, 0, -e), Vector3.new(e, 0, -e), Vector3.new(e, 0, e), Vector3.new(-e, 0, e),
        Vector3.new(-e, 0, -e), Vector3.new(e, 0, -e), Vector3.new(e, 0, e), Vector3.new(-e, 0, e),
    }
    shape.rgba = { 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFF40, 0xFFFFFF40, 0xFFFFFF40, 0xFFFFFF40 }
    shape.lines = { 0, 1, 1, 2, 2, 3, 3, 0 }
    shape.tris = { 4, 5, 6, 4, 6, 7 }
    return shape
end
-- An arrow pointing down at the NPC: a four-sided point (tip at 0) under a square shaft, white so it can be tinted
local function arrowShape()
    local w, s, neck, top = 150, 55, 260, 560
    local shape = ShapeData.new()
    shape.positions = {
        Vector3.new(0, 0, 0),
        Vector3.new(-w, neck, -w), Vector3.new(w, neck, -w), Vector3.new(w, neck, w), Vector3.new(-w, neck, w),
        Vector3.new(-s, neck, -s), Vector3.new(s, neck, -s), Vector3.new(s, neck, s), Vector3.new(-s, neck, s),
        Vector3.new(-s, top, -s), Vector3.new(s, top, -s), Vector3.new(s, top, s), Vector3.new(-s, top, s),
    }
    local rgba = {}
    for i = 1, 13 do rgba[i] = 0xFFFFFFE6 end
    shape.rgba = rgba
    shape.tris = { 0, 2, 1, 0, 3, 2, 0, 4, 3, 0, 1, 4, 1, 2, 3, 1, 3, 4,
                   5, 6, 10, 5, 10, 9, 6, 7, 11, 6, 11, 10, 7, 8, 12, 7, 12, 11, 8, 5, 9, 8, 9, 12, 9, 10, 11, 9, 11, 12 }
    shape.lines = { 0, 1, 0, 2, 0, 3, 0, 4, 1, 2, 2, 3, 3, 4, 4, 1, 9, 10, 10, 11, 11, 12, 12, 9 }
    return shape
end
local COMPASS_STEPS = 16
local function compassShape(k)
    local a = k * 2 * math.pi / COMPASS_STEPS
    local dx, dz = math.cos(a), math.sin(a)
    local function at(u, v) return Vector3.new(u * dx - v * dz, 24, u * dz + v * dx) end
    local shape = ShapeData.new()
    shape.positions = { at(380, -45), at(600, -45), at(600, 45), at(380, 45), at(600, -150), at(820, 0), at(600, 150) }
    local rgba = {}
    for i = 1, 7 do rgba[i] = 0xFFFFFFE6 end
    shape.rgba = rgba
    shape.tris = { 0, 1, 2, 0, 2, 3, 4, 5, 6 }
    shape.lines = { 0, 1, 1, 4, 4, 5, 5, 6, 6, 2, 2, 3, 3, 0 }
    return shape
end
local outlines, arrows, compass = {}, {}, {}
do
    local tile, arrow = tileShape(), arrowShape()
    for i = 1, MAX_SHOWN do
        local o = ShapeList.CreateInstance("overHereTile" .. i)
        if o then o:SetShapeData(tile); o.visible = false; outlines[#outlines + 1] = { shape = o } end
        local a = ShapeList.CreateInstance("overHereArrow" .. i)
        if a then a:SetShapeData(arrow); a.visible = false; arrows[#arrows + 1] = { shape = a } end
    end
    for k = 0, COMPASS_STEPS - 1 do
        local c = ShapeList.CreateInstance("heyListenCompass" .. k)
        if c then c:SetShapeData(compassShape(k)); c.visible = false end
        compass[k] = c
    end
end

-- Minimap dots: a dark square behind a coloured one; distances: a number over each arrow. Made once. -----------------
local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local DOT, RIM = 6, 8
local dots, labels = {}, {}
for i = 1, MAX_SHOWN do
    local back = ui.Rectangle.new(layer)
    back.fill, back.clickthrough, back.hidden = true, true, true
    back:SetSize(RIM, RIM)
    pcall(function() back.colour = Vector4.new(0.02, 0.02, 0.03, 0.85) end)
    local front = ui.Rectangle.new(layer)
    front.fill, front.clickthrough, front.hidden = true, true, true
    front:SetSize(DOT, DOT)
    dots[i] = { back = back, front = front }
    local t = ui.Text.new(layer)
    t:SetSize(60, 20)
    t.font = id.Font.MUSEO_SANS_15PT_REGULAR
    t.clickthrough, t.hidden = true, true
    pcall(function() t.isShadowed = true end)
    pcall(function() t:AlignTo(ui.AlignMode.CENTRE) end)
    labels[i] = { piece = t }
end

-- Where the minimap is: the biggest square piece of the minimap windows (or the one picked in the cog) -------------
local map = { candidates = {}, at = nil, told = false, lastFind = -1e9 }
local function rectOf(comp)
    local w, h = get(function() return comp.width end), get(function() return comp.height end)
    local at = get(function() return comp.xyGlobal end)
    if type(w) ~= "number" or type(h) ~= "number" or not at or type(at.x) ~= "number" then return nil end
    if get(function() return comp.hidden end) == true then return nil end
    return { x = at.x, y = at.y, w = w, h = h }
end
local function findMinimap()
    local list = {}
    for _, iface in ipairs(MAP_INTERFACES) do
        if get(function() return ui.Interfaces:GetInterface(iface) end) then
            for c = 0, MAP_PIECES do
                local comp = get(function() return ui.Interfaces:GetComponent(iface, c) end)
                local r = comp and rectOf(comp)
                if r and r.w >= 100 and r.h >= 100 and r.w / r.h > 0.85 and r.w / r.h < 1.18 then
                    r.key = iface .. ":" .. c
                    list[#list + 1] = r
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.w * a.h > b.w * b.h end)
    map.candidates = list
    local pick = list[1]
    for _, r in ipairs(list) do if r.key == prefs.piece then pick = r end end
    map.at = pick
    if not map.told and #list > 0 then
        map.told = true
        local parts = {}
        for i, r in ipairs(list) do
            if i > 8 then break end
            parts[#parts + 1] = string.format("%s %dx%d at %d,%d", r.key, r.w, r.h, r.x, r.y)
        end
        log("Hey, Listen! - minimap pieces (biggest first): " .. table.concat(parts, "; ") .. ". Using " .. pick.key .. ".")
    end
end

-- Which NPCs: once per server tick, the nearest on the list -----------------------------------------------------------
local now = 0
local scan = { targets = {}, counts = {}, lastPing = {}, near = {}, wantNear = false, nearest = nil }
local function liftOf(npc, at)
    local box = get(function() return npc.aabb end)
    local low = box and get(function() return box.minimum.y end)
    local high = box and get(function() return box.maximum.y end)
    if type(low) == "number" and type(high) == "number" and math.abs(low - at.y) < 300 and high - low > 100 and high - low < 8000 then
        return high + 120 - at.y
    end
    return LIFT
end
-- the list entry an NPC belongs to: one for its exact ID first, else one for its name
local function entryFor(n, byId, byName)
    local cid = get(function() return n.configID end)
    local pid = get(function() return n.parentConfigID end)
    return (cid and byId[cid]) or (pid and byId[pid]) or byName[plain(get(function() return n.displayName end))]
end
Event.ServerLogic.Subscribe("overHereFind", function()
    pcall(function()
        scan.targets = {}
        if now - map.lastFind >= 500 or not map.at then map.lastFind = now; pcall(findMinimap) end
        if #prefs.list == 0 and not scan.wantNear then scan.counts, scan.nearest = {}, nil; return end
        local me = get(function() return Player.GetEntity() end)
        local here = me and get(function() return me.coordGrid end)
        local mine = me and get(function() return me.position end)
        if not here then return end
        local byId, byName = {}, {}
        for _, e in ipairs(prefs.list) do
            if e.id then byId[e.id] = byId[e.id] or e else byName[plain(e.name)] = byName[plain(e.name)] or e end
        end
        local list, counts, near = {}, {}, {}
        for _, n in ipairs(get(function() return NPCList.ByDistance(here, RANGE) end) or {}) do
            local at = get(function() return n.isValid ~= false and n.position end)
            local d = (at and mine) and ((at.x - mine.x) ^ 2 + (at.z - mine.z) ^ 2) or math.huge
            local tiles = (at and mine) and math.floor(math.max(math.abs(at.x - mine.x), math.abs(at.z - mine.z)) / TILE + 0.5) or nil
            local e = at and entryFor(n, byId, byName)
            if e then
                local size = tonumber(get(function() return n.config.gridSize end)) or 1
                list[#list + 1] = { npc = n, d = d, at = at, entry = e, tiles = tiles, size = math.max(1, math.min(size, 10)) }
                counts[e] = (counts[e] or 0) + 1
            end
            if scan.wantNear and at and tiles and tiles <= 20 then
                local name = tostring(get(function() return n.displayName end) or ""):gsub("<[^>]*>", "")
                if plain(name) ~= "" then
                    local row = near[name]
                    if not row then row = { name = name, count = 0, tiles = tiles }; near[name] = row; near[#near + 1] = row end
                    row.count = row.count + 1
                    if tiles < row.tiles then row.tiles = tiles end
                end
            end
        end
        table.sort(list, function(a, b) return a.d < b.d end)
        for i = 1, math.min(MAX_SHOWN, #list) do
            scan.targets[i] = list[i]
            list[i].lift = list[i].at and liftOf(list[i].npc, list[i].at) or LIFT
        end
        scan.nearest = list[1]
        -- each NPC on the list plays its own sound when more of it come into range than there were a moment ago
        for e, c in pairs(counts) do
            if c > (scan.counts[e] or 0) and prefs.ping and e.sound ~= "off" and now - (scan.lastPing[e] or -1e9) >= PING_GAP then
                scan.lastPing[e] = now
                play(e.sound)
            end
        end
        scan.counts = counts
        if scan.wantNear then
            local rows = {}
            for _, r in ipairs(near) do rows[#rows + 1] = r end
            table.sort(rows, function(a, b) if a.tiles ~= b.tiles then return a.tiles < b.tiles end return a.name < b.name end)
            scan.near = rows
        end
        if model.ui then model.ui.Tick() end
    end)
end)

-- Every client tick: colours, outlines, arrows, distances, dots and the compass follow ---------------------------------
local function colourOf(e, i)
    if e.colour == "rainbow" then return hsv((now / 150 + i * 0.13) % 1) end
    return FIXED[e.colour] or FIXED.green
end
-- the camera's facing on the ground (x east, z north), for turning the minimap
local function facing()
    local cam, focus = get(function() return Camera.GetPosition() end), get(function() return Camera.GetFocusPosition() end)
    if not (cam and focus) then return nil end
    local a, b = focus.x - cam.x, focus.z - cam.z
    local len = math.sqrt(a * a + b * b)
    if len < 1 then return nil end
    return a / len, b / len
end
local lastFacing = { 0, 1 }
local function placeDots(mine)
    local m = map.at
    local fa, fb = facing()
    if fa then lastFacing = { fa, fb } else fa, fb = lastFacing[1], lastFacing[2] end
    local used = 0
    if prefs.minimap and m and mine then
        local cx, cy, radius = m.x + m.w / 2, m.y + m.h / 2, math.min(m.w, m.h) / 2 - RIM
        for i, t in ipairs(scan.targets) do
            local at = t.entry.dot and get(function() return t.npc.isValid ~= false and t.npc.position end)
            if at then
                local dx, dz = (at.x - mine.x) / TILE, (at.z - mine.z) / TILE
                local ahead, right = dx * fa + dz * fb, dx * fb - dz * fa       -- up the minimap = the way the camera faces
                local px, py = right * prefs.scale, -ahead * prefs.scale
                if px * px + py * py <= radius * radius then
                    used = used + 1
                    local d = dots[used]
                    local c = colourOf(t.entry, i)
                    d.back:SetPos(math.floor(cx + px - RIM / 2), math.floor(cy + py - RIM / 2))
                    d.front:SetPos(math.floor(cx + px - DOT / 2), math.floor(cy + py - DOT / 2))
                    pcall(function() d.front.colour = Vector4.new(c[1], c[2], c[3], 1) end)
                    d.back.hidden, d.front.hidden = false, false
                end
            end
        end
    end
    for i = used + 1, #dots do dots[i].back.hidden, dots[i].front.hidden = true, true end
end
local PANELS = { { 1473, 5 }, { 1464, 15 }, { 517, 201 }, { 1430, 0 }, { 1670, 0 }, { 1671, 0 }, { 1672, 0 }, { 1673, 0 },
                 { 137, 0 } }
local panels = { rects = {}, at = -1e9 }
local function rectIn(c, base, margin)
    local at = get(function() return c.xyGlobal end)
    local w, h = get(function() return c.width end), get(function() return c.height end)
    if not at or type(at.x) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return nil end
    return { at.x - base.x - margin, at.y - base.y - margin, at.x - base.x + w + margin, at.y - base.y + h + margin }
end
function panels.find()
    panels.at, panels.rects = now, {}
    local base = get(function() return layer.xyGlobal end) or { x = 0, y = 0 }
    local sw, sh = get(function() return layer.width end), get(function() return layer.height end)
    for _, p in ipairs(PANELS) do
        local c = get(function() return ui.Interfaces:GetComponent(p[1], p[2]) end)
        local r = c and get(function() return c.visibleGlobal end) ~= false and rectIn(c, base, 12)
        -- (a full-screen root isn't a panel: it would hide every number)
        if r and not (type(sw) == "number" and type(sh) == "number" and r[3] - r[1] >= sw * 0.6 and r[4] - r[2] >= sh * 0.6) then
            panels.rects[#panels.rects + 1] = r
        end
    end
end
function panels.over(x, y)
    if now - panels.at >= 150 then pcall(panels.find) end
    local base = get(function() return layer.xyGlobal end) or { x = 0, y = 0 }
    local m = map.at
    if m and x >= m.x - base.x - 12 and x <= m.x - base.x + m.w + 12 and y >= m.y - base.y - 12 and y <= m.y - base.y + m.h + 12 then
        return true
    end
    local win = model.ui and model.ui.window and model.ui.window:GetState() ~= "closed" and model.ui.window.layer
    local r = win and rectIn(win, base, 6)
    if r and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then return true end
    for _, q in ipairs(panels.rects) do
        if x >= q[1] and x <= q[3] and y >= q[2] and y <= q[4] then return true end
    end
    return false
end
-- where a world point is on the plugin layer; nil when it's off screen
local function onScreen(v)
    local s = get(function() return ScreenConvert.Vector3ToScreen(v) end)
    if not s or type(s.x) ~= "number" or type(s.y) ~= "number" then return nil end
    local base = get(function() return layer.xyGlobal end) or { x = 0, y = 0 }
    local x, y = s.x - base.x, s.y - base.y
    local w, h = get(function() return layer.width end), get(function() return layer.height end)
    if type(w) == "number" and type(h) == "number" and (x < 0 or y < 0 or x > w or y > h) then return nil end
    return x, y
end
local function showLabel(i, x, y, text, c)
    local l = labels[i]
    l.piece:SetPos(math.floor(x - 30), math.floor(y - 20))
    if l.text ~= text then l.piece.content = text; l.text = text end
    pcall(function() l.piece.colour = Vector4.new(c[1], c[2], c[3], 1) end)
    if l.piece.hidden then l.piece.hidden = false end
end
local compassShown = nil
local function placeCompass(mine)
    local t = scan.nearest
    local k = nil
    if prefs.compass and t and mine then
        local at = get(function() return t.npc.isValid ~= false and t.npc.position end)
        if at and not onScreen(Vector3.new(at.x, at.y + 200, at.z)) then
            local a = math.atan2 and math.atan2(at.z - mine.z, at.x - mine.x) or math.atan(at.z - mine.z, at.x - mine.x)
            k = math.floor(a / (2 * math.pi / COMPASS_STEPS) + 0.5) % COMPASS_STEPS
            local shape = compass[k]
            if shape then
                shape.translation = Vector3.new(mine.x, mine.y, mine.z)
                shape.colour = packed(colourOf(t.entry, 1))
                shape.visible = true
            end
        end
    end
    if compassShown ~= nil and compassShown ~= k and compass[compassShown] then compass[compassShown].visible = false end
    compassShown = k
end
Event.Logic.Subscribe("overHereFollow", function()
    pcall(function()
        now = now + 1
        local bob = math.sin(now / 8) * 60
        local usedO, usedA, usedL = 0, 0, 0
        for i, t in ipairs(scan.targets) do
            local at = get(function() return t.npc.isValid ~= false and t.npc.position end)
            if at then
                local c = colourOf(t.entry, i)
                if prefs.outlines and t.entry.outline and usedO < #outlines then
                    usedO = usedO + 1
                    local o = outlines[usedO]
                    o.shape.translation = Vector3.new(at.x, at.y + 8, at.z)
                    o.shape.colour = packed(c)
                    if o.size ~= t.size then o.size = t.size; pcall(function() o.shape.scale = Vector3.new(t.size, 1, t.size) end) end
                    o.shape.visible = true
                end
                if prefs.arrows and t.entry.arrow and usedA < #arrows then
                    usedA = usedA + 1
                    local a = arrows[usedA]
                    a.shape.translation = Vector3.new(at.x, at.y + t.lift + bob, at.z)
                    a.shape.colour = packed(c)
                    a.shape.visible = true
                    if prefs.distance and t.tiles and usedL < #labels then
                        local x, y = onScreen(Vector3.new(at.x, at.y + t.lift + bob + 620, at.z))
                        if x and not panels.over(x, y) then usedL = usedL + 1; showLabel(usedL, x, y, tostring(t.tiles), c) end
                    end
                end
            end
        end
        for i = usedO + 1, #outlines do outlines[i].shape.visible = false end
        for i = usedA + 1, #arrows do arrows[i].shape.visible = false end
        for i = usedL + 1, #labels do if not labels[i].piece.hidden then labels[i].piece.hidden = true end end
        local mine = get(function() return Player.GetEntity().position end)
        placeDots(mine)
        placeCompass(mine)
        if model.ui then model.ui.Animate() end
    end)
end)

-- The window ------------------------------------------------------------------------------------------------------------
local api = {
    list = function() return prefs.list end, label = model.label, chip = model.chip, soundLabel = model.soundLabel,
    sounds = SOUNDS, add = model.add, removeAt = model.removeAt, cycleColour = model.cycleColour, toggle = model.toggle,
    setSound = model.setSound, play = play, copyText = model.copyText, addTyped = model.addTyped,
    master = function(key) return prefs[key] end, setMaster = model.setMaster, indexOf = model.indexOf,
    status = function() return #scan.targets, scan.nearest and scan.nearest.tiles or nil end,
    near = function() return scan.near end, wantNear = function(on) scan.wantNear = on end,
    names = function() return require("npc_names") end,
    liveName = function(n) return get(function() return config.NPC.FromID(n).name end) end,
    win = prefs.win,
    onState = function(state) prefs.win.state = state; save() end,
    onMove = function(x, y) prefs.win.x, prefs.win.y = x, y; save() end,
}
do
    local ok, made = pcall(ListenUI.make, RetroUI, layer, api)
    if ok then model.ui = made else log("Hey, Listen! - window: " .. tostring(made)) end
end

-- The cog ---------------------------------------------------------------------------------------------------------
Event.SettingsLayerReady.Subscribe("overHereSettings", function(event)
    local font = id.Font.MUSEO_SANS_15PT_REGULAR
    local panel = ui.Layer.new(event.component)
    panel:SetPos(8, 8)
    panel:SetSize(420, 560)
    local function button(text, x, y, w, fn, parent)
        local b = ui.Button.new(parent or panel)
        b:SetPos(x, y); b:SetSize(w, 25); b.label = text
        b.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
        pcall(function() b.text.font = font end)
        b:Subscribe(ui.Hook.ONBUTTONPRESSED, function() fn(b) end)
        return b
    end
    local function text(s, x, y, w)
        local t = ui.Text.new(panel)
        t:SetPos(x, y); t:SetSize(w or 400, 24); t.font = font; t.clickthrough = true; t.content = s
        return t
    end
    local function onOff(v) return v and "on" or "off" end
    local function switch(label, key, x, y)
        button(label .. ": " .. onOff(prefs[key]), x, y, 200, function(b)
            prefs[key] = not prefs[key]; b.label = label .. ": " .. onOff(prefs[key]); model.changed()
        end)
    end
    local function windowOpen() return model.ui ~= nil and model.ui.window:GetState() ~= "closed" end
    button("Show window: " .. onOff(windowOpen()), 0, 0, 200, function(b)
        if model.ui then
            if windowOpen() then model.ui.window:Close() else model.ui.window:Open() end
        end
        b.label = "Show window: " .. onOff(windowOpen())
    end)
    switch("Tile outlines", "outlines", 0, 30)
    switch("Arrows", "arrows", 0, 60)
    switch("Distances", "distance", 0, 90)
    switch("Sounds", "ping", 0, 120)
    switch("Minimap dots", "minimap", 0, 150)
    switch("Compass", "compass", 0, 180)
    local function colourName() return prefs.colour:gsub("^%l", string.upper) end
    button("Colours: " .. colourName(), 210, 0, 200, function(b)          -- new ones, and every one on the list
        for k, word in ipairs(COLOURS) do
            if word == prefs.colour then prefs.colour = COLOURS[k % #COLOURS + 1] break end
        end
        for _, e in ipairs(prefs.list) do e.colour = prefs.colour end
        b.label = "Colours: " .. colourName(); model.changed()
    end)
    local scaleText = text("Minimap scale: " .. prefs.scale .. " px a tile", 210, 32, 200)
    local function setScale(v)
        prefs.scale = math.max(1, math.min(16, v)); scaleText.content = "Minimap scale: " .. prefs.scale .. " px a tile"; save()
    end
    button("Scale -", 210, 60, 96, function() setScale(prefs.scale - 0.5) end)
    button("Scale +", 314, 60, 96, function() setScale(prefs.scale + 0.5) end)
    local function pieceLabel() return "Minimap piece: " .. (map.at and map.at.key or "not found") end
    button(pieceLabel(), 210, 90, 200, function(b)
        local list = map.candidates
        if #list == 0 then return end
        local k = 1
        for i, r in ipairs(list) do if map.at and r.key == map.at.key then k = i % #list + 1 end end
        map.at, prefs.piece = list[k], list[k].key
        b.label = pieceLabel(); save()
    end)
    local note = text("", 0, 216)
    local rows = nil
    local function build()
        if rows then pcall(function() rows:Destroy() end) end
        rows = ui.Layer.new(panel)
        rows:SetPos(0, 246)
        rows:SetSize(420, 300)
        note.content = #prefs.list == 0 and "Hold Alt and right-click an NPC to point at it." or
            ("Pointing at (Alt + right-click an NPC to add more):")
        for i, e in ipairs(prefs.list) do
            if i > 8 then break end
            local y = (i - 1) * 30
            local label = ui.Text.new(rows)
            label:SetPos(0, y); label:SetSize(300, 25); label.font = font; label.clickthrough = true
            label.content = model.label(e)
            button("Remove", 330, y, 80, function() model.removeAt(i); build() end, rows)
        end
    end
    build()
end)

function PluginShutdown()
    Event.MiniMenuReady.Unsubscribe("overHereMenu")
    Event.ServerLogic.Unsubscribe("overHereFind")
    Event.Logic.Unsubscribe("overHereFollow")
    Event.SettingsLayerReady.Unsubscribe("overHereSettings")
    for i = 1, MAX_SHOWN do
        pcall(function() ShapeList.DestroyInstance("overHereTile" .. i) end)
        pcall(function() ShapeList.DestroyInstance("overHereArrow" .. i) end)
    end
    for k = 0, COMPASS_STEPS - 1 do pcall(function() ShapeList.DestroyInstance("heyListenCompass" .. k) end) end
    for _, d in ipairs(dots) do pcall(function() d.back:Destroy() end); pcall(function() d.front:Destroy() end) end
    for _, l in ipairs(labels) do pcall(function() l.piece:Destroy() end) end
    if model.ui then pcall(model.ui.Destroy) end
end

log("Hey, Listen! " .. VERSION .. ": on. " .. (#prefs.list == 0 and "Hold Alt and right-click an NPC to point at it." or
    ("Pointing at: " .. model.copyText())))
