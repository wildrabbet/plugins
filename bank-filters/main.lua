-- Bank Filters 0.4.1
-- Find items to sort out and mark your own collections with custom bank presets.

local filters = require("filters")
local Marks = require("marks")
local marks = Marks.load(PersistentDB:GetStructuredData("itemMarks"))
local marksDirty = false
local Presets = require("presets")
local Food = require("food")
local presets = Presets.load(PersistentDB:GetStructuredData("itemPresets"))
local presetsDirty = false
local savePresets
local stopped = false

-- Settings, kept between sessions ------------------------------------------------------------------------------------
-- Saved straight away on every change, so a client crash loses nothing.

local switchRows = { { "healing", "Show healing", false }, { "placeholders", "Hide placeholders", false } }
for _, kind in ipairs(filters.KINDS) do
    switchRows[#switchRows + 1] = { kind, filters.LOOK[kind].label, true }
end
for _, kind in ipairs(filters.EXTRAS) do
    local look = filters.LOOK[kind]
    switchRows[#switchRows + 1] = { kind, look.setting or look.button or look.label, false }
end
-- Same saved switches as the bank buttons. No chat access or other permission is needed.
local switches = require("settings").new("switches", switchRows, "Healing: base HP; VAR = variable; ? = unknown.\nTOP100 is dated, not live. No healing bonuses.")

local function saveSettings()
    PersistentDB:SetStructuredData("switches", switches)
end

-- Finding the bank -----------------------------------------------------------------------------------------------
-- The bank's item grid is the component holding one picture per bank slot, each picture knowing which item it shows
-- (its associated object). The game's lists of interface names can't be searched, so the first time the bank is open
-- every open interface is checked once for the component whose item pictures best match the bank's slot count. That
-- interface is remembered, and from then on it is the only one looked at.

local MAX_INTERFACE_ID = 3000   -- interface IDs checked on that first search
local MAX_MISSES = 25           -- static IDs run from 0 upwards: this many missing in a row ends an interface
local bank = { interfaceID = nil, gridID = nil, grid = nil, visible = false }
local scanWait = 0              -- ticks until the first search may run again

-- A message for the console, written once rather than every tick.
local said = {}
local function sayOnce(text)
    if not said[text] then said[text] = true log("Bank Filters: " .. text) end
end

local function itemPictures(parent)
    local found = {}
    local function visit(component)
        local ok, objectID = pcall(function() return component.associatedObjectID end)
        if ok and type(objectID) == "number" and objectID >= 0 then
            local okShown, shown = pcall(function() return component.visibleGlobal end)
            found[#found + 1] = { component = component, objectID = objectID, count = component.associatedObjectQuantity or 1,
                                  visible = not okShown or shown ~= false }
        end
        return false   -- keep going
    end
    pcall(function() parent:IterateDynamicComponents(visit) end)
    pcall(function() parent:IterateStaticComponents(visit) end)
    return found
end

-- In one interface: the component with the most item pictures, how many it has, and its static ID.
local function busiestComponent(interfaceID)
    local best, bestCount, bestStatic = nil, 0, -1
    local staticID, misses = 0, 0
    while misses < MAX_MISSES do
        local component = ui.Interfaces:GetComponent(interfaceID, staticID)
        if component then
            misses = 0
            local count = #itemPictures(component)
            if count > bestCount then best, bestCount, bestStatic = component, count, staticID end
        else
            misses = misses + 1
        end
        staticID = staticID + 1
    end
    return best, bestCount, bestStatic
end

-- How many slots of the bank hold something, or nil while the game has no bank contents (the bank is closed).
local function bankSlotsUsed()
    local ok, inv = pcall(Inventory.Find, config.Inv.BANK)
    if not ok then sayOnce("could not read the bank's contents: " .. tostring(inv)) return nil end
    if inv == nil then return nil end
    if type(inv) == "table" then inv = inv[1] end      -- in case it comes as a list of one
    local okUsed, used = pcall(function() return inv.valid and inv.usedSlotCount end)
    if okUsed and type(used) == "number" then return used end
    return nil
end

-- The bank's interface ID and item grid, or nil while the bank isn't loaded. Once found, both IDs are remembered
-- (in this plugin's saved settings), so every later opening is a direct lookup.
local function findGrid()
    local saved = PersistentDB:GetInt("bankInterfaceID")
    if saved then
        if not ui.Interfaces:GetInterface(saved) then return nil end
        local savedGrid = PersistentDB:GetInt("bankGridComponent")
        local grid = savedGrid and ui.Interfaces:GetComponent(saved, savedGrid)
        if grid and #itemPictures(grid) > 0 then return saved, grid, savedGrid end
        local busiest, count, staticID = busiestComponent(saved)   -- the game moved it: look again in the same interface
        if busiest and count > 0 then
            PersistentDB:SetInt("bankGridComponent", staticID)
            return saved, busiest, staticID
        end
        return nil
    end

    -- the first time: the open interface whose item grid comes closest to the bank's number of used slots. A search
    -- that finds nothing waits 15 ticks (9 s) before the next, so it never runs every tick.
    -- If the game won't say how full the bank is, the biggest grid of 30 or more wins (more than a full backpack).
    if scanWait > 0 then scanWait = scanWait - 1 return nil end
    scanWait = 15
    local used = bankSlotsUsed()
    local bestID, bestGrid, bestCount, bestStatic, bestGap, open = nil, nil, 0, -1, math.huge, 0
    for interfaceID = 0, MAX_INTERFACE_ID do
        if ui.Interfaces:GetInterface(interfaceID) then
            open = open + 1
            local grid, count, staticID = busiestComponent(interfaceID)
            local gap = used and math.abs(count - used) or -count
            local bigEnough = count >= (used and 8 or 30)
            if grid and bigEnough and gap < bestGap then
                bestID, bestGrid, bestCount, bestStatic, bestGap = interfaceID, grid, count, staticID, gap
            end
        end
    end
    if not bestGrid then
        log("Bank Filters: searched " .. open .. " open interfaces, no bank grid yet (bank slots used: "
            .. tostring(used) .. "). Open your bank.")
        return nil
    end
    used = used or bestCount
    PersistentDB:SetInt("bankInterfaceID", bestID)
    PersistentDB:SetInt("bankGridComponent", bestStatic)
    log("Bank Filters: found the bank: interface " .. bestID .. ", component " .. bestStatic .. ", " .. bestCount
        .. " item pictures for " .. used .. " used bank slots")
    return bestID, bestGrid, bestStatic
end

-- Tags on the slots ----------------------------------------------------------------------------------------------
-- Each tag is a coloured frame and a label on the bank grid itself, kept on its slot: every tick each tag moves to
-- where its slot is now (scrolling, tab changes). Tags let clicks through to the slot underneath.
-- Reuse tags during one opening. Reopening can replace the grid while old handles still report visible: fetch the
-- current grid and attach a fresh set. Hide retired tags rather than destroying them during that transition;
-- deferred deletes could otherwise collide with the new set.

local TAG_CATEGORY = 200 -- dynamic IDs for tags: categories 200-234 (236 IDs each), clear of the game's own
local TAG_IDS = 35 * 236
local nextTagID = (PersistentDB:GetInt("nextTagID") or 0) % TAG_IDS   -- carried over a reload, for the same reason
local pool = {}          -- every tag made so far: { frame, text, id, slot, x, y, textHeight }
local inUse = 0          -- pool[1] to pool[inUse] are on slots now; the rest are hidden
local covers = {}        -- every placeholder cover made so far: { box, slot, x, y }
local coversInUse = 0    -- covers[1] to covers[coversInUse] are on slots now
local shownKey = ""      -- what the tags were last built for
local bankItems = {}     -- IDs to current bank pictures; menu actions must belong to these, not the backpack

local function newTagID()
    local category, dynamic = TAG_CATEGORY + math.floor(nextTagID / 236), nextTagID % 236
    nextTagID = (nextTagID + 1) % TAG_IDS
    return category, dynamic
end

local function tagAt(i)
    if pool[i] then return pool[i] end
    local category, dynamic = newTagID()
    local tag = { id = { category, dynamic }, textHeight = 0 }
    tag.frame = ui.Rectangle.new(bank.grid, category, dynamic)
    tag.frame.fill = false
    tag.frame.outlineThickness = 2
    tag.frame.clickthrough = true
    tag.backing = ui.Rectangle.new(bank.grid, newTagID())
    tag.backing.fill = true
    tag.backing.colour = Vector4.new(0.02, 0.025, 0.035, 0.96)
    tag.backing.clickthrough = true
    tag.text = ui.Text.new(bank.grid, newTagID())
    tag.text.isShadowed = true
    tag.text.clickthrough = true
    tag.text:AlignTo(ui.AlignMode.CENTRE)
    pool[i] = tag
    return tag
end

-- Placeholder covers: with "Hide placeholders" on, each placeholder (an item you have 0 of) gets a box in the bank's
-- own background colour, so the greyed-out picture doesn't show. The box lets clicks through: the slot still works
-- exactly as before.
local BANK_BACKGROUND = Vector4.new(51 / 255, 46 / 255, 41 / 255, 1)

local function showCover(i, slot)
    local cover = covers[i]
    if not cover then
        cover = { box = ui.Rectangle.new(bank.grid, newTagID()) }
        cover.box.fill = true
        cover.box.colour = BANK_BACKGROUND
        cover.box.clickthrough = true
        covers[i] = cover
    end
    cover.slot, cover.x, cover.y = slot, slot.x, slot.y
    cover.box:SetPos(slot.x, slot.y)
    cover.box:SetSize(slot.width, slot.height)
    cover.box.hidden = false
    pcall(function() cover.box:MoveToFront() end)   -- over the slot, which the game redraws on reopening
end

-- Hides every cover from number first onward.
local function hideCoversFrom(first)
    for i = first, #covers do
        covers[i].box.hidden = true
        covers[i].slot = nil
    end
end

-- Hides every tag from number first onward.
local function hideTagsFrom(first)
    for i = first, #pool do
        pool[i].frame.hidden = true
        pool[i].backing.hidden = true
        pool[i].text.hidden = true
        if pool[i].star then pool[i].star.hidden = true end
        pool[i].slot = nil
    end
end

-- A retired interface may reject writes, or still answer them despite no longer drawing.
local function retireTags()
    for _, tag in ipairs(pool) do
        pcall(function() tag.frame.hidden = true; tag.backing.hidden = true; tag.text.hidden = true end)
        if tag.star then pcall(function() tag.star.hidden = true end) end
    end
    for _, cover in ipairs(covers) do
        pcall(function() cover.box.hidden = true end)
    end
    pool, inUse, shownKey = {}, 0, ""
    covers, coversInUse = {}, 0
end

-- Deletes every tag: only when the bank's grid is gone or the plugin is switched off.
local function deleteTags()
    for _, tag in ipairs(pool) do
        pcall(function() tag.frame:Destroy() end)
        pcall(function() tag.backing:Destroy() end)
        pcall(function() tag.text:Destroy() end)
        if tag.star then pcall(function() tag.star:Destroy() end) end
    end
    for _, cover in ipairs(covers) do
        pcall(function() cover.box:Destroy() end)
    end
    pool, inUse, shownKey = {}, 0, ""
    covers, coversInUse = {}, 0
end

-- Moves each tag and cover to where its slot is now. Only the ones whose slot moved are touched.
local function followSlots()
    for i = 1, coversInUse do
        local cover = covers[i]
        local ok, x, y = pcall(function() return cover.slot.x, cover.slot.y end)
        if ok and (x ~= cover.x or y ~= cover.y) then
            cover.x, cover.y = x, y
            cover.box:SetPos(x, y)
        end
    end
    for i = 1, inUse do
        local tag = pool[i]
        local ok, x, y = pcall(function() return tag.slot.x, tag.slot.y end)
        if ok and (x ~= tag.x or y ~= tag.y) then
            tag.x, tag.y = x, y
            tag.frame:SetPos(x, y)
            local captionY = y + tag.slot.height - tag.textHeight - 1
            tag.backing:SetPos(x + 1, captionY)
            tag.text:SetPos(x, captionY)
            if tag.star then tag.star:SetPos(x + tag.slot.width - 12, y + 1) end
        end
    end
end

-- For each label, the largest game font in which it fits inside a bank slot (looked up once per label and kept).
-- false = no font fits that label: the slot gets its coloured frame only.
local labelFonts = {}
local function fontFor(label, slotWidth, padding)
    padding = padding or 4
    local key = label .. ":" .. slotWidth .. ":" .. padding
    if labelFonts[key] ~= nil then return labelFonts[key] end
    local best, bestHeight = false, -1
    for fontID = 0, 300 do
        local ok, font = pcall(config.Font.FromID, fontID)
        if ok and font then
            local okSize, width, height = pcall(function() return font:GetStringWidth(label), font.upperCaseAscent end)
            -- a believable width: at least 4 px a letter (some fonts lack letters and measure almost nothing)
            local believable = okSize and width and height and width >= #label * 4 and height >= 9 and height <= 14
            if believable and width <= slotWidth - padding and height > bestHeight then
                best, bestHeight = font, height
            end
        end
    end
    labelFonts[key] = best
    if best then sayOnce(label .. " labels use font " .. best.id .. " (" .. bestHeight .. " px high)")
    else sayOnce("no game font fits " .. label .. " inside a " .. slotWidth .. " px slot: frame only") end
    return best
end

-- Short captions fit a readable font; full category names remain on the buttons.
local SHORT = { REPAIR = "FIX", TURNIN = "GIVE", SPIRIT = "TREE", SEEDS = "SEED", HERBS = "HERB",
                METAL = "ORE", GIZMO = "GIZ", PLANKS = "WOOD", SPORES = "SPORE", SIPHON = "SIPH",
                EFFIGY = "EFF", ROCKS = "ROCK" }

local function showTag(i, slot, label, rgba, favourite, cellWidth, custom, textRGBA)
    if not custom then label = SHORT[label] or label end
    local tag = tagAt(i)
    local colour = Vector4.new(rgba[1], rgba[2], rgba[3], rgba[4])
    tag.slot, tag.x, tag.y = slot, slot.x, slot.y
    tag.frame:SetPos(slot.x, slot.y)
    tag.frame:SetSize(slot.width, slot.height)
    tag.frame.colour = colour
    tag.frame.hidden = false

    -- Icons are narrower than their bank cells. DECANT can use the gap to the next icon, without overlapping it.
    local captionWidth = label == "DECANT" and math.max(slot.width, math.min(cellWidth or slot.width, slot.width + 8)) or slot.width
    -- User captions share a four-letter reference font, so 750 and SHRK have the same size and baseline.
    local font = label ~= "" and fontFor(custom and "KEEP" or label, captionWidth, label == "DECANT" and 2 or 4)
    if font then
        tag.textHeight = font.upperCaseAscent + 4
        local captionY = slot.y + slot.height - tag.textHeight - 1
        tag.backing:SetPos(slot.x + 1, captionY)
        tag.backing:SetSize(captionWidth - 2, tag.textHeight)
        tag.backing.hidden = false
        tag.text:SetPos(slot.x, captionY)
        tag.text:SetSize(captionWidth, tag.textHeight)
        tag.text.content = label
        tag.text.font = font.id
        tag.text.colour = textRGBA and Vector4.new(textRGBA[1], textRGBA[2], textRGBA[3], textRGBA[4]) or Vector4.new(1, 1, 1, 1)
        tag.text.hidden = false
    else
        tag.backing.hidden = true
        tag.text.hidden = true
    end

    pcall(function() tag.frame:MoveToFront() end)
    pcall(function() tag.backing:MoveToFront() end)
    pcall(function() tag.text:MoveToFront() end)
    if favourite then
        if not tag.star then
            tag.star = ui.Text.new(bank.grid, newTagID())
            tag.star.clickthrough, tag.star.isShadowed = true, true
            tag.star:AlignTo(ui.AlignMode.CENTRE)
        end
        local starFont = fontFor("*", 16)
        if starFont then
            tag.star.font, tag.star.content = starFont.id, "*"
            tag.star.colour = Vector4.new(1, 0.82, 0.30, 1)
            tag.star:SetPos(slot.x + slot.width - 12, slot.y + 1)
            tag.star:SetSize(12, 16)
            tag.star.hidden = false
            tag.star:MoveToFront()
        else
            tag.star.hidden = true
        end
    elseif tag.star then
        tag.star.hidden = true
    end
end

-- Item actions are exposed by ObjType even in the bank; cache the classification once per item ID.
local itemInfo = {}
local function infoFor(objectID)
    local info = itemInfo[objectID]
    if info then return info end
    local item = config.Obj.FromID(objectID)
    if not item then return nil end
    local options = {}
    pcall(function() for _, option in pairs(item.interfaceOpNames) do options[#options + 1] = option end end)
    info = { name = item.name, value = item.cost, gear = filters.isGear(options), healing = Food.caption(objectID, item.name, options) }
    itemInfo[objectID] = info
    return info
end

local function describe(picture, slotNumber)
    local info = infoFor(picture.objectID)
    if not info then return nil end
    return { id = picture.objectID, name = info.name, count = picture.count, value = info.value, slot = slotNumber, gear = info.gear,
             keep = Marks.has(marks, "keeps", picture.objectID),
             favourite = Marks.has(marks, "favourites", picture.objectID), healing = info.healing }
end

-- The pictures in bank order: top to bottom, left to right.
local function inBankOrder(pictures)
    table.sort(pictures, function(a, b)
        if a.component.y ~= b.component.y then return a.component.y < b.component.y end
        return a.component.x < b.component.x
    end)
    return pictures
end

local function refreshTags(pictures)
    -- one short string describing the slots and switches; nothing is redone while it stays the same
    local parts, cellWidth, previous = {}, nil, nil
    for i, picture in ipairs(pictures) do
        local c = picture.component
        if previous and c.y == previous.y and c.x > previous.x then
            local step = c.x - previous.x
            cellWidth = cellWidth and math.min(cellWidth, step) or step
        end
        previous = c
        parts[i] = picture.objectID .. ":" .. picture.count .. ":" .. c.width .. ":" .. c.height .. ":" .. tostring(picture.visible)
    end
    parts[#parts + 1] = "cell:" .. tostring(cellWidth)
    parts[#parts + 1] = "healing:" .. tostring(switches.healing)
    parts[#parts + 1] = "placeholders:" .. tostring(switches.placeholders)
    for _, kind in ipairs(filters.KINDS) do parts[#parts + 1] = kind .. tostring(switches[kind]) end
    for _, kind in ipairs(filters.EXTRAS) do parts[#parts + 1] = kind .. tostring(switches[kind]) end
    local key = table.concat(parts, ",")
    if key == shownKey then
        followSlots()
        return
    end

    -- Slot numbers count every picture, hidden or not, so "your first bank slots" (LOW) means the same slots whichever
    -- tab is open or whatever is searched.
    local used, counts, covered, hidden = 0, {}, 0, 0
    for slotNumber, picture in ipairs(pictures) do
        local item = picture.visible and describe(picture, slotNumber)
        local kind, label, colour = nil, nil, nil
        local preset = Presets.match(presets, picture.objectID)
        if not picture.visible then
            hidden = hidden + 1
            preset = nil                     -- a slot the game is hiding: no tag
        elseif switches.placeholders and picture.count == 0 then
            covered = covered + 1            -- a placeholder: covered, and no tag
            showCover(covered, picture.component)
            preset = nil
            item = nil
        elseif switches.healing and item and item.healing then
            kind, label = "healing", item.healing
            colour = preset and Presets.COLOURS[preset.colour][2] or { 0.40, 0.95, 0.45, 1 }
        elseif preset then
            kind, label, colour = "preset", preset.label, Presets.COLOURS[preset.colour][2]
        elseif item and not presets.focus then kind, label, colour = filters.tagFor(item, switches) end
        if kind then
            used = used + 1
            local textColour = preset and Presets.COLOURS[preset.textColour][2]
            showTag(used, picture.component, label, colour, item and item.favourite, cellWidth, preset ~= nil or kind == "healing", textColour)
            counts[kind] = (counts[kind] or 0) + 1
        end
    end
    hideTagsFrom(used + 1)
    hideCoversFrom(covered + 1)
    inUse, coversInUse, shownKey = used, covered, key
    if covered > 0 then counts.placeholder = covered end

    -- one console line per new result, e.g. "tagged 41 of 1920 slots: decant 12, loot 9, store 20"
    local summary = {}
    for _, kind in ipairs({ "healing", "preset", "loot", "sell", "decant", "junk", "low", "repair", "turnin", "store", "mtx", "resource", "gear", "traded", "keep", "favourite", "placeholder" }) do
        if counts[kind] then summary[#summary + 1] = kind .. " " .. counts[kind] end
    end
    -- "(N hidden by the game)" shows that a tab switch or search was seen
    local hiddenNote = hidden > 0 and (" (" .. hidden .. " hidden by the game)") or ""
    sayOnce("tagged " .. used .. " of " .. #pictures .. " slots" .. hiddenNote .. ": " .. (#summary > 0 and table.concat(summary, ", ") or "none"))
end

-- Buttons beside the bank ----------------------------------------------------------------------------------------
-- A column of the game's own buttons just left of the bank grid, each with a bar in its tag's colour. A filter that
-- is on shows bright; one that is off is dimmed. CLEAN switches every tidying filter; ALL switches everything,
-- MTX, RESOURCES, GEAR and the dated most-traded view too.

local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local BUTTON_W, BUTTON_H, GAP, BAR_W = 76, 24, 3, 4
local buttons = {}       -- name -> { button, bar, row, kind }
local EVERY_SWITCH = {}  -- the tidying filters, then the optional views
for _, kind in ipairs(filters.KINDS) do EVERY_SWITCH[#EVERY_SWITCH + 1] = kind end
for _, kind in ipairs(filters.EXTRAS) do EVERY_SWITCH[#EVERY_SWITCH + 1] = kind end

local function placeButton(name, label, row, kind, onPress)
    local button = ui.Button.new(layer)
    button:SetSize(BUTTON_W, BUTTON_H)
    button.label = label
    button.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
    button.hidden = true
    button:Subscribe(ui.Hook.ONBUTTONPRESSED, onPress)
    local bar = nil
    if kind then
        local c = (kind == "clean" or kind == "all") and { 1.0, 0.82, 0.30, 1 }
            or kind == "placeholders" and { 0.62, 0.58, 0.52, 1 }     -- grey: a view choice, not a filter
            or filters.LOOK[kind].colour
        bar = ui.Rectangle.new(layer)
        bar:SetSize(BAR_W, BUTTON_H)
        bar.fill = true
        bar.colour = Vector4.new(c[1], c[2], c[3], c[4])
        bar.hidden = true
    end
    buttons[name] = { button = button, bar = bar, row = row, kind = kind }
end

-- True when every switch in the list is on.
local function allOn(list)
    for _, kind in ipairs(list) do
        if not switches[kind] then return false end
    end
    return true
end

-- Bright for a switch that is on, dimmed for one that is off.
local function showSwitches()
    for _, entry in pairs(buttons) do
        local on
        if entry.kind == "clean" then on = allOn(filters.KINDS)
        elseif entry.kind == "all" then on = allOn(EVERY_SWITCH)
        else on = switches[entry.kind] end
        entry.button.alpha = on and 1.0 or 0.70
        entry.bar.alpha = on and 1.0 or 0.2
    end
end

-- The buttons show while the bank is open, and only then.
local function showButtons()
    local open = bank.grid ~= nil and bank.visible
    for _, entry in pairs(buttons) do
        entry.button.hidden = not open
        entry.bar.hidden = not open
    end
end

local function flip(kind)
    switches[kind] = not switches[kind]
    saveSettings()
    showSwitches()
end

-- Every switch in the list on, or all of them off when they already are.
local function flipList(list)
    if presets.focus then presets.focus = nil; shownKey = ""; savePresets() end
    local on = not allOn(list)
    for _, kind in ipairs(list) do switches[kind] = on end
    saveSettings()
    showSwitches()
end

placeButton("clean", "CLEAN", 1, "clean", function() flipList(filters.KINDS) end)
for row, kind in ipairs(filters.KINDS) do
    placeButton(kind, filters.LOOK[kind].label, row + 1, kind, function() flip(kind) end)
end
for i, kind in ipairs(filters.EXTRAS) do
    local look = filters.LOOK[kind]
    placeButton(kind, look.button or look.label, #filters.KINDS + 1 + i, kind, function() flip(kind) end)
end
placeButton("all", "ALL", #filters.KINDS + #filters.EXTRAS + 2, "all", function() flipList(EVERY_SWITCH) end)
-- Hide placeholders: its own switch, left out of CLEAN and ALL (it hides slots rather than tagging them)
placeButton("placeholders", "HIDE 0", #filters.KINDS + #filters.EXTRAS + 3, "placeholders", function() flip("placeholders") end)
showSwitches()

-- Keeps the column next to the bank wherever the bank window is.
local function placeButtons()
    local grid, base = bank.grid.xyGlobal, layer.xyGlobal
    local x = math.max(BAR_W + 4, grid.x - base.x - BUTTON_W - 14)
    local y = grid.y - base.y
    for _, entry in pairs(buttons) do
        local top = y + (entry.row - 1) * (BUTTON_H + GAP)
        entry.button:SetPos(x, top)
        entry.bar:SetPos(x - BAR_W - 2, top)
    end
end

-- Watching the bank ----------------------------------------------------------------------------------------------
-- Once per server tick (0.6 s): is the bank on screen, and has what it shows changed? Nothing runs every frame.

local function bankOnScreen()
    local ok, visible, width, height, x, y = pcall(function()
        local spot = bank.grid.xyGlobal
        return bank.grid.visibleGlobal, bank.grid.width, bank.grid.height, spot.x, spot.y
    end)
    if not ok then return false end
    local open = visible == true and width > 0 and height > 0 and (x > 0 or y > 0)
    if open ~= bank.visible then
        log(formatStr("Bank Filters: bank {} (visible {}, size {}x{}, at {},{})", open and "open" or "closed",
            tostring(visible), width, height, x, y))
    end
    return open
end

savePresets = function()
    local ok, result = pcall(function() return PersistentDB:SetStructuredData("itemPresets", presets) end)
    presetsDirty = not ok or result == false
end
local presetEditor = require("preset_ui").new(layer, presets, function()
    shownKey = ""
    savePresets()
end, function() return not stopped and bank.grid ~= nil and bank.visible and bankOnScreen() end)

local function forgetBank()
    presetEditor.close()
    retireTags()
    bank.interfaceID, bank.gridID, bank.grid, bank.visible = nil, nil, nil, false
    showButtons()
    bankItems = {}
end

local function saveMarks()
    local ok, result = pcall(function() return PersistentDB:SetStructuredData("itemMarks", marks) end)
    marksDirty = not ok or result == false
end

local function toggleMark(kind, objectID)
    if stopped or not bank.visible or not bankItems[objectID] then return end
    if Marks.toggle(marks, kind, objectID) then
        shownKey = ""
        saveMarks()
    else
        sayOnce("item mark limit reached")
    end
end

local function menuObject(entry)
    if entry.actionEntryType ~= MiniMenuEntryType.INTERFACE then return nil end
    local data = entry.componentData
    local objectID = data and data.objConfig and data.objConfig.id
    local candidates = objectID and bankItems[objectID]
    if not candidates or not data.component then return nil end
    for _, picture in ipairs(candidates) do
        if data.component == picture.component then return objectID end
        -- Some APIs return a fresh wrapper. Match the actual bank slot, not just the same item in the backpack.
        local ok, same = pcall(function()
            local a, b = data.component.xyGlobal, picture.component.xyGlobal
            return a.x == b.x and a.y == b.y and data.component.width == picture.component.width
                and data.component.height == picture.component.height
        end)
        if ok and same then return objectID end
    end
end

local function menuText(entry)
    return entry.overrideText and entry.overrideText ~= "" and entry.overrideText or entry.fullText
end

local function presetItem(presetID, objectID, present)
    if stopped or not bank.visible or not bankOnScreen() or not bankItems[objectID] then return end
    local ok, problem = Presets.setItem(presets, presetID, objectID, present)
    if ok then shownKey = ""; savePresets() else log("Bank Filters: " .. problem) end
end
local function openPresets(mode, objectID)
    if stopped or not bank.visible or not bankOnScreen() or not bankItems[objectID] then return end
    local pos, base = bank.grid.xyGlobal, layer.xyGlobal
    local x, y = math.max(8, pos.x - base.x + 40), math.max(8, pos.y - base.y + 30)
    if mode == "new" then presetEditor.edit(nil, objectID, x, y) else presetEditor.manage(x, y) end
end

local function markMenu(event)
    if stopped or not bank.visible then return end
    local menu = event.miniMenu
    local count = menu.entryCount
    if count < 1 or count > 64 then return end
    local objectID, examine, placeholder
    for i = 1, count do
        local entry = menu.entries[i]
        local candidate = menuObject(entry)
        if candidate and (entry.actionVerbType == MiniMenuActionVerbType.EXAMINE or entry.verbText == "Examine") then
            objectID, examine = candidate, i
        end
        if candidate and entry.verbText == "Withdraw-Placeholder" then
            placeholder = i
        end
    end
    if not objectID then return end
    local reversed = menu.entries[1].actionType == MiniMenuActionType.CANCEL
    if not reversed and menu.entries[count].actionType ~= MiniMenuActionType.CANCEL then return end
    local anchor = placeholder or (reversed and examine + 1 or examine - 1)
    local original = menu.entries[anchor]
    if not original or menuObject(original) ~= objectID then return end
    local anchorText = menuText(original)
    -- Check Swap before adding: if unsupported, do not leave a local mark as the highest-priority left click.
    menu:Swap(1, 1)
    local name = infoFor(objectID).name
    local choices = {
        { (Marks.has(marks, "favourites", objectID) and "Unfavourite " or "Favourite ") .. name, toggleMark, "favourites", objectID },
        { (Marks.has(marks, "keeps", objectID) and "Unkeep " or "Keep ") .. name, toggleMark, "keeps", objectID },
    }
    for _, preset in ipairs(presets.entries) do
        local present = Presets.has(preset, objectID)
        choices[#choices + 1] = { (present and "Remove from preset: " or "Add to preset: ") .. preset.name,
                                 presetItem, preset.id, objectID, not present }
    end
    if #presets.entries < Presets.LIMIT then choices[#choices + 1] = { "New preset...", openPresets, "new", objectID } end
    choices[#choices + 1] = { "Manage presets...", openPresets, "manage", objectID }
    -- Each insert goes beside the same native anchor. Reverse the choices to preserve their displayed order.
    for offset = 1, #choices do
        local choice = choices[#choices - offset + 1]
        local label = choice[1]
        menu:Add(label, choice[2], choice[3], choice[4], choice[5])
        local entries, added, beside = menu.entries
        for i = 1, count + offset do
            local entry = entries[i]
            if entry then
                if entry.actionEntryType == MiniMenuEntryType.PLUGIN and menuText(entry) == label then added = i end
                if menuText(entry) == anchorText and menuObject(entry) == objectID then beside = i end
            end
        end
        if not added or not beside then error("cannot locate added menu entry or bank action") end
        local target = beside
        if reversed and added < beside then target = beside - 1 end
        if not reversed and added > beside then target = beside + 1 end
        local step = added < target and 1 or -1
        for i = added, target - step, step do menu:Swap(i, i + step) end
    end
end

local menuError
Event.MiniMenuReady.Subscribe("bankFiltersMarks", function(event)
    local ok, problem = pcall(markMenu, event)
    if not ok and problem ~= menuError then log("Bank Filters menu: " .. tostring(problem)) end
    menuError = ok and nil or problem
end)

local function onTick()
    if stopped then return end
    showSwitches() -- the settings cog changes this same live table
    if marksDirty then saveMarks() end
    if presetsDirty then savePresets() end
    if bank.interfaceID and not ui.Interfaces:GetInterface(bank.interfaceID) then forgetBank() end
    -- IDs survive a bank rebuild; a component handle need not. One direct lookup each server tick also notices
    -- reopening when the old grid stays at 0,0 and never reports its own replacement.
    if bank.interfaceID then
        bank.grid = ui.Interfaces:GetComponent(bank.interfaceID, bank.gridID)
        if not bank.grid then forgetBank() end
    end
    if not bank.grid then
        bank.interfaceID, bank.grid, bank.gridID = findGrid()
        if not bank.grid then return end
    end

    local visible = bankOnScreen()
    if visible ~= bank.visible then
        presetEditor.close()
        retireTags()
        bank.visible = visible
        showButtons()
        if visible then
            log("Bank Filters: attached fresh tags to grid " .. bank.interfaceID .. ":" .. bank.gridID)
        end
    end
    if not visible then bankItems = {}; return end

    placeButtons()
    local pictures = inBankOrder(itemPictures(bank.grid))
    bankItems = {}
    for _, picture in ipairs(pictures) do
        local candidates = bankItems[picture.objectID] or {}
        candidates[#candidates + 1] = picture
        bankItems[picture.objectID] = candidates
    end
    refreshTags(pictures)
end

local lastError
Event.ServerLogic.Subscribe("bankFiltersTick", function()
    local ok, problem = pcall(onTick)
    if not ok then
        if problem ~= lastError then log("Bank Filters: " .. tostring(problem)) end
        lastError = problem
    else
        lastError = nil
    end
end)

-- Turning the plugin off removes everything it drew.
function PluginShutdown()
    stopped = true
    Event.SettingsLayerReady.Unsubscribe("switches")
    Event.MiniMenuReady.Unsubscribe("bankFiltersMarks")
    saveSettings()
    saveMarks()
    savePresets()
    presetEditor.close()
    deleteTags()
    forgetBank()
    PersistentDB:SetInt("nextTagID", nextTagID)
    for _, entry in pairs(buttons) do
        pcall(function() entry.button:Destroy() end)
        pcall(function() entry.bar:Destroy() end)
    end
end

log("Bank Filters 0.4.1 is on: tags follow tab switches and searches; HIDE 0 hides placeholders")
