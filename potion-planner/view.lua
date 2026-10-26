local View = {}
View.WIDTH = 612
View.HEIGHT = 612
View.ROWS = 10                       -- potions in the list at once
View.DETAIL_ROWS = 7                 -- lines in the right-hand display at once
View.WRAP = 46                       -- letters per full-width line in the right-hand display

local P = 3                          -- one art pixel
local W, H = View.WIDTH, View.HEIGHT
local CX = math.floor(W / 2)
local CROWN = 84                     -- height of the arched top
local BASE = H - 36                  -- where the plinth starts
local LX, LW = 30, 234               -- left column: search and the potion list
local RX, RW = 276, 306              -- right column: the chosen potion and its plan
local ROW_H, DETAIL_H = 24, 20
local LIST_Y, DETAIL_Y = 165, 284

View.LAYOUT = {
    search = { LX + 30, 91 }, batches = { RX + 42, 163 }, source = { RX, 513 },
    all = { LX, 126 }, favourites = { LX + 120, 126 },
    previous = { LX + 204, 159 }, next = { LX + 204, 381 },
    row = { LX + 6, LIST_Y }, rowStep = ROW_H,
    favourite = { RX + RW - 33, 93 }, minus = { RX, 159 }, plus = { RX + 141, 159 }, method = { RX + 180, 159 },
    recursive = { RX, 198 }, bank = { RX + 123, 198 }, add = { RX + 216, 198 },
    batch = { RX, 231 }, ingredients = { RX + 78, 231 }, steps = { RX + 156, 231 }, sources = { RX + 234, 231 },
    detail = { RX + 6, DETAIL_Y }, remove = { RX + RW - 27, DETAIL_Y }, detailStep = DETAIL_H,
    detailPrevious = { RX + RW - 45, 438 }, detailNext = { RX + RW - 21, 438 },
    hide = { RX + RW - 60, 516 },
    popup = { 141, 150 }, stock = { 18, 81 }, price = { 174, 81 },
    save = { 18, 171 }, reset = { 120, 171 }, close = { 228, 171 },
}
local L = View.LAYOUT

-- Colours (0xRRGGBBAA), the same as Soundbox's
local INK = 0x141010FF
local WOOD, WOOD_LIGHT, WOOD_DARK, WOOD_GRAIN = 0x7E3F22FF, 0xA05A30FF, 0x4F2412FF, 0x6E361CFF
local CHROME, CHROME_LIGHT, CHROME_DARK = 0xB9C4CCFF, 0xF2F6F8FF, 0x6F7C86FF
local GOLD, GOLD_LIGHT, GOLD_DARK = 0xE8B23CFF, 0xFFE08AFF, 0x9C6B1EFF
local TUBE, GLASS, GLASS_LIGHT, LCD = 0x2A140CFF, 0x0E1A26FF, 0x23384CFF, 0x10150EFF
local CREAM, DARK, NUMBER, FADED = 0xFFF1C9FF, 0x2B1608FF, 0xF2C14EFF, 0x9FB3C8FF
local BULBS = { 0xFF4D4DFF, 0xFFB03BFF, 0xFFE45CFF, 0x5EE07AFF, 0x45B5FFFF, 0xC77DFFFF }
-- and a few of the Apothecary's own
local GREEN, RED, SOFT_RED = 0x5EE07AFF, 0xFF6A5AFF, 0xFF9A8AFF
local PARCHMENT_DARK, INK_SOFT, SHADE = 0xE2CC96FF, 0x5A3A1EFF, 0xFFFFFF0C

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
        if description and description:GetStringWidth("Potion") > 0 then
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

