-- Pixel Art Bars 0.1.0
-- Adds a configurable, cute little Pixel art HP and Adrenaline bar below your character.

local ACTION_BAR = 1430
local MAX_STATIC = 200               -- action bar components looked through when finding the HP text
local PER_ROW = 10                   -- hearts in a row
local LIFE_PER_HEART = 1000
local HEAD_HEIGHT = 800              -- world units from your feet to the top of your head (measured), if no bounding box
local HEAD_GAP = 52                  -- interface units above your head, at least
local BAR_RISE = 240                 -- world units above the head where the game's bars sit (with a little margin)
local BAR_ROOM = 30                  -- interface units the bars take up
local UNDER_GAP = 12                 -- interface units below your feet, for hearts under your character
local ABILITY_ROW = 74               -- Cooldown Bar's boxes start this far below your feet (its UNDER_GAP); the bars sit on it
local MENU_LABEL = "Pixel Art Bars"
local HIDE_W, HIDE_H = 40, 18        -- the HIDE button
local TAB_W, TAB_H = 18, 16          -- the heart that opens hidden hearts again

local function get(fn)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
end

-- Settings -----------------------------------------------------------------------------------------------------------

local SHOW_ORDER = { "screen", "head", "both", "off" }
local SHOW_TEXT = { screen = "on screen", head = "on your character", both = "screen and character", off = "off" }
local SIZE_ORDER = { "auto", "1x", "2x", "3x", "4x", "5x", "6x" }  -- one art pixel; auto = 2x, or 1x when 2x won't fit the bar
local THEME_ORDER = { "red", "pink", "gold", "green", "blue", "purple" }
local ORB_ORDER = { "blue", "green", "purple", "red", "gold", "pink" }
local ALERT_ORDER = { "off", 50, 60, 70, 80, 90, 100 }       -- adrenaline % for the alert
local LOW_ORDER = { 25, 35, 50 }                              -- the hearts blink below this % of your health
local LOOK_ORDER = { "hearts", "bars" }
local BAR_COLOUR_ORDER = { "shifts", "red", "pink", "gold", "green", "blue", "purple" }

-- x, y = where a dragged panel's bottom-left corner is; nil while it sits on the HP bar
-- under = the character hearts go just below your feet (the default); over = above your head
local prefs = { show = "head", size = "auto", blink = true, hidden = false, x = nil, y = nil, under = true, adren = true,
                heart = "red", orb = "blue", alertAt = "off", alertColour = "red", alertFlash = true, lowAt = 25,
                look = "bars", barColour = "shifts" }
local saved = get(function() return PersistentDB:GetStructuredData("hearts") end)
if type(saved) == "table" then
    if SHOW_TEXT[saved.show] then
        prefs.show = saved.show
    elseif saved.show == false then
        prefs.show = "off"
    end
    for _, size in ipairs(SIZE_ORDER) do
        if saved.size == size then prefs.size = size end
    end
    if saved.size == "large" then prefs.size = "2x" elseif saved.size == "small" then prefs.size = "1x" end   -- 0.2 names
    if type(saved.blink) == "boolean" then prefs.blink = saved.blink end
    if type(saved.under) == "boolean" then prefs.under = saved.under end
    if type(saved.adren) == "boolean" then prefs.adren = saved.adren end
    if type(saved.hidden) == "boolean" then prefs.hidden = saved.hidden end
    for key, list in pairs({ heart = THEME_ORDER, orb = ORB_ORDER, alertAt = ALERT_ORDER, alertColour = THEME_ORDER, lowAt = LOW_ORDER,
                             look = LOOK_ORDER, barColour = BAR_COLOUR_ORDER }) do
        for _, v in ipairs(list) do if saved[key] == v then prefs[key] = v end end
    end
    if type(saved.alertFlash) == "boolean" then prefs.alertFlash = saved.alertFlash end
    if saved.look == "flat" then prefs.look = "bars" end
    if type(saved.x) == "number" and type(saved.y) == "number" then
        prefs.x, prefs.y = saved.x, saved.y
    end
end
local function save()
    pcall(function()
        PersistentDB:SetStructuredData("hearts", { show = prefs.show, size = prefs.size, blink = prefs.blink,
            hidden = prefs.hidden, x = prefs.x, y = prefs.y, under = prefs.under, adren = prefs.adren, heart = prefs.heart,
            orb = prefs.orb, alertAt = prefs.alertAt, alertColour = prefs.alertColour, alertFlash = prefs.alertFlash, lowAt = prefs.lowAt,
            look = prefs.look, barColour = prefs.barColour })
    end)
