-- XP Meter 0.3.0
-- XP per hour and the time to your next level, for the skills you trained most recently.

local RetroUI = require("retro_ui")
local Xp = require("xp")
local C = RetroUI.COLOURS

local function get(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local NAMES = { [3] = "Constitution" }
local function skillName(n)
    if NAMES[n] then return NAMES[n] end
    local raw = get(function() return SkillType.FromID(n) end)
    if type(raw) ~= "string" then return "Skill " .. tostring(n) end
    return (raw:lower():gsub("^%l", string.upper))
end

local meter = Xp.new(function(skill) return get(function() return Player.GetLevelUncapped(skill) end) end)

local saved = get(function() return PersistentDB:GetStructuredData("xpMeter") end)
if type(saved) ~= "table" then saved = {} end
local function save(changes)
    for k, v in pairs(changes) do saved[k] = v end
    pcall(function() PersistentDB:SetStructuredData("xpMeter", saved) end)   -- always a table
end

local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local window = RetroUI.Window(layer, {
    width = 420, height = 333, crown = 60, title = "XP METER",
    program = true,
    x = tonumber(saved.x) or 40, y = tonumber(saved.y) or 540,
    onMove = function(x, y) save({ x = x, y = y }) end,
    onHide = function(hidden) save({ hidden = hidden }) end,
})
local box = window.inner
local ROW, GAP, ROWS = 27, 3, 4
local COLS = { name = 9, gained = 150, rate = 225 }   -- x inside the box: where names start, where numbers end (time to level: the right edge)

local now, started = 0, nil
local shown = nil
local goal = Xp.GOAL_HEADING[saved.goal] and saved.goal or "next"   -- what the last column counts down to

local function lines()
    local out = { goal = goal }
    for _, s in ipairs(meter:recent(ROWS)) do
        local st = meter:stats(s, now, goal)
        out[#out + 1] = { skillName(s.skill) .. " " .. st.level, "+" .. Xp.short(st.gained),
                          st.perHour and (Xp.short(st.perHour) .. "/h") or "-", st.done and "done" or Xp.duration(st.toGoal) }
    end
    local total = 0
    for _, s in pairs(meter.skills) do total = total + s.gained end
    local session = started and Xp.duration((now - started) / 50) or "-"
    out.footer = "Session " .. session .. "   " .. Xp.short(total) .. " XP"
    return out
end

local function draw(paint)
    local v = shown or lines()
    local y = box.y + 3
    paint:Text(box.x + COLS.name, y, 140, 21, "SKILL", C.FADED)
    paint:Text(box.x + COLS.gained - 70, y, 70, 21, "GAINED", C.FADED, { align = "right" })
    paint:Text(box.x + COLS.rate - 75, y, 75, 21, "PER HOUR", C.FADED, { align = "right" })
    paint:Text(box.x + box.width - 89, y, 80, 21, Xp.GOAL_HEADING[v.goal], C.GOLD, { align = "right" })   -- click: next goal
    y = y + 24
    for i = 1, ROWS do
        local row = v[i]
        paint:Glass(box.x, y, box.width, ROW)
        if row then
            paint:Text(box.x + COLS.name, y, 140, ROW, row[1], C.CREAM)
            paint:Text(box.x + COLS.gained - 70, y, 70, ROW, row[2], C.NUMBER, { align = "right" })
            paint:Text(box.x + COLS.rate - 75, y, 75, ROW, row[3], C.NUMBER, { align = "right" })
            paint:Text(box.x + box.width - 69, y, 60, ROW, row[4], row[4] == "done" and C.GREEN or C.NUMBER, { align = "right" })
        elseif i == 1 then
            paint:Text(box.x + COLS.name, y, box.width - 18, ROW, "Train any skill to start.", C.FADED)
        elseif i == 2 and not v[1] then
            paint:Text(box.x + COLS.name, y, box.width - 18, ROW, "Click " .. Xp.GOAL_HEADING[v.goal] .. " to count to 99, 120 or 200M.", C.FADED)
        end
        y = y + ROW + GAP
    end
    paint:Button(box.x, y + 3, 96, 27, "RESET", false)
    paint:Text(box.x + 105, y + 3, box.width - 105, 27, v.footer, C.CREAM, { align = "right" })
end

local function same(a, b)
    if not a or not b or #a ~= #b or a.footer ~= b.footer or a.goal ~= b.goal then return false end
    for i = 1, #a do for j = 1, 4 do if a[i][j] ~= b[i][j] then return false end end end
    return true
end

local function refresh(force)
    local v = lines()
    if force or not same(v, shown) then
        shown = v
        window:Redraw(draw)
    end
end

window:Area(box.x, box.y + 3 + 24 + ROWS * (ROW + GAP) + 3, 96, 27, function()
    meter:reset()
    started = nil
    log("XP Meter: reset.")
    refresh(true)
end)

-- The last column's heading: each click moves the goal on (next level, 99, 120, 200M, round again)
window:Area(box.x + box.width - 89, box.y + 3, 80, 21, function()
    for i, g in ipairs(Xp.GOALS) do
        if g == goal then goal = Xp.GOALS[i % #Xp.GOALS + 1]; break end
    end
    save({ goal = goal })
    log("XP Meter: counting down " .. Xp.GOAL_HEADING[goal]:lower() .. ".")
    refresh(true)
end)

Event.SkillTransmit.Subscribe("xpMeterGain", function(event)
    pcall(function()
        meter:gain(event.skill, event.oldXP, event.newXP, now)
        started = started or now
    end)
end)

Event.Logic.Subscribe("xpMeterTick", function()
    pcall(function()
        window:Animate()
        now = now + 1
        if now % 50 == 0 and not window:IsHidden() then refresh(false) end   -- once a second, and only if it changed
    end)
end)

if saved.hidden == true then window:Hide() end
refresh(true)

-- The cog: Show window (X closes the window; this brings it back)
Event.SettingsLayerReady.Subscribe("xpMeterCog", function(event)
    pcall(function() RetroUI.ShowWindowButton(event.component, window, 8, 8) end)
end)

function PluginShutdown()
    Event.SettingsLayerReady.Unsubscribe("xpMeterCog")
    Event.SkillTransmit.Unsubscribe("xpMeterGain")
    Event.Logic.Unsubscribe("xpMeterTick")
    window:Destroy()
end

log("XP Meter 0.3.0: on. Train a skill: XP per hour and time " .. Xp.GOAL_HEADING[goal]:lower() ..
    " show for your last 4 skills.")
