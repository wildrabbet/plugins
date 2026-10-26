-- Soundbox! 0.2.3
-- Browse RuneScape sounds, play them and save your favourites.

-- Size and layout (interface units; the pixel art is drawn on a 3-unit grid)
local P = 3                          -- one art pixel
local W, H = 384, 585
local DOME = 108                     -- height of the arched top
local PAD = 30                       -- inside edge of the cabinet's wood
local ROWS, ROW_H = 9, 24            -- the display: 9 sounds at a time
local TUNER_W, GAP = 30, 6
local DW = W - 2 * PAD - TUNER_W - GAP
local TABS_Y, BAR_Y = 124, 157      -- the tab row and the category bar
local DY, DH = 195, ROWS * ROW_H
local READ_Y, BUTTONS_Y, GRILLE_Y = 417, 453, 489
local BUDGET = 2000                  -- game values read per client tick while searching for sounds
local EMPTY_RUN = 3000               -- this many empty config IDs in a row ends a search step

-- Colours (0xRRGGBBAA): black outlines, dark wood, chrome, RuneScape gold, and the bubble lights
local INK = 0x141010FF
local WOOD, WOOD_LIGHT, WOOD_DARK, WOOD_GRAIN = 0x7E3F22FF, 0xA05A30FF, 0x4F2412FF, 0x6E361CFF
local CHROME, CHROME_LIGHT, CHROME_DARK = 0xB9C4CCFF, 0xF2F6F8FF, 0x6F7C86FF
local GOLD, GOLD_LIGHT, GOLD_DARK = 0xE8B23CFF, 0xFFE08AFF, 0x9C6B1EFF
local TUBE = 0x2A140CFF
local GLASS, GLASS_LIGHT = 0x0E1A26FF, 0x23384CFF
local LCD, CLOTH = 0x10150EFF, 0x3A1414FF
local BULBS = { 0xFF4D4DFF, 0xFFB03BFF, 0xFFE45CFF, 0x5EE07AFF, 0x45B5FFFF, 0xC77DFFFF }
local CREAM, DARK, NUMBER, FADED = 0xFFF1C9FF, 0x2B1608FF, 0xF2C14EFF, 0x9FB3C8FF

local function get(fn)               -- read a game value; nil if it is not there
    local ok, value = pcall(fn)
    if ok then return value end
end
-- Local UI preferences only; neither this helper nor Soundbox reads chat.
local options = require("settings").new("soundboxSettings", {
    { "hideUnavailable", "Hide unavailable sounds", false },
    { "retry", "Retry unavailable sounds", true },
}, "An unavailable sound may still be loading. Turn hiding off to find and retry it.")

local nameParts, namesProblem = {}, ""
for part = 1, 99 do
    local ok, text = pcall(require, string.format("data/sounds%02d", part))
    if ok and type(text) == "table" then text = text[1] end    -- each part is { "<names>" }
    if not ok or type(text) ~= "string" then
        if part == 1 then namesProblem = tostring(text) end
        break
    end
    nameParts[part] = text
end
pcall(function() PersistentDB:SetString("namesProblem", namesProblem) end)
if namesProblem ~= "" then log("Soundbox: the sound names did not load (" .. namesProblem .. ")") end

-- The game's classic pixel fonts when it has them (looked up by name), otherwise its standard font.
local STANDARD = id.Font.MUSEO_SANS_15PT_REGULAR
local function pickFont(names)
    for _, name in ipairs(names) do
        local font = get(function() return id.Font[name:upper()] end)
        if font then return font, name end
    end
    for _, pair in ipairs(get(function() return config.Enum.FONT_NAME.values end) or {}) do
        local fontID, fontName = pair[1], tostring(pair[2]):lower()
        if type(fontID) ~= "number" then fontID = get(function() return fontID.id end) end
        for _, name in ipairs(names) do
            if fontID and fontName == name then return fontID, fontName end
        end
    end
    return STANDARD, "standard"
end
local TITLE_FONT, titleName = pickFont({ "b12_full", "b12" })
local FONT, textName = pickFont({ "p12_full", "p12", "p11_full" })
log("Soundbox: fonts " .. titleName .. " / " .. textName)

local function rgba(hex)             -- 0xRRGGBBAA -> Vector4
    local a = hex % 256; hex = (hex - a) / 256
    local b = hex % 256; hex = (hex - b) / 256
    local g = hex % 256; local r = (hex - g) / 256
    return Vector4.new(r / 255, g / 255, b / 255, a / 255)
end

local function textStyle(hex, horizontal, font)
    local style = ui.TextDataConfig.new()
    style.font = font or FONT
    style.colour = rgba(hex)
    style.alignHorizontal = horizontal or ui.AlignMode.TOPLEFT
    style.alignVertical = ui.AlignMode.CENTRE
    return style
end