end
local function nextIn(list, value)
    for i, v in ipairs(list) do
        if v == value then
            return list[i % #list + 1]
        end
    end
    return list[1]
end

-- How many screen units one art pixel takes: the chosen size, or 2 for auto (the bar may still drop to 1 to fit)
local function pixelSize()
    return tonumber((prefs.size or ""):match("^(%d)x$")) or 2
end

-- Finding the HP text on the action bar ----------------------------------------------------------------------------

local function lifeFrom(text)
    local now, most = tostring(text or ""):gsub("<[^>]*>", ""):match("^%s*([%d,]+)%s*/%s*([%d,]+)%s*$")
    if not now then
        return nil
    end
    now, most = tonumber((now:gsub(",", ""))), tonumber((most:gsub(",", "")))
    if not now or not most or most <= 0 then
        return nil
    end
    return now, most
end

-- The text component at one spot: { componentID, child } where child = the text sits in child (0, 8)
local function componentAt(spot)
    local component = get(function() return ui.Interfaces:GetComponent(ACTION_BAR, spot[1]) end)
    if component and spot[2] then
        component = get(function() return component:GetChild(0, 8) end)
    end
    return component
end

local function readSpot(spot)
    local component = spot and componentAt(spot)
    if not component then
        return nil
    end
    local now, most = lifeFrom(get(function() return component.content end))
    if now then
        return component, now, most
    end
end

local function findSpot()
    if not get(function() return ui.Interfaces:GetInterface(ACTION_BAR) end) then
        return nil
    end
    local best, bestX = nil, math.huge
    for componentID = 0, MAX_STATIC do
        for _, child in ipairs({ false, true }) do
            local spot = { componentID, child }
            local component, _, most = readSpot(spot)
            if component and most >= LIFE_PER_HEART then
                local spotX = get(function() return component.xyGlobal.x end) or 0
                if spotX < bestX then
                    best, bestX = spot, spotX
                end
            end
        end
    end
    if best then
        pcall(function() PersistentDB:SetStructuredData("hpSpot", { id = best[1], child = best[2] }) end)
        log("Pixel Art Bars: found the HP text on the action bar (component " .. best[1] .. (best[2] and ", child" or "") .. ")")
    end
    return best
end

-- Where the HP text is: component 9, inside child (0, 8), as the search above found it in the game (the prayer text is
-- at 16 and the summoning text at 22, the same way). If that ever stops holding an HP text, the search finds it again.
local spot = { 9, true }
local savedSpot = get(function() return PersistentDB:GetStructuredData("hpSpot") end)
if type(savedSpot) == "table" and type(savedSpot.id) == "number" then
    spot = { savedSpot.id, savedSpot.child == true }
end

-- The adrenaline text on the action bar -------------------------------------------------------------------------------

local ADREN_VAR, ADREN_VAR_NAME = 679, "SA_ENERGY"
local function adrenFromVar()
    local value = get(function()
        local v = var.VarPlayer.FromID(ADREN_VAR)
        if v.configName == ADREN_VAR_NAME then
            return v.value
        end
    end)
    if type(value) == "number" and value >= 0 and value <= 1000 then
        return value / 10
    end
end

-- "43%" -> 43 (nil for anything else; a space before the % is fine). Used to find the adrenaline bar on the action
-- bar, so the orbs can be drawn onto it.
local function adrenFrom(text)
    local digits = tostring(text or ""):gsub("<[^>]*>", ""):match("^%s*(%d+)%s*%%%s*$")
    local value = digits and tonumber(digits)
    if value and value >= 0 and value <= 100 then
        return value
    end
end

local function adrenPiece(where)
    local component = get(function() return ui.Interfaces:GetComponent(ACTION_BAR, where[1]) end)
    if component and where.dyn then
        component = get(function() return component:GetChild(where.cat, where.dyn) end)
    end
    return component
end

local function readAdren(where)
    local component = where and adrenPiece(where)
    local value = component and adrenFrom(get(function() return component.content end))
    if value then
        return component, value
    end
end

-- Looks through the action bar, every piece and every child of each, for the left-most "number%" text: the adrenaline.
local function findAdren()
    if not get(function() return ui.Interfaces:GetInterface(ACTION_BAR) end) then
        return nil
    end
    local best, bestX = nil, math.huge
    local function consider(component, where)
        local content = get(function() return component.content end)
        if adrenFrom(content) then
            local x = get(function() return component.xyGlobal.x end) or 0
            if x < bestX then
                best, bestX = where, x
            end
        end
    end
    for componentID = 0, MAX_STATIC do
        local component = get(function() return ui.Interfaces:GetComponent(ACTION_BAR, componentID) end)
        if component then
            consider(component, { componentID, false })
            pcall(function()
                component:IterateDynamicComponents(function(child)
                    local cat = get(function() return child.categoryID end) or 0
                    local dyn = get(function() return child.dynamicID end)
                    if type(dyn) == "number" then
                        consider(child, { componentID, true, cat = cat, dyn = dyn })
                    end
                    return false
                end)
            end)
        end
    end
    if best then
        pcall(function()
            PersistentDB:SetStructuredData("adrenSpot", { id = best[1], child = best[2], cat = best.cat, dyn = best.dyn })
        end)
        log("Pixel Art Bars: found the adrenaline text on the action bar (component " .. best[1] ..
            (best.dyn and (", child " .. tostring(best.cat) .. ":" .. best.dyn) or "") .. ")")
    end
    return best
end

local adrenSpot = nil
local savedAdren = get(function() return PersistentDB:GetStructuredData("adrenSpot") end)
if type(savedAdren) == "table" and type(savedAdren.id) == "number" then
    adrenSpot = { savedAdren.id, savedAdren.child == true, cat = savedAdren.cat, dyn = savedAdren.dyn }
end

-- The art -------------------------------------------------------------------------------------------------------------

local INK = 0x141010FF
local BAR_BACKGROUND = 0x181614FF    -- the action bar's own dark background (sampled from the game), hides its number
local GOLD, GOLD_LIGHT, GOLD_DARK = 0xE8B23CFF, 0xFFE08AFF, 0x9C6B1EFF
local THEMES = {}
for name, c in pairs({
    red    = { 0xE8343CFF, 0xFF9A9AFF, 0x8A1A20FF, 0x3A1414FF },
    pink   = { 0xF06CB4FF, 0xFFC2E4FF, 0x9C2E6EFF, 0x3A1428FF },
    gold   = { 0xE8B23CFF, 0xFFE08AFF, 0x9C6B1EFF, 0x3A2A10FF },
    green  = { 0x3CC85AFF, 0xB4F5C0FF, 0x1E7832FF, 0x143A1CFF },
    blue   = { 0x3C8CF0FF, 0xC4E8FFFF, 0x1E46A0FF, 0x16213AFF },
    purple = { 0xA05AF0FF, 0xDCC4FFFF, 0x5A28A0FF, 0x24163AFF },
}) do THEMES[name] = { R = c[1], B = c[1], W = c[2], D = c[3], empty = c[4] } end
local ARMOUR_COLOURS = { S = 0xC4CBD3FF, W = 0xF4F7FAFF, D = 0x6E7882FF, empty = 0x262B30FF }
-- 9 x 8 art: k = outline, W = shine, D = shade, R / S = the heart's red / the armour's steel
local HEART = {
    ".kkk.kkk.",
    "kRWRkRRDk",
    "kRWRRRRDk",
    "kRRRRRRDk",
    ".kRRRRDk.",
    "..kRRDk..",
    "...kDk...",
    "....k....",
}
local ARMOUR = {
    "kkk...kkk",
    "kWSk.kSDk",
    "kWSSkSSDk",
    "kkWSSSDkk",
    ".kWSSSDk.",
    ".kDDDDDk.",
    ".kSSSSDk.",
    ".kkkkkkk.",
}
local ORB = {
    "..kkkkk..",
    ".kBWWBBk.",
    "kBWBBBBDk",
    "kBBBBBBDk",
    "kBBBBBBDk",
    "kBBBBBDDk",
    ".kBDDDDk.",
    "..kkkkk..",
}
local ORBS = 10                      -- adrenaline orbs, one per 10%, filled in half-orb steps (5%), rounded down
local ICON_W, ICON_H = 9, 8

local function rect(canvas, x, y, w, h, colour)
    if w > 0 and h > 0 then
        canvas:AddRectangle(math.floor(x), math.floor(y), math.floor(w), math.floor(h), colour)
    end
end

-- One heart or armour piece at (x, y): fill = 0 (empty), 1 (half, left side) or 2 (full); px = size of one art pixel
local function icon(canvas, art, colours, x, y, fill, px)
    for row, line in ipairs(art) do
        for col = 1, #line do
            local c = line:sub(col, col)
            if c ~= "." then
                local colour = INK
                if c ~= "k" then
                    local filled = fill == 2 or (fill == 1 and col <= 5)
                    colour = filled and colours[c] or colours.empty
                end
                rect(canvas, x + (col - 1) * px, y + (row - 1) * px, px, px, colour)
            end
        end
    end
end

-- How many hearts, and how many half-hearts are filled: full health always fills every heart
local function heartsFor(now, most)
    local count = math.max(1, math.ceil(most / LIFE_PER_HEART))
    local halves = math.ceil(math.max(0, math.min(now, most)) / most * count * 2)
    if now > 0 and halves == 0 then
        halves = 1
    end
    return count, halves
end

-- Life points over the maximum, as armour: how many pieces, and how many half-pieces (the last one may be a half)
local function armourFor(now, most)
    local over = now - most
    if over <= 0 then
        return 0, 0
    end
    local halves = math.ceil(over / (LIFE_PER_HEART / 2))
    return math.ceil(halves / 2), halves
end

-- The size of the hearts block: rows of up to 10 (fewer when only `room` units across are free), the first row of
-- hearts at the bottom and the armour on top
local function layout(count, pieces, px, room)
    local cellW, cellH = (ICON_W + 1) * px, (ICON_H + 1) * px
    local perRow = PER_ROW
    if room then
        perRow = math.max(1, math.min(PER_ROW, math.floor((room + px) / cellW)))
        -- too narrow for one full row: share the icons out evenly (orbs 5 + 5, not 9 + 1)
        if perRow < PER_ROW and count > perRow then
            perRow = math.ceil(count / math.ceil(count / perRow))
        end
    end
    local heartRows = math.ceil(count / perRow)
    local rows = heartRows + math.ceil(pieces / perRow)
    local across = math.min(perRow, math.max(count, pieces))
    return { px = px, cellW = cellW, cellH = cellH, perRow = perRow, heartRows = heartRows, rows = rows,
             w = across * cellW - px, h = rows * cellH - px }
end

-- Paints the hearts and armour with the block's top-left at (ox, oy). flash = the low-health blink is on its empty beat.
local function paintIcons(canvas, L, ox, oy, life, flash)
    for i = 1, life.count do
        local fill = life.halves >= i * 2 and 2 or (life.halves == i * 2 - 1 and 1 or 0)
        if flash and fill > 0 then
            fill = 0                     -- the low-health blink: filled hearts flash empty
        end
        local row = math.floor((i - 1) / L.perRow)
        icon(canvas, HEART, THEMES[prefs.heart] or THEMES.red, ox + ((i - 1) % L.perRow) * L.cellW, oy + (L.rows - 1 - row) * L.cellH, fill, L.px)
    end
    for i = 1, life.pieces do
        local row = L.heartRows + math.floor((i - 1) / L.perRow)
        icon(canvas, ARMOUR, ARMOUR_COLOURS, ox + ((i - 1) % L.perRow) * L.cellW, oy + (L.rows - 1 - row) * L.cellH,
            life.pieceHalves >= i * 2 and 2 or 1, L.px)
    end
end

local function paintOrbs(canvas, L, ox, oy, halves, theme)
    for i = 1, ORBS do
        local fill = halves >= i * 2 and 2 or (halves == i * 2 - 1 and 1 or 0)
        local col, row = (i - 1) % L.perRow, math.floor((i - 1) / L.perRow)
        icon(canvas, ORB, THEMES[theme] or THEMES.blue, ox + col * L.cellW, oy + row * L.cellH, fill, L.px)
    end
end

local BAR_W, CAP_H, BAR_GAP = 13, 13, 3
local BAR_STEPS = 60                               -- 1.67% a step
local BAR_LEN = CAP_H - 1 + BAR_STEPS + 6          -- 78 (the cap's last outline column is the body's first)
local WOOD = { outline = 0x4A2208FF, light = 0xF6A23CFF, mid = 0xD9741CFF, dark = 0x9A4810FF, tile = 0x3A1C0AFF }
local CHANNEL_EMPTY, CHANNEL_SHADE = 0xEAC896FF, 0xC9A06AFF
local LETTERS = {
    H = { "k...k", "k...k", "kkkkk", "k...k", "k...k" },
    A = { ".kkk.", "k...k", "kkkkk", "k...k", "k...k" },
}
local LETTER_COLOURS = { H = 0xF04A3CFF, A = 0xFFD24AFF }

-- The bars block: H, then A after it in the same row when the adrenaline shows
local function barsLayout(px, both)
    local n = both and 2 or 1
    return { px = px, n = n, w = (n * BAR_LEN + (n - 1) * BAR_GAP) * px, h = BAR_W * px }
end

local function barState(life)
    local s = {}
    local frac = math.max(0, math.min(life.now, life.most)) / life.most
    s.health = math.ceil(frac * BAR_STEPS)
    if life.now > 0 and s.health == 0 then s.health = 1 end
    s.over = life.now > life.most and math.min(s.health, math.ceil((life.now - life.most) / life.most * BAR_STEPS)) or 0
    if prefs.barColour ~= "shifts" and THEMES[prefs.barColour] then
        s.healthTheme = prefs.barColour
    else
        s.healthTheme = frac >= 0.5 and "green" or (frac >= 0.25 and "gold" or "red")
    end
    if life.adren then
        s.adren = math.floor(math.min(100, life.adren) * BAR_STEPS / 100)
        s.adrenTheme = THEMES[life.orbTheme] and life.orbTheme or "blue"
    end
    s.key = table.concat({ s.health, s.over, s.healthTheme, tostring(s.adren), tostring(s.adrenTheme) }, ":")
    return s
end

-- One bar with its top-left at (x, y): steps of fill in `colours` (a theme), the leading `over` of them steel
local function paintBar(canvas, x, y, px, letter, steps, colours, over)
    local function at(cx, cy, w, h, colour) rect(canvas, x + cx * px, y + cy * px, w * px, h * px, colour) end
    local function framed(left, w)                 -- outline, frame lit top-left and shaded bottom-right
        at(left, 0, w, BAR_W, WOOD.outline)
        at(left + 1, 1, w - 2, BAR_W - 2, WOOD.dark)
        at(left + 1, 1, w - 3, BAR_W - 3, WOOD.light)
        at(left + 2, 2, w - 4, BAR_W - 4, WOOD.mid)
    end
    framed(0, CAP_H)
    at(3, 3, CAP_H - 6, BAR_W - 6, WOOD.tile)
    for row, line in ipairs(LETTERS[letter]) do
        for col = 1, #line do
            if line:sub(col, col) == "k" then at(3 + col, 3 + row, 1, 1, LETTER_COLOURS[letter]) end
        end
    end
    local left = CAP_H - 1
    framed(left, BAR_STEPS + 6)
    local cx, cy, ch = left + 3, 3, BAR_W - 6     -- the channel: from cx, BAR_STEPS long, ch high
    at(cx, cy, BAR_STEPS, ch, CHANNEL_EMPTY)
    at(cx, cy + ch - 1, BAR_STEPS, 1, CHANNEL_SHADE)
    local function fill(from, count, main, light, dark)
        if count <= 0 then return end
        at(from, cy, count, ch, main)
        at(from, cy, count, 1, light)              -- shine along the top
        at(from, cy + ch - 1, count, 1, dark)      -- shade along the bottom
    end
    over = over or 0
    fill(cx, steps, colours.R, colours.W, colours.D)
    fill(cx + steps - over, over, ARMOUR_COLOURS.S, ARMOUR_COLOURS.W, ARMOUR_COLOURS.D)
    if steps > 0 then
        at(cx + steps - 1, cy, 1, ch, over > 0 and ARMOUR_COLOURS.W or colours.W)   -- the light rim on the leading edge
    end
end

-- Both bars, the block's top-left at (ox, oy)
local function paintBars(canvas, B, ox, oy, state)
    paintBar(canvas, ox, oy, B.px, "H", state.health, THEMES[state.healthTheme], state.over)
    if B.n == 2 then
        paintBar(canvas, ox + (BAR_LEN + BAR_GAP) * B.px, oy, B.px, "A", state.adren or 0, THEMES[state.adrenTheme], 0)
    end
end

-- The game's bold pixel font when it has it, otherwise its standard font
local function boldFont()
    local ok, result = pcall(function()
        local candidate = id.Font.B12_FULL
        local description = config.Font.FromID(candidate)
        if description and description:GetStringWidth("HIDE") > 0 then
            return candidate
        end
    end)
    if ok and result then
        return result
    end
    return id.Font.MUSEO_SANS_15PT_REGULAR
end

-- Components ----------------------------------------------------------------------------------------------------------

local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)