-- A potion's liquid colour, guessed from its name (only for the little bottles; it never affects a number)
local LIQUIDS = {
    { "overload", 0x4B3A5CFF }, { "prayer", 0x3FC8C0FF }, { "restore", 0xE86AA8FF }, { "brew", 0xE8D25AFF },
    { "antifire", 0xB06AE0FF }, { "attack", 0x4A7CE8FF }, { "strength", 0xE8E8E8FF }, { "defence", 0xE89A3AFF },
    { "magic", 0x45B5FFFF }, { "ranging", 0x5EE07AFF }, { "adrenaline", 0xF08A3AFF }, { "poison", 0x7FC24AFF },
    { "energy", 0xC8783AFF }, { "stamina", 0xC8783AFF }, { "juju", 0x8A6A3AFF }, { "combat", 0x3FA8A0FF },
    { "necro", 0x6AE0C8FF }, { "aggression", 0xD04A3AFF },
}
local FALLBACK = { 0xB65A74FF, 0x71AC8DFF, 0x779ED0FF, 0xB68CCCFF, 0xD6A655FF }
local function liquidColour(name)
    local lower = clean(name):lower()
    for _, pair in ipairs(LIQUIDS) do
        if lower:find(pair[1], 1, true) then
            return pair[2]
        end
    end
    local sum = 0
    for i = 1, #lower do
        sum = sum + lower:byte(i)
    end
    return FALLBACK[sum % #FALLBACK + 1]
end

-- Lighter and darker shades of a colour, for the bottles
local function shade(hex, towards, amount)
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

-- Pixel sprites: one letter per art pixel, "." is clear
local BOTTLE = {
    "....kck....",
    "....kCk....",
    "...kkkkk...",
    "....kgk....",
    "....kgk....",
    "...kgggk...",
    "..kgggggk..",
    ".kgLLLLLgk.",
    "kLwlLLLLLLk",
    "kLwLLLLLLLk",
    "kLlLLLLLLdk",
    "kLLLLLLLLdk",
    "kLLLLLLLddk",
    ".kdddddddk.",
    "..kkkkkkk..",
}
local SMALL_BOTTLE = { ".kck.", ".kgk.", "kgggk", "kLLLk", "kLwLk", "kLLdk", ".kkk." }
local STAR = { "..k..", ".kyk.", "kyyyk", ".kyk.", "k.k.k" }

function View.new(parent, actions, position)
    local self = { controls = {}, actions = actions }
    local fonts = { normal = font("P12_FULL"), bold = font("B12_FULL") }
    local fontInfo = {}
    local alignRight = ui.AlignMode.BOTTOMRIGHT or ui.AlignMode.TOPLEFT

    local root = ui.Layer.new(parent)
    root:SetPos(position.x, position.y)
    root:SetSize(W, H)
    root.clickthrough = false
    self.root = root

    -- A clear rectangle that takes clicks and the mouse wheel
    local function blocker(container, x, y, width, height, wheel)
        local area = ui.Rectangle.new(container)
        area:SetPos(x, y)
        area:SetSize(width, height)
        area.fill = true
        area.colour = Vector4.new(0, 0, 0, 0.004)
        area.clickthrough = false
        area:Subscribe(ui.Hook.ONCLICK, function()
            return false
        end)
        area:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
            if wheel then
                wheel(delta)
            end
            return false
        end)
        return area
    end
    blocker(root, 0, 0, W, H)

    -- Dragging by the crown (the same way as Soundbox): a press on the top starts it, the window follows the mouse every
    -- client tick, and it ends when the button is let go, or once the cursor has been off the top for 15 ticks (the
    -- mouse button can't be read). The new place is passed to actions.move(x, y) when main.lua has it.
    local pos = { x = position.x, y = position.y }
    local drag = nil
    local function mouse()
        local okX, mx = pcall(Mouse.GetX)
        local okY, my = pcall(Mouse.GetY)
        if okX and okY and type(mx) == "number" and type(my) == "number" then
            return mx, my
        end
    end
    local handle = blocker(root, 0, 0, W, CROWN)
    local function endDrag()
        if not drag then
            return
        end
        drag = nil
        if actions.move then
            pcall(actions.move, pos.x, pos.y)
        end
    end
    handle:Subscribe(ui.Hook.ONCLICK, function()
        local mx, my = mouse()
        if mx then
            drag = { mx, my, pos.x, pos.y, 0 }
        end
        return false
    end)
    pcall(function()
        handle:Subscribe(ui.Hook.ONRELEASE, function()
            endDrag()
            return false
        end)
    end)
    local function followDrag()
        if not drag then
            return
        end
        local mx, my = mouse()
        if not mx then
            return
        end
        local okW, parentWidth = pcall(function() return parent.width end)
        local okH, parentHeight = pcall(function() return parent.height end)
        parentWidth = okW and type(parentWidth) == "number" and parentWidth or 4000
        parentHeight = okH and type(parentHeight) == "number" and parentHeight or 4000
        pos.x = math.floor(math.max(60 - W, math.min(parentWidth - 60, drag[3] + mx - drag[1])))
        pos.y = math.floor(math.max(0, math.min(parentHeight - 40, drag[4] + my - drag[2])))
        root:SetPos(pos.x, pos.y)
        local okOver, over = pcall(function() return handle.isMouseOver end)
        if okOver and over == false then
            drag[5] = drag[5] + 1
            if drag[5] > 15 then
                endDrag()
            end
        else
            drag[5] = 0
        end
    end
    local spots = {}                  -- every control's rectangle, for keeping clicks off the world (below)

    -- Three canvases: the cabinet and everything that changes, the bulbs, and the cauldron's bubbles
    local function newCanvas(container, width, height)
        local canvas = ui.Canvas.new(container)
        canvas:SetSize(width, height)
        canvas.clickthrough = true
        return canvas
    end
    local art = newCanvas(root, W, H)
    local lights = newCanvas(root, W, H)
    local bubbles = newCanvas(root, W, H)
    self.canvas = art
    local target = art                -- the canvas the drawing helpers draw on

    -- Drawing helpers ----------------------------------------------------------------------------------------------

    local function rect(x, y, width, height, colour)
        if width > 0 and height > 0 then
            target:AddRectangle(x, y, width, height, colour)
        end
    end

    -- A pixel-art block: black outline, a face, a light top and left edge and a dark bottom and right edge
    local function block(x, y, width, height, face, light, dark)
        rect(x, y, width, height, INK)
        rect(x + P, y + P, width - 2 * P, height - 2 * P, face)
        if light then
            rect(x + P, y + P, width - 2 * P, P, light)
            rect(x + P, y + P, P, height - 2 * P, light)
        end
        if dark then
            rect(x + P, y + height - 2 * P, width - 2 * P, P, dark)
            rect(x + width - 2 * P, y + P, P, height - 2 * P, dark)
        end
    end

    -- A pixel arrow, four steps tall, around (cx, cy)
    local function arrow(cx, cy, dir, colour)
        for i = 0, 3 do
            local size = ((dir == "down" or dir == "right") and (2 * (3 - i) + 1) or (2 * i + 1)) * P
            local half = math.floor(size / 2)
            if dir == "up" or dir == "down" then
                rect(cx - half, cy - 2 * P + i * P, size, P, colour)
            else
                rect(cx - 2 * P + i * P, cy - half, P, size, colour)
            end
        end
    end

    -- A small arrow (2-unit steps) for the little page buttons under the display
    local function smallArrow(cx, cy, dir, colour)
        for i = 0, 3 do
            local size = (dir == "right" and (2 * (3 - i) + 1) or (2 * i + 1)) * 2
            rect(cx - 4 + i * 2, cy - math.floor(size / 2), 2, size, colour)
        end
    end

    local function sprite(x, y, rows, palette, size)
        local s = size or P
        for j, row in ipairs(rows) do
            for i = 1, #row do
                local colour = palette[row:sub(i, i)]
                if colour then
                    rect(x + (i - 1) * s, y + (j - 1) * s, s, s, colour)
                end
            end
        end
    end

    local function bottlePalette(colour)
        return { k = INK, c = WOOD_LIGHT, C = WOOD, g = 0xCFE3EAFF, L = colour, l = shade(colour, 255, 0.45),
                 d = shade(colour, 0, 0.45), w = 0xFFFFFFFF }
    end

    local function measure(text, selected)
        if fontInfo[selected] == nil then
            fontInfo[selected] = (pcall(function() return config.Font.FromID(selected) end))
                and config.Font.FromID(selected) or false
        end
        local info = fontInfo[selected]
        local ok, width = pcall(function() return info:GetStringWidth(text) end)
        return ok and width or #text * 7
    end

    -- Text cut to fit, ending in "..." if it had to be cut
    local function fitted(value, width, selected)
        local content = clean(value)
        if measure(content, selected) <= width then
            return content
        end
        while #content > 0 and measure(content .. "...", selected) > width do
            content = content:sub(1, -2)
        end
        return content .. "..."
    end

    -- align: nil = left, "centre" or "right"
    local function text(x, y, width, height, value, colour, bold, align)
        local style = ui.TextDataConfig.new()
        style.font = bold and fonts.bold or fonts.normal
        style.colour = rgba(colour or CREAM)
        style.alignHorizontal = align == "centre" and ui.AlignMode.CENTRE or align == "right" and alignRight
            or ui.AlignMode.TOPLEFT
        style.alignVertical = ui.AlignMode.CENTRE
        target:AddText(x, y, width, height, fitted(value, width, style.font), style)
    end

    -- Up to two lines of wrapped text (for messages that must be read in full)
    local function wrappedText(x, y, width, value, colour)
        local words, lines, line = clean(value), {}, ""
        for word in words:gmatch("%S+") do
            local candidate = line == "" and word or (line .. " " .. word)
            if measure(candidate, fonts.normal) > width and line ~= "" then
                lines[#lines + 1] = line
                line = word
            else
                line = candidate
            end
        end
        if line ~= "" then
            lines[#lines + 1] = line
        end
        for i = 1, math.min(2, #lines) do
            local shown = lines[i]
            if i == 2 and #lines > 2 then
                shown = shown .. " " .. table.concat(lines, " ", 3)
            end
            text(x, y + (i - 1) * 15, width, 15, shown, colour)
        end
    end

    -- A chrome button (gold when on) with a centred label
    local function button(x, y, width, height, label, on)
        local face = on and GOLD or CHROME
        local light = on and GOLD_LIGHT or CHROME_LIGHT
        local dark = on and GOLD_DARK or CHROME_DARK
        block(x, y, width, height, face, light, dark)
        if label and label ~= "" then
            text(x + 3, y, width - 6, height, label, DARK, false, "centre")
        end
    end

    -- Controls --------------------------------------------------------------------------------------------------------

    local function control(key, x, y, width, height, callback, wheel)
        local area = blocker(root, x, y, width, height, wheel)
        area:Subscribe(ui.Hook.ONCLICK, function()
            local current = self.controls[key]
            if not area.hidden and current and current.callback then
                current.callback()
            end
            return false
        end)
        self.controls[key] = { area = area, callback = callback }
        spots[#spots + 1] = { x, y, width, height, area }
        return area
    end

    local function field(container, x, y, width, value, onChange)
        local input = ui.InputField.new(container)
        input:SetPos(x, y)
        input:SetSize(width, 25)
        input.stylesheetID = id.StyleSheet.INPUT_DEFAULT
        input.content = value
        input.clickthrough = false
        if onChange then
            input:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, _, contents)
                onChange(tostring(contents or ""))
            end)
        end
        input:Subscribe(ui.Hook.ONSCROLLWHEEL, function()
            return false
        end)
        return input
    end

    -- The minus and plus buttons change the quantity box by one, as if the number had been typed
    local function nudge(step)
        local current = tonumber((tostring(self.batches.content or ""):gsub(",", ""))) or 1
        local nextValue = math.max(1, math.min(100000, math.floor(current) + step))
        self.batches.content = tostring(nextValue)
        actions.batches(tostring(nextValue))
    end

    self.search = field(root, L.search[1], L.search[2], LW - 36, "", actions.search)
    self.batches = field(root, L.batches[1], L.batches[2], 90, "1", actions.batches)
    control("all", L.all[1], L.all[2], 114, 27, function() actions.filter(false) end)
    control("favourites", L.favourites[1], L.favourites[2], 114, 27, function() actions.filter(true) end)
    control("previous", L.previous[1], L.previous[2], 30, 30, function() actions.page(-1) end, actions.wheel)
    control("next", L.next[1], L.next[2], 30, 30, function() actions.page(1) end, actions.wheel)
    for index = 1, View.ROWS do
        local row = index
        control("row" .. index, L.row[1], L.row[2] + (index - 1) * ROW_H, 186, ROW_H, function()
            actions.select(row)
        end, actions.wheel)
    end
    control("favourite", L.favourite[1], L.favourite[2], 27, 27, actions.favourite)
    control("minus", L.minus[1], L.minus[2], 33, 33, function() nudge(-1) end)
    control("plus", L.plus[1], L.plus[2], 33, 33, function() nudge(1) end)
    control("method", L.method[1], L.method[2], 126, 33, actions.method)
    control("recursive", L.recursive[1], L.recursive[2], 117, 27, actions.recursive)
    control("bank", L.bank[1], L.bank[2], 87, 27, actions.bank)
    control("add", L.add[1], L.add[2], 90, 27, actions.add)
    for _, tab in ipairs({ "batch", "ingredients", "steps", "sources" }) do
        local name = tab
        control(name, L[name][1], L[name][2], 72, 27, function() actions.tab(name) end)
    end
    for index = 1, View.DETAIL_ROWS do
        local row = index
        local y = L.detail[2] + (index - 1) * DETAIL_H
        control("detail" .. index, L.detail[1], y, RW - 39, DETAIL_H, function()
            actions.edit(row)
        end, actions.detailWheel)
        control("remove" .. index, L.remove[1], y, 21, DETAIL_H, function()
            actions.remove(row)
        end, actions.detailWheel)
    end
    control("detailPrevious", L.detailPrevious[1], L.detailPrevious[2], 21, 18, function() actions.detailPage(-1) end)
    control("detailNext", L.detailNext[1], L.detailNext[2], 21, 18, function() actions.detailPage(1) end)
    control("hide", L.hide[1], L.hide[2], 60, 24, actions.hide)
    self.source = field(root, L.source[1], L.source[2], RW - 66, "", nil)
    self.source.hidden = true

    -- The item editor: a small chrome-framed card over the window ------------------------------------------------

    local PW, PH = 330, 210
    local popup = ui.Layer.new(root)
    popup:SetPos(L.popup[1], L.popup[2])
    popup:SetSize(PW, PH)
    popup.hidden = true
    popup.clickthrough = false
    blocker(popup, 0, 0, PW, PH)
    local popupArt = newCanvas(popup, PW, PH)
    self.popup = popup
    self.stockField = field(popup, L.stock[1], L.stock[2], 138, "", nil)
    self.priceField = field(popup, L.price[1], L.price[2], 138, "", nil)
    local function popupButton(spot, width, callback)
        local area = blocker(popup, spot[1], spot[2], width, 27)
        area:Subscribe(ui.Hook.ONCLICK, function()
            callback()
            return false
        end)
    end
    popupButton(L.save, 96, function()
        actions.saveItem(self.stockField.content, self.priceField.content)
    end)
    popupButton(L.reset, 102, actions.resetItem)
    popupButton(L.close, 84, actions.closeItem)

    function self:editor(item, stock, price, errorText, guideText)
        popup.hidden = item == nil
        if not item then
            return
        end
        popup:MoveToFront()
        self.stockField.content = tostring(stock or 0)
        self.priceField.content = price ~= nil and tostring(price) or ""
        target = popupArt
        popupArt:Clear()
        block(0, 0, PW, PH, CHROME, CHROME_LIGHT, CHROME_DARK)
        block(6, 6, PW - 12, PH - 12, CREAM, 0xFFFFFFFF, PARCHMENT_DARK)
        block(12, 12, PW - 24, 33, GOLD, GOLD_LIGHT, GOLD_DARK)
        text(18, 12, PW - 36, 33, item.name, DARK, true, "centre")
        text(18, 57, 138, 21, "You own", INK_SOFT, true)
        text(174, 57, 138, 21, "Your price (GP)", INK_SOFT, true)
        text(18, 111, PW - 36, 16, "A blank price uses the dated guide price.", INK_SOFT)
        text(18, 127, PW - 36, 16, guideText or "Stock is for this session. Your prices are saved.", INK_SOFT)
        if errorText then
            text(18, 145, PW - 36, 18, errorText, RED, true)
        end
        button(L.save[1], L.save[2], 96, 27, "Apply", true)
        button(L.reset[1], L.reset[2], 102, 27, "Use guide price", false)
        button(L.close[1], L.close[2], 84, 27, "Cancel", false)
        target = art
    end

    -- The cabinet: rings, crown, bulbs and the parts that never change ---------------------------------------------

    local function crownHalf(y, inset)
        local a, b = math.floor(W / 2) - inset, CROWN - inset
        local dy = CROWN - y
        if dy > b then
            return 0
        end
        return math.floor(a * math.sqrt(1 - (dy / b) ^ 2) / P) * P
    end

    local bulbs = {}
    do
        local a, b = CX - 19, CROWN - 19
        for i = 0, 40 do
            local angle = math.pi * i / 40
            bulbs[#bulbs + 1] = { math.floor((CX - a * math.cos(angle) - 3) / P) * P,
                                  math.floor((CROWN - b * math.sin(angle) - 3) / P) * P }
        end
        for y = CROWN + 9, BASE - 33, 12 do
            table.insert(bulbs, 1, { 15, y })          -- the left side runs up into the crown
            bulbs[#bulbs + 1] = { W - 21, y }          -- the right side runs down from it
        end
    end

    local function drawCabinet()
        local rings = { { 0, INK }, { P, CHROME_DARK }, { 2 * P, CHROME }, { 4 * P, INK }, { 5 * P, TUBE },
                        { 8 * P, INK }, { 9 * P, WOOD } }
        for y = 0, CROWN - 1, P do
            for _, ring in ipairs(rings) do
                local half = crownHalf(y + P, ring[1])
                rect(CX - half, y, half * 2, P, ring[2])
            end
        end
        for _, ring in ipairs(rings) do
            local inset = ring[1]
            rect(inset, CROWN, W - 2 * inset, BASE - inset - CROWN, ring[2])
        end
        rect(2 * P, CROWN, P, BASE - 4 * P - CROWN, CHROME_LIGHT)
        rect(9 * P, CROWN, P, BASE - 10 * P - CROWN, WOOD_LIGHT)
        rect(W - 10 * P, CROWN, P, BASE - 10 * P - CROWN, WOOD_DARK)
        for x = 9 * P + 18, W - 9 * P - 18, 27 do
            rect(x, CROWN + 6, P, BASE - 10 * P - CROWN - 12, WOOD_GRAIN)
        end
        -- nameplate with a little bottle each side
        block(CX - 102, 33, 204, 36, GOLD, GOLD_LIGHT, GOLD_DARK)
        text(CX - 102, 33, 204, 36, "APOTHECARY", DARK, true, "centre")
        sprite(CX - 138, 34, SMALL_BOTTLE, bottlePalette(0xE86AA8FF))
        sprite(CX + 123, 34, SMALL_BOTTLE, bottlePalette(0x3FC8C0FF))
        -- plinth and feet
        block(6, BASE, W - 12, 24, WOOD_DARK, WOOD, INK)
        block(21, H - 15, 39, 15, CHROME, CHROME_LIGHT, CHROME_DARK)
        block(W - 60, H - 15, 39, 15, CHROME, CHROME_LIGHT, CHROME_DARK)
    end

    -- The cauldron under the list (its bubbles are drawn on their own canvas)
    local POT_X, POT_Y = LX + 57, 459
    local function drawCauldron(label)
        rect(POT_X + 33, POT_Y + 66, 54, P, 0x3A1A0CFF)
        for i = 0, 5 do
            local flame = ({ 9, 15, 12, 18, 12, 9 })[i + 1]
            rect(POT_X + 36 + i * 9, POT_Y + 66 - flame, 6, flame, 0xFF7A1AFF)
            rect(POT_X + 37 + i * 9, POT_Y + 66 - math.floor(flame / 2), 3, math.floor(flame / 2), 0xFFE45CFF)
        end
        block(POT_X + 18, POT_Y + 18, 84, 42, 0x2A2A32FF, 0x4A4A58FF, 0x16161CFF)
        rect(POT_X + 24, POT_Y + 54, 9, 9, INK)
        rect(POT_X + 87, POT_Y + 54, 9, 9, INK)
        block(POT_X + 12, POT_Y + 12, 96, 12, CHROME_DARK, CHROME, INK)
        rect(POT_X + 18, POT_Y + 15, 84, 6, 0x3FBF5AFF)
        rect(POT_X + 24, POT_Y + 15, 12, P, 0xB8F5C4FF)
        rect(POT_X + 60, POT_Y + 18, 9, P, 0xB8F5C4FF)
        text(POT_X + 111, POT_Y + 21, 66, 18, "BREWING", GOLD_LIGHT, true)
        text(POT_X + 111, POT_Y + 39, 66, 18, label or "", NUMBER, true)
    end

    -- Bulbs and bubbles: redrawn every 12 client ticks (0.24 s) while the window shows
    local phase = 0
    local function drawLights()
        target = lights
        lights:Clear()
        for i, bulb in ipairs(bulbs) do
            rect(bulb[1], bulb[2], 2 * P, 2 * P, BULBS[(i + phase) % #BULBS + 1])
            rect(bulb[1], bulb[2], P, P, 0xFFFFFFB0)
        end
        target = bubbles
        bubbles:Clear()
        for i = 0, 4 do
            local cycle = 7 + i
            local step = (phase + i * 3) % cycle
            if step < cycle - 1 then
                local x = POT_X + 27 + i * 15 + (step % 2) * P
                local y = POT_Y + 9 - step * 5
                rect(x, y, 2 * P, 2 * P, 0x5EE07ACC)
                rect(x, y, P, P, 0xFFFFFFB0)
            end
        end
        target = art
    end
    local ticks = 0
    local logicKey = "potionPlannerView"
    Event.Logic.Subscribe(logicKey, function()
        followDrag()
        if root.hidden then
            return
        end
        ticks = ticks + 1
        if ticks % 12 == 0 then
            phase = phase + 1
            pcall(drawLights)
        end
    end)

    -- Everything that changes --------------------------------------------------------------------------------------

    function self:render(vm)
        root.hidden = vm.hidden
        target = art
        art:Clear()
        drawCabinet()

        -- left: search frame with a magnifying glass, the two filters, the list, its tuner and page readout
        block(LX, 87, LW, 33, CHROME, CHROME_LIGHT, CHROME_DARK)
        local gx, gy = LX + 9, 93
        rect(gx + P, gy, 3 * P, P, INK)
        rect(gx + P, gy + 4 * P, 3 * P, P, INK)
        rect(gx, gy + P, P, 3 * P, INK)
        rect(gx + 4 * P, gy + P, P, 3 * P, INK)
        rect(gx + 4 * P, gy + 4 * P, P, P, INK)
        rect(gx + 5 * P, gy + 5 * P, P, P, INK)
        button(L.all[1], L.all[2], 114, 27, "All potions", not vm.onlyFavourites)
        button(L.favourites[1], L.favourites[2], 114, 27, "Favourites", vm.onlyFavourites)

        block(LX, 159, 198, 252, GLASS, GLASS_LIGHT)
        for index = 1, View.ROWS do
            local entry = vm.rows[index]
            local y = LIST_Y + (index - 1) * ROW_H
            self.controls["row" .. index].area.hidden = not entry
            if entry then
                local lit = entry.selected
                if lit then
                    rect(LX + 6, y, 186, ROW_H, GOLD)
                end
                sprite(LX + 10, y + 2, SMALL_BOTTLE, bottlePalette(liquidColour(entry.name)))
                local methods = tostring(entry.caption or ""):match("^(%d+) recipe")
                text(LX + 30, y, methods and 132 or 156, ROW_H, entry.name, lit and DARK or CREAM)
                if methods then
                    text(LX + 162, y, 24, ROW_H, methods, lit and DARK or NUMBER, false, "right")
                end
            end
        end
        if #vm.rows == 0 then
            text(LX + 12, 252, 174, 30, "No matching potions.", FADED, false, "centre")
        end
        -- the tuner: up, down and a gold handle showing how far down the list you are
        target = art
        block(LX + 204, 159, 30, 252, CHROME_DARK, nil, INK)
        block(L.previous[1], L.previous[2], 30, 30, CHROME, CHROME_LIGHT, CHROME_DARK)
        arrow(L.previous[1] + 15, L.previous[2] + 15, "up", INK)
        block(L.next[1], L.next[2], 30, 30, CHROME, CHROME_LIGHT, CHROME_DARK)
        arrow(L.next[1] + 15, L.next[2] + 15, "down", INK)
        local page, pages = tostring(vm.pageLabel or ""):match("^%s*(%d+)%s*/%s*(%d+)")
        page, pages = tonumber(page) or 1, tonumber(pages) or 1
        local travel = 381 - 192 - 36
        local handleY = 192 + (pages > 1 and math.floor(travel * (page - 1) / (pages - 1) / P) * P or 0)
        block(LX + 207, handleY, 24, 36, GOLD, GOLD_LIGHT, GOLD_DARK)
        block(LX, 417, LW, 30, LCD)
        text(LX + 9, 417, LW - 18, 30, "PAGE " .. tostring(vm.pageLabel or ""), NUMBER)

        -- right: the chosen potion's card
        block(RX, 87, RW, 66, CREAM, 0xFFFFFFFF, PARCHMENT_DARK)
        rect(RX + 9, 93, 39, 54, PARCHMENT_DARK)
        sprite(RX + 12, 97, BOTTLE, bottlePalette(liquidColour(vm.title)))
        text(RX + 57, 92, RW - 96, 18, vm.title, DARK, true)
        text(RX + 57, 110, RW - 66, 16, vm.subtitle, INK_SOFT)
        text(RX + 57, 127, RW - 66, 16, vm.outputLabel, INK_SOFT)
        block(L.favourite[1], L.favourite[2], 27, 27, vm.favourite and GOLD or CHROME,
              vm.favourite and GOLD_LIGHT or CHROME_LIGHT, vm.favourite and GOLD_DARK or CHROME_DARK)
        sprite(L.favourite[1] + 6, L.favourite[2] + 6, STAR, { k = DARK, y = vm.favourite and GOLD_LIGHT or CHROME_LIGHT })

        -- how many to make: minus, the quantity box on an LCD, plus, then the recipe method
        button(L.minus[1], L.minus[2], 33, 33, "", false)
        rect(L.minus[1] + 10, L.minus[2] + 15, 13, P, INK)
        block(RX + 39, 159, 96, 33, LCD)
        button(L.plus[1], L.plus[2], 33, 33, "", false)
        rect(L.plus[1] + 10, L.plus[2] + 15, 13, P, INK)
        rect(L.plus[1] + 15, L.plus[2] + 10, P, 13, INK)
        button(L.method[1], L.method[2], 126, 33, vm.methodLabel, false)

        button(L.recursive[1], L.recursive[2], 117, 27, vm.recursive and "MAKE PARTS: ON" or "MAKE PARTS: OFF", vm.recursive)
        button(L.bank[1], L.bank[2], 87, 27, "READ BANK", false)
        button(L.add[1], L.add[2], 90, 27, vm.addLabel or "Add to batch", true)
        local tabs = { { "batch", "Batch" }, { "ingredients", "Shopping" }, { "steps", "Steps" }, { "sources", "Notes" } }
        for _, tab in ipairs(tabs) do
            button(L[tab[1]][1], L[tab[1]][2], 72, 27, tab[2], vm.tab == tab[1])
        end

        -- the display: a heading, two columns, and the lines of the open tab
        block(RX, 264, RW, 171, GLASS, GLASS_LIGHT)
        local columns = vm.detailColumns
        text(RX + 9, 268, columns and 138 or RW - 18, 16, vm.detailHeading, FADED)
        if columns then
            text(RX + 147, 268, 90, 16, columns[1], FADED, false, "centre")
            text(RX + 237, 268, 60, 16, columns[2], FADED, false, "right")
        end
        for index = 1, View.DETAIL_ROWS do
            local line = vm.detail[index]
            local y = DETAIL_Y + (index - 1) * DETAIL_H
            self.controls["detail" .. index].area.hidden = not line or not line.editable
            self.controls["remove" .. index].area.hidden = not line or not line.removable
            if line then
                if index % 2 == 0 then
                    rect(RX + 6, y, RW - 12, DETAIL_H, SHADE)
                end
                if line.full then
                    text(RX + 9, y, RW - 18, DETAIL_H, line.name, CREAM)
                else
                    text(RX + 9, y, 138, DETAIL_H, line.name, CREAM)
                    text(RX + 147, y, 90, DETAIL_H, line.quantity or "", FADED, false, "centre")
                    local priceWidth = line.removable and 33 or 60
                    text(RX + 237, y, priceWidth, DETAIL_H, line.price or "", line.warning and SOFT_RED or NUMBER,
                         false, "right")
                    if line.removable then
                        block(L.remove[1], y + 1, 21, DETAIL_H - 2, 0x7A1E1EFF, RED, 0x3A0E0EFF)
                        text(L.remove[1], y + 1, 21, DETAIL_H - 2, "X", CREAM, true, "centre")
                    end
                end
            end
        end
        text(RX, 438, RW - 51, 18, vm.detailFooter, CREAM)
        block(L.detailPrevious[1], L.detailPrevious[2], 21, 18, CHROME, CHROME_LIGHT, CHROME_DARK)
        smallArrow(L.detailPrevious[1] + 10, L.detailPrevious[2] + 9, "left", INK)
        block(L.detailNext[1], L.detailNext[2], 21, 18, CHROME, CHROME_LIGHT, CHROME_DARK)
        smallArrow(L.detailNext[1] + 10, L.detailNext[2] + 9, "right", INK)

        -- totals on the LCD strip
        block(RX, 459, RW, 51, LCD)
        text(RX + 9, 462, 66, 15, "MATERIALS", FADED)
        text(RX + 72, 462, 78, 15, vm.materialCost, NUMBER, true, "right")
        text(RX + 159, 462, 54, 15, "TO BUY", FADED)
        text(RX + 210, 462, 87, 15, vm.buyCost, NUMBER, true, "right")
        local profitColour = vm.profitColour == "red" and RED or vm.profitColour == "green" and GREEN or FADED
        text(RX + 9, 477, 66, 15, "PROFIT", FADED)
        text(RX + 75, 477, 135, 15, vm.profit, profitColour, true)
        if vm.xp then
            text(RX + 210, 477, 87, 15, vm.xp, NUMBER, true, "right")
        end
        text(RX + 9, 492, RW - 18, 15, vm.stockLabel, FADED)

        -- the message line (two lines if needed), or the copyable source link on the Notes tab
        self.source.hidden = vm.tab ~= "sources"
        if vm.tab == "sources" then
            if self.source.content ~= vm.source then
                self.source.content = vm.source or ""
            end
        else
            wrappedText(RX, 513, RW - 66, vm.notice, vm.warning and SOFT_RED or CREAM)
        end
        button(L.hide[1], L.hide[2], 60, 24, "HIDE", false)

        drawCauldron(tostring(vm.outputLabel or ""):match("[%d,]+$"))
        text(18, BASE + 3, W - 36, 18, vm.footer, GOLD_LIGHT, false, "centre")
        drawLights()
    end

    function self:setPosition(x, y)
        pos.x, pos.y = x, y
        root:SetPos(x, y)
    end

    local fieldSpots = {
        { L.search[1], L.search[2], LW - 36, 25 }, { L.batches[1], L.batches[2], 90, 25 },
    }
    local function overWindow()
        if root.hidden then
            return nil
        end
        local mx, my = mouse()
        if not mx then
            return nil
        end
        local okXY, origin = pcall(function() return root.xyGlobal end)
        local x = mx - (okXY and origin and origin.x or pos.x)
        local y = my - (okXY and origin and origin.y or pos.y)
        if x < 0 or y < 0 or x >= W or y >= H then
            return nil
        end
        if y < CROWN and math.abs(x - CX) > crownHalf(math.min(CROWN, y + P), 0) then
            return nil
        end
        return x, y
    end
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
        if not x then
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
        local overControl = y < CROWN or not popup.hidden
        for _, spot in ipairs(spots) do
            if not spot[5].hidden and x >= spot[1] and y >= spot[2] and x < spot[1] + spot[3] and y < spot[2] + spot[4] then
                overControl = true
            end
        end
        for _, spot in ipairs(fieldSpots) do
            if x >= spot[1] and y >= spot[2] and x < spot[1] + spot[3] and y < spot[2] + spot[4] then
                overControl = true
            end
        end
        if not overControl then
            local leftClick = leftClickIsLast and count or 1
            if cancel and cancel ~= leftClick then
                menu:Swap(cancel, leftClick)
            end
            return
        end
        menu:Add("Apothecary", function() end)
        local total, entries, ours = menu.entryCount, menu.entries, nil
        for i = 1, total do
            if entries[i].actionEntryType == MiniMenuEntryType.PLUGIN and entryText(entries[i]) == "Apothecary" then
                ours = i
            end
        end
        local leftClick = leftClickIsLast and total or 1
        if ours and ours ~= leftClick then
            menu:Swap(ours, leftClick)
        end
    end
    local menuKey = "potionPlannerMenu"
    local lastMenuProblem = nil
    pcall(function()
        Event.MiniMenuReady.Subscribe(menuKey, function(event)
            local ok, problem = pcall(guardMenu, event)
            if not ok and problem ~= lastMenuProblem then
                log("Potion Planner menu: " .. tostring(problem))
            end
            lastMenuProblem = not ok and problem or nil
        end)
    end)

    function self:destroy()
        pcall(function() Event.MiniMenuReady.Unsubscribe(menuKey) end)
        Event.Logic.Unsubscribe(logicKey)
        root.hidden = true
        root:Destroy()
    end

    return self
end

return View