-- Names from the game's data, made safe to draw: colour and image tags, control characters (a stray zero byte stops
-- text drawing) and spare spaces are taken out.
local function clean(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("<[^>]*>", ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- "ELFCITY2_HARP_NOTES" -> "Elfcity2 harp notes"
local function pretty(configName)
    local text = tostring(configName):lower():gsub("_", " ")
    return (text:gsub("^%l", string.upper))
end

-- The sounds found so far ----------------------------------------------------------------------------------------
-- Three collections. Each is one searchable list with nine-row pages.
local ALL = "All sounds"
local BOSSES, FAVOURITES = "All bosses", "Favourites"
local tabs = {
    { name = "Sounds" }, { name = "Bosses" }, { name = "Faves" },
}
local inCategory = { [ALL] = {}, [BOSSES] = {} }
local sounds, seen, byID = {}, {}, {} -- unique sounds; category membership; named sound lookup

local function newSound(label, soundID, kind, category)
    local sound = { label = label, lower = label:lower(), id = soundID, kind = kind, category = category,
                    categoryLower = category:lower() }
    return sound
end

local function addSound(category, label, soundID, kind)     -- the Sounds tab
    if byID[soundID] then return end
    local sound = newSound(label, soundID, kind, category)
    byID[soundID] = sound
    sounds[#sounds + 1] = sound
    table.insert(inCategory[ALL], sound)
end

local function addBossSound(boss, label, soundID)          -- boss labels, in one list
    local key = "boss|" .. boss .. "|" .. soundID
    if seen[key] then return end
    seen[key] = true
    local sound = newSound(boss .. " - " .. label, soundID, "boss", boss)
    table.insert(inCategory[BOSSES], sound)
end

-- Favourites are kept as { label, id, kind } entries
local favourites = get(function() return PersistentDB:GetStructuredData("favourites") end)
if type(favourites) ~= "table" then favourites = {} end

local function isFavourite(sound)
    for _, f in ipairs(favourites) do
        if sound and f.id == sound.id and f.label == sound.label then return true end
    end
    return false
end

local function favouriteSounds()
    local list = {}
    for _, f in ipairs(favourites) do
        -- Old versions allowed other number systems. Only retain named Sound IDs here.
        if type(f) == "table" and byID[f.id] and (f.kind == "sound" or f.kind == "boss") then
            local label = type(f.label) == "string" and f.label or byID[f.id].label
            list[#list + 1] = { label = label, lower = label:lower(), id = f.id, category = FAVOURITES,
                                categoryLower = "favourites", kind = f.kind }
        end
    end
    return list
end

-- Bosses: the game's own boss list (the Boss Slayer lists) names each boss's monster. Every monster with that name
-- (each phase and form of the boss) then gives up its sound settings and its idle and movement sounds.
local bossNames = {}                 -- monster name -> true
local bossWords = {}                 -- { boss name, WORD } to look for in sound names, e.g. { "Kalphite Queen", "KALPHITE_QUEEN" }
local COMMON = { THE = true, KING = true, QUEEN = true, LORD = true, GIANT = true, GREAT = true, DARK = true }
local function findBosses()
    local found = 0
    for _, listName in ipairs({ "BSLAYER_BOSS_LIST_ENUM", "BSLAY_INT_TO_STRUCT", "BSLAY_STRUCT_ALPHABETISED" }) do
        for _, pair in ipairs(get(function() return config.Enum[listName].values end) or {}) do
            local struct = pair[2]
            if type(struct) == "number" then struct = get(function() return config.Struct.FromID(struct) end) end
            for _, param in ipairs(struct and get(function() return struct.params end) or {}) do
                local value = get(function() return struct:GetParamValue(param) end)
                if value and get(function() return value.typeName end) == "NPC" then
                    local name = clean(get(function() return value.name end))
                    if name and name ~= "" and name ~= "null" and not bossNames[name] then
                        bossNames[name] = true
                        found = found + 1
                        local whole = name:upper():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
                        bossWords[#bossWords + 1] = { name, whole }
                        local first = whole:match("^[^_]+")
                        if first and first ~= whole and #first >= 4 and not COMMON[first] then
                            bossWords[#bossWords + 1] = { name, first }
                        end
                    end
                end
            end
        end
    end
    log("Soundbox: " .. found .. " bosses in the game's boss list")
end

-- The game's named sounds (id.Sound): the jukebox's list. "ARCH_INFO_POPUP" goes under "Arch" as "Arch info popup",
-- and under a boss on the Bosses tab when its name has that boss's name in it.
local function addNamed(name, soundID)
    local label = pretty(name)
    addSound(pretty(name:match("^([^_]+)") or name), label, soundID, "sound")
    local padded = "_" .. name:upper() .. "_"
    for _, boss in ipairs(bossWords) do
        if padded:find("_" .. boss[2] .. "_", 1, true) then addBossSound(boss[1], label, soundID) end
    end
end

local listed, names, byLine = 0, {}, true
local function findGameSounds()
    pcall(function()
        for name, soundID in pairs(id.Sound) do
            if type(name) == "string" and type(soundID) == "number" then listed = listed + 1; addNamed(name, soundID) end
        end
    end)
    if listed > 0 then
        log("Soundbox: the game listed " .. listed .. " named sounds")
        return
    end
    for _, text in ipairs(nameParts) do   -- read at load (see the top); split now
        for name in text:gmatch("[^\n]+") do names[#names + 1] = name end
    end
    nameParts = nil
    if #names > 0 then
        local asked, agree = 0, 0
        for _, n in ipairs({ 1, 2, #names // 2, #names - 1, #names }) do
            local value = get(function() return id.Sound[names[n]] end)
            if value ~= nil then asked = asked + 1; if value == n then agree = agree + 1 end end
        end
        byLine = asked > 0 and agree == asked -- no answers must not validate guessed IDs
        log("Soundbox: " .. #names .. " sound names; " .. agree .. " of " .. asked .. " checked match id.Sound"
            .. (byLine and "" or ", so each name is looked up"))
        return
    end
    -- No list: offer only this publicly named reference, not thousands of guessed IDs.
    local example = get(function() return id.Sound.ARCH_INFO_POPUP end)
    log("Soundbox: no sound names (ARCH_INFO_POPUP = " .. tostring(example) .. "); only known names are listed")
    if type(example) == "number" then addNamed("ARCH_INFO_POPUP", example) end
end

local function lookAtName(n)
    local name = names[n]
    if not name then return false end
    local soundID = byLine and n or get(function() return id.Sound[name] end)
    if type(soundID) == "number" then addNamed(name, soundID) end
    return true, 1
end

local steps = {
    { what = "bosses", once = findBosses },
    { what = "sound names", once = findGameSounds },
    { what = "game sounds", look = lookAtName },
}
local stepIndex, nextID, lastFound = 1, 0, 0
local ready = false

-- Searching ----------------------------------------------------------------------------------------------------------
-- Every word typed must match. Best first: the exact ID, then names starting with the word, then a word in the
-- name starting with it, then anywhere in the name or category. IDs match only known named sounds.
local category, query = ALL, ""
local results, sel, top = {}, 1, 1   -- what the display lists, the lit row, the first row shown
local current, playing, failed = nil, nil, false
local retry = nil
local unavailable = get(function() return PersistentDB:GetStructuredData("unavailableSounds") end)
if type(unavailable) ~= "table" then unavailable = {} end
local unavailableIDs = {}
for key, value in pairs(unavailable) do
    local n = tonumber(key)
    if value == true and n and n >= 0 and n == math.floor(n) then unavailableIDs[tostring(n)] = true end
end
local lastPlayback
local function remember(result, attempts, problem, explicit)
    lastPlayback = { id = current.id, name = current.label, result = result, attempts = attempts,
                     settings = explicit and "SCRIPT/SFX/NONE" or "default",
                     detail = tostring(problem or ""):sub(1, 200) }
    if playing then lastPlayback.isPlaying = get(function() return playing.isPlaying end) end
    pcall(function() PersistentDB:SetStructuredData("lastPlayback", lastPlayback) end)
end

local function terms(text)
    local list = {}
    for word in text:lower():gmatch("%S+") do list[#list + 1] = word end
    return list
end

local function score(sound, words)
    local total, idText = 0, tostring(sound.id)
    for _, word in ipairs(words) do
        if word == idText then total = total + 6
        elseif word:match("^%d+$") and idText:sub(1, #word) == word then total = total + 3
        elseif sound.lower:sub(1, #word) == word then total = total + 4
        elseif sound.lower:find(" " .. word, 1, true) then total = total + 3
        elseif sound.lower:find(word, 1, true) or sound.categoryLower:find(word, 1, true) then total = total + 1
        else return 0 end
    end
    return total
end

local tabNumber = 1
local function countOf(name)
    return name == FAVOURITES and #favouriteSounds() or #(inCategory[name] or {})
end

local tabCategory = { ALL, BOSSES, FAVOURITES }

local draw                           -- set further down, once the window exists

local function search(keepPlace)
    local words = terms(query)
        local source = category == FAVOURITES and favouriteSounds() or (inCategory[category] or {})
        if options.hideUnavailable then
            local visible = {}
            for _, sound in ipairs(source) do
                if not unavailableIDs[tostring(sound.id)] then visible[#visible + 1] = sound end
            end
            source = visible
        end
        if #words == 0 then
            results = source
        else
            local scored = {}
            for _, sound in ipairs(source) do
                local s = score(sound, words)
                if s > 0 then scored[#scored + 1] = { sound = sound, score = s } end
            end
            table.sort(scored, function(a, b)
                if a.score ~= b.score then return a.score > b.score end
                return a.sound.lower < b.sound.lower
            end)
            results = {}
            for _, entry in ipairs(scored) do results[#results + 1] = entry.sound end
        end
    if not keepPlace or sel > #results then sel, top = 1, 1 end
    draw()
end

-- The cabinet --------------------------------------------------------------------------------------------------------
local CX = W // 2
local topLayer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local saved = get(function() return PersistentDB:GetStructuredData("position") end)
local px = math.floor(type(saved) == "table" and tonumber(saved.x) or 80)
local py = math.floor(type(saved) == "table" and tonumber(saved.y) or 100)

local cabinet = ui.Layer.new(topLayer)
cabinet:SetPos(px, py)
cabinet:SetSize(W, H)

-- Half the width of the arched top at height y, for an arch `inset` units in from the edge, in whole art pixels.
local function domeHalf(y, inset)
    local t = (DOME - y) / (DOME - inset)
    if t > 1 then return 0 end
    return math.floor((CX - inset) * math.sqrt(math.max(0, 1 - t * t)) / P) * P
end

-- Clear rectangles under the whole jukebox take its clicks and mouse wheel, so they never reach the game behind it.
-- A click there (not on a button) shows the game's yellow "clicked nothing" cross, drawn by the jukebox itself.
local function swallow() return false end
local scrollPage                    -- bound after drawing; wheel events only browse
local function wheel(_, delta)
    if scrollPage then scrollPage(delta) end
    return false
end
local clickedNothing                 -- set once the cross can be drawn
local function blocker(x, y, w, h)
    local r = ui.Rectangle.new(cabinet)
    r.clickthrough = false           -- a false hook return only stops other listeners
    r:SetPos(x, y)
    r:SetSize(w, h)
    r.fill = true
    r.colour = Vector4.new(0, 0, 0, 0.004)
    r:Subscribe(ui.Hook.ONCLICK, function()
        if clickedNothing then clickedNothing() end
        return false
    end)
    r:Subscribe(ui.Hook.ONSCROLLWHEEL, wheel)
end
for y = 0, DOME - 1, 12 do
    local half = domeHalf(math.min(DOME, y + 12), 0)
    blocker(CX - half, y, half * 2, 12)
end
blocker(0, DOME, W, H - DOME)

local function rect(c, x, y, w, h, colour)
    if w > 0 and h > 0 then c:AddRectangle(x, y, w, h, colour) end
end

-- A pixel-art block: black outline, a face, a light top and left edge and a dark bottom and right edge.
local function block(c, x, y, w, h, face, light, dark)
    rect(c, x, y, w, h, INK)
    rect(c, x + P, y + P, w - 2 * P, h - 2 * P, face)
    if light then
        rect(c, x + P, y + P, w - 2 * P, P, light)
        rect(c, x + P, y + P, P, h - 2 * P, light)
    end
    if dark then
        rect(c, x + P, y + h - 2 * P, w - 2 * P, P, dark)
        rect(c, x + w - 2 * P, y + P, P, h - 2 * P, dark)
    end
end

-- A pixel arrow, four steps tall, pointing "up", "down", "left" or "right" around (cx, cy).
local function arrow(c, cx, cy, dir, colour)
    for i = 0, 3 do
        local size = ((dir == "down" or dir == "right") and (2 * (3 - i) + 1) or (2 * i + 1)) * P
        if dir == "up" or dir == "down" then
            rect(c, cx - size // 2, cy - 2 * P + i * P, size, P, colour)
        else
            rect(c, cx - 2 * P + i * P, cy - size // 2, P, size, colour)
        end
    end
end

-- A pixel quaver for the nameplate
local function note(c, x, y, colour)
    rect(c, x, y + 4 * P, 3 * P, 2 * P, colour)
    rect(c, x + 2 * P, y, P, 5 * P, colour)
    rect(c, x + 3 * P, y, 2 * P, P, colour)
    rect(c, x + 4 * P, y + P, P, P, colour)
end

local art = ui.Canvas.new(cabinet)
art:SetSize(W, H)
art.clickthrough = true
local BASE = H - 36                  -- where the plinth starts

do
    -- the cabinet's rings, outside in: black edge, chrome rim, black, the light tube, black, then the wood
    local rings = { { 0, INK }, { P, CHROME_DARK }, { 2 * P, CHROME }, { 4 * P, INK }, { 5 * P, TUBE }, { 8 * P, INK }, { 9 * P, WOOD } }
    for y = 0, DOME - 1, P do
        for _, ring in ipairs(rings) do
            local half = domeHalf(y + P, ring[1])
            rect(art, CX - half, y, half * 2, P, ring[2])
        end
    end
    for _, ring in ipairs(rings) do
        local inset = ring[1]
        rect(art, inset, DOME, W - 2 * inset, BASE - inset - DOME, ring[2])
    end
    -- chrome shine down the left of the rim, wood shading and grain
    rect(art, 2 * P, DOME, P, BASE - 4 * P - DOME, CHROME_LIGHT)
    rect(art, 9 * P, DOME, P, BASE - 10 * P - DOME, WOOD_LIGHT)
    rect(art, W - 10 * P, DOME, P, BASE - 10 * P - DOME, WOOD_DARK)
    for x = 9 * P + 18, W - 9 * P - 18, 27 do rect(art, x, DOME + 6, P, BASE - 10 * P - DOME - 12, WOOD_GRAIN) end

    -- nameplate with two notes
    block(art, CX - 84, 33, 168, 36, GOLD, GOLD_LIGHT, GOLD_DARK)
    art:AddText(CX - 84, 33, 168, 36, "SOUNDBOX", textStyle(DARK, ui.AlignMode.CENTRE, TITLE_FONT))
    note(art, CX - 117, 39, GOLD_LIGHT)
    note(art, CX + 99, 39, GOLD_LIGHT)

    -- search frame with a magnifying glass
    block(art, PAD, 84, W - 2 * PAD, 33, CHROME, CHROME_LIGHT, CHROME_DARK)
    local gx, gy = PAD + 9, 90
    rect(art, gx + P, gy, 3 * P, P, INK); rect(art, gx + P, gy + 4 * P, 3 * P, P, INK)
    rect(art, gx, gy + P, P, 3 * P, INK); rect(art, gx + 4 * P, gy + P, P, 3 * P, INK)
    rect(art, gx + 4 * P, gy + 4 * P, P, P, INK); rect(art, gx + 5 * P, gy + 5 * P, P, P, INK)

    -- category window, display window and readout
    block(art, PAD + 36, BAR_Y, W - 2 * PAD - 72, 30, GLASS, GLASS_LIGHT)
    block(art, PAD, DY - 6, DW, DH + 12, GLASS, GLASS_LIGHT)
    block(art, PAD, READ_Y, W - 2 * PAD, 30, LCD)

    -- speaker cloth with chrome bars, and the coin slot
    block(art, PAD, GRILLE_Y, W - 2 * PAD, 54, CLOTH)
    for x = PAD + 12, W - PAD - 15, 12 do
        rect(art, x, GRILLE_Y + 3, P, 48, CHROME_DARK)
        rect(art, x, GRILLE_Y + 3, P, P, CHROME_LIGHT)
    end
    block(art, CX - 24, GRILLE_Y + 15, 48, 24, CHROME, CHROME_LIGHT, CHROME_DARK)
    rect(art, CX - 12, GRILLE_Y + 25, 24, P, INK)

    -- plinth and feet
    block(art, 6, BASE, W - 12, 24, WOOD_DARK, WOOD, INK)
    block(art, 21, H - 15, 39, 15, CHROME, CHROME_LIGHT, CHROME_DARK)
    block(art, W - 60, H - 15, 39, 15, CHROME, CHROME_LIGHT, CHROME_DARK)
end

-- The bubble lights: a ring of bulbs round the arch and down both sides, chasing colours like an old jukebox.
local lights = ui.Canvas.new(cabinet)
lights:SetSize(W, H)
lights.clickthrough = true
local bulbs = {}
do
    local a, b = CX - 19, DOME - 19
    for i = 0, 30 do
        local t = math.pi * i / 30
        local x = math.floor((CX - a * math.cos(t) - 3) / P) * P
        local y = math.floor((DOME - b * math.sin(t) - 3) / P) * P
        bulbs[#bulbs + 1] = { x, y }
    end
    for y = DOME + 9, BASE - 33, 12 do
        table.insert(bulbs, 1, { 15, y })              -- the left side runs up into the arch
        bulbs[#bulbs + 1] = { W - 21, y }              -- the right side runs down from it
    end
end
local phase = 0
local function drawLights()
    lights:Clear()
    for i, bulb in ipairs(bulbs) do
        rect(lights, bulb[1], bulb[2], 2 * P, 2 * P, BULBS[(i + phase) % #BULBS + 1])
        rect(lights, bulb[1], bulb[2], P, P, 0xFFFFFFB0)
    end
end
drawLights()

-- The face: everything that changes (category, display, tuner, readout, buttons), redrawn when something does
local face = ui.Canvas.new(cabinet)
face:SetSize(W, H)
face.clickthrough = true

local fontInfo = get(function() return config.Font.FromID(FONT) end)
local function fit(text, width)       -- shorten with "..." to fit the given width
    local function measure(s)
        return get(function() return fontInfo:GetStringWidth(s, true) end) or #s * 7
    end
    if measure(text) <= width then return text end
    while #text > 1 and measure(text .. "...") > width do text = text:sub(1, -2) end
    return text .. "..."
end

local styleName, styleNameLit = textStyle(CREAM), textStyle(DARK)
local styleNumber, styleNumberLit = textStyle(NUMBER, ui.AlignMode.BOTTOMRIGHT), textStyle(DARK, ui.AlignMode.BOTTOMRIGHT)
local styleFaded, stylePill = textStyle(FADED, ui.AlignMode.CENTRE), textStyle(GOLD_LIGHT, ui.AlignMode.CENTRE)
local styleUnavailable = textStyle(FADED)
local styleReadout, styleButton = textStyle(NUMBER), textStyle(DARK, ui.AlignMode.CENTRE)

local controls = {}                  -- the pixel buttons: { x, y, w, h, label or arrow, action, hover, pressed }
local function control(x, y, w, h, label, action)
    local c = { x = x, y = y, w = w, h = h, label = label, action = action, hover = false, pressed = 0 }
    controls[#controls + 1] = c
    return c
end

local function drawControl(c)
    local down, on = c.pressed > 0, c.isOn and c.isOn()
    local faceColour = down and CHROME_DARK or (c.hover and CHROME_LIGHT or CHROME)
    local light, dark = CHROME_LIGHT, CHROME_DARK
    if on then faceColour, light, dark = (c.hover and GOLD_LIGHT or GOLD), GOLD_LIGHT, GOLD_DARK end
    block(face, c.x, c.y, c.w, c.h, faceColour, not down and light or nil, not down and dark or nil)
    local shift = down and P or 0
    local cx, cy = c.x + c.w // 2 + shift, c.y + c.h // 2 + shift
    local label = type(c.label) == "function" and c.label() or c.label
    if label == "up" or label == "down" or label == "left" or label == "right" then
        arrow(face, cx, cy, label, INK)
    else
        face:AddText(c.x + shift, c.y + shift, c.w, c.h, label, styleButton)
    end
end

local function readoutText()
    if not ready then
        return "TUNING IN: " .. steps[stepIndex].what
    elseif current then
        local what = retry and "RETRYING " or (failed and "UNAVAILABLE " or (not playing and "STOP " or "FREQ "))
        return fit(what .. current.id .. "   " .. current.label, W - 2 * PAD - 18)
    end
    return countOf(ALL) .. " SOUNDS READY - TUNE IN!"
end

draw = function()
    face:Clear()
    -- category window
    local pillText = category .. "  (" .. countOf(category) .. ")"
    face:AddText(PAD + 36, BAR_Y, W - 2 * PAD - 72, 30, fit(pillText, W - 2 * PAD - 90), stylePill)
    -- display rows
    local x0, rowW = PAD + 6, DW - 18
    if #results == 0 then
        face:AddText(x0, DY, rowW, DH, not ready and "Tuning in..." or "Nothing found", styleFaded)
    end
    for row = 0, ROWS - 1 do
        local i = top + row
        local entry = results[i]
        if not entry then break end
        local y, lit = DY + row * ROW_H, i == sel
        if lit then
            rect(face, x0, y + 1, rowW, ROW_H - 2, INK)
            face:AddGradientV(x0 + 1, y + 2, rowW - 2, ROW_H - 4, GOLD_LIGHT, GOLD)
        elseif row < ROWS - 1 then
            rect(face, x0 + 3, y + ROW_H - 1, rowW - 6, 1, GLASS_LIGHT)
        end
        local number = entry.isCategory and tostring(entry.count) or tostring(entry.id)
        local dim = not entry.isCategory and unavailableIDs[tostring(entry.id)]
        local label = (dim and "! " or "") .. entry.label
        face:AddText(x0 + 6, y, rowW - 62, ROW_H, fit(label, rowW - 66),
                     lit and styleNameLit or (dim and styleUnavailable or styleName))
        face:AddText(x0 + rowW - 54, y, 48, ROW_H, number,
                     lit and styleNumberLit or (dim and styleUnavailable or styleNumber))
    end
    if #results > ROWS then           -- scroll bar down the right of the display
        local thumb = math.max(12, DH * ROWS // #results)
        local at = (DH - thumb) * (top - 1) // math.max(1, #results - ROWS)
        rect(face, PAD + DW - 12, DY, P, DH, GLASS_LIGHT)
        rect(face, PAD + DW - 12, DY + at, P, thumb, CHROME)
    end
    face:AddText(PAD + 9, READ_Y, W - 2 * PAD - 18, 30, readoutText(), styleReadout)
    for _, c in ipairs(controls) do drawControl(c) end
end

local function previewSettings()
    return get(function()
        local p = audio.SoundPlaybackParams.new()
        p.type, p.audioBus, p.emitterShape = audio.SoundType.SCRIPT, audio.AudioBus.SFX, audio.EmitterShape.NONE
        p.volume, p.numLoops, p.delayTick = 1, 0, 0
        return p
    end)
end

local function markUnavailable(request, detail)
    retry, failed = nil, true
    unavailableIDs[tostring(current.id)] = true
    pcall(function() PersistentDB:SetStructuredData("unavailableSounds", unavailableIDs) end)
    remember("unavailable", request.tries, detail, request.params ~= nil)
    log("Soundbox: " .. current.id .. " unavailable after " .. request.tries .. " attempts; saved for retry")
    if options.hideUnavailable then search(true) end
end
local function attempt(request)
    request.tries = request.tries + 1
    local ok, instance = pcall(audio.Play, request.sound.id, request.params)
    playing = ok and instance or nil
    if playing then
        retry, failed = nil, false
        unavailableIDs[tostring(current.id)] = nil
        pcall(function() PersistentDB:SetStructuredData("unavailableSounds", unavailableIDs) end)
        remember("instance returned", request.tries, "Audibility is not known to the plugin", request.params ~= nil)
        log("Soundbox: " .. current.id .. " returned an instance (" .. lastPlayback.settings .. ")")
        if options.hideUnavailable then search(true) end
    elseif request.tries >= (options.retry and 7 or 1) then
        markUnavailable(request, ok and "nil: resource loading or mixer instance limit" or instance)
    else
        retry, request.wait = request, 50
        remember("retrying", request.tries, ok and "nil: loading or instance limit" or instance, request.params ~= nil)
    end
end

local function play(sound)
    if not sound or not byID[sound.id] then return end
    if playing then pcall(function() playing:Stop() end) end
    current, playing, failed, retry = sound, nil, false, nil
    attempt({ sound = sound, tries = 0, params = previewSettings() })
    draw()
end

local function chooseTab(number)
    tabNumber = number
    category = tabCategory[number]
    search(false)
end

scrollPage = function(delta)          -- one wheel step = one page; browsing never starts audio
    if #results == 0 then return end
    if not delta or delta == 0 then return end
    local lastPage = ((#results - 1) // ROWS) * ROWS + 1
    top = math.max(1, math.min(lastPage, top + (delta > 0 and ROWS or -ROWS)))
    sel = top
    draw()
end

local function toggleFavourite()
    if not current then return end
    if isFavourite(current) then
        for i = #favourites, 1, -1 do
            if favourites[i].id == current.id and favourites[i].label == current.label then table.remove(favourites, i) end
        end
    else
        favourites[#favourites + 1] = { label = current.label, id = current.id, kind = current.kind }
    end
    pcall(function() PersistentDB:SetStructuredData("favourites", favourites) end)
    search(category ~= FAVOURITES)
end

local half = (DH + 12 - GAP) // 2
local bw = (W - 2 * PAD - 3 * 6) // 4
local tw = (W - 2 * PAD - (#tabs - 1) * 6) // #tabs
for number, tab in ipairs(tabs) do
    local c = control(PAD + (number - 1) * (tw + 6), TABS_Y, tw, 28, tab.name, function() chooseTab(number) end)
    c.isOn = function() return tabNumber == number end
end
control(PAD, BAR_Y, 30, 30, "left", function() scrollPage(-1) end)
control(W - PAD - 30, BAR_Y, 30, 30, "right", function() scrollPage(1) end)
control(PAD + DW + GAP, DY - 6, TUNER_W, half, "up", function() scrollPage(-1) end)
control(PAD + DW + GAP, DY - 6 + half + GAP, TUNER_W, half, "down", function() scrollPage(1) end)
control(PAD, BUTTONS_Y, bw, 30, "Play", function() play(current or results[sel]) end)
control(PAD + (bw + 6), BUTTONS_Y, bw, 30, "Stop", function()
    if playing then pcall(function() playing:Stop() end) end
    playing, retry, failed = nil, nil, false -- Stop must cancel a pending retry too
    if current then remember("stopped", lastPlayback and lastPlayback.attempts or 0, "Stopped by user", false) end
    draw()
end)
control(PAD + 2 * (bw + 6), BUTTONS_Y, bw, 30, function() return isFavourite(current) and "Unfavourite" or "Favourite" end, toggleFavourite)
local hideControl = control(PAD + 3 * (bw + 6), BUTTONS_Y, bw, 30, "Hide", nil)

-- search field, in the chrome frame beside the magnifying glass
local field = ui.InputField.new(cabinet)
field.clickthrough = false
field.stylesheetID = id.StyleSheet.INPUT_DEFAULT
field:SetPos(PAD + 30, 88)
field:SetSize(W - 2 * PAD - 36, 25)
field:Subscribe(ui.Hook.ONSCROLLWHEEL, wheel)
field:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, reason, contents)
    local submit = get(function() return ui.InputFieldActionResult.SUBMIT end)
    if reason ~= nil and reason == submit then        -- Enter: play the lit sound, or pick the lit category
        local entry = results[sel]
        play(entry)
        return
    end
    query = tostring(contents or "")
    search(false)
end)

-- Hide leaves a small chrome "SOUNDBOX" button where the jukebox was; it sits outside the hidden cabinet.
local reopen = ui.Layer.new(topLayer)
reopen:SetPos(px, py)
reopen:SetSize(120, 30)
reopen.hidden = true
local reopenArt = ui.Canvas.new(reopen)
reopenArt:SetSize(120, 30)
reopenArt.clickthrough = true
block(reopenArt, 0, 0, 120, 30, GOLD, GOLD_LIGHT, GOLD_DARK)
reopenArt:AddText(0, 0, 120, 30, "SOUNDBOX", textStyle(DARK, ui.AlignMode.CENTRE, TITLE_FONT))
local reopenClick = ui.Rectangle.new(reopen)
reopenClick.clickthrough = false
reopenClick:SetSize(120, 30)
reopenClick.fill = true
reopenClick.colour = Vector4.new(0, 0, 0, 0.004)
reopenClick:Subscribe(ui.Hook.ONSCROLLWHEEL, swallow)
reopenClick:Subscribe(ui.Hook.ONCLICK, function()
    cabinet.hidden = false
    reopen.hidden = true
    return false
end)
hideControl.action = function()
    reopen:SetPos(px, py)
    cabinet.hidden = true
    reopen.hidden = false
end

-- The yellow cross for clicks on the cabinet itself: shrinking over a few frames, like the game's own.
local marks = ui.Canvas.new(cabinet)
marks:SetSize(W, H)
marks.clickthrough = true
local cross = nil                    -- { x, y, frame }
local function drawCross()
    marks:Clear()
    if not cross then return end
    local arm = 4 - cross[3] // 5
    for _, pass in ipairs({ { 0x3A3200FF, 1, 4 }, { 0xFFF200FF, 0, 2 } }) do
        local colour, edge, size = pass[1], pass[2], pass[3]
        for k = -arm, arm do
            rect(marks, cross[1] + 2 * k - edge, cross[2] + 2 * k - edge, size, size, colour)
            rect(marks, cross[1] + 2 * k - edge, cross[2] - 2 * k - edge, size, size, colour)
        end
    end
end
clickedNothing = function()
    local mx, my = get(Mouse.GetX), get(Mouse.GetY)
    if not mx or not my then return end
    local origin = get(function() return cabinet.xyGlobal end)
    cross = { math.floor(mx - (origin and origin.x or px)), math.floor(my - (origin and origin.y or py)), 0 }
    drawCross()
end

-- Clear click areas on top of everything ------------------------------------------------------------------------
-- Areas that do something when clicked, as { x, y, w, h } inside the jukebox. Over these the menu's top entry is
-- "Soundbox"; the search field is the first one.
local clickables = { { PAD + 30, 88, W - 2 * PAD - 36, 25 } }
local function catcher(x, y, w, h, isButton)
    local r = ui.Rectangle.new(cabinet)
    r.clickthrough = false
    r:SetPos(x, y)
    r:SetSize(w, h)
    r.fill = true
    r.colour = Vector4.new(0, 0, 0, 0.004)
    r:Subscribe(ui.Hook.ONSCROLLWHEEL, wheel)
    if isButton ~= false then clickables[#clickables + 1] = { x, y, w, h } end
    return r
end

catcher(PAD + 36, BAR_Y, W - 2 * PAD - 72, 30):Subscribe(ui.Hook.ONCLICK, function()
    search(false)
    return false
end)

-- The display: click to play; wheel to browse a page without playing.
local rows = catcher(PAD + 6, DY, DW - 18, DH)
local function rowAt(y)
    local fromTop = y - (get(function() return rows.xyGlobal.y end) or 0)
    if fromTop < 0 or fromTop >= DH then fromTop = y end   -- the hook gave a position inside the display already
    return top + math.floor(fromTop / ROW_H)
end
rows:Subscribe(ui.Hook.ONCLICK, function(_, _, y)
    local i = rowAt(y or 0)
    local entry = results[i]
    if entry then
        sel = i
        play(entry)
    end
    return false
end)
rows:Subscribe(ui.Hook.ONSCROLLWHEEL, wheel)

-- moving the jukebox: press on its top and drag; it follows the mouse until the button is let go
local handle = catcher(PAD, 0, W - 2 * PAD, 81)
local drag = nil                      -- { mouseX, mouseY, startX, startY, ticksAway }
handle:Subscribe(ui.Hook.ONCLICK, function()
    local mx, my = get(Mouse.GetX), get(Mouse.GetY)
    if mx and my then drag = { mx, my, px, py, 0 } end
    clickedNothing()
    return false
end)
local function endDrag()
    if not drag then return end
    drag = nil
    pcall(function() PersistentDB:SetStructuredData("position", { x = px, y = py }) end)
end
handle:Subscribe(ui.Hook.ONRELEASE, function() endDrag() return false end)

local function followMouse()
    if not drag then return end
    local mx, my = get(Mouse.GetX), get(Mouse.GetY)
    if not mx or not my then return end
    local maxX = (get(function() return topLayer.width end) or 4000) - 60
    local maxY = (get(function() return topLayer.height end) or 4000) - 40
    px = math.floor(math.max(60 - W, math.min(maxX, drag[3] + mx - drag[1])))
    py = math.floor(math.max(0, math.min(maxY, drag[4] + my - drag[2])))
    cabinet:SetPos(px, py)
    -- the mouse button state is not available, so a drag also ends once the cursor has been off the top a while
    if get(function() return handle.isMouseOver end) == false then
        drag[5] = drag[5] + 1
        if drag[5] > 15 then endDrag() end
    else
        drag[5] = 0
    end
end

-- the pixel buttons: light up under the mouse, press in when clicked
for _, c in ipairs(controls) do
    local r = catcher(c.x, c.y, c.w, c.h)
    r:Subscribe(ui.Hook.ONCLICK, function()
        c.pressed = 6
        if c.action then c.action() end
        draw()
        return false
    end)
    r:Subscribe(ui.Hook.ONMOUSEOVER, function() c.hover = true; draw() end)
    r:Subscribe(ui.Hook.ONMOUSELEAVE, function() c.hover = false; draw() end)
end

-- Keeping clicks off the world ------------------------------------------------------------------------------------
-- A left-click runs the top entry of the game's menu. Over the jukebox that would be "Walk here", so while the cursor
-- is over it the top entry is changed: over a button it becomes "Soundbox", which does nothing (the jukebox's own
-- click areas do the work, and the game shows its red click cross); anywhere else it becomes the game's own Cancel.
-- The cursor's place inside the jukebox, or nil when it is not over it.
local function overJukebox()
    if get(function() return cabinet.hidden end) then return nil end
    local mx, my = get(Mouse.GetX), get(Mouse.GetY)
    if not mx or not my then return nil end
    local origin = get(function() return cabinet.xyGlobal end)
    local x, y = mx - (origin and origin.x or px), my - (origin and origin.y or py)
    if x < 0 or y < 0 or x >= W or y >= H then return nil end
    if y < DOME and math.abs(x - CX) > domeHalf(math.min(DOME, y + P), 0) then return nil end
    return x, y
end

local function nothing() end
local function menuText(entry)
    local override = get(function() return entry.overrideText end)
    if override and override ~= "" then return override end
    return get(function() return entry.fullText end) or ""
end

local lastMenuProblem
Event.MiniMenuReady.Subscribe("soundboxClicks", function(event)
    local ok, problem = pcall(function()
        local x, y = overJukebox()
        if not x then return end
        local menu = event.miniMenu
        -- Cancel is always the lowest entry, so the left-click entry sits at the other end of the list
        local before, cancel = menu.entryCount, nil
        for i = 1, before do
            if menu.entries[i].actionType == MiniMenuActionType.CANCEL then cancel = i end
        end
        local leftClickIsLast = cancel ~= before
        local overButton = false
        for _, a in ipairs(clickables) do
            if x >= a[1] and y >= a[2] and x < a[1] + a[3] and y < a[2] + a[4] then overButton = true end
        end
        if not overButton then
            local leftClick = leftClickIsLast and before or 1
            if cancel and cancel ~= leftClick then menu:Swap(cancel, leftClick) end
            return
        end
        menu:Add("Soundbox", nothing)
        local count, entries, ours = menu.entryCount, menu.entries, nil
        for i = 1, count do
            if entries[i].actionEntryType == MiniMenuEntryType.PLUGIN and menuText(entries[i]) == "Soundbox" then ours = i end
        end
        local leftClick = leftClickIsLast and count or 1
        if ours and ours ~= leftClick then menu:Swap(ours, leftClick) end
    end)
    if not ok and problem ~= lastMenuProblem then log("Soundbox menu: " .. tostring(problem)) end
    lastMenuProblem = not ok and problem or nil
end)

-- Saving the list of sounds found, as plain text in pieces of about 60,000 characters ("soundList1", ...)
local function saveList()
    local pieces, lines, size = {}, {}, 0
    local function close()
        if #lines > 0 then pieces[#pieces + 1] = table.concat(lines, "\n") end
        lines, size = {}, 0
    end
    for _, sound in ipairs(sounds) do
        local line = sound.id .. "\t" .. sound.kind .. "\t" .. sound.category .. "\t" .. sound.label
        lines[#lines + 1] = line
        size = size + #line + 1
        if size > 60000 then close() end
    end
    close()
    for i, piece in ipairs(pieces) do pcall(function() PersistentDB:SetString("soundList" .. i, piece) end) end
    pcall(function() PersistentDB:SetInt("soundListPieces", #pieces) end)
    pcall(function() PersistentDB:SetInt("soundCount", #sounds) end)
    log("Soundbox: saved " .. #sounds .. " unique id.Sound entries in " .. #pieces .. " pieces")
end

-- Each client tick: follow a drag, run the lights, let pressed buttons spring back, and work through the next batch
-- of game data until every sound is found.
local ticks = 0
local hidingUnavailable = options.hideUnavailable
Event.Logic.Subscribe("soundbox", function()
    ticks = ticks + 1
    followMouse()
    if options.hideUnavailable ~= hidingUnavailable then
        hidingUnavailable = options.hideUnavailable
        search(true)
    end
    if retry and not options.retry then markUnavailable(retry, "Further retries disabled by user"); draw() end
    if retry then
        retry.wait = retry.wait - 1
        if retry.wait <= 0 then
            attempt(retry)
            draw()
        end
    end
    if playing then
        local active = get(function() return playing.isPlaying end)
        if active == true and lastPlayback and lastPlayback.isPlaying ~= true then
            lastPlayback.isPlaying = true
            pcall(function() PersistentDB:SetStructuredData("lastPlayback", lastPlayback) end)
        end
    end
    if cross then                     -- the yellow cross shrinks away over 20 ticks
        cross[3] = cross[3] + 1
        if cross[3] >= 20 then cross = nil end
        drawCross()
    end
    local hidden = get(function() return cabinet.hidden end)
    if not hidden and ticks % 6 == 0 then
        phase = phase + 1
        drawLights()
    end
    local springBack = false
    for _, c in ipairs(controls) do
        if c.pressed > 0 then
            c.pressed = c.pressed - 1
            if c.pressed == 0 then springBack = true end
        end
    end
    if springBack then draw() end

    if stepIndex > #steps then return end
    local step = steps[stepIndex]
    local function nextStep()
        log("Soundbox: " .. step.what .. " done, " .. #sounds .. " sounds so far")
        if step.what == "game sounds" then   -- everything A to Z, "All sounds" and "All bosses" first
            local function byName(a, b)
                local x, y = a.lower:match("^sound (%d+)$"), b.lower:match("^sound (%d+)$")
                if x and y then return tonumber(x) < tonumber(y) end
                return a.lower < b.lower
            end
            for _, list in pairs(inCategory) do table.sort(list, byName) end
            ready = true
        end
        stepIndex, nextID, lastFound = stepIndex + 1, 0, 0
        if stepIndex > #steps then
            log("Soundbox: ready, " .. #sounds .. " sounds")
            saveList()
        end
        search(true)
    end
    if step.once then
        pcall(step.once)
        nextStep()
        return
    end
    local budget = BUDGET
    while budget > 0 do
        local ok, found, cost = pcall(step.look, nextID)
        budget = budget - ((ok and cost) or 1)
        if ok and found then lastFound = nextID end
        nextID = nextID + 1
        if nextID - lastFound > EMPTY_RUN then
            nextStep()
            return
        end
    end
    if ticks % 25 == 0 then draw() end
end)

search(false)

function PluginShutdown()
    Event.Logic.Unsubscribe("soundbox")
    Event.MiniMenuReady.Unsubscribe("soundboxClicks")
    Event.SettingsLayerReady.Unsubscribe("soundboxSettings")
    if playing then pcall(function() playing:Stop() end) end
    pcall(function() cabinet:Destroy() end)
    pcall(function() reopen:Destroy() end)
end

log("Soundbox 0.2.3 is on: wheel browses pages; local options are in the Plugin Hub settings cog")