local function newLayer(w, h, clickthrough)
    local l = ui.Layer.new(layer)
    l:SetSize(w, h)
    l.clickthrough = clickthrough
    l.hidden = true
    return l
end
local function newCanvas(parent, w, h)
    local c = ui.Canvas.new(parent)
    c:SetSize(w, h)
    c.clickthrough = true
    return c
end
-- a clear rectangle that takes the clicks
local function catcher(parent, w, h)
    local area = ui.Rectangle.new(parent)
    area:SetSize(w, h)
    area.fill = true
    area.colour = Vector4.new(0, 0, 0, 0.004)
    area.clickthrough = false
    return area
end

-- the on-screen panel
local panel = newLayer(10, 10, false)
local panelArt = newCanvas(panel, 10, 10)
local grab = catcher(panel, 10, 10)

-- HIDE: a small gold button on the panel's top-right corner, shown while the mouse is over the panel
local hideTab = newLayer(HIDE_W, HIDE_H, false)
local hideArt = newCanvas(hideTab, HIDE_W, HIDE_H)
local hideClick = catcher(hideTab, HIDE_W, HIDE_H)
rect(hideArt, 0, 0, HIDE_W, HIDE_H, INK)
rect(hideArt, 1, 1, HIDE_W - 2, HIDE_H - 2, GOLD_LIGHT)
rect(hideArt, 2, 2, HIDE_W - 3, HIDE_H - 3, GOLD_DARK)
rect(hideArt, 2, 2, HIDE_W - 4, HIDE_H - 4, GOLD)
pcall(function()
    local style = ui.TextDataConfig.new()
    style.font = boldFont()
    style.colour = Vector4.new(20 / 255, 16 / 255, 16 / 255, 1)
    style.alignHorizontal = ui.AlignMode.CENTRE
    style.alignVertical = ui.AlignMode.CENTRE
    hideArt:AddText(0, 0, HIDE_W, HIDE_H, "HIDE", style)
end)

