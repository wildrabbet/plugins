-- Alert! 0.1.1
-- Set reminders on backpack slots and choose a colour for their flashing alerts.

local RetroUI = require("retro_ui")
local Alerts = require("alerts")
local Slots = require("slots")
local C = RetroUI.COLOURS

local SET, CLEAR = "Set alert", "Clear alert"
local MODES = { "alt", "always", "off" }
local MODE_TEXT = { alt = "Alt + right-click", always = "Every right-click", off = "Off" }
local MENU_MAX = 64                      -- menus longer than this are not ours to touch

-- The pulse colours the window offers. rgb (0 to 1) is the pulse; face is the same colour on the window's swatch.
local COLOURS = {
    { name = "White", rgb = { 1, 1, 1 }, face = 0xFFFFFFFF },
    { name = "Red", rgb = { 1, 0.27, 0.27 }, face = 0xFF4545FF },
    { name = "Orange", rgb = { 1, 0.6, 0.15 }, face = 0xFF9926FF },
    { name = "Yellow", rgb = { 1, 0.9, 0.2 }, face = 0xFFE633FF },
    { name = "Green", rgb = { 0.3, 1, 0.4 }, face = 0x4DFF66FF },
    { name = "Cyan", rgb = { 0.3, 0.95, 1 }, face = 0x4DF2FFFF },
    { name = "Blue", rgb = { 0.3, 0.5, 1 }, face = 0x4D80FFFF },
    { name = "Pink", rgb = { 1, 0.45, 0.8 }, face = 0xFF73CCFF },
}

-- Read a game value; nil if it is not there
local function get(fn)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
end

-- Runs a handler so one bad moment cannot stop the plugin. A new problem is logged once, not 50 times a second.
local function guarded(name, fn)
    local lastProblem = nil
    return function(...)
        local ok, problem = pcall(fn, ...)
        if not ok and problem ~= lastProblem then
            log("Alert! " .. name .. ": " .. tostring(problem))
        end
        lastProblem = not ok and problem or nil
    end
end

-- Settings ------------------------------------------------------------------------------------------------------------

-- colour: which swatch was chosen last (1 = White); the next alert starts with it
local prefs = { menu = "alt", sound = true, debug = false, colour = 1, x = nil, y = nil }
local saved = get(function() return PersistentDB:GetStructuredData("alertPrefs") end)
if type(saved) == "table" then
    for _, mode in ipairs(MODES) do
        if saved.menu == mode then prefs.menu = mode end
    end
    if type(saved.sound) == "boolean" then prefs.sound = saved.sound end
    if type(saved.debug) == "boolean" then prefs.debug = saved.debug end
    if COLOURS[saved.colour] then prefs.colour = saved.colour end
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
end
local function save()
    pcall(function() PersistentDB:SetStructuredData("alertPrefs", prefs) end)
end
Slots.load()

-- The alerts ----------------------------------------------------------------------------------------------------------

local alerts = Alerts.new()
local now = 0                            -- client logic ticks since the game started (50 a second)
local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)

-- The pulse: one rectangle per alert, in the alert's colour, made when first needed and kept (hidden) for the next alert.
-- It lets every click through, so it never gets in the way of using the slot.
local overlays = {}                      -- alert key -> its rectangle
local spare = {}                         -- rectangles with no alert, ready to reuse

local function takeOverlay()
    local box = table.remove(spare)
    if box then
        return box
    end
    box = ui.Rectangle.new(layer)
    box.fill = true
    box.clickthrough = true
    box.hidden = true
    return box
end

