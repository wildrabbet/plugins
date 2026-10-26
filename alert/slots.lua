-- Slots: works out which backpack slot a right-click is on, and where that slot is on screen now.
--
-- A slot is known by where it sits inside its grid, not by the item in it. So an alert stays on the same slot when the
-- item is used up or swapped for another one, and an empty slot can have an alert too.
-- An item slot is found from the right-click entry. An empty slot has no item to ask, so it is found from the backpack
-- grid the plugin learned the first time the mouse was over a backpack item (kept between sessions) and the mouse
-- position. Everything is read from the game with pcall, because the game's interface pieces can change shape.
-- Nothing here clicks, moves or changes anything.

local Slots = {}

-- Read a game value; nil if it is not there
local function get(fn)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
end

local function whole(n)
    return math.floor(n + 0.5)
end

-- The backpack's items: { object id = how many slots hold it }, or nil when the game has no backpack to read
local function backpackItems()
    local inv = get(function() return Inventory.Find(config.Inv.INV) end)
    if type(inv) == "table" and inv.GetSlots == nil and inv[1] then
        inv = inv[1]                     -- some calls hand back a list of one
    end
    if not inv or get(function() return inv.isValid end) == false then
        return nil
    end
    local slots = get(function() return inv:GetSlots() end)
    if type(slots) ~= "table" then
        return nil
    end
    local have = {}
    for _, slot in pairs(slots) do
        local object = slot and get(function() return slot.obj end)
        local objectID = object and get(function() return object.id end)
        if type(objectID) == "number" and objectID > 0 then
            have[objectID] = (have[objectID] or 0) + 1
        end
    end
    return have
end

-- Visits the pieces built into a grid and the ones the game makes while it runs. visit(component) returns true to stop.
local function eachChild(grid, visit)
    local stopped = false
    local function wrapped(component)
        if not stopped and visit(component) then
            stopped = true
        end
        return stopped
    end
    pcall(function() grid:IterateDynamicComponents(wrapped) end)
    if not stopped then
        pcall(function() grid:IterateStaticComponents(wrapped) end)
    end
end