-- the heart left behind by HIDE
local reopenTab = newLayer(TAB_W, TAB_H, false)
local reopenArt = newCanvas(reopenTab, TAB_W, TAB_H)
local reopenClick = catcher(reopenTab, TAB_W, TAB_H)
icon(reopenArt, HEART, THEMES[prefs.heart] or THEMES.red, 0, 0, 2, 2)

-- the orbs drawn onto the action bar's adrenaline bar (while the hearts are on the HP bar)
local adrenPanel = newLayer(10, 10, true)
local adrenArt = newCanvas(adrenPanel, 10, 10)

-- on your character: hearts only, no plate
local headLayer = newLayer(10, 10, true)
local headArt = newCanvas(headLayer, 10, 10)

-- The on-screen panel ---------------------------------------------------------------------------------------------------

local function origin()
    local base = get(function() return layer.xyGlobal end)
    return base and base.x or 0, base and base.y or 0
end

-- A component's box on the plugin layer
local function boxOf(component)
    local at = component and get(function() return component.xyGlobal end)
    if not at then
        return nil
    end
    local bx, by = origin()
    return { x = at.x - bx, y = at.y - by, w = get(function() return component.width end) or 0,
             h = get(function() return component.height end) or 0 }
end

-- The HP bar's box: the whole bar (the heart, the number and the red line) when its size looks like a bar, otherwise
-- just the number
local function barBox(text, where)
    local box = boxOf(text)
    local holder = where and where[2] and get(function() return ui.Interfaces:GetComponent(ACTION_BAR, where[1]) end)
    local bar = boxOf(holder)
    if box and bar and bar.w >= box.w and bar.w <= 360 and bar.h >= box.h and bar.h <= 60 then
        return bar
    end
    return box
