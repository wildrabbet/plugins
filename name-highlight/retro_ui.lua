-- Retro UI Kit library: the painter, sprites and windows on their own (no demo, no events), so a plugin can either
-- depend on the Retro UI Kit plugin or carry this one file. main.lua of the Retro UI Kit loads this file.
-- Draws only: it reads no game data, sends nothing and needs no permissions. Plain rectangles and text on
-- ui.Canvas on a 3-unit pixel grid; no image files. Window click areas take the click and the mouse wheel.

local RetroUI = {}
RetroUI.VERSION = "0.2.0"
RetroUI.P = 3                        -- one art pixel, in interface units

local P = RetroUI.P

-- Colours (0xRRGGBBAA)
RetroUI.COLOURS = {
    INK = 0x141010FF,
    WOOD = 0x7E3F22FF, WOOD_LIGHT = 0xA05A30FF, WOOD_DARK = 0x4F2412FF, WOOD_GRAIN = 0x6E361CFF,
    CHROME = 0xB9C4CCFF, CHROME_LIGHT = 0xF2F6F8FF, CHROME_DARK = 0x6F7C86FF,
    GOLD = 0xE8B23CFF, GOLD_LIGHT = 0xFFE08AFF, GOLD_DARK = 0x9C6B1EFF,
    TUBE = 0x2A140CFF, GLASS = 0x0E1A26FF, GLASS_LIGHT = 0x23384CFF, LCD = 0x10150EFF, CLOTH = 0x3A1414FF,
    CREAM = 0xFFF1C9FF, DARK = 0x2B1608FF, NUMBER = 0xF2C14EFF, FADED = 0x9FB3C8FF,
    GREEN = 0x5EE07AFF, RED = 0xFF6A5AFF, PARCHMENT = 0xFFF1C9FF, PARCHMENT_DARK = 0xE2CC96FF,
    BULBS = { 0xFF4D4DFF, 0xFFB03BFF, 0xFFE45CFF, 0x5EE07AFF, 0x45B5FFFF, 0xC77DFFFF },
}
local C = RetroUI.COLOURS

-- Pixel sprites: one letter per art pixel, "." is clear. Draw with paint:Sprite(x, y, rows, palette).
RetroUI.SPRITES = {
    BOTTLE = {
        "....kck....", "....kCk....", "...kkkkk...", "....kgk....", "....kgk....", "...kgggk...", "..kgggggk..",
        ".kgLLLLLgk.", "kLwlLLLLLLk", "kLwLLLLLLLk", "kLlLLLLLLdk", "kLLLLLLLLdk", "kLLLLLLLddk", ".kdddddddk.",
        "..kkkkkkk..",
    },
    SMALL_BOTTLE = { ".kck.", ".kgk.", "kgggk", "kLLLk", "kLwLk", "kLLdk", ".kkk." },
    STAR = { "..k..", ".kyk.", "kyyyk", ".kyk.", "k.k.k" },
    NOTE = { "..kkk", "..k.k", "..k..", "..k..", "kkk..", "kkk.." },
    COIN = { ".kkk.", "kyyyk", "kyYyk", "kyyyk", ".kkk." },
    HEART = { "kk.kk", "krkrk", "krrrk", ".krk.", "..k.." },
}

-- Shades of a colour, for sprites: towards = 255 lightens, 0 darkens
function RetroUI.Shade(hex, towards, amount)
    local alpha = hex % 256
    local value = math.floor(hex / 256)
    local blue = value % 256
    value = math.floor(value / 256)
    local green = value % 256
    local red = math.floor(value / 256)
    local function mix(v)
        return math.floor(v + (towards - v) * amount + 0.5)
    end
    return ((mix(red) * 256 + mix(green)) * 256 + mix(blue)) * 256 + alpha
end

-- The palette for the BOTTLE sprites, with the liquid in any colour
function RetroUI.BottlePalette(liquid)
    return { k = C.INK, c = C.WOOD_LIGHT, C = C.WOOD, g = 0xCFE3EAFF, L = liquid,
             l = RetroUI.Shade(liquid, 255, 0.45), d = RetroUI.Shade(liquid, 0, 0.45), w = 0xFFFFFFFF }
end

local function rgba(hex)
    local alpha = hex % 256
    hex = math.floor(hex / 256)
    local blue = hex % 256
    hex = math.floor(hex / 256)
    local green = hex % 256
    local red = math.floor(hex / 256)
    return Vector4.new(red / 255, green / 255, blue / 255, alpha / 255)
end

-- The game's classic pixel fonts when it has them, otherwise its standard font
local function font(name)
    local ok, result = pcall(function()
        local candidate = id.Font[name]
        local description = config.Font.FromID(candidate)
        if description and description:GetStringWidth("Retro") > 0 then
            return candidate
        end
    end)
    if ok and result then
        return result
    end
    return id.Font.MUSEO_SANS_15PT_REGULAR
end

local function clean(value)
    local text = tostring(value or "")
    text = text:gsub("<[^>]*>", "")
    text = text:gsub("%c", " ")
    return text
end

-- The painter --------------------------------------------------------------------------------------------------------
-- Wraps one ui.Canvas. Every method draws on it; nothing here makes components.