-- The ids of the items pictured directly inside a grid
local function pictures(grid)
    local found = {}
    eachChild(grid, function(component)
        local objectID = get(function() return component.associatedObjectID end)
        if type(objectID) == "number" and objectID > 0 then
            found[#found + 1] = objectID
        end
    end)
    return found
end

function Slots.isBackpack(grid, objectID)
    local have = backpackItems()
    if not have or not have[objectID] then
        return false
    end
    for _, pictureID in ipairs(pictures(grid)) do
        if not have[pictureID] then
            return false
        end
    end
    return true
end

-- The backpack grid, learned --------------------------------------------------------------------------------------------
-- known = { interfaceID, gridID, gridW, gridH, w, h, ax, ay, pitchX, pitchY }
--   gridW, gridH: the grid's size (to notice when the game has rebuilt it as something else)
--   w, h: a slot's size.  ax, ay: where one slot sits in the grid.  pitchX, pitchY: the distance from one slot to the
--   next across and down, found from the slots seen so far (known once two columns and two rows have been seen).
local known = nil

local function save()
    pcall(function() PersistentDB:SetStructuredData("backpackGrid", known) end)
end

function Slots.load()
    local saved = get(function() return PersistentDB:GetStructuredData("backpackGrid") end)
    if type(saved) ~= "table" then
        return
    end
    for _, key in ipairs({ "interfaceID", "gridID", "w", "h", "ax", "ay" }) do
        if type(saved[key]) ~= "number" then
            return
        end
    end
    known = { interfaceID = saved.interfaceID, gridID = saved.gridID, w = saved.w, h = saved.h, ax = saved.ax, ay = saved.ay,
              gridW = type(saved.gridW) == "number" and saved.gridW or nil,
              gridH = type(saved.gridH) == "number" and saved.gridH or nil,
              pitchX = type(saved.pitchX) == "number" and saved.pitchX or nil,
              pitchY = type(saved.pitchY) == "number" and saved.pitchY or nil }
end

-- Is the grid known, and is its slot spacing known too?
function Slots.complete()
    return known ~= nil and known.pitchX ~= nil and known.pitchY ~= nil
end

-- The distance from one slot to the next: the smallest gap between two different offsets that is at least one slot wide
local function pitchOf(values, least)
    table.sort(values)
    local best
    for i = 2, #values do
        local gap = values[i] - values[i - 1]
        if gap >= least and (not best or gap < best) then
            best = gap
        end
    end
    return best
end

-- Where each slot-sized piece of a grid sits: offsets from the grid's top left, empty slots included
local function slotOffsets(grid, base, w, h)
    local found = {}
    eachChild(grid, function(component)
        local pieceW, pieceH = get(function() return component.width end), get(function() return component.height end)
        local at = pieceW == w and pieceH == h and get(function() return component.xyGlobal end)
        if at then
            found[#found + 1] = { whole(at.x - base.x), whole(at.y - base.y) }
        end
    end)
    return found
end

-- Remembers the backpack grid from a slot that was found by its item, and the slot spacing from the grid's pieces.
-- Saved when it changes. (Cheap once the spacing is known: it returns at once.)
function Slots.learn(info)
    local same = known ~= nil and known.interfaceID == info.interfaceID and known.gridID == info.gridID
        and known.gridW == info.gridW and known.gridH == info.gridH and known.w == info.w and known.h == info.h
    if same and Slots.complete() then
        return
    end
    local fresh = same and known or { interfaceID = info.interfaceID, gridID = info.gridID, gridW = info.gridW,
                                      gridH = info.gridH, w = info.w, h = info.h, ax = info.dx, ay = info.dy }
    local before = tostring(fresh.pitchX) .. "," .. tostring(fresh.pitchY)
    local base = get(function() return info.grid.xyGlobal end)
    if base then
        local xs, ys = {}, {}
        for _, offset in ipairs(slotOffsets(info.grid, base, info.w, info.h)) do
            xs[#xs + 1], ys[#ys + 1] = offset[1], offset[2]
        end
        local px, py = pitchOf(xs, info.w), pitchOf(ys, info.h)
        if px and (not fresh.pitchX or px < fresh.pitchX) then fresh.pitchX = px end
        if py and (not fresh.pitchY or py < fresh.pitchY) then fresh.pitchY = py end
    end
    if not same or before ~= tostring(fresh.pitchX) .. "," .. tostring(fresh.pitchY) then
        known = fresh
        save()
    end
end

-- Slots ----------------------------------------------------------------------------------------------------------------

local function slotAt(k, grid, dx, dy, name)
    return {
        key = k.interfaceID .. ":" .. k.gridID .. ":" .. dx .. ":" .. dy,
        interfaceID = k.interfaceID, gridID = k.gridID, dx = dx, dy = dy, w = k.w, h = k.h,
        gridW = k.gridW, gridH = k.gridH, name = name, grid = grid,
    }
end

function Slots.fromEntry(entry)
    if get(function() return entry.actionEntryType == MiniMenuEntryType.INTERFACE end) ~= true then
        return nil
    end
    local data = get(function() return entry.componentData end)
    local component = data and get(function() return data.component end)
    local object = data and get(function() return data.objConfig end)
    local objectID = object and get(function() return object.id end)
    if not component or type(objectID) ~= "number" or objectID <= 0 then
        return nil
    end
    local grid = get(function() return component.parentStatic end) or get(function() return component.parent end)
    if not grid then
        return nil
    end
    local at = get(function() return component.xyGlobal end)
    local base = get(function() return grid.xyGlobal end)
    local w = get(function() return component.width end)
    local h = get(function() return component.height end)
    local interfaceID = get(function() return component.interfaceID end)
    local gridID = get(function() return grid.staticID end)
    if not at or not base or type(w) ~= "number" or type(h) ~= "number"
        or type(interfaceID) ~= "number" or type(gridID) ~= "number" then
        return nil
    end
    -- the grid learned before is the backpack; any other grid has to prove it
    local learned = known ~= nil and known.interfaceID == interfaceID and known.gridID == gridID
    if not learned and not Slots.isBackpack(grid, objectID) then
        return nil, true
    end
    local dx, dy = whole(at.x - base.x), whole(at.y - base.y)
    local info = slotAt({ interfaceID = interfaceID, gridID = gridID, w = whole(w), h = whole(h),
                          gridW = get(function() return grid.width end), gridH = get(function() return grid.height end) },
                        grid, dx, dy, get(function() return object.name end))
    return info
end

-- The grid component again, by its ids (the old one can go stale when the game rebuilds the interface). nil when it is
-- not there or has become something of another size.
local function findGrid(k)
    local grid = get(function() return ui.Interfaces:GetComponent(k.interfaceID, k.gridID) end)
    if not grid then
        return nil
    end
    local same = get(function() return grid.width == k.gridW and grid.height == k.gridH end)
    return same and grid or nil
end

-- The slot under the mouse, found from the learned backpack grid: for a slot with no item in it. nil when the grid is
-- not known, not showing, or the mouse is not over one of its slots.
function Slots.fromMouse()
    local k = known
    if not k then
        return nil
    end
    local grid = findGrid(k)
    if not grid or get(function() return grid.visibleGlobal end) == false then
        return nil
    end
    local at = get(function() return grid.xyGlobal end)
    local mouse = get(function() return Mouse.GetPosition() end)
    if not at or not mouse then
        return nil
    end
    local mx, my = mouse.x - at.x, mouse.y - at.y
    local gridW, gridH = k.gridW or 1e9, k.gridH or 1e9
    if mx < 0 or my < 0 or mx >= gridW or my >= gridH then
        return nil
    end
    -- the grid's own pieces first: the empty slots are usually there too, as slot-sized pieces
    local dx, dy
    eachChild(grid, function(component)
        local pieceW, pieceH = get(function() return component.width end), get(function() return component.height end)
        local where = pieceW == k.w and pieceH == k.h and get(function() return component.xyGlobal end)
        if where then
            local cx, cy = whole(where.x - at.x), whole(where.y - at.y)
            if mx >= cx and mx < cx + k.w and my >= cy and my < cy + k.h then
                dx, dy = cx, cy
                return true
            end
        end
    end)
    -- otherwise the slot grid worked out from the spacing learned
    if not dx and k.pitchX and k.pitchY then
        local cx = k.ax + math.floor((mx - k.ax) / k.pitchX) * k.pitchX
        local cy = k.ay + math.floor((my - k.ay) / k.pitchY) * k.pitchY
        if cx >= 0 and cy >= 0 and mx < cx + k.w and my < cy + k.h and cx + k.w <= gridW and cy + k.h <= gridH then
            dx, dy = cx, cy
        end
    end
    if not dx then
        return nil
    end
    return slotAt(k, grid, dx, dy, "an empty slot")
end

-- What the plugin knows, for the log: the learned grid, the grid's rectangle now, and the mouse
function Slots.describe()
    local out = { known = known and { interfaceID = known.interfaceID, gridID = known.gridID, gridW = known.gridW,
                                      gridH = known.gridH, w = known.w, h = known.h, ax = known.ax, ay = known.ay,
                                      pitchX = known.pitchX, pitchY = known.pitchY } or "not learned yet" }
    local mouse = get(function() return Mouse.GetPosition() end)
    out.mouse = mouse and { x = mouse.x, y = mouse.y } or "none"
    local grid = known and findGrid(known)
    local at = grid and get(function() return grid.xyGlobal end)
    out.grid = at and { x = at.x, y = at.y, w = known.gridW, h = known.gridH,
                        visible = get(function() return grid.visibleGlobal end) } or "not found"
    return out
end

-- Where the slot is on screen now (the top left corner, in the game window's units), or nil when its grid is not
-- showing (another tab is open, or the backpack is closed). The grid is looked up again by its ids twice a second, and
-- straight away if the old one stops answering.
function Slots.where(info, now)
    local at = info.grid and get(function() return info.grid.xyGlobal end)
    if not at or not info.lookedAt or now - info.lookedAt >= 25 then
        info.lookedAt = now
        local fresh = findGrid({ interfaceID = info.interfaceID, gridID = info.gridID, gridW = info.gridW, gridH = info.gridH })
        if fresh then
            info.grid = fresh
            at = get(function() return fresh.xyGlobal end)
        end
    end
    if not at or get(function() return info.grid.visibleGlobal end) == false then
        return nil
    end
    return at.x + info.dx, at.y + info.dy
end

return Slots