end

local function mouse()
    local okX, x = pcall(Mouse.GetX)
    local okY, y = pcall(Mouse.GetY)
    if okX and okY and type(x) == "number" and type(y) == "number" then
        return x, y
    end
end

-- Is the mouse over a shown component of size w x h?
local function over(component, w, h)
    if component.hidden then
        return false
    end
    local mx, my = mouse()
    local at = mx and get(function() return component.xyGlobal end)
    if not at then
        return false
    end
    return mx >= at.x and my >= at.y and mx < at.x + w and my < at.y + h
end

local function hovered(area, component, w, h)
    local ok, value = pcall(function() return area.isMouseOver end)
    if ok and type(value) == "boolean" then
        return value and not component.hidden
    end
    return over(component, w, h)
end

local placed = nil                   -- the panel as shown: { x, y, w, h }
local reopenAt = nil                 -- where the heart tab goes while the panel is hidden
local screenKey, headKey, boxKey = "", "", ""
local drag, hoverTicks = nil, 0
local lastPanel = ""

-- Dragging: a press on the panel starts it, the panel follows the mouse every client tick, and it ends when the button
-- is let go (or once the cursor has been off the panel for 15 ticks, as the mouse button can't be read). A press that
-- doesn't move 3 units is just a click.
local function endDrag()
    if drag and drag.moved then
        save()
    end
    drag = nil
end
grab:Subscribe(ui.Hook.ONCLICK, function()
    local mx, my = mouse()
    if mx and placed then
        drag = { mx = mx, my = my, x = placed.x, bottom = placed.y + placed.h, off = 0, moved = false }
    end
    return false
end)
grab:Subscribe(ui.Hook.ONRELEASE, function()
    endDrag()
    return false
end)
local function followDrag()
    if not drag or not placed then
        return
    end
    local mx, my = mouse()
    if not mx then
        return
    end
    local dx, dy = mx - drag.mx, my - drag.my
    if drag.moved or math.abs(dx) + math.abs(dy) >= 3 then
        drag.moved = true
        local pw = get(function() return layer.width end)
        local ph = get(function() return layer.height end)
        pw = type(pw) == "number" and pw or 4000
        ph = type(ph) == "number" and ph or 4000
        prefs.x = math.floor(math.max(20 - placed.w, math.min(pw - 20, drag.x + dx)))
        prefs.y = math.floor(math.max(20, math.min(ph + placed.h - 20, drag.bottom + dy)))
    end
    local onIt = get(function() return grab.isMouseOver end)
    if onIt == false then
        drag.off = drag.off + 1
        if drag.off > 15 then
            endDrag()
        end
    else
        drag.off = 0
    end
end

hideClick:Subscribe(ui.Hook.ONCLICK, function()
    prefs.hidden = true
    drag = nil
    save()
    return false
end)
reopenClick:Subscribe(ui.Hook.ONCLICK, function()
    prefs.hidden = false
    hoverTicks = 0
    save()
    return false
end)

-- The orbs on the action bar's adrenaline bar, the same way the hearts sit on the HP bar
local adrenKey, adrenWhere, adrenBoxKey = "", "", ""
local function drawAdrenDocked(life)
    local box = life.adrenText and barBox(life.adrenText, adrenSpot)
    if not box then
        adrenPanel.hidden = true
        return
    end
    local boxKeyNow = table.concat({ box.x, box.y, box.w, box.h }, ",")
    if boxKeyNow ~= adrenBoxKey then
        adrenBoxKey = boxKeyNow
        log("Pixel Art Bars: on the adrenaline bar at " .. math.floor(box.x) .. ", " .. math.floor(box.y) .. " (" ..
            math.floor(box.w) .. " x " .. math.floor(box.h) .. ")")
    end
    local room = box.w - 2
    local L = layout(ORBS, 0, pixelSize(), room)
    if prefs.size == "auto" and (L.w + 2 > box.w or L.h + 2 > box.h + 2) then
        L = layout(ORBS, 0, 1, room)
    end
    local w, h = math.floor(math.max(L.w + 4, box.w + 2)), math.floor(math.max(L.h + 4, box.h + 2))
    local x, y = math.floor(box.x - 1), math.floor(box.y + box.h + 1 - h)
    local key = table.concat({ life.adrenHalves, L.px, w, h, tostring(life.orbTheme) }, ":")
    if key ~= adrenKey then
        adrenKey = key
        adrenArt:SetSize(w, h)
        adrenArt:Clear()
        rect(adrenArt, 0, 0, w, h, BAR_BACKGROUND)
        paintOrbs(adrenArt, L, 2, math.floor((h - L.h) / 2), life.adrenHalves, life.orbTheme)
    end
    local where = table.concat({ x, y, w, h }, ",")
    if where ~= adrenWhere then
        adrenWhere = where
        adrenPanel:SetPos(x, y)
        adrenPanel:SetSize(w, h)
    end
    adrenPanel.hidden = false
end

local function drawBarsScreen(text, life, flash)
    local box = barBox(text, spot)
    local docked = prefs.x == nil
    adrenPanel.hidden = true
    if docked and not box then
        panel.hidden, placed, reopenAt = true, nil, nil
        return
    end
    local B = barsLayout(pixelSize(), life.adren ~= nil)            -- auto = 2x
    local x, bottom
    if docked then
        x, bottom = box.x, box.y - 4
    else
        x, bottom = prefs.x, prefs.y
    end
    x, bottom = math.floor(x), math.floor(bottom)
    reopenAt = { x, bottom - TAB_H }
    if prefs.hidden then
        panel.hidden, placed = true, nil
        return
    end
    placed = { x = x, y = bottom - B.h, w = B.w, h = B.h }
    local state = barState(life)
    local key = table.concat({ "bars", state.key, B.px, B.w, B.h }, ":")
    if key ~= screenKey then
        screenKey = key
        panelArt:SetSize(B.w, B.h)
        panelArt:Clear()
        paintBars(panelArt, B, 0, 0, state)
    end
    local where = table.concat({ placed.x, placed.y, B.w, B.h }, ",")
    if where ~= lastPanel then
        lastPanel = where
        panel:SetPos(placed.x, placed.y)
        panel:SetSize(B.w, B.h)
        grab:SetSize(B.w, B.h)
    end
    panel.hidden = false
end

local function drawScreen(text, life, flash)
    if prefs.look == "bars" then
        return drawBarsScreen(text, life, flash)
    end
    local box = barBox(text, spot)
    local docked = prefs.x == nil
    if docked and not box then
        panel.hidden, placed, reopenAt = true, nil, nil
        adrenPanel.hidden = true
        return
    end
    if docked then
        local key = table.concat({ box.x, box.y, box.w, box.h }, ",")
        if key ~= boxKey then
            boxKey = key
            log("Pixel Art Bars: on the HP bar at " .. math.floor(box.x) .. ", " .. math.floor(box.y) .. " (" ..
                math.floor(box.w) .. " x " .. math.floor(box.h) .. ")")
        end
    end
    local room = docked and box.w - 2 or nil       -- on the bar, rows are only as long as the bar is wide
    local L = layout(life.count, life.pieces, pixelSize(), room)
    -- auto: large hearts, unless they don't fit on the HP bar
    if docked and prefs.size == "auto" and (L.w + 2 > box.w or L.h + 2 > box.h + 2) then
        L = layout(life.count, life.pieces, 1, room)
    end
    -- On the bar the hearts sit on a patch of the bar's own background that hides its number and red line. Dragged
    -- away they float with nothing behind them.
    local pad = docked and 2 or 0
    -- dragged away, the adrenaline orbs sit in a row under the hearts in the same panel
    local Lo = (not docked and life.adren) and layout(ORBS, 0, L.px) or nil
    local blockW = Lo and math.max(L.w, Lo.w) or L.w
    local blockH = Lo and (L.h + 2 * L.px + Lo.h) or L.h
    local w, h = blockW + 2 * pad, blockH + 2 * pad
    local x, bottom
    if docked then
        -- the patch reaches 1 unit past the bar on every side so none of its frame peeks out
        w, h = math.max(w, box.w + 2), math.max(h, box.h + 2)
        x, bottom = box.x - 1, box.y + box.h + 1
    else
        x, bottom = prefs.x, prefs.y
    end
    x, bottom, w, h = math.floor(x), math.floor(bottom), math.floor(w), math.floor(h)
    -- hidden on the bar, the heart to open it again sits just left of the bar, on the game's own heart
    reopenAt = docked and { x - TAB_W - 4, math.floor(box.y + (box.h - TAB_H) / 2) } or { x, bottom - TAB_H }
    if prefs.hidden then
        panel.hidden, placed = true, nil
        adrenPanel.hidden = true
        return
    end
    -- on the bar, the orbs go onto the adrenaline bar
    if docked and life.adren then
        drawAdrenDocked(life)
    else
        adrenPanel.hidden = true
    end
    placed = { x = x, y = bottom - h, w = w, h = h }
    local key = table.concat({ life.count, life.halves, life.pieceHalves, L.px, w, h, tostring(flash), tostring(docked),
                               tostring(Lo and life.adrenHalves), prefs.heart, tostring(life.orbTheme) }, ":")
    if key ~= screenKey then
        screenKey = key
        panelArt:SetSize(w, h)
        panelArt:Clear()
        if docked then
            rect(panelArt, 0, 0, w, h, BAR_BACKGROUND)
        end
        local oy = math.floor((h - blockH) / 2)
        paintIcons(panelArt, L, pad, oy, life, flash)
        if Lo then
            paintOrbs(panelArt, Lo, pad, oy + L.h + 2 * L.px, life.adrenHalves, life.orbTheme)
        end
    end
    local where = table.concat({ placed.x, placed.y, w, h }, ",")
    if where ~= lastPanel then
        lastPanel = where
        panel:SetPos(placed.x, placed.y)
        panel:SetSize(w, h)
        grab:SetSize(w, h)
    end
    panel.hidden = false
end

-- On your character (under your feet or over your head) ---------------------------------------------------------------

local me, meTicks = nil, 0
local function drawHead(life, flash)
    meTicks = meTicks + 1
    if not me or meTicks >= 25 then
        me, meTicks = get(function() return PlayerList.Self() end), 0
    end
    local feet = me and get(function() return me.position end)
    if not feet then
        headLayer.hidden = true
        return
    end
    -- the top of your head: the top of your character's bounding box (in the world, its bottom at your feet), so it
    -- fits any outfit or size. A box that isn't at your feet, or a height that isn't a character's (under 300 or over
    -- 2,000 units), is not trusted and the measured height is used instead.
    local minY = get(function() return me.aabb.minimum.y end)
    local maxY = get(function() return me.aabb.maximum.y end)
    local tall = HEAD_HEIGHT
    if type(minY) == "number" and type(maxY) == "number" and math.abs(minY - feet.y) < 200 then
        local height = maxY - feet.y
        if height >= 300 and height <= 2000 then
            tall = height
        end
    end
    local headY = feet.y + tall
    local top = get(function() return ScreenConvert.Vector3ToScreen(Vector3.new(feet.x, headY, feet.z)) end)
    local bars = get(function() return ScreenConvert.Vector3ToScreen(Vector3.new(feet.x, headY + BAR_RISE, feet.z)) end)
    if not top or type(top.x) ~= "number" then
        headLayer.hidden = true
        return
    end
    -- your feet on screen
    local under = get(function() return ScreenConvert.Vector3ToScreen(Vector3.new(feet.x, feet.y, feet.z)) end)
    if not under or type(under.x) ~= "number" then
        headLayer.hidden = true
        return
    end
    local W, H, key, paint
    if prefs.look == "bars" then
        local B = barsLayout(pixelSize(), life.adren ~= nil)
        local state = barState(life)
        W, H = B.w, B.h
        key = table.concat({ "bars", state.key, B.px }, ":")
        paint = function() paintBars(headArt, B, 0, 0, state) end
    else
        local L = layout(life.count, life.pieces, pixelSize())
        -- the adrenaline orbs in a row under the hearts
        local Lo = life.adren and layout(ORBS, 0, L.px) or nil
        W = Lo and math.max(L.w, Lo.w) or L.w
        H = Lo and (L.h + 2 * L.px + Lo.h) or L.h
        key = table.concat({ life.count, life.halves, life.pieceHalves, L.px, tostring(flash),
                             tostring(Lo and life.adrenHalves), prefs.heart, tostring(life.orbTheme) }, ":")
        paint = function()
            paintIcons(headArt, L, math.floor((W - L.w) / 2), 0, life, flash)
            if Lo then
                paintOrbs(headArt, Lo, math.floor((W - Lo.w) / 2), L.h + 2 * L.px, life.adrenHalves, life.orbTheme)
            end
        end
    end
    if key ~= headKey then
        headKey = key
        headLayer:SetSize(W, H)
        headArt:SetSize(W, H)
        headArt:Clear()
        paint()
    end
    if prefs.under and prefs.look == "bars" then
        -- the bars right on top of Cooldown Bar's row of abilities
        headLayer:SetPos(math.floor(under.x - W / 2), math.floor(under.y + ABILITY_ROW - 3 - H))
    elseif prefs.under then
        -- hearts just below your feet
        headLayer:SetPos(math.floor(under.x - W / 2), math.floor(under.y + UNDER_GAP))
    else
        -- whichever is higher: 52 above your head, or clear of the game's bars
        local bottom = top.y - HEAD_GAP
        if bars and type(bars.y) == "number" then bottom = math.min(bottom, bars.y - BAR_ROOM) end
        headLayer:SetPos(math.floor(top.x - W / 2), math.floor(bottom - H))
    end
    headLayer.hidden = false
