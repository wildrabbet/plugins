-- Retro UI Kit 0.2.0
-- The pixel-art window kit our plugins use, for plugin makers.

local RetroUI = require("retro_ui")
local C = RetroUI.COLOURS

-- The demo window (settings cog) -------------------------------------------------------------------------------------
-- Shows every piece so plugin makers can see what they get. Closed by default.

local demoState = "closed"
local saved = (function()
    local ok, value = pcall(function() return PersistentDB:GetStructuredData("retroUI") end)
    return ok and value or nil
end)()
if type(saved) == "table" then
    local s = saved.state
    if s == "small" or s == "big" or s == "min" or s == "closed" then
        demoState = s
    elseif saved.demo == true then
        demoState = "small"
    end
end

local demo = nil
local demoOn, demoPage = true, 1

local function drawPieces(paint)
    local x, y = 30, 60
    paint:Chrome(x, y, 324, 33)
    paint:Magnifier(x + 9, y + 6)
    paint:Text(x + 33, y, 280, 33, "Search box frame (put window:Field here)", 0x56606AFF)
    paint:Button(x, y + 39, 102, 27, "Chrome", false)
    paint:Button(x + 108, y + 39, 102, 27, "Gold = on", demoOn)
    paint:Button(x + 216, y + 39, 108, 27, "Pressed", false, true)
    paint:Glass(x, y + 72, 324, 102)
    paint:Row(x + 6, y + 78, 312, 24, "A lit row", 42, true)
    paint:Row(x + 6, y + 102, 312, 24, "A row with a number", 1234, false)
    paint:Row(x + 6, y + 126, 312, 24, "Page " .. demoPage .. " (click the arrows)", nil, false)
    paint:Sprite(x + 285, y + 150, RetroUI.SPRITES.SMALL_BOTTLE, RetroUI.BottlePalette(0x3FC8C0FF))
    paint:LCD(x, y + 180, 324, 30)
    paint:Text(x + 9, y + 180, 150, 30, "LCD READOUT", C.FADED)
    paint:Text(x + 159, y + 180, 156, 30, "1,234,567", C.NUMBER, { bold = true, align = "right" })
    paint:Card(x, y + 216, 216, 54)
    paint:Sprite(x + 9, y + 222, RetroUI.SPRITES.BOTTLE, RetroUI.BottlePalette(0xE86AA8FF), 2)
    paint:Text(x + 42, y + 222, 168, 18, "A parchment card", C.DARK, { bold = true })
    paint:Text(x + 42, y + 240, 168, 16, "for a chosen item", 0x5A3A1EFF)
    paint:Chrome(x + 222, y + 216, 48, 54)
    paint:Arrow(x + 246, y + 231, "up")
    paint:Arrow(x + 246, y + 255, "down")
    paint:Chrome(x + 276, y + 216, 48, 54)
    paint:Sprite(x + 282, y + 222, RetroUI.SPRITES.STAR, { k = C.DARK, y = C.GOLD_LIGHT })
    paint:Sprite(x + 303, y + 222, RetroUI.SPRITES.COIN, { k = C.DARK, y = C.GOLD, Y = C.GOLD_LIGHT })
    paint:Sprite(x + 282, y + 246, RetroUI.SPRITES.HEART, { k = C.DARK, r = C.RED })
    paint:Sprite(x + 303, y + 246, RetroUI.SPRITES.NOTE, { k = C.DARK })
end

-- the big size ([]) adds a column on what the title bar's buttons do
local BUTTON_NOTES = { "- shrinks it to the title bar.", "[] swaps small and big.", "X closes it. The plugin keeps",
                       "running; the cog's Show window", "opens it again.", "", "Drag it by the title bar.",
                       "A still click on the title's", "words shrinks it too." }

local function drawDemo(paint, window, state)
    drawPieces(paint)
    if state ~= "big" then return end
    paint:Glass(366, 60, 237, 270)
    for i, line in ipairs(BUTTON_NOTES) do
        paint:Text(375, 66 + (i - 1) * 24, 219, 24, line, i == 7 and C.GOLD or C.CREAM)
    end
end

local function buildDemo(window)
    window:Area(138, 99, 102, 27, function()
        demoOn = not demoOn
        window:Redraw()
    end)
    window:Area(252, 276, 48, 27, function()
        demoPage = math.max(1, demoPage - 1)
        window:Redraw()
    end)
    window:Area(252, 303, 48, 27, function()
        demoPage = demoPage + 1
        window:Redraw()
    end)
end

pcall(function()
    local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    demo = RetroUI.ProgramWindow(layer, {
        title = "RETRO UI KIT", small = { 384, 351 }, big = { 624, 351 }, state = demoState, x = 160, y = 90,
        build = buildDemo, draw = drawDemo,
        onState = function(state)
            pcall(function() PersistentDB:SetStructuredData("retroUI", { state = state }) end)
        end,
    })
end)

Event.Logic.Subscribe("retroUIDemo", function()
    if demo then
        demo:Animate()
    end
end)

Event.SettingsLayerReady.Subscribe("retroUISettings", function(event)
    local panel = ui.Layer.new(event.component)
    panel:SetPos(8, 8)
    panel:SetSize(360, 90)
    local note = ui.Text.new(panel)
    note:SetPos(0, 0)
    note:SetSize(350, 40)
    note.font = id.Font.MUSEO_SANS_15PT_REGULAR
    note.clickthrough = true
    note.content = "A library for plugin makers. The demo window shows every piece."
    if demo then
        RetroUI.ShowWindowButton(panel, demo, 0, 44, 250)
    end
end)

function PluginShutdown()
    Event.Logic.Unsubscribe("retroUIDemo")
    Event.SettingsLayerReady.Unsubscribe("retroUISettings")
    if demo then
        demo:Destroy()
        demo = nil
    end
end

log("Retro UI Kit " .. RetroUI.VERSION .. " is on")

return RetroUI
