-- Summoning HUD 0.0.1
-- Keep familiar information together in an on-screen display.

local familiar = require("familiar")

local ACTION_BAR, PANEL = 1430, 662
local SOURCES = {
    name    = { { PANEL, 58 } },
    time    = { { PANEL, 10 }, { PANEL, 115 } },
    points  = { { ACTION_BAR, 22, true }, { PANEL, 42, true }, { PANEL, 70, true } },
    scrolls = { { PANEL, 84 } },
    pouches = { { PANEL, 82 } },
}
local CHILD_CATEGORY, CHILD_DYNAMIC = 0, 8

-- Settings, kept between sessions -------------------------------------------------------------------------------

local settings = PersistentDB:GetStructuredData("settings") or {}
for key, value in pairs(familiar.DEFAULTS) do
    if type(settings[key]) ~= "number" then settings[key] = value end
end

-- Reading the familiar panel -------------------------------------------------------------------------------------

-- The text at one source and whether it is on screen, or nil when the component is missing or empty.
local function textAt(source)
    local ok, text, visible = pcall(function()
        local component = ui.Interfaces:GetComponent(source[1], source[2])
        if not component then return nil end
        if source[3] then component = component:GetChild(CHILD_CATEGORY, CHILD_DYNAMIC) or component end
        return component.content, component.visibleGlobal
    end)
    if ok and type(text) == "string" and text ~= "" then return text, visible end
    return nil
end

-- One number's text: from a source that is on screen if there is one, else from a hidden one.
local function readField(sources)
    local hidden = nil
    for _, source in ipairs(sources) do
        local text, visible = textAt(source)
        if text and visible then return text end
        hidden = hidden or text
    end
    return hidden
end

-- What the game shows now, or nil when it has no familiar panel loaded.
local function readPanel()
    if not ui.Interfaces:GetInterface(PANEL) then return nil end
    local shown = {}
    for field, sources in pairs(SOURCES) do shown[field] = readField(sources) end
    return shown
end

-- The bar ---------------------------------------------------------------------------------------------------------
-- A dark box near the top of the screen: the familiar's name and time on the first line, the special-move points bar
-- under it, then the scroll count. Drawn on the layer the game gives plugins, above the game view.

local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local WIDTH, HEIGHT, PAD = 230, 62, 6
local COLOURS = {
    text = Vector4.new(1.0, 0.95, 0.80, 1.0),     -- the game's cream
    warn = Vector4.new(1.0, 0.35, 0.30, 1.0),     -- red
    back = Vector4.new(0.05, 0.04, 0.03, 0.75),
    flash = Vector4.new(0.55, 0.08, 0.06, 0.85),  -- the back while flashing (points under half)
    track = Vector4.new(0.20, 0.18, 0.15, 1.0),
    normal = Vector4.new(0.30, 0.65, 1.00, 1.0),  -- blue
    half = Vector4.new(1.00, 0.80, 0.25, 1.0),    -- gold
    low = Vector4.new(0.95, 0.25, 0.20, 1.0),     -- red
}

local function newText(parent, x, y, w, h)
    local text = ui.Text.new(parent)
    text:SetPos(x, y)
    text:SetSize(w, h)
    text.font = id.Font.MUSEO_SANS_15PT_REGULAR
    text.isShadowed = true
    text.colour = COLOURS.text
    text.clickthrough = true
    return text
end

local function newBox(parent, x, y, w, h, colour)
    local box = ui.Rectangle.new(parent)
    box:SetPos(x, y)
    box:SetSize(w, h)
    box.fill = true
    box.colour = colour
    box.clickthrough = true
    return box
end

local hud = ui.Layer.new(layer)
hud:SetSize(WIDTH, HEIGHT)
hud:SetPos(-WIDTH / 2, 0, 0.5, 0.12)               -- centred, 12% down the screen
hud.clickthrough = true
hud.hidden = true
local back = newBox(hud, 0, 0, WIDTH, HEIGHT, COLOURS.back)
local nameText = newText(hud, PAD, 2, WIDTH - 2 * PAD - 60, 18)
local timeText = newText(hud, WIDTH - PAD - 60, 2, 60, 18)
timeText:AlignTo(ui.AlignMode.BOTTOMRIGHT, ui.AlignMode.CENTRE)   -- right-aligned across, centred down
local track = newBox(hud, PAD, 24, WIDTH - 2 * PAD, 12, COLOURS.track)
local fill = newBox(hud, PAD, 24, 0, 12, COLOURS.normal)
local pointsText = newText(hud, PAD, 22, WIDTH - 2 * PAD, 16)
pointsText:AlignTo(ui.AlignMode.CENTRE)
local scrollText = newText(hud, PAD, 40, WIDTH - 2 * PAD, 18)

-- Shows the familiar's state on the bar (or hides the bar without a familiar). Only changed values are written.
-- While points are under half the back switches colour every tick (0.6 s): a flash that is hard to miss.
local shownKey, flashOn = nil, false
local function draw(state)
    flashOn = state ~= nil and state.flash and not flashOn
    local key = state and table.concat({ state.name, tostring(state.seconds), tostring(state.points),
        tostring(state.scrolls), state.band, tostring(state.renew), tostring(state.restock), tostring(flashOn) }, "|")
        or "none"
    if key == shownKey then return end
    shownKey = key

    hud.hidden = state == nil
    if not state then return end
    back.colour = flashOn and COLOURS.flash or COLOURS.back

    nameText.content = state.name
    timeText.content = state.renew and ("Renew " .. familiar.clock(state.seconds)) or familiar.clock(state.seconds)
    timeText.colour = state.renew and COLOURS.warn or COLOURS.text

    local share = (state.points and state.pointsMax and state.pointsMax > 0) and state.points / state.pointsMax or 0
    fill:SetSize(math.floor((WIDTH - 2 * PAD) * share + 0.5), 12)
    fill.colour = COLOURS[state.band]
    pointsText.content = state.points and (state.points .. " / " .. (state.pointsMax or 60) .. " special") or "special: --"

    if state.scrolls then
        scrollText.content = state.restock and (state.scrolls .. " scrolls - restock") or (state.scrolls .. " scrolls")
    else
        scrollText.content = "no scrolls"
    end
    scrollText.colour = state.restock and COLOURS.warn or COLOURS.text
end

-- Watching the familiar ------------------------------------------------------------------------------------------
-- Once per server tick (0.6 s), the same rate the game updates the panel. Nothing runs every frame.

local said = {}
local function sayOnce(text)
    if not said[text] then said[text] = true log("Summoning HUD: " .. text) end
end

Event.ServerLogic.Subscribe("summoningHudTick", function()
    local ok, problem = pcall(function()
        local shown = readPanel()
        if shown == nil then sayOnce("waiting for the game's familiar panel (summon a familiar)") end
        draw(shown and familiar.read(shown, settings))
    end)
    if not ok then log("Summoning HUD: " .. tostring(problem)) end
end)

function PluginShutdown()
    PersistentDB:SetStructuredData("settings", settings)
    pcall(function() hud:Destroy() end)
end

log("Summoning HUD is on")