end

-- The HIDE button and the heart tab -------------------------------------------------------------------------------------

local function updateTabs(screenOn)
    local shown = screenOn and placed ~= nil and not prefs.hidden
    local hovering = shown and (hovered(grab, panel, placed.w, placed.h) or hovered(hideClick, hideTab, HIDE_W, HIDE_H))
    hoverTicks = hovering and 40 or math.max(0, hoverTicks - 1)
    local showHide = shown and hoverTicks > 0 and not (drag and drag.moved)
    if showHide then
        hideTab:SetPos(placed.x + placed.w - HIDE_W, placed.y - HIDE_H)
    end
    hideTab.hidden = not showHide
    local showTab = screenOn and prefs.hidden and reopenAt ~= nil
    if showTab then
        reopenTab:SetPos(reopenAt[1], reopenAt[2])
    end
    reopenTab.hidden = not showTab
end

local function hideAll()
    panel.hidden, hideTab.hidden, reopenTab.hidden, headLayer.hidden, adrenPanel.hidden = true, true, true, true, true
    placed, drag = nil, nil
end

-- Keeping clicks off the world: a left click runs the top entry of the game's menu, and over the panel that would be
-- whatever is behind it. So while the cursor is over the panel or its buttons, the plugin's own entry (which does
-- nothing; the panel does the work) becomes the left click.
local function entryText(entry)
    local override = get(function() return entry.overrideText end)
    if override and override ~= "" then
        return override
    end
    return get(function() return entry.fullText end) or ""
