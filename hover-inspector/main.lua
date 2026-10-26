-- Hover Inspector 0.2.0
-- Shows what the game's menu knows about whatever is under your mouse.

local RetroUI = require("retro_ui")
local C = RetroUI.COLOURS

local function get(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

-- Names of the documented MiniMenuActionType and MiniMenuEntryType values (Jagex docs, Game > MiniMenu)
local ACTIONS = {
    [2] = "TGT_LOC", [3] = "OP_LOC1", [4] = "OP_LOC2", [5] = "OP_LOC3", [6] = "OP_LOC4", [8] = "TGT_NPC", [9] = "OP_NPC1",
    [10] = "OP_NPC2", [11] = "OP_NPC3", [12] = "OP_NPC4", [13] = "OP_NPC5", [15] = "TGT_PLAYER", [16] = "TGT_SELF",
    [17] = "TGT_OBJ", [18] = "OP_OBJ1", [19] = "OP_OBJ2", [20] = "OP_OBJ3", [21] = "OP_OBJ4", [22] = "OP_OBJ5", [23] = "WALK",
    [25] = "TGT_BUTTON", [30] = "PAUSE_BUTTON", [44] = "OP_PLAYER1", [45] = "OP_PLAYER2", [46] = "OP_PLAYER3",
    [47] = "OP_PLAYER4", [48] = "OP_PLAYER5", [49] = "OP_PLAYER6", [50] = "OP_PLAYER7", [51] = "OP_PLAYER8",
    [52] = "OP_PLAYER9", [53] = "OP_PLAYER10", [57] = "IF_BUTTONX1", [58] = "IF_BUTTONT", [59] = "TGT_GROUND",
    [60] = "FACE_SQUARE", [1001] = "OP_LOC5", [1002] = "OP_LOC6", [1003] = "OP_NPC6", [1004] = "OP_OBJ6", [1005] = "WIKI",
    [1006] = "CANCEL", [1007] = "IF_BUTTONX2", [1008] = "OP_MAPELEMENT1", [1009] = "OP_MAPELEMENT2",
    [1010] = "OP_MAPELEMENT3", [1011] = "OP_MAPELEMENT4", [1012] = "OP_MAPELEMENT5",
}
for n = 1, 10 do ACTIONS[2043 + n] = "OP_PLAYER" .. n .. "_LOWPRIORITY" end
for n = 1, 5 do ACTIONS[2008 + n] = "OP_NPC" .. n .. "_LOWPRIORITY" end
ACTIONS[3003] = "OP_NPC6_LOWPRIORITY"
local SOURCES = { [0] = "NONE", [1] = "INTERFACE", [2] = "OBJ", [3] = "LOC", [4] = "NPC", [5] = "OTHER", [6] = "MINIMENU",
                  [7] = "PLAYER", [8] = "SELF", [9] = "MAP", [10] = "PLUGIN" }

local function plain(text) return type(text) == "string" and (text:gsub("<[^>]->", "")) or "" end
local function named(value, list) return (list[value] or "?") .. " = " .. tostring(value) end
local function tile(x, z, level)
    if type(x) ~= "number" then return "-" end
    return x .. ", " .. tostring(z) .. (type(level) == "number" and ("  plane " .. level) or "")
end
local function gridText(g)
    return g and tile(get(function() return g.x end), get(function() return g.z end), get(function() return g.level end)) or "-"
end

-- One menu entry, read into plain values: { text, action, source, id, tile, more }
local function read(entry)
    local e = { text = plain(get(function() return entry.fullText end)), action = get(function() return entry.actionType end),
                source = get(function() return entry.actionEntryType end), id = "-", tile = "-", more = {} }
    local npc = get(function() return entry.npcData end)
    local loc = get(function() return entry.locData end)
    local obj = get(function() return entry.objData end)
    local player = get(function() return entry.playerData end)
    local ground = get(function() return entry.groundData end)
    local element = get(function() return entry.mapElementData end)
    local comp = get(function() return entry.componentData end)
    if npc then
        local ent = get(function() return npc.entity end)
        e.id = "NPC " .. tostring(ent and get(function() return ent.configID end)) .. "  " .. tostring(ent and get(function() return ent.displayName end))
        e.tile = gridText(ent and get(function() return ent.coordGrid end))
        if ent and get(function() return ent.isMultiNPC end) then
            e.more[#e.more + 1] = "multi-NPC, parent " .. tostring(get(function() return ent.parentConfigID end))
        end
        e.more[#e.more + 1] = "uid " .. tostring(ent and get(function() return ent.uid end))
        local size = ent and get(function() return ent.config.gridSize end)
        local feet = ent and get(function() return ent.position.y end)
        local low = ent and get(function() return ent.aabb.minimum.y end)
        local high = ent and get(function() return ent.aabb.maximum.y end)
        local box = (type(feet) == "number" and type(low) == "number" and type(high) == "number") and
            ("box " .. math.floor(low - feet) .. " to " .. math.floor(high - feet) .. " over feet") or "box ?"
        e.more[#e.more + 1] = "size " .. tostring(size) .. ", " .. box
    elseif loc then
        local cfg = get(function() return loc.config end)
        e.id = "LOC " .. tostring(cfg and get(function() return cfg.id end)) .. "  " .. tostring(cfg and get(function() return cfg.name end))
        e.tile = tile(get(function() return loc.coordGridX end), get(function() return loc.coordGridZ end))
        e.more[#e.more + 1] = "south-west tile"
    elseif obj then
        local cfg = get(function() return obj.config end)
        local ent = get(function() return obj.entity end)
        e.id = "OBJ " .. tostring(cfg and get(function() return cfg.id end)) .. "  " .. tostring(cfg and get(function() return cfg.name end))
        e.tile = gridText(ent and get(function() return ent.coordGrid end))
        e.more[#e.more + 1] = "stack index " .. tostring(get(function() return obj.stackIndex end))
    elseif player then
        local ent = get(function() return player.entity end)
        e.id = "PLAYER  " .. tostring(ent and get(function() return ent.displayName end))
        e.tile = gridText(ent and get(function() return ent.coordGrid end))
    elseif comp then
        local c = get(function() return comp.component end)
        local i, s, d = c and get(function() return c.interfaceID end), c and get(function() return c.staticID end), c and get(function() return c.dynamicID end)
        e.id = "COMPONENT " .. tostring(i) .. ":" .. tostring(s) .. ((type(d) == "number" and d >= 0) and ("/" .. d) or "")
        e.more[#e.more + 1] = "op " .. tostring(get(function() return comp.opIndex end))
        local cfg = get(function() return comp.objConfig end)
        if cfg then
            e.more[#e.more + 1] = "item " .. tostring(get(function() return cfg.id end)) .. " " .. tostring(get(function() return cfg.name end))
        end
    elseif element then
        e.id = "MAP ELEMENT " .. tostring(get(function() return element.mapElementID end))
        e.more[#e.more + 1] = "category " .. tostring(get(function() return element.categoryID end))
    end
    if ground then
        e.tile = tile(get(function() return ground.coordGridX end), get(function() return ground.coordGridZ end))
        if get(function() return ground.fromMiniMap end) == true then e.more[#e.more + 1] = "from the minimap" end
    end
    return e
end

local saved = get(function() return PersistentDB:GetStructuredData("hoverInspector") end)
if type(saved) ~= "table" then saved = {} end
local function save(changes)
    for k, v in pairs(changes) do saved[k] = v end
    pcall(function() PersistentDB:SetStructuredData("hoverInspector", saved) end)   -- always a table
end

local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local window = RetroUI.Window(layer, {
    width = 480, height = 459, crown = 60, title = "HOVER INSPECTOR",
    program = true,
    x = tonumber(saved.x) or 400, y = tonumber(saved.y) or 120,   -- beside Tile Info (40-370) by default
    onMove = function(x, y) save({ x = x, y = y }) end,
    onHide = function(hidden) save({ hidden = hidden }) end,
})
local box = window.inner
local ROW, GAP, SMALL = 24, 3, 21
local OTHERS = 4

local entries = {}                    -- the menu now, read: the first is what a left click does
local locked, dirty = false, true

local function draw(paint)
    local top = entries[1]
    local rows = {
        { "ACTION", top and (top.text ~= "" and top.text or "-") or "hover something" },
        { "TYPE", top and named(top.action, ACTIONS) or "-" },
        { "SOURCE", top and named(top.source, SOURCES) or "-" },
        { "ID", top and top.id or "-" },
        { "TILE", top and top.tile or "-" },
        { "MORE", top and (#top.more > 0 and table.concat(top.more, ", ") or "-") or "-" },
    }
    local y = box.y + 3
    for _, r in ipairs(rows) do
        paint:Glass(box.x, y, box.width, ROW)
        paint:Text(box.x + 9, y, 78, ROW, r[1], C.FADED)
        paint:Text(box.x + 87, y, box.width - 96, ROW, r[2], C.NUMBER)
        y = y + ROW + GAP
    end
    paint:Text(box.x, y, box.width, SMALL, "OTHER ENTRIES", C.CREAM, { bold = true })
    y = y + SMALL
    paint:Glass(box.x, y, box.width, OTHERS * SMALL + 6)
    for i = 2, OTHERS + 1 do
        local e = entries[i]
        if e then
            paint:Text(box.x + 9, y + 3 + (i - 2) * SMALL, box.width - 18, SMALL,
                       (e.text ~= "" and e.text or "-") .. "   (" .. tostring(ACTIONS[e.action] or e.action) .. ")", C.CREAM)
        end
    end
    y = y + OTHERS * SMALL + 12
    paint:Button(box.x, y, 96, 27, locked and "LOCKED" or "LOCK", locked)
    paint:Button(box.x + 105, y, 96, 27, "LOG", false)
    paint:Text(box.x + 210, y, box.width - 210, 27, #entries .. " entr" .. (#entries == 1 and "y" or "ies"), C.FADED, { align = "right" })
end

local buttonsY = box.y + 3 + 6 * (ROW + GAP) + SMALL + OTHERS * SMALL + 12
window:Area(box.x, buttonsY, 96, 27, function()
    locked = not locked
    dirty = true
end)
window:Area(box.x + 105, buttonsY, 96, 27, function()
    log("Hover Inspector: " .. #entries .. " entr" .. (#entries == 1 and "y" or "ies"))
    for i, e in ipairs(entries) do
        log("  " .. i .. ". " .. e.text .. " | " .. named(e.action, ACTIONS) .. " | " .. named(e.source, SOURCES) ..
            " | " .. e.id .. " | tile " .. e.tile .. (#e.more > 0 and (" | " .. table.concat(e.more, ", ")) or ""))
    end
end)

-- The menu under the mouse. Menus with nothing but Cancel (the inspector itself, empty sky) keep the last real one.
Event.MiniMenuReady.Subscribe("hoverInspectorMenu", function(event)
    if locked or window:IsHidden() then return end
    pcall(function()
        local menu = event.miniMenu
        local count = get(function() return menu.entryCount end) or 0
        local list, real = {}, false
        for i = count, math.max(1, count - 11), -1 do
            local entry = get(function() return menu.entries[i] end)
            if entry then
                local e = read(entry)
                if e.action ~= 1006 then
                    list[#list + 1] = e
                    real = true
                end
            end
        end
        if real then
            entries = list
            dirty = true
        end
    end)
end)

local ticks = 0
Event.Logic.Subscribe("hoverInspectorTick", function()
    pcall(function()
        window:Animate()
        ticks = ticks + 1
        if dirty and ticks % 5 == 0 and not window:IsHidden() then
            dirty = false
            window:Redraw(draw)
        end
    end)
end)

if saved.hidden == true then window:Hide() end
window:Redraw(draw)

-- The cog: Show window (X closes the window; this brings it back)
Event.SettingsLayerReady.Subscribe("hoverInspectorCog", function(event)
    pcall(function() RetroUI.ShowWindowButton(event.component, window, 8, 8) end)
end)

function PluginShutdown()
    Event.SettingsLayerReady.Unsubscribe("hoverInspectorCog")
    Event.MiniMenuReady.Unsubscribe("hoverInspectorMenu")
    Event.Logic.Unsubscribe("hoverInspectorTick")
    window:Destroy()
end

log("Hover Inspector 0.2.0: on. Hover anything for its IDs; LOCK freezes it, LOG prints every entry to the console.")
