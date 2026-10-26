local M = {}

function M.new(name, switches, note)
    local values = {}
    for _, s in ipairs(switches) do values[s[1]] = s[3] end
    local ok, saved = pcall(function() return PersistentDB:GetStructuredData(name) end)
    if ok and type(saved) == "table" then
        for key, value in pairs(saved) do
            if type(values[key]) == "boolean" and type(value) == "boolean" then values[key] = value end
        end
    end
    local function save() pcall(function() PersistentDB:SetStructuredData(name, values) end) end

    -- The game makes the settings layer each time the cog is opened; the buttons are made inside it
    Event.SettingsLayerReady.Subscribe(name, function(event)
        local font = id.Font.MUSEO_SANS_15PT_REGULAR
        local panel = ui.Layer.new(event.component)
        panel:SetPos(8, 8)
        panel:SetSize(360, 40 + #switches * 28)
        local text = ui.Text.new(panel)
        text:SetPos(0, 0); text:SetSize(350, 40); text.font = font; text.clickthrough = true
        text.content = type(note) == "function" and note() or note or "Click a switch to turn it on or off."
        for i, s in ipairs(switches) do
            local key, label = s[1], s[2]
            local button = ui.Button.new(panel)
            button:SetPos(0, 20 + i * 28); button:SetSize(250, 24)
            button.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
            pcall(function() button.text.font = font end)
            local function refresh() button.label = label .. ": " .. (values[key] and "on" or "off") end
            refresh()
            button:Subscribe(ui.Hook.ONBUTTONPRESSED, function() values[key] = not values[key]; refresh(); save() end)
        end
    end)
    return values
end

return M