end
local function guardMenu(event)
    local onPanel = placed ~= nil and over(panel, placed.w, placed.h)
    if not (onPanel or over(hideTab, HIDE_W, HIDE_H) or over(reopenTab, TAB_W, TAB_H)) then
        return
    end
    local menu = event.miniMenu
    local count, cancel = menu.entryCount, nil
    for i = 1, count do
        if menu.entries[i].actionType == MiniMenuActionType.CANCEL then
            cancel = i
        end
    end
    local leftClickIsLast = cancel ~= count
    menu:Add(MENU_LABEL, function() end)
    local total, entries, ours = menu.entryCount, menu.entries, nil
    for i = 1, total do
        if entries[i].actionEntryType == MiniMenuEntryType.PLUGIN and entryText(entries[i]) == MENU_LABEL then
            ours = i
        end
    end
    local leftClick = leftClickIsLast and total or 1
    if ours and ours ~= leftClick then
        menu:Swap(ours, leftClick)
    end
end
local lastMenuProblem = nil
Event.MiniMenuReady.Subscribe("pixelArtBarsMenu", function(event)
    local ok, problem = pcall(guardMenu, event)
    if not ok and problem ~= lastMenuProblem then
        log("Pixel Art Bars menu: " .. tostring(problem))
    end
    lastMenuProblem = not ok and problem or nil
end)