local function drawAlerts()
    local base = get(function() return layer.xyGlobal end)
    local shown = {}
    for _, alert in ipairs(alerts:all()) do
        local alpha = alerts:alpha(alert, now)
        local x, y
        if alpha > 0 then
            x, y = Slots.where(alert.info, now)
        end
        if x then
            local box = overlays[alert.key]
            if not box then
                box = takeOverlay()
                overlays[alert.key] = box
            end
            box:SetPos(math.floor(x - (base and base.x or 0)), math.floor(y - (base and base.y or 0)))
            box:SetSize(alert.info.w, alert.info.h)
            local rgb = alert.colour
            box.colour = Vector4.new(rgb[1], rgb[2], rgb[3], alpha)
            box.hidden = false
            shown[alert.key] = true
        end
    end
    for key, box in pairs(overlays) do
        if not shown[key] then
            box.hidden = true
            if not alerts:get(key) then          -- the alert is gone: keep the rectangle for later
                overlays[key] = nil
                spare[#spare + 1] = box
            end
        end
    end
end

local function ring()
    if prefs.sound then
        pcall(function() audio.Play(id.Sound.ARCH_INFO_POPUP) end)
    end
end

local function clearAlert(key)
    alerts:clear(key)
    drawAlerts()
end

-- Where things sit in the window (top to bottom): the time box, the colour swatches, the buttons, the readout
local WIDTH, HEIGHT = 330, 240
local FIELD_Y = 84
local SWATCH_X, SWATCH_Y, SWATCH_W, SWATCH_H, SWATCH_STEP = 15, 130, 33, 24, 38
local BUTTON_Y = 164
local LCD_Y = 200

local window, field = nil, nil
local pending = nil                      -- the slot the window is setting an alert for
local typed = ""                         -- what is in the time box
local status = nil                       -- a message in the readout, until the window is closed
local colourIndex = prefs.colour         -- the swatch chosen now (the last one used, to start with)

local function swatchX(i)
    return SWATCH_X + (i - 1) * SWATCH_STEP
end

local function redraw()
    if not window then
        return
    end
    window:Redraw(function(paint)
        paint:Text(15, 6, 200, 24, "SET ALERT", C.GOLD, { bold = true })
        local what = pending and ("On: " .. (pending.name or "this slot")) or "No slot chosen yet."
        paint:Text(15, 36, 300, 22, what, C.CREAM)
        paint:Text(15, 60, 300, 20, "Time: 30s, 5m, 2h or 1h30m", C.FADED)
        paint:Text(15, 108, 300, 18, "COLOUR: " .. COLOURS[colourIndex].name:upper(), C.FADED)
        for i, colour in ipairs(COLOURS) do
            if i == colourIndex then                      -- the chosen swatch has a gold frame
                paint:Rect(swatchX(i) - 3, SWATCH_Y - 3, SWATCH_W + 6, SWATCH_H + 6, C.GOLD)
            end
            paint:Block(swatchX(i), SWATCH_Y, SWATCH_W, SWATCH_H, colour.face, RetroUI.Shade(colour.face, 255, 0.45),
                        RetroUI.Shade(colour.face, 0, 0.45))
        end
        paint:Button(15, BUTTON_Y, 94, 27, "SET", false)
        paint:Button(115, BUTTON_Y, 116, 27, "EVERY TICK", false)
        paint:Button(237, BUTTON_Y, 78, 27, "CANCEL", false)
        paint:LCD(15, LCD_Y, 300, 30)
        paint:Text(24, LCD_Y, 282, 30, status or ("ACTIVE ALERTS: " .. alerts:count()), C.NUMBER)
    end)
end

-- A swatch was clicked: the next alert uses that colour, and so does every one after it until another is chosen
local function chooseColour(i)
    colourIndex = i
    prefs.colour = i
    save()
    redraw()
end

local function closeWindow()
    if window then
        window:Close()
    end
    pending, status = nil, nil
end

local function submit(kind)
    if not pending then
        status = "Alt + right-click a backpack slot first."
        redraw()
        return
    end
    local seconds, label = nil, "every game tick"
    if kind == "timer" then
        typed = get(function() return field.content end) or typed
        local problem
        seconds, problem = Alerts.parseTime(typed)
        if not seconds then
            status = problem
            redraw()
            return
        end
        label = typed
    end
    local colour = COLOURS[colourIndex]
    local alert, problem = alerts:add(pending.key, kind, now, seconds, label, pending, colour.rgb)
    if not alert then
        status = problem
        redraw()
        return
    end
    log("Alert!: " .. label .. " on " .. tostring(pending.name) .. " (slot " .. pending.key .. ", " .. colour.name .. ")")
    closeWindow()
end

local function buildWindow()
    local x, y = prefs.x, prefs.y
    if not x then                        -- the first time: just above the mouse, kept on screen
        local mouse = get(function() return Mouse.GetPosition() end)
        local screenW = get(function() return layer.width end) or 1920
        local screenH = get(function() return layer.height end) or 1080
        x = math.max(0, math.min(screenW - WIDTH, (mouse and mouse.x or screenW / 2) - WIDTH / 2))
        y = math.max(0, math.min(screenH - HEIGHT, (mouse and mouse.y or screenH / 2) - HEIGHT - 24))
    end
    window = RetroUI.Window(layer, {
        width = WIDTH, height = HEIGHT, crown = 0, title = "ALERT!", x = math.floor(x), y = math.floor(y),
        program = true, contentTop = 6,
        onMove = function(newX, newY)
            prefs.x, prefs.y = newX, newY
            save()
        end,
    })
    -- Enter sets the timer, Esc cancels (clicking elsewhere does neither)
    local enter = get(function() return ui.InputFieldActionResult.SUBMIT end)
    local escape = get(function() return ui.InputFieldActionResult.SUBMIT_ON_ESCAPE end)
    field = window:Field(15, FIELD_Y, 300, "", function(text, reason)
        typed = text
        if enter ~= nil and reason == enter then
            submit("timer")
        elseif escape ~= nil and reason == escape then
            closeWindow()
        end
    end)
    for i = 1, #COLOURS do
        window:Area(swatchX(i), SWATCH_Y, SWATCH_W, SWATCH_H, function() chooseColour(i) end)
    end
    window:Area(15, BUTTON_Y, 94, 27, function() submit("timer") end)
    window:Area(115, BUTTON_Y, 116, 27, function() submit("tick") end)
    window:Area(237, BUTTON_Y, 78, 27, closeWindow)
end

-- Opens the window for a slot (the right-click entry runs this)
local function openWindow(info)
    if not window then
        buildWindow()
    end
    pending, typed, status = info, "", nil
    colourIndex = prefs.colour
    pcall(function() field.content = "" end)
    window:Show()
    redraw()
end

-- The right-click entries ---------------------------------------------------------------------------------------------

local function menuText(entry)
    local override = get(function() return entry.overrideText end)
    if override and override ~= "" then
        return override
    end
    return get(function() return entry.fullText end)
end

local function isOurs(entry, label)
    return get(function() return entry.actionEntryType == MiniMenuEntryType.PLUGIN end) == true and menuText(entry) == label
end

local function indexOf(menu, label)
    for i = 1, menu.entryCount do
        if isOurs(menu.entries[i], label) then
            return i
        end
    end
end

local function cancelIndex(menu)
    for i = 1, menu.entryCount do
        if get(function() return menu.entries[i].actionType == MiniMenuActionType.CANCEL end) then
            return i
        end
    end
end

-- Moves an entry to the place next to Cancel (the lowest of the menu) on the side where the rest of the menu is, one
-- swap at a time so every other entry keeps its order, and with it the game's own left-click action. Cancel's place is
-- looked up again after every swap, because a swap can move it.
local function placeLow(menu, label)
    for _ = 1, MENU_MAX do
        local cancel, at = cancelIndex(menu), indexOf(menu, label)
        if not cancel or not at then
            return
        end
        local target = cancel + (cancel <= menu.entryCount / 2 and 1 or -1)
        if at == target then
            return
        end
        menu:Swap(at, at + (target > at and 1 or -1))
    end
end

-- Is Alt held right now? If the game cannot say, treat it as held, so the entry is not lost.
local function altHeld()
    if get(function() return Keyboard.IsAvailable() end) ~= true then
        return true
    end
    return get(function() return Keyboard.IsAltDown() end) == true
end

-- Is the menu nothing but plain entries (the game's Cancel and Walk here, or another plugin's)? Then the mouse is over
-- the world, or over a slot with no item in it.
local function plainMenu(menu)
    local none = get(function() return MiniMenuEntryType.NONE end) or 0
    local plugin = get(function() return MiniMenuEntryType.PLUGIN end)
    for i = 1, menu.entryCount do
        local kind = get(function() return menu.entries[i].actionEntryType end)
        if kind ~= none and kind ~= plugin then
            return false
        end
    end
    return true
end

local lastLogged = -100
local function writeDown(menu, info, empty)
    if now - lastLogged < 25 then
        return
    end
    lastLogged = now
    local entries = {}
    for i = 1, math.min(menu.entryCount, 20) do
        local entry = menu.entries[i]
        local data = get(function() return entry.componentData end)
        local component = data and get(function() return data.component end)
        entries[i] = {
            text = menuText(entry), type = get(function() return entry.actionEntryType end),
            object = data and get(function() return data.objConfig.id end),
            interface = component and get(function() return component.interfaceID end),
            static = component and get(function() return component.staticID end),
            category = component and get(function() return component.categoryID end),
            dynamic = component and get(function() return component.dynamicID end),
        }
    end
    pcall(function()
        PersistentDB:SetStructuredData("lastRightClick", { tick = now, alt = altHeld(), slot = info and info.key or "none",
                                                           empty = empty == true, plain = plainMenu(menu),
                                                           where = Slots.describe(), entries = entries })
    end)
end

local onMenu = guarded("menu", function(event)
    local menu = event.miniMenu
    local count = menu.entryCount
    if count < 1 or count > MENU_MAX then
        return
    end
    local alt = altHeld()
    local wantSet = prefs.menu == "always" or (prefs.menu == "alt" and alt)
    local wantEmpty = prefs.menu ~= "off" and alt        -- an empty slot needs Alt in both modes (see the header)
    -- until the backpack's slot spacing is known, look at backpack items now and then even without Alt, to learn it
    local learning = not Slots.complete() and now % 10 == 0
    if not wantSet and not wantEmpty and alerts:count() == 0 and not prefs.debug and not learning then
        return                           -- the usual case: nothing to do, and nothing worked out
    end
    -- the backpack slot under the cursor: the first entry that belongs to one (or an item that is not in the backpack)
    local info, decided
    for i = 1, count do
        info, decided = Slots.fromEntry(menu.entries[i])
        if info or decided then
            break
        end
    end
    local empty = false
    if info then
        Slots.learn(info)
    elseif not decided and plainMenu(menu) and (wantEmpty or alerts:count() > 0 or prefs.debug) then
        info = Slots.fromMouse()         -- no item here: an empty slot, found from the mouse and the learned grid
        empty = info ~= nil
    end
    if prefs.debug then
        writeDown(menu, info, empty)
    end
    if not info then
        return
    end
    local wantClear = true
    if empty then
        wantSet = wantEmpty
        wantClear = count >= 2 or alt
    elseif count < 3 then
        return                           -- an item menu is never this short; with so few entries ours would be the left click
    end
    local active = alerts:get(info.key)
    if active and wantClear and not indexOf(menu, CLEAR) then
        menu:Add(CLEAR, clearAlert, info.key)
        placeLow(menu, CLEAR)
    end
    if wantSet and not indexOf(menu, SET) then
        menu:Add(SET, openWindow, info)
        placeLow(menu, SET)
    end
end)

-- Events --------------------------------------------------------------------------------------------------------------

Event.MiniMenuReady.Subscribe("alertMenu", onMenu)

Event.Logic.Subscribe("alertLogic", guarded("logic", function(event)
    now = (event and event.logicTick) or (now + 1)
    local rang = alerts:step(now)
    if #rang > 0 then
        ring()
    end
    drawAlerts()
    if window then
        window:Animate()                 -- follows a drag
    end
end))

Event.ServerLogic.Subscribe("alertServerTick", guarded("server tick", function()
    alerts:serverTick(now)
end))

-- Logging out (to the lobby or the login screen) clears every alert. Changing world does not.
Event.GameStateChanged.Subscribe("alertGameState", guarded("game state", function(event)
    local lobby = get(function() return GameState.LOBBY end) or 20
    local login = get(function() return GameState.LOGINSCREEN end) or 10
    if event.newState == lobby or event.newState == login then
        alerts:clearAll()
        alerts:resetCheck()
        drawAlerts()
        redraw()
    end
end))

-- Settings in the Plugin Hub (the cog) --------------------------------------------------------------------------------

Event.SettingsLayerReady.Subscribe("alertSettings", guarded("settings", function(event)
    local font = id.Font.MUSEO_SANS_15PT_REGULAR
    local panel = ui.Layer.new(event.component)
    panel:SetPos(8, 8)
    panel:SetSize(380, 330)

    local function label(text, y, height)
        local t = ui.Text.new(panel)
        t:SetPos(0, y)
        t:SetSize(370, height)
        t.font = font
        t.clickthrough = true
        t.content = text
    end
    local function button(text, y, onPress)
        local b = ui.Button.new(panel)
        b:SetPos(0, y)
        b:SetSize(290, 25)
        b.label = text
        b.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
        pcall(function() b.text.font = font end)
        b:Subscribe(ui.Hook.ONBUTTONPRESSED, function() onPress(b) end)
        return b
    end

    local function modeText() return "Set alert shows on: " .. MODE_TEXT[prefs.menu] end
    button(modeText(), 0, function(b)
        for i, mode in ipairs(MODES) do
            if mode == prefs.menu then
                prefs.menu = MODES[i % #MODES + 1]
                break
            end
        end
        b.label = modeText()
        save()
    end)
    local function soundText() return "Sound when a timer ends: " .. (prefs.sound and "on" or "off") end
    button(soundText(), 30, function(b)
        prefs.sound = not prefs.sound
        b.label = soundText()
        save()
    end)
    local function debugText() return "Log what I right-click: " .. (prefs.debug and "on" or "off") end
    button(debugText(), 60, function(b)
        prefs.debug = not prefs.debug
        b.label = debugText()
        save()
    end)
    local function activeText() return "Clear all alerts (" .. alerts:count() .. " now)" end
    button(activeText(), 90, function(b)
        alerts:clearAll()
        drawAlerts()
        redraw()
        b.label = activeText()
    end)

    label("Alt + right-click a backpack slot, then choose Set alert. An empty slot works once the plugin has seen an "
          .. "item in your backpack. Clear alert is in the right-click menu of a slot that has one.", 130, 75)
    label("Timers count game ticks while the game is open. They reset when you log out or close the game.", 210, 45)
    label(alerts:checkText() .. " (Close and reopen this window to update it.)", 260, 70)
end))

-- Turning the plugin off removes everything it drew
function PluginShutdown()
    Event.MiniMenuReady.Unsubscribe("alertMenu")
    Event.Logic.Unsubscribe("alertLogic")
    Event.ServerLogic.Unsubscribe("alertServerTick")
    Event.GameStateChanged.Unsubscribe("alertGameState")
    Event.SettingsLayerReady.Unsubscribe("alertSettings")
    for _, box in pairs(overlays) do
        pcall(function() box:Destroy() end)
    end
    for _, box in ipairs(spare) do
        pcall(function() box:Destroy() end)
    end
    if window then
        pcall(function() window:Destroy() end)
    end
end

log("Alert! is on")