function RetroUI.Painter(canvas)
    local paint = { canvas = canvas }
    local fonts = { normal = font("P12_FULL"), bold = font("B12_FULL") }
    local widths = {}

    local function measure(text, selected)
        if widths[selected] == nil then
            local ok, info = pcall(function() return config.Font.FromID(selected) end)
            widths[selected] = ok and info or false
        end
        local info = widths[selected]
        local ok, width = pcall(function() return info:GetStringWidth(text) end)
        return ok and width or #text * 7
    end

    function paint:Clear()
        canvas:Clear()
    end

    -- How wide a piece of text is in the game's font, in interface units
    function paint:Measure(text, bold)
        return measure(clean(text), bold and fonts.bold or fonts.normal)
    end

    function paint:Rect(x, y, width, height, colour)
        if width > 0 and height > 0 then
            canvas:AddRectangle(math.floor(x), math.floor(y), math.floor(width), math.floor(height), colour)
        end
    end

    -- A pixel-art block: black outline, a face, a light top and left edge and a dark bottom and right edge
    function paint:Block(x, y, width, height, face, light, dark)
        self:Rect(x, y, width, height, C.INK)
        self:Rect(x + P, y + P, width - 2 * P, height - 2 * P, face)
        if light then
            self:Rect(x + P, y + P, width - 2 * P, P, light)
            self:Rect(x + P, y + P, P, height - 2 * P, light)
        end
        if dark then
            self:Rect(x + P, y + height - 2 * P, width - 2 * P, P, dark)
            self:Rect(x + width - 2 * P, y + P, P, height - 2 * P, dark)
        end
    end

    function paint:Chrome(x, y, width, height)
        self:Block(x, y, width, height, C.CHROME, C.CHROME_LIGHT, C.CHROME_DARK)
    end

    function paint:Gold(x, y, width, height)
        self:Block(x, y, width, height, C.GOLD, C.GOLD_LIGHT, C.GOLD_DARK)
    end

    function paint:Glass(x, y, width, height)
        self:Block(x, y, width, height, C.GLASS, C.GLASS_LIGHT)
    end

    function paint:LCD(x, y, width, height)
        self:Block(x, y, width, height, C.LCD)
    end

    function paint:Card(x, y, width, height)
        self:Block(x, y, width, height, C.PARCHMENT, 0xFFFFFFFF, C.PARCHMENT_DARK)
    end

    function paint:Text(x, y, width, height, value, colour, options)
        options = options or {}
        local selected = options.bold and fonts.bold or fonts.normal
        local content = clean(value)
        if measure(content, selected) > width then
            while #content > 0 and measure(content .. "...", selected) > width do
                content = content:sub(1, -2)
            end
            content = content .. "..."
        end
        local style = ui.TextDataConfig.new()
        style.font = selected
        style.colour = rgba(colour or C.CREAM)
        style.alignHorizontal = options.align == "centre" and ui.AlignMode.CENTRE
            or options.align == "right" and (ui.AlignMode.BOTTOMRIGHT or ui.AlignMode.TOPLEFT)
            or ui.AlignMode.TOPLEFT
        style.alignVertical = ui.AlignMode.CENTRE
        canvas:AddText(math.floor(x), math.floor(y), math.floor(width), math.floor(height), content, style)
    end

    -- A chrome button with a centred label; gold when on, pushed in when pressed
    function paint:Button(x, y, width, height, label, on, pressed)
        local face = on and C.GOLD or C.CHROME
        local light = on and C.GOLD_LIGHT or C.CHROME_LIGHT
        local dark = on and C.GOLD_DARK or C.CHROME_DARK
        if pressed then
            self:Block(x, y, width, height, dark)
        else
            self:Block(x, y, width, height, face, light, dark)
        end
        if label and label ~= "" then
            local shift = pressed and P or 0
            self:Text(x + 3 + shift, y + shift, width - 6, height, label, C.DARK, { align = "centre" })
        end
    end

    -- A pixel arrow, four steps tall, pointing "up", "down", "left" or "right" around (cx, cy)
    function paint:Arrow(cx, cy, dir, colour, step)
        local unit = step or P
        for i = 0, 3 do
            local size = ((dir == "down" or dir == "right") and (2 * (3 - i) + 1) or (2 * i + 1)) * unit
            local half = math.floor(size / 2)
            if dir == "up" or dir == "down" then
                self:Rect(cx - half, cy - 2 * unit + i * unit, size, unit, colour or C.INK)
            else
                self:Rect(cx - 2 * unit + i * unit, cy - half, unit, size, colour or C.INK)
            end
        end
    end

    function paint:Sprite(x, y, rows, palette, size)
        local s = size or P
        for j, row in ipairs(rows) do
            for i = 1, #row do
                local colour = palette[row:sub(i, i)]
                if colour then
                    self:Rect(x + (i - 1) * s, y + (j - 1) * s, s, s, colour)
                end
            end
        end
    end

    -- A magnifying glass, for search boxes (18 x 18)
    function paint:Magnifier(x, y)
        self:Rect(x + P, y, 3 * P, P, C.INK)
        self:Rect(x + P, y + 4 * P, 3 * P, P, C.INK)
        self:Rect(x, y + P, P, 3 * P, C.INK)
        self:Rect(x + 4 * P, y + P, P, 3 * P, C.INK)
        self:Rect(x + 4 * P, y + 4 * P, P, P, C.INK)
        self:Rect(x + 5 * P, y + 5 * P, P, P, C.INK)
    end

    -- A gold nameplate centred on cx
    function paint:Nameplate(cx, y, width, title)
        self:Gold(cx - math.floor(width / 2), y, width, 36)
        self:Text(cx - math.floor(width / 2), y, width, 36, title, C.DARK, { bold = true, align = "centre" })
    end

    -- A list row in dark glass: name on the left, a number on the right; gold with dark text when lit
    function paint:Row(x, y, width, height, name, number, lit)
        if lit then
            self:Rect(x, y, width, height, C.GOLD)
        end
        local numberWidth = number and 48 or 0
        self:Text(x + 6, y, width - 12 - numberWidth, height, name, lit and C.DARK or C.CREAM)
        if number then
            self:Text(x + width - 6 - numberWidth, y, numberWidth, height, tostring(number), lit and C.DARK or C.NUMBER,
                      { align = "right" })
        end
    end

    -- The cabinet: rings (black, chrome rim, black, light tube, black, wood), an arched crown and a plinth with feet
    function paint:Cabinet(width, height, crown)
        crown = crown or 84
        local base = height - 36
        local cx = math.floor(width / 2)
        local function half(y, inset)
            return RetroUI.CrownHalf(width, crown, y, inset)
        end
        local rings = { { 0, C.INK }, { P, C.CHROME_DARK }, { 2 * P, C.CHROME }, { 4 * P, C.INK }, { 5 * P, C.TUBE },
                        { 8 * P, C.INK }, { 9 * P, C.WOOD } }
        for y = 0, crown - 1, P do
            for _, ring in ipairs(rings) do
                local h = half(y + P, ring[1])
                self:Rect(cx - h, y, h * 2, P, ring[2])
            end
        end
        for _, ring in ipairs(rings) do
            local inset = ring[1]
            self:Rect(inset, crown, width - 2 * inset, base - inset - crown, ring[2])
        end
        self:Rect(2 * P, crown, P, base - 4 * P - crown, C.CHROME_LIGHT)
        self:Rect(9 * P, crown, P, base - 10 * P - crown, C.WOOD_LIGHT)
        self:Rect(width - 10 * P, crown, P, base - 10 * P - crown, C.WOOD_DARK)
        for x = 9 * P + 18, width - 9 * P - 18, 27 do
            self:Rect(x, crown + 6, P, base - 10 * P - crown - 12, C.WOOD_GRAIN)
        end
        self:Block(6, base, width - 12, 24, C.WOOD_DARK, C.WOOD, C.INK)
        self:Chrome(21, height - 15, 39, 15)
        self:Chrome(width - 60, height - 15, 39, 15)
    end

    -- Bulbs: a list of { x, y } (see RetroUI.BulbSpots), coloured in a chase that moves with phase
    function paint:Bulbs(spots, phase)
        for i, spot in ipairs(spots) do
            self:Rect(spot[1], spot[2], 2 * P, 2 * P, C.BULBS[(i + (phase or 0)) % #C.BULBS + 1])
            self:Rect(spot[1], spot[2], P, P, 0xFFFFFFB0)
        end
    end

    return paint
end

-- Where a cabinet's bulbs go: round the crown, then down both sides
function RetroUI.BulbSpots(width, height, crown)
    crown = crown or 84
    local base = height - 36
    local cx = math.floor(width / 2)
    local spots = {}
    local a, b = cx - 19, crown - 19
    local count = math.max(12, math.floor(width / 15))
    for i = 0, count do
        local angle = math.pi * i / count
        spots[#spots + 1] = { math.floor((cx - a * math.cos(angle) - 3) / P) * P,
                              math.floor((crown - b * math.sin(angle) - 3) / P) * P }
    end
    for y = crown + 9, base - 33, 12 do
        table.insert(spots, 1, { 15, y })
        spots[#spots + 1] = { width - 21, y }
    end
    return spots
end

-- Half the width of a cabinet ring at height y of the arched crown (inset: how far in the ring is; 27 = the wood)
function RetroUI.CrownHalf(width, crown, y, inset)
    local a, b = math.floor(width / 2) - inset, crown - inset
    local dy = crown - y
    if b <= 0 or dy > b then
        return 0
    end
    return math.floor(a * math.sqrt(1 - (dy / b) ^ 2) / P) * P
end

local windowCount = 0                -- gives each window its own menu-event name

RetroUI.HIDE_ALL_VAR = "CASTLEWARS_RED_KILLS"
function RetroUI.HideAllState()
    local ok, value = pcall(function() return var.VarClient[RetroUI.HIDE_ALL_VAR].value end)
    if ok and type(value) == "number" then
        return value, value % 2 == 1
    end
    return nil
end

local function mouse()
    local okX, x = pcall(Mouse.GetX)
    local okY, y = pcall(Mouse.GetY)
    if okX and okY and type(x) == "number" and type(y) == "number" then
        return x, y
    end
end

function RetroUI.Window(parent, options)
    options = options or {}
    if options.program then return RetroUI.ProgramFromWindow(parent, options) end
    local width = math.floor(options.width or 384)
    local height = math.floor(options.height or 300)
    local crown = math.floor(options.crown or 84)
    local window = { width = width, height = height, crown = crown, areas = {}, spots = {} }
    local pos = { x = math.floor(options.x or 0), y = math.floor(options.y or 0) }

    local layer = ui.Layer.new(parent)
    layer:SetPos(pos.x, pos.y)
    layer:SetSize(width, height)
    layer.clickthrough = false
    window.layer = layer

    -- a clear rectangle that takes clicks and the wheel
    local function catcher(container, x, y, w, h)
        local area = ui.Rectangle.new(container)
        area:SetPos(math.floor(x), math.floor(y))
        area:SetSize(math.floor(w), math.floor(h))
        area.fill = true
        area.colour = Vector4.new(0, 0, 0, 0.004)
        area.clickthrough = false
        area:Subscribe(ui.Hook.ONSCROLLWHEEL, function() return false end)
        return area
    end
    local back = catcher(layer, 0, 0, width, height)
    back:Subscribe(ui.Hook.ONCLICK, function() return false end)

    local function canvas(container, w, h)
        local c = ui.Canvas.new(container)
        c:SetSize(w, h)
        c.clickthrough = true
        return c
    end
    window.art = RetroUI.Painter(canvas(layer, width, height))
    local lights = RetroUI.Painter(canvas(layer, width, height))

    -- The nameplate: as wide as its title (120 to 204), placed where the arch's wood is wide enough to hold it with
    -- room to spare, so it never covers the chrome rim or the bulbs
    local top = math.max(crown, 33)
    if crown > 0 and options.title then
        local plateWidth = math.max(120, math.min(204, width - 96, window.art:Measure(options.title, true) + 48))
        local plateY = 30
        while plateY < crown and 2 * RetroUI.CrownHalf(width, crown, plateY, 9 * P) - 24 < plateWidth do
            plateY = plateY + P
        end
        window.plate = { x = math.floor((width - plateWidth) / 2), y = plateY, width = plateWidth }
        top = math.max(top, plateY + 36 + 6)
    end
    window.inner = { x = 30, y = top, width = width - 60, height = height - 36 - 27 - top }
    local spots = (options.lights ~= false and crown > 0) and RetroUI.BulbSpots(width, height, crown) or {}
    local phase, ticks = 0, 0

    local drag, handle = nil, nil
    local function titleClick()
        if options.onTitleClick then
            return options.onTitleClick
        end
        if options.hideButton ~= false then
            return function() window:Hide() end
        end
        return nil
    end
    local function endDrag(clicked)
        if not drag then
            return
        end
        local press = drag
        drag = nil
        if options.onMove then
            pcall(options.onMove, pos.x, pos.y)
        end
        local click = titleClick()
        if clicked and not press.moved and press.onPlate and click then
            pcall(click)
        end
    end
    local function onPlate(mx, my)
        local plate = window.plate
        if not plate then
            return false
        end
        local okXY, origin = pcall(function() return layer.xyGlobal end)
        local x = mx - (okXY and origin and origin.x or pos.x)
        local y = my - (okXY and origin and origin.y or pos.y)
        return x >= plate.x and x < plate.x + plate.width and y >= plate.y and y < plate.y + 36
    end
    if options.draggable ~= false then
        handle = catcher(layer, 0, 0, width, math.max(24, top - 3))
        handle:Subscribe(ui.Hook.ONCLICK, function()
            local mx, my = mouse()
            if mx then
                drag = { mx, my, pos.x, pos.y, 0, moved = false, held = 0, onPlate = onPlate(mx, my) }
            end
            return false
        end)
        handle:Subscribe(ui.Hook.ONRELEASE, function()
            endDrag(true)
            return false
        end)
    end
    local function followDrag()
        if not drag then
            return
        end
        local mx, my = mouse()
        if not mx then
            return
        end
        if not drag.moved and math.abs(mx - drag[1]) + math.abs(my - drag[2]) >= 3 then
            drag.moved = true
        end
        local okW, parentWidth = pcall(function() return parent.width end)
        local okH, parentHeight = pcall(function() return parent.height end)
        parentWidth = okW and type(parentWidth) == "number" and parentWidth or 4000
        parentHeight = okH and type(parentHeight) == "number" and parentHeight or 4000
        pos.x = math.floor(math.max(60 - width, math.min(parentWidth - 60, drag[3] + mx - drag[1])))
        pos.y = math.floor(math.max(0, math.min(parentHeight - 40, drag[4] + my - drag[2])))
        layer:SetPos(pos.x, pos.y)
        local okOver, over = pcall(function() return handle.isMouseOver end)
        if okOver and over == false then
            drag[5] = drag[5] + 1
            if drag[5] > 15 then
                endDrag(false)
                return
            end
        else
            drag[5] = 0
        end
        drag.held = drag.held + 1
        if drag.onPlate and not drag.moved and drag.held > 25 and titleClick() then
            endDrag(true)
        end
    end

    -- A clickable spot. onClick() runs on a click; onWheel(delta) on the mouse wheel. Returns the area (hide it with
    -- area.hidden = true when its button isn't shown).
    function window:Area(x, y, w, h, onClick, onWheel)
        local area = ui.Rectangle.new(layer)
        area:SetPos(math.floor(x), math.floor(y))
        area:SetSize(math.floor(w), math.floor(h))
        area.fill = true
        area.colour = Vector4.new(0, 0, 0, 0.004)
        area.clickthrough = false
        area:Subscribe(ui.Hook.ONCLICK, function()
            if not area.hidden and onClick then
                onClick()
            end
            return false
        end)
        area:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
            if onWheel then
                onWheel(delta)
            end
            return false
        end)
        self.areas[#self.areas + 1] = area
        self.spots[#self.spots + 1] = { math.floor(x), math.floor(y), math.floor(w), math.floor(h), area }
        return area
    end

    -- A text box (the game's own input style). onChange(text, reason) runs when it changes.
    function window:Field(x, y, w, value, onChange)
        local input = ui.InputField.new(layer)
        input:SetPos(math.floor(x), math.floor(y))
        input:SetSize(math.floor(w), 25)
        input.stylesheetID = id.StyleSheet.INPUT_DEFAULT
        input.content = value or ""
        input.clickthrough = false
        if onChange then
            input:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, reason, contents)
                onChange(tostring(contents or ""), reason)
            end)
        end
        input:Subscribe(ui.Hook.ONSCROLLWHEEL, function() return false end)
        return input
    end

    -- HIDE: a small button on the plinth (top right for a window without a crown). Hiding leaves a gold tab with the
    -- title where the window was; clicking the tab opens it again, and dragging it carries it (and the window) elsewhere.
    local hideSpot = crown > 0 and { width - 75, height - 33, 60, 18 } or { width - 66, 6, 60, 18 }
    local reopen, tabWidth, tabHandle = nil, 0, nil
    local tabAt, tabDrag = { x = 0, y = 0 }, nil
    -- Puts the gold tab at (x, y), kept fully on screen
    local function placeTab(x, y)
        local okW, parentWidth = pcall(function() return parent.width end)
        local okH, parentHeight = pcall(function() return parent.height end)
        parentWidth = okW and type(parentWidth) == "number" and parentWidth or 4000
        parentHeight = okH and type(parentHeight) == "number" and parentHeight or 4000
        tabAt.x = math.floor(math.max(0, math.min(parentWidth - tabWidth, x)))
        tabAt.y = math.floor(math.max(0, math.min(parentHeight - 30, y)))
        reopen:SetPos(tabAt.x, tabAt.y)
    end
    -- Ends a press on the tab: a press that moved was a drag (report the new place); one that didn't is a click
    local function endTabDrag(clicked)
        local press = tabDrag
        if not press then
            return
        end
        tabDrag = nil
        if press.moved then
            if options.onMove then
                pcall(options.onMove, pos.x, pos.y)
            end
        elseif clicked then
            window:Show()
        end
    end
    if options.hideButton ~= false then
        window:Area(hideSpot[1], hideSpot[2], hideSpot[3], hideSpot[4], function() window:Hide() end)
        tabWidth = math.max(90, math.min(204, window.art:Measure(options.title or "OPEN", true) + 36))
        reopen = ui.Layer.new(parent)
        reopen:SetSize(tabWidth, 30)
        reopen.hidden = true
        reopen.clickthrough = false
        local tab = RetroUI.Painter(canvas(reopen, tabWidth, 30))
        tab:Gold(0, 0, tabWidth, 30)
        tab:Text(0, 0, tabWidth, 30, options.title or "OPEN", C.DARK, { bold = true, align = "centre" })
        -- The tab drags the same way as the window (a press starts it, the tab follows the mouse every client tick, and
        -- letting go ends it). A press that hasn't moved 3 units by then is a click and opens the window.
        tabHandle = catcher(reopen, 0, 0, tabWidth, 30)
        tabHandle:Subscribe(ui.Hook.ONCLICK, function()
            local mx, my = mouse()
            if mx then
                tabDrag = { mx = mx, my = my, x = tabAt.x, y = tabAt.y, off = 0, held = 0, moved = false }
            else
                window:Show()
            end
            return false
        end)
        tabHandle:Subscribe(ui.Hook.ONRELEASE, function()
            endTabDrag(true)
            return false
        end)
    end
    local function followTabDrag()
        local press = tabDrag
        if not press then
            return
        end
        local mx, my = mouse()
        if not mx then
            return
        end
        local dx, dy = mx - press.mx, my - press.my
        if not press.moved and math.abs(dx) + math.abs(dy) >= 3 then
            press.moved = true
        end
        if press.moved then
            placeTab(press.x + dx, press.y + dy)
            -- the window opens again where the tab is now
            pos.x, pos.y = tabAt.x - math.floor((width - tabWidth) / 2), tabAt.y
            layer:SetPos(pos.x, pos.y)
        end
        local okOver, over = pcall(function() return tabHandle.isMouseOver end)
        if okOver and over == false then
            press.off = press.off + 1
            if press.off > 15 then
                endTabDrag(false)
                return
            end
        else
            press.off = 0
        end
        press.held = press.held + 1
        if not press.moved and press.held > 25 then
            endTabDrag(true)
        end
    end

    local function relative(component, fallbackX, fallbackY)
        local mx, my = mouse()
        if not mx then
            return nil
        end
        local okXY, origin = pcall(function() return component.xyGlobal end)
        local ox = okXY and type(origin) ~= "nil" and origin.x or fallbackX
        local oy = okXY and type(origin) ~= "nil" and origin.y or fallbackY
        return mx - ox, my - oy
    end
    local function overWindow()
        if layer.hidden then
            return nil
        end
        local x, y = relative(layer, pos.x, pos.y)
        if not x or x < 0 or y < 0 or x >= width or y >= height then
            return nil
        end
        if crown > 0 and y < crown and math.abs(x - math.floor(width / 2)) > RetroUI.CrownHalf(width, crown, math.min(crown, y + P), 0) then
            return nil
        end
        return x, y
    end
    local function overTab()
        if not reopen or reopen.hidden then
            return false
        end
        local x, y = relative(reopen, pos.x + math.floor((width - tabWidth) / 2), pos.y)
        return x ~= nil and x >= 0 and y >= 0 and x < tabWidth and y < 30
    end
    local menuLabel = options.title or "Window"
    local function entryText(entry)
        local okOverride, override = pcall(function() return entry.overrideText end)
        if okOverride and override and override ~= "" then
            return override
        end
        local okFull, full = pcall(function() return entry.fullText end)
        return okFull and full or ""
    end
    local function guardMenu(event)
        local x, y = overWindow()
        local onTab = x == nil and overTab()
        if x == nil and not onTab then
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
        local overArea = onTab
        if x then
            if handle and y < math.max(24, top - 3) then
                overArea = true
            end
            for _, spot in ipairs(window.spots) do
                if not spot[5].hidden and x >= spot[1] and y >= spot[2] and x < spot[1] + spot[3] and y < spot[2] + spot[4] then
                    overArea = true
                end
            end
        end
        if not overArea then
            local leftClick = leftClickIsLast and count or 1
            if cancel and cancel ~= leftClick then
                menu:Swap(cancel, leftClick)
            end
            return
        end
        menu:Add(menuLabel, function() end)
        local total, entries, ours = menu.entryCount, menu.entries, nil
        for i = 1, total do
            if entries[i].actionEntryType == MiniMenuEntryType.PLUGIN and entryText(entries[i]) == menuLabel then
                ours = i
            end
        end
        local leftClick = leftClickIsLast and total or 1
        if ours and ours ~= leftClick then
            menu:Swap(ours, leftClick)
        end
    end
    windowCount = windowCount + 1
    local menuKey = "retroUIWindowMenu" .. windowCount
    if options.guardMenu ~= false then
        local lastProblem = nil
        pcall(function()
            Event.MiniMenuReady.Subscribe(menuKey, function(event)
                local ok, problem = pcall(guardMenu, event)
                if not ok and problem ~= lastProblem then
                    log("Retro UI window menu: " .. tostring(problem))
                end
                lastProblem = not ok and problem or nil
            end)
        end)
    end

    function window:Hide()
        drag = nil
        layer.hidden = true
        if reopen then
            placeTab(pos.x + math.floor((width - tabWidth) / 2), pos.y)
            reopen.hidden = false
            pcall(function() reopen:MoveToFront() end)
        end
        if options.onHide then
            pcall(options.onHide, true)
        end
    end

    function window:Show()
        tabDrag = nil
        layer.hidden = false
        if reopen then
            reopen.hidden = true
        end
        if options.onHide then
            pcall(options.onHide, false)
        end
    end

    function window:IsHidden()
        return layer.hidden == true
    end

    function window:ContentLayer()
        return layer
    end

    local allSeen, hiddenByAll, allTicks = nil, false, 0
    local function followHideAll()
        allTicks = allTicks + 1
        if options.hideAll == false or not reopen or allTicks % 5 ~= 0 then
            return
        end
        local serial, hidden = RetroUI.HideAllState()
        if serial == nil or serial == allSeen then
            return
        end
        local first = allSeen == nil
        allSeen = serial
        if first then
            return
        end
        if hidden then
            if not layer.hidden then
                hiddenByAll = true
                window:Hide()
            end
        elseif hiddenByAll then
            hiddenByAll = false
            if layer.hidden then
                window:Show()
            end
        end
    end

    local function drawLights()
        lights:Clear()
        lights:Bulbs(spots, phase)
    end

    -- Redraws the cabinet, then your content: drawContent(paint, window)
    function window:Redraw(drawContent)
        self.art:Clear()
        if crown > 0 then
            self.art:Cabinet(width, height, crown)
            if self.plate then
                self.art:Nameplate(math.floor(width / 2), self.plate.y, self.plate.width, options.title)
            end
        else
            self.art:Block(0, 0, width, height, C.WOOD, C.WOOD_LIGHT, C.WOOD_DARK)
        end
        if options.hideButton ~= false then
            self.art:Button(hideSpot[1], hideSpot[2], hideSpot[3], hideSpot[4], "HIDE", false)
        end
        if drawContent then
            drawContent(self.art, self)
        end
        drawLights()
    end

    -- Every client tick: follows a drag (of the window or its gold tab), and moves the bulbs along every 12 ticks (0.24 s)
    function window:Animate()
        followDrag()
        followTabDrag()
        followHideAll()
        if layer.hidden or #spots == 0 then
            return
        end
        ticks = ticks + 1
        if ticks % 12 == 0 then
            phase = phase + 1
            drawLights()
        end
    end

    function window:SetPos(x, y)
        pos.x, pos.y = math.floor(x), math.floor(y)
        layer:SetPos(pos.x, pos.y)
    end

    function window:GetPos()
        return pos.x, pos.y
    end

    function window:SetHidden(hidden)
        if hidden then
            self:Hide()
        else
            self:Show()
        end
    end

    function window:Destroy()
        pcall(function() Event.MiniMenuReady.Unsubscribe(menuKey) end)
        layer.hidden = true
        pcall(function() layer:Destroy() end)
        if reopen then
            reopen.hidden = true
            pcall(function() reopen:Destroy() end)
        end
    end

    window:Redraw(nil)
    return window
end

RetroUI.BAR = 30
local programCount = 0
function RetroUI.ProgramWindow(parent, options)
    options = options or {}
    local BAR = RetroUI.BAR
    local sizes = { small = options.small or { 270, 252 }, big = options.big or options.small or { 420, 408 } }
    local title = options.title or "Window"
    local window = { state = "closed", spots = {} }
    local open = sizes[options.state] and options.state or "small"      -- the size it opens at, and returns to
    local pos = { x = math.floor(options.x or 0), y = math.floor(options.y or 0) }

    local layer = ui.Layer.new(parent)
    layer:SetPos(pos.x, pos.y)
    layer.clickthrough = false
    window.layer = layer
    local function catcher(container)
        local area = ui.Rectangle.new(container)
        area.fill = true
        area.colour = Vector4.new(0, 0, 0, 0.004)
        area.clickthrough = false
        area:Subscribe(ui.Hook.ONSCROLLWHEEL, function() return false end)
        return area
    end
    local back = catcher(layer)
    back:Subscribe(ui.Hook.ONCLICK, function() return false end)
    local artCanvas = ui.Canvas.new(layer)
    artCanvas.clickthrough = true
    local lightCanvas = ui.Canvas.new(layer)
    lightCanvas.clickthrough = true
    window.art = RetroUI.Painter(artCanvas)
    local lights = RetroUI.Painter(lightCanvas)
    local minWidth = math.max(165, math.min(300, window.art:Measure(title, true) + 30 + 3 * 27 + 9))
    local function sizeOf(state)
        if state == "min" then return minWidth, BAR end
        local s = sizes[state] or sizes.small
        return s[1], s[2]
    end
    -- where the three buttons sit on a bar of width w: - [] X, 24 x 22 each, from the right
    local function buttonX(w, i) return w - 3 * 27 - 6 + (i - 1) * 27 end
    -- a window with one size has nothing for [] to do: it's drawn faded and ignores clicks
    local oneSize = sizes.small[1] == sizes.big[1] and sizes.small[2] == sizes.big[2]

    -- options.flatContent (a Window made with program = true): one content layer for good, from the window's top
    -- (its spots are in window units, like the cabinet's were), made before the title bar so the bar stays on top
    local content, contentSize = nil, nil   -- the content's own layer and the size it was made for
    if options.flatContent then
        content = ui.Layer.new(layer)
        content:SetPos(0, 0)
        content.clickthrough = false
        contentSize = "small"
        window.content = content
    end

    -- the title bar: a drag handle (all of it left of the buttons) and the three buttons, made once and moved to fit
    local drag, handle = nil, catcher(layer)
    local buttons = {}
    local function mouseXY()
        local okX, mx = pcall(Mouse.GetX)
        local okY, my = pcall(Mouse.GetY)
        if okX and okY and type(mx) == "number" and type(my) == "number" then return mx, my end
    end
    -- onTitleClick: a press on the title's words (where the old nameplate was) that doesn't move; a drag never counts
    local titleWidth = window.art:Measure(title, true) + 12
    local function onTitle(mx)
        local okXY, origin = pcall(function() return layer.xyGlobal end)
        local x = mx - (okXY and origin and origin.x or pos.x)
        return x >= 6 and x < 12 + titleWidth
    end
    handle:Subscribe(ui.Hook.ONCLICK, function()
        local mx, my = mouseXY()
        if mx then drag = { mx, my, pos.x, pos.y, off = 0, moved = false, held = 0, onTitle = onTitle(mx) } end
        return false
    end)
    handle:Subscribe(ui.Hook.ONRELEASE, function()
        if drag then
            local press = drag
            drag = nil
            if options.onMove then pcall(options.onMove, pos.x, pos.y) end
            if not press.moved and press.onTitle and options.onTitleClick then pcall(options.onTitleClick) end   -- a click
        end
        return false
    end)

    local phase = 0
    local function drawLights()
        lights:Clear()
        if window.state ~= "small" and window.state ~= "big" then return end
        local w = sizeOf(window.state)
        for i = 0, math.floor((w - 12 * P) / 15) do
            local x = 6 * P + i * 15
            lights:Rect(x, BAR + 3 * P, 2 * P, 2 * P, C.BULBS[(i + phase) % #C.BULBS + 1])
            lights:Rect(x, BAR + 3 * P, P, P, 0xFFFFFFB0)
        end
    end
    local function frame(w, h)
        local art = window.art
        art:Rect(0, 0, w, h, C.INK)
        art:Rect(P, BAR, w - 2 * P, h - BAR - P, C.CHROME_DARK)
        art:Rect(2 * P, BAR, w - 4 * P, h - BAR - 2 * P, C.CHROME)
        art:Rect(2 * P, BAR, P, h - BAR - 3 * P, C.CHROME_LIGHT)
        art:Rect(4 * P, BAR + P, w - 8 * P, h - BAR - 5 * P, C.INK)
        art:Rect(5 * P, BAR + P, w - 10 * P, h - BAR - 6 * P, C.WOOD)
        for x = 5 * P + 15, w - 5 * P - 6, 27 do art:Rect(x, BAR + 12, P, h - BAR - 6 * P - 15, C.WOOD_GRAIN) end
    end
    local function titleBar(w)
        local art = window.art
        art:Gold(0, 0, w, BAR)
        art:Text(12, 0, w - 3 * 27 - 24, BAR, title, C.DARK, { bold = true })
        for i = 1, 3 do
            local x = buttonX(w, i)
            art:Chrome(x, 4, 24, 22)
            if i == 1 then                                        -- -
                art:Rect(x + 7, 16, 10, 3, C.INK)
            elseif i == 2 and oneSize then                        -- [] with one size: faded
                art:Rect(x + 6, 8, 12, 12, C.CHROME_DARK); art:Rect(x + 9, 13, 6, 4, C.CHROME)
            elseif i == 2 and window.state == "big" then          -- [] on a big window: back to small (two squares)
                art:Rect(x + 9, 8, 9, 9, C.INK); art:Rect(x + 6, 11, 9, 9, C.INK); art:Rect(x + 9, 14, 3, 3, C.CHROME)
            elseif i == 2 then                                    -- [] : bigger
                art:Rect(x + 6, 8, 12, 12, C.INK); art:Rect(x + 9, 13, 6, 4, C.CHROME)
            end
            if i == 3 then                                        -- X
                for k = 0, 3 do art:Rect(x + 6 + k * 3, 8 + k * 3, 3, 3, C.INK); art:Rect(x + 15 - k * 3, 8 + k * 3, 3, 3, C.INK) end
            end
        end
    end

    -- Redraws the frame and your content (options.draw)
    function window:Redraw()
        local art = self.art
        art:Clear()
        if self.state == "closed" then return end
        local w, h = sizeOf(self.state)
        if self.state ~= "min" then
            frame(w, h)
            self.inner = { x = 21, y = BAR + 27, width = w - 42, height = h - BAR - 27 - 21 }
            if options.draw then
                local ok, problem = pcall(options.draw, art, self, self.state)
                if not ok then log("Retro UI program window: " .. tostring(problem)) end
            end
        end
        titleBar(w)
        drawLights()
    end

    -- A clickable spot on the content (made in options.build): onClick() on a click, onWheel(delta) on the wheel. x, y
    -- are window units; the content layer starts under the title bar, so its pieces sit BAR higher on it
    function window:Area(x, y, w, h, onClick, onWheel)
        local area = ui.Rectangle.new(content or layer)
        area:SetPos(math.floor(x), math.floor(y) - ((content and not options.flatContent) and BAR or 0))
        area:SetSize(math.floor(w), math.floor(h))
        area.fill = true
        area.colour = Vector4.new(0, 0, 0, 0.004)
        area.clickthrough = false
        area:Subscribe(ui.Hook.ONCLICK, function()
            if not area.hidden and onClick then onClick() end
            return false
        end)
        area:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
            if onWheel and not area.hidden then onWheel(delta) end
            return false
        end)
        self.spots[#self.spots + 1] = { math.floor(x), math.floor(y), math.floor(w), math.floor(h), area }
        return area
    end

    -- A text box (the game's own input style) on the content; onChange(text, reason) runs when it changes
    function window:Field(x, y, w, value, onChange)
        local input = ui.InputField.new(content or layer)
        input:SetPos(math.floor(x), math.floor(y) - ((content and not options.flatContent) and BAR or 0))
        input:SetSize(math.floor(w), 25)
        input.stylesheetID = id.StyleSheet.INPUT_DEFAULT
        input.content = value or ""
        input.clickthrough = false
        if onChange then
            input:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, reason, contents)
                onChange(tostring(contents or ""), reason)
            end)
        end
        input:Subscribe(ui.Hook.ONSCROLLWHEEL, function() return false end)
        return input
    end

    -- Moves to a state: "small", "big", "min" or "closed". The content's areas are made again for a new size.
    function window:SetState(state)
        if state ~= "small" and state ~= "big" and state ~= "min" and state ~= "closed" then return end
        if state == self.state then return end
        drag = nil
        self.state = state
        if state == "small" or state == "big" then open = state end
        layer.hidden = state == "closed"
        local w, h = sizeOf(state)
        layer:SetSize(w, h)
        back:SetPos(0, 0); back:SetSize(w, h)
        artCanvas:SetSize(w, h)
        lightCanvas:SetSize(w, h)
        handle:SetPos(0, 0); handle:SetSize(buttonX(w, 1) - 3, BAR)
        for i, b in ipairs(buttons) do b:SetPos(buttonX(w, i), 4) end
        -- the content stays (hidden) while minimised or closed, and is made again only for the other size (for a
        -- window with one size, never: its areas are made once, by the plugin, as with Window)
        local wanted = (state == "small" or state == "big") and (oneSize and "small" or state) or nil
        if content and wanted and contentSize ~= wanted then
            content.hidden = true
            pcall(function() content:Destroy() end)
            content = nil
        end
        if content then content.hidden = wanted == nil end
        if content and options.flatContent and wanted then content:SetSize(w, h) end
        if wanted and not content then
            self.spots = {}
            content = ui.Layer.new(layer)                -- under the title bar, so the bar's buttons stay on top
            content:SetPos(0, BAR)
            content:SetSize(w, h - BAR)
            content.clickthrough = false
            contentSize = wanted
            if options.build then
                local ok, problem = pcall(options.build, self, state)
                if not ok then log("Retro UI program window: " .. tostring(problem)) end
            end
        end
        self:Redraw()
        if options.onState then pcall(options.onState, state) end
    end
    function window:GetState() return self.state end
    function window:OpenSize() return open end
    function window:Open() self:SetState(open) end
    function window:Close() self:SetState("closed") end

    for i, act in ipairs({
        function() window:SetState(window.state == "min" and open or "min") end,                   -- -
        function()
            if oneSize then return end
            window:SetState((window.state == "big" or (window.state == "min" and open == "big")) and "small" or "big")
        end,
        function() window:SetState("closed") end,                                                     -- X
    }) do
        local b = catcher(layer)
        b:SetSize(24, 22)
        b:Subscribe(ui.Hook.ONCLICK, function() act(); return false end)
        buttons[i] = b
    end

    -- Every client tick: follows a drag, and moves the bulbs along every 12 ticks
    local ticks = 0
    function window:Animate()
        if drag then
            local mx, my = mouseXY()
            if mx then
                local okW, pw = pcall(function() return parent.width end)
                local okH, ph = pcall(function() return parent.height end)
                pw = okW and type(pw) == "number" and pw or 4000
                ph = okH and type(ph) == "number" and ph or 4000
                local w = sizeOf(self.state)
                if not drag.moved and math.abs(mx - drag[1]) + math.abs(my - drag[2]) >= 3 then drag.moved = true end
                drag.held = drag.held + 1
                if drag.onTitle and not drag.moved and drag.held > 25 and options.onTitleClick then
                    drag = nil
                    pcall(options.onTitleClick)
                    return
                end
                pos.x = math.floor(math.max(60 - w, math.min(pw - 60, drag[3] + mx - drag[1])))
                pos.y = math.floor(math.max(0, math.min(ph - BAR, drag[4] + my - drag[2])))
                layer:SetPos(pos.x, pos.y)
                local okOver, over = pcall(function() return handle.isMouseOver end)
                if okOver and over == false then
                    drag.off = drag.off + 1
                    if drag.off > 15 then
                        drag = nil
                        if options.onMove then pcall(options.onMove, pos.x, pos.y) end
                    end
                else
                    drag.off = 0
                end
            end
        end
        ticks = ticks + 1
        if ticks % 12 == 0 and (self.state == "small" or self.state == "big") then
            phase = phase + 1
            drawLights()
        end
    end
    function window:SetPos(x, y)
        pos.x, pos.y = math.floor(x), math.floor(y)
        layer:SetPos(pos.x, pos.y)
    end
    function window:GetPos() return pos.x, pos.y end

    -- Keeping clicks off the world while the cursor is over the window (as Window does): over a click area the top
    -- menu entry becomes the window's own (which does nothing); anywhere else on it, the game's own Cancel
    local function guard(event)
        if window.state == "closed" then return end
        local okXY, origin = pcall(function() return layer.xyGlobal end)
        local mx, my = mouseXY()
        if not mx then return end
        local x = mx - (okXY and origin and origin.x or pos.x)
        local y = my - (okXY and origin and origin.y or pos.y)
        local w, h = sizeOf(window.state)
        if x < 0 or y < 0 or x >= w or y >= h then return end
        local menu = event.miniMenu
        local count, cancel = menu.entryCount, nil
        for i = 1, count do
            if menu.entries[i].actionType == MiniMenuActionType.CANCEL then cancel = i end
        end
        local leftClickIsLast = cancel ~= count
        local overArea = y < BAR
        for _, spot in ipairs(window.spots) do
            if not spot[5].hidden and x >= spot[1] and y >= spot[2] and x < spot[1] + spot[3] and y < spot[2] + spot[4] then
                overArea = true
            end
        end
        if not overArea then
            local leftClick = leftClickIsLast and count or 1
            if cancel and cancel ~= leftClick then menu:Swap(cancel, leftClick) end
            return
        end
        menu:Add(title, function() end)
        local total, entries, ours = menu.entryCount, menu.entries, nil
        for i = 1, total do
            if entries[i].actionEntryType == MiniMenuEntryType.PLUGIN then
                local okT, text = pcall(function() return entries[i].fullText end)
                if okT and text == title then ours = i end
            end
        end
        local leftClick = leftClickIsLast and total or 1
        if ours and ours ~= leftClick then menu:Swap(ours, leftClick) end
    end
    programCount = programCount + 1
    local menuKey = "retroUIProgramMenu" .. programCount
    if options.guardMenu ~= false then
        local lastProblem = nil
        pcall(function()
            Event.MiniMenuReady.Subscribe(menuKey, function(event)
                local ok, problem = pcall(guard, event)
                if not ok and problem ~= lastProblem then log("Retro UI program window menu: " .. tostring(problem)) end
                lastProblem = not ok and problem or nil
            end)
        end)
    end

    function window:Destroy()
        pcall(function() Event.MiniMenuReady.Unsubscribe(menuKey) end)
        layer.hidden = true
        pcall(function() layer:Destroy() end)
    end

    window:SetState(sizes[options.state] and options.state or (options.state == "min" or options.state == "closed") and options.state or "small")
    return window
end

function RetroUI.ProgramFromWindow(parent, options)
    local width = math.floor(options.width or 384)
    local height = math.floor(options.height or 300)
    local crown = math.floor(options.crown or 84)
    -- where the cabinet's content would start (Window's own sums)
    local top = math.max(crown, 33)
    if crown > 0 and options.title then
        local measurer = RetroUI.Painter({})
        local plateWidth = math.max(120, math.min(204, width - 96, measurer:Measure(options.title, true) + 48))
        local plateY = 30
        while plateY < crown and 2 * RetroUI.CrownHalf(width, crown, plateY, 9 * P) - 24 < plateWidth do
            plateY = plateY + P
        end
        top = math.max(top, plateY + 36 + 6)
    end
    -- options.contentTop: where the plugin's own drawing really starts, when that's above the cabinet's content line
    -- (Alert!'s crownless window draws its heading at 6). A crownless window had no plinth: 9 units under its content.
    top = options.contentTop or top
    local dy = top - (RetroUI.BAR + 27)
    local h = height - (crown > 0 and 63 or 9) - dy + 21
    local stored = nil                   -- the plugin's drawContent
    local compat = { dy = dy, inner = { x = 30, y = top, width = width - 60, height = height - 36 - 27 - top } }
    -- a painter for the plugin's own numbers: everything it draws lands dy higher on the window's canvas
    local shifted = nil
    local pw, building = nil, true      -- (no onHide while it's being made: the plugin reads its own saved state after)
    pw = RetroUI.ProgramWindow(parent, {
        title = options.title, small = { width, h }, big = { width, h }, x = options.x, y = options.y, flatContent = true,
        state = options.hidden and "min" or "small", guardMenu = options.guardMenu, onMove = options.onMove,
        onTitleClick = options.onTitleClick or function() if pw then pw:SetState("min") end end,
        draw = function(paint, window)
            if not stored then return end
            if not shifted then
                local canvas = paint.canvas
                shifted = RetroUI.Painter({
                    Clear = function() end,
                    AddRectangle = function(_, x, y, w, hh, colour) canvas:AddRectangle(x, y - dy, w, hh, colour) end,
                    AddText = function(_, x, y, w, hh, text, style) canvas:AddText(x, y - dy, w, hh, text, style) end,
                })
            end
            stored(shifted, compat)
        end,
        onState = function(state)
            if not building and options.onHide then pcall(options.onHide, state ~= "small" and state ~= "big") end
        end,
    })
    building = false
    compat.layer, compat.art, compat.program = pw.layer, pw.art, pw
    function compat:Area(x, y, w, hh, onClick, onWheel) return pw:Area(x, y - dy, w, hh, onClick, onWheel) end
    function compat:Field(x, y, w, value, onChange) return pw:Field(x, y - dy, w, value, onChange) end
    function compat:Redraw(drawContent)
        if drawContent then stored = drawContent end
        pw:Redraw()
    end
    function compat:Hide() pw:SetState("min") end
    function compat:Show() pw:Open() end
    function compat:IsHidden() local st = pw:GetState() return st ~= "small" and st ~= "big" end
    function compat:SetHidden(hidden) if hidden then self:Hide() else self:Show() end end
    function compat:Open() pw:Open() end
    function compat:Close() pw:Close() end
    function compat:IsClosed() return pw:GetState() == "closed" end
    -- A layer in the plugin's own numbers (moved up by dy) for its own pieces (item sprites, an extra canvas); it hides
    -- with the content when the window is minimised or closed
    local own = nil
    function compat:ContentLayer()
        if not own then
            own = ui.Layer.new(pw.content or pw.layer)
            own:SetPos(0, -dy)
            own:SetSize(width, height)
            own.clickthrough = true
        end
        return own
    end
    function compat:SetPos(x, y) pw:SetPos(x, y) end
    function compat:GetPos() return pw:GetPos() end
    function compat:Destroy() pw:Destroy() end
    local allSeen, hiddenByAll, allTicks = nil, false, 0
    function compat:Animate()
        pw:Animate()
        allTicks = allTicks + 1
        if options.hideAll == false or allTicks % 5 ~= 0 then return end
        local serial, hidden = RetroUI.HideAllState()
        if serial == nil or serial == allSeen then return end
        local first = allSeen == nil
        allSeen = serial
        if first then return end
        if hidden then
            if not self:IsHidden() then hiddenByAll = true; self:Hide() end
        elseif hiddenByAll then
            hiddenByAll = false
            if self:IsHidden() then self:Show() end
        end
    end
    return compat
end

function RetroUI.ShowWindowButton(parent, window, x, y, w)
    local function isOpen()
        if window.IsClosed then return not window:IsClosed() end
        return window:GetState() ~= "closed"
    end
    local b = ui.Button.new(parent)
    b:SetPos(math.floor(x or 0), math.floor(y or 0))
    b:SetSize(math.floor(w or 200), 25)
    pcall(function() b.stylesheetID = id.StyleSheet.BUTTON_DEFAULT end)
    pcall(function() b.text.font = id.Font.MUSEO_SANS_15PT_REGULAR end)
    local function label() b.label = "Show window: " .. (isOpen() and "on" or "off") end
    label()
    b:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
        if isOpen() then window:Close() else window:Open() end
        label()
    end)
    return b
end

return RetroUI
