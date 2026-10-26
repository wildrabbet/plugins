local P = require("presets")
local M = {}
function M.new(parent, state, changed, allowed)
    local window, message, generation = nil, nil, 0
    local api = {}
    function api.close()
        generation = generation + 1
        if window then window.hidden = true; window:Destroy(); window = nil end
    end
    local function page(title, x, y)
        api.close()
        window = ui.Layer.new(parent)
        window:SetPos(x, y); window:SetSize(360, 370)
        window.clickthrough = false
        local background = ui.Rectangle.new(window)
        background:SetSize(360, 370); background.fill = true; background.clickthrough = false
        background.colour = Vector4.new(0.055, 0.065, 0.085, 0.99)
        local token = generation
        local function text(content, px, py, width)
            local t = ui.Text.new(window)
            t:SetPos(px, py); t:SetSize(width or 336, 26)
            t.font = id.Font.MUSEO_SANS_15PT_REGULAR; t.content = content; t.clickthrough = true
            return t
        end
        local function button(label, px, py, width, callback)
            local b = ui.Button.new(window)
            b:SetPos(px, py); b:SetSize(width, 24); b.label = label; b.clickthrough = false
            b.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
            b:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
                if token == generation and allowed() then callback() end
            end)
            return b
        end
        text(title, 12, 10, 290)
        button("X", 320, 8, 28, api.close)
        message = text("", 12, 336)
        window:MoveToFront()
        return text, button, token
    end
    function api.edit(presetID, seed, x, y)
        if not allowed() then return end
        local preset = P.find(state, presetID)
        if presetID and not preset then return end
        local text, button, token = page(preset and "Edit preset" or "New preset", x, y)
        local name, label = preset and preset.name or "", preset and preset.label or ""
        local colour = preset and preset.colour or (#state.entries % #P.COLOURS + 1)
        local textColour = preset and preset.textColour or 7
        -- Input callbacks update the draft only; focus loss or Escape never saves it.
        local function field(value, top, onChange)
            local f = ui.InputField.new(window)
            f:SetPos(12, top); f:SetSize(336, 26); f.content = value; f.clickthrough = false
            f.stylesheetID = id.StyleSheet.INPUT_DEFAULT
            f:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, _, contents)
                if token == generation then onChange(tostring(contents or "")) end
            end)
            return f
        end
        text("Name (up to 24 characters)", 12, 42)
        field(name, 68, function(v) name = v end)
        text("Tag on the item (1-4 letters or numbers)", 12, 100)
        field(label, 126, function(v) label = v end)
        local swatch = ui.Rectangle.new(window)
        swatch:SetPos(310, 166); swatch:SetSize(36, 24); swatch.fill = true; swatch.clickthrough = true
        local colourButton
        local function showColour()
            colourButton.label = "Border: " .. P.COLOURS[colour][1]
            local c = P.COLOURS[colour][2]; swatch.colour = Vector4.new(c[1], c[2], c[3], c[4])
        end
        colourButton = button("", 12, 166, 288, function()
            colour = colour % #P.COLOURS + 1; showColour()
            if preset then preset.colour = colour; changed() end
        end)
        showColour()
        -- Text and border are independent. Preview the selected text colour against the same dark backing.
        local preview = text("Aa", 310, 198, 36)
        local textButton
        local function showTextColour()
            textButton.label = "Text: " .. P.COLOURS[textColour][1]
            local c = P.COLOURS[textColour][2]; preview.colour = Vector4.new(c[1], c[2], c[3], c[4])
        end
        textButton = button("", 12, 198, 288, function()
            textColour = textColour % #P.COLOURS + 1; showTextColour()
            if preset then preset.textColour = textColour; changed() end
        end)
        showTextColour()
        button("Save", 12, 230, 162, function()
            local saved, problem = P.save(state, presetID, name, label, colour, textColour)
            if not saved then message.content = problem; return end
            if seed then P.setItem(state, saved.id, seed, true) end
            changed(); api.close()
        end)
        button(preset and "Close" or "Cancel", 186, 230, 162, api.close)
        if preset then
            message.content = "Colours apply and save immediately."
            local visibility
            visibility = button("Markers: " .. (preset.enabled and "on" or "off"), 12, 266, 162, function()
                preset.enabled = not preset.enabled
                visibility.label = "Markers: " .. (preset.enabled and "on" or "off"); changed()
            end)
            local focus
            focus = button(state.focus == presetID and "Show all presets" or "Only this preset", 186, 266, 162, function()
                state.focus = state.focus ~= presetID and presetID or nil
                preset.enabled = true; visibility.label = "Markers: on"
                focus.label = state.focus == presetID and "Show all presets" or "Only this preset"; changed()
            end)
            local armed, remove = false, nil
            remove = button("Delete preset", 12, 302, 162, function()
                if not armed then armed = true; remove.label = "Confirm delete"; return end
                P.delete(state, presetID); changed(); api.manage(x, y)
            end)
            button("Back to presets", 186, 302, 162, function() api.manage(x, y) end)
        end
    end
    function api.manage(x, y)
        if not allowed() then return end
        local text, button = page("Your item presets", x, y)
        text("Choose a preset to rename, recolour or delete.", 12, 42)
        for i, preset in ipairs(state.entries) do
            button(preset.name .. " (" .. P.count(preset) .. ")", 12, 70 + (i - 1) * 28, 336,
                   function() api.edit(preset.id, nil, x, y) end)
        end
        if #state.entries < P.LIMIT then button("New preset", 12, 302, 162, function() api.edit(nil, nil, x, y) end) end
        button("Show all presets", 186, 302, 162, function() state.focus = nil; changed(); api.manage(x, y) end)
    end
    return api
end
return M
