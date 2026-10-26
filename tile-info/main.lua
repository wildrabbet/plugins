-- Tile Info 0.2.0
-- Shows where you are, in the numbers plugin makers need.

local RetroUI = require("retro_ui")
local C = RetroUI.COLOURS

local function get(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local saved = get(function() return PersistentDB:GetStructuredData("tileInfo") end)
if type(saved) ~= "table" then saved = {} end
local function save(changes)
    for k, v in pairs(changes) do saved[k] = v end
    pcall(function() PersistentDB:SetStructuredData("tileInfo", saved) end)   -- always a table (strings are refused)
end

local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local window = RetroUI.Window(layer, {
    width = 360, height = 363, crown = 60, title = "TILE INFO",
    program = true,
    x = tonumber(saved.x) or 40, y = tonumber(saved.y) or 160,
    onMove = function(x, y) save({ x = x, y = y }) end,
    onHide = function(hidden) save({ hidden = hidden }) end,
})
local box = window.inner
local ROW, GAP = 24, 3
local LABELS = { "TILE", "PLANE", "SQUARE", "PACKED", "MOUSE", "WALKING TO", "PING" }

local mouseTile = nil               -- { x, z } from the last Walk here entry under the mouse
local shown = nil                   -- the values on screen, so it only redraws when one changes

local function tileText(x, z) return (type(x) == "number" and type(z) == "number") and (x .. ", " .. z) or "-" end

-- Everything on the window right now, as text
local function values()
    local entity = get(function() return Player.GetEntity() end)
    local grid = entity and get(function() return entity.coordGrid end)
    local x, z = grid and get(function() return grid.x end), grid and get(function() return grid.z end)
    local level = grid and get(function() return grid.level end)
    local sx, sz = grid and get(function() return grid.mapSquareX end), grid and get(function() return grid.mapSquareZ end)
    local lx, lz = grid and get(function() return grid.localX end), grid and get(function() return grid.localZ end)
    local packed = grid and get(function() return grid:ToPacked() end)
    local route = entity and get(function() return entity.routeEnd end)
    local rx, rz = route and get(function() return route.x end), route and get(function() return route.z end)
    local walking = (type(rx) == "number" and (rx ~= x or rz ~= z)) and tileText(rx, rz) or "-"
    local ping = get(function() return World.GetPing() end)
    return {
        tileText(x, z),
        type(level) == "number" and tostring(level) or "-",
        type(sx) == "number" and (sx .. ", " .. tostring(sz) .. (type(sz) == "number" and (" = " .. (sx * 256 + sz)) or "") ..
            "  (" .. tostring(lx) .. ", " .. tostring(lz) .. ")") or "-",
        type(packed) == "number" and string.format("%d", packed) or "-",
        mouseTile and tileText(mouseTile.x, mouseTile.z) or "-",
        walking,
        (type(ping) == "number" and ping >= 0) and (ping .. " ms") or "-",
    }
end

local logArea
local function draw(paint)
    local v = shown or values()
    for i, label in ipairs(LABELS) do
        local y = box.y + 3 + (i - 1) * (ROW + GAP)
        paint:Glass(box.x, y, box.width, ROW)
        paint:Text(box.x + 9, y, 108, ROW, label, C.FADED)
        paint:Text(box.x + 117, y, box.width - 126, ROW, v[i], C.NUMBER, { align = "right" })
    end
    local by = box.y + 3 + #LABELS * (ROW + GAP) + 3
    paint:Button(box.x, by, 90, 27, "LOG", false)
    paint:Text(box.x + 99, by, box.width - 99, 27, "prints it to the console", C.CREAM)
end

local function refresh(force)
    local v = values()
    local changed = force or not shown
    if not changed then
        for i = 1, #v do if v[i] ~= shown[i] then changed = true break end end
    end
    if changed then
        shown = v
        window:Redraw(draw)
    end
end

logArea = window:Area(box.x, box.y + 3 + #LABELS * (ROW + GAP) + 3, 90, 27, function()
    local v = values()
    log("Tile Info: tile " .. v[1] .. ", plane " .. v[2] .. ", square " .. v[3] .. ", packed " .. v[4] ..
        ", mouse " .. v[5] .. ", walking to " .. v[6] .. ", ping " .. v[7])
end)

-- The tile under the mouse: the game's own "Walk here" entry carries it (MiniMenuActionType.WALK = 23, groundData)
Event.MiniMenuReady.Subscribe("tileInfoMouse", function(event)
    pcall(function()
        local menu = event.miniMenu
        local count = get(function() return menu.entryCount end) or 0
        local found = nil
        for i = 1, math.min(count, 12) do
            local entry = menu.entries[i]
            if get(function() return entry.actionType end) == 23 then
                local ground = get(function() return entry.groundData end)
                local gx = ground and get(function() return ground.coordGridX end)
                local gz = ground and get(function() return ground.coordGridZ end)
                if type(gx) == "number" and type(gz) == "number" then found = { x = gx, z = gz } end
                break
            end
        end
        mouseTile = found
    end)
end)

-- Every client tick: the kit's drag and bulbs; the numbers every 10 ticks (5 a second), and only while it's open
local ticks = 0
Event.Logic.Subscribe("tileInfoTick", function()
    pcall(function()
        window:Animate()
        ticks = ticks + 1
        if ticks % 10 == 0 and not window:IsHidden() then refresh(false) end
    end)
end)

if saved.hidden == true then window:Hide() end
refresh(true)

-- The cog: Show window (X closes it; this brings it back)
Event.SettingsLayerReady.Subscribe("tileInfoCog", function(event)
    pcall(function() RetroUI.ShowWindowButton(event.component, window, 8, 8) end)
end)

function PluginShutdown()
    Event.MiniMenuReady.Unsubscribe("tileInfoMouse")
    Event.Logic.Unsubscribe("tileInfoTick")
    Event.SettingsLayerReady.Unsubscribe("tileInfoCog")
    window:Destroy()
end

log("Tile Info 0.2.0: on. Drag it by the title bar; - shrinks it, X closes it (cog: Show window); LOG prints your position.")