-- Every client tick: read the HP text, then draw what changed ------------------------------------------------------------

local ticks, blinkOn, lastProblem = 0, false, nil
Event.Logic.Subscribe("pixelArtBars", function()
    local ok, problem = pcall(function()
        ticks = ticks + 1
        if prefs.show == "off" then
            hideAll()
            return
        end
        local text, now, most = readSpot(spot)
        if not text or most < LIFE_PER_HEART then
            hideAll()
            if ticks % 50 == 0 then          -- look again once a second until the action bar shows
                spot = findSpot()
            end
            return
        end
        if not get(function() return text.visibleGlobal end) then
            hideAll()
            return
        end
        if ticks % 15 == 0 then
            blinkOn = not blinkOn
        end
        local life = { now = now, most = most }
        life.count, life.halves = heartsFor(now, most)
        life.pieces, life.pieceHalves = armourFor(now, most)
        if prefs.adren then
            -- the value from the game's variable (or the bar's text); the bar's text also tells where to draw on the bar
            local adrenText, textValue = readAdren(adrenSpot)
            if not textValue and ticks % 50 == 25 then     -- look for the adrenaline text once a second until found
                adrenSpot = findAdren()
            end
            local value = adrenFromVar() or textValue
            if value then
                life.adren, life.adrenHalves = value, math.floor(value / 5)
                if textValue and get(function() return adrenText.visibleGlobal end) ~= false then
                    life.adrenText = adrenText
                end
            end
        end
        local alerting = prefs.alertAt ~= "off" and life.adren ~= nil and life.adren >= prefs.alertAt
        life.orbTheme = (alerting and not (prefs.alertFlash and blinkOn)) and prefs.alertColour or prefs.orb
        local flash = prefs.blink and blinkOn and now * 100 < most * prefs.lowAt
        local screenOn = prefs.show == "screen" or prefs.show == "both"
        followDrag()
        if screenOn then
            drawScreen(text, life, flash)
        else
            panel.hidden, placed, drag = true, nil, nil
            adrenPanel.hidden = true
        end
        if prefs.show == "head" or prefs.show == "both" then
            drawHead(life, flash)
        else
            headLayer.hidden = true
        end
        updateTabs(screenOn)
    end)
    if not ok and problem ~= lastProblem then
        log("Pixel Art Bars: " .. tostring(problem))
    end
    lastProblem = not ok and problem or nil
end)

-- Settings in the Plugin Hub (the cog) ------------------------------------------------------------------------------

Event.SettingsLayerReady.Subscribe("pixelArtBarsSettings", function(event)
    local settings = ui.Layer.new(event.component)
    settings:SetPos(8, 8)
    settings:SetSize(540, 220)
    local function button(y, label, press, x, w)
        local b = ui.Button.new(settings)
        b:SetPos(x or 0, y)
        b:SetSize(w or 280, 25)
        b.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
        b.label = label()
        b:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
            press()
            b.label = label()
            save()
            screenKey, headKey, adrenKey = "", "", ""
        end)
    end
    local function pct(v) return v == "off" and "off" or (v .. "%") end
    button(192, function() return "Look: " .. prefs.look end,
        function() prefs.look = nextIn(LOOK_ORDER, prefs.look) end)
    button(192, function() return "Health bar colour: " .. prefs.barColour end,
        function() prefs.barColour = nextIn(BAR_COLOUR_ORDER, prefs.barColour) end, 290, 250)
    button(0, function() return "Heart colour: " .. prefs.heart end,
        function() prefs.heart = nextIn(THEME_ORDER, prefs.heart) end, 290, 250)
    button(32, function() return "Orb colour: " .. prefs.orb end,
        function() prefs.orb = nextIn(ORB_ORDER, prefs.orb) end, 290, 250)
    button(64, function() return "Adrenaline alert at: " .. pct(prefs.alertAt) end,
        function() prefs.alertAt = nextIn(ALERT_ORDER, prefs.alertAt) end, 290, 250)
    button(96, function() return "Alert colour: " .. prefs.alertColour end,
        function() prefs.alertColour = nextIn(THEME_ORDER, prefs.alertColour) end, 290, 250)
    button(128, function() return "Alert flashes: " .. (prefs.alertFlash and "on" or "off") end,
        function() prefs.alertFlash = not prefs.alertFlash end, 290, 250)
    button(160, function() return "Low health at: " .. pct(prefs.lowAt) end,
        function() prefs.lowAt = nextIn(LOW_ORDER, prefs.lowAt) end, 290, 250)
    button(0, function() return "Show: " .. SHOW_TEXT[prefs.show] end,
        function() prefs.show = nextIn(SHOW_ORDER, prefs.show) end)
    button(32, function() return "Size: " .. prefs.size end,
        function() prefs.size = nextIn(SIZE_ORDER, prefs.size) end)
    button(64, function() return "Hearts blink when low: " .. (prefs.blink and "on" or "off") end,
        function() prefs.blink = not prefs.blink end)
    button(96, function() return "By your character: " .. (prefs.under and "at your feet" or "over your head") end,
        function() prefs.under = not prefs.under end)
    button(128, function() return "Adrenaline orbs: " .. (prefs.adren and "on" or "off") end,
        function() prefs.adren = not prefs.adren end)
    button(160, function() return "Put the panel back on the HP bar" end,
        function() prefs.x, prefs.y, prefs.hidden = nil, nil, false end)
end)

function PluginShutdown()
    Event.Logic.Unsubscribe("pixelArtBars")
    Event.MiniMenuReady.Unsubscribe("pixelArtBarsMenu")
    Event.SettingsLayerReady.Unsubscribe("pixelArtBarsSettings")
    for _, component in ipairs({ panel, hideTab, reopenTab, headLayer, adrenPanel }) do
        pcall(function() component:Destroy() end)
    end
end

log("Pixel Art Bars 0.1.0 is on")
