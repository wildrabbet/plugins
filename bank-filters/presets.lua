-- Named item annotations only. No game calls, inventory actions or bank loadouts.
local P = { LIMIT = 8, ITEM_LIMIT = 4096 }
P.COLOURS = {
    { "Cyan", { 0.25, 0.85, 1, 1 } }, { "Gold", { 1, 0.82, 0.30, 1 } },
    { "Violet", { 0.74, 0.48, 1, 1 } }, { "Green", { 0.40, 0.95, 0.45, 1 } },
    { "Pink", { 1, 0.45, 0.75, 1 } }, { "Orange", { 1, 0.60, 0.25, 1 } },
    { "White", { 1, 1, 1, 1 } }, { "Blue", { 0.40, 0.60, 1, 1 } },
}
local function integer(n, maximum)
    return type(n) == "number" and n >= 1 and n <= maximum and n == math.floor(n)
end
local function itemKey(id)
    id = tonumber(id)
    if integer(id, 2147483647) then return string.format("%.0f", id) end
end
function P.find(state, id)
    for _, preset in ipairs(state.entries) do if preset.id == id then return preset end end
end
function P.count(preset)
    local n = 0
    for _ in pairs(preset.items) do n = n + 1 end
    return n
end
function P.has(preset, id) return preset.items[itemKey(id) or ""] == true end

-- Restrict names to plain text so they cannot inject menu formatting. The short tag is independently editable.
local function fields(state, id, name, label, colour, textColour)
    if type(name) ~= "string" or type(label) ~= "string" then return nil, "Enter a name and tag." end
    name, label = name:match("^%s*(.-)%s*$"), label:upper():match("^%s*(.-)%s*$")
    if #name < 1 or #name > 24 or name:find("[^%w %-%_'&%(%)%/]") then
        return nil, "Name: 1-24 plain text characters."
    end
    if #label < 1 or #label > 4 or label:find("[^A-Z0-9]") then return nil, "Tag: 1-4 letters or numbers." end
    if not integer(colour, #P.COLOURS) then return nil, "Choose a colour." end
    if not integer(textColour, #P.COLOURS) then return nil, "Choose a text colour." end
    for _, preset in ipairs(state.entries) do
        if preset.id ~= id and preset.name:lower() == name:lower() then return nil, "That preset name already exists." end
    end
    return { name = name, label = label, colour = colour, textColour = textColour }
end
function P.save(state, id, name, label, colour, textColour)
    local current = P.find(state, id)
    if textColour == nil then textColour = current and current.textColour or 7 end -- White for older presets.
    local value, problem = fields(state, id, name, label, colour, textColour)
    if not value then return nil, problem end
    local preset = P.find(state, id)
    if id and not preset then return nil, "That preset was deleted." end
    if not preset then
        if #state.entries >= P.LIMIT or state.nextID >= 2147483647 then return nil, "Eight presets is the limit." end
        preset = { id = state.nextID, enabled = true, items = {} }
        state.nextID = state.nextID + 1
        state.entries[#state.entries + 1] = preset
    end
    preset.name, preset.label, preset.colour = value.name, value.label, value.colour
    preset.textColour = value.textColour
    return preset
end
function P.setItem(state, id, objectID, present)
    local preset, key = P.find(state, id), itemKey(objectID)
    if not preset or not key then return false, "Preset or item is no longer available." end
    if present and not preset.items[key] and P.count(preset) >= P.ITEM_LIMIT then return false, "Preset item limit reached." end
    preset.items[key] = present and true or nil
    return true
end
function P.delete(state, id)
    for i, preset in ipairs(state.entries) do
        if preset.id == id then
            table.remove(state.entries, i)
            if state.focus == id then state.focus = nil end
            return true
        end
    end
    return false
end
function P.match(state, objectID)
    for _, preset in ipairs(state.entries) do
        if preset.enabled and (not state.focus or state.focus == preset.id) and P.has(preset, objectID) then return preset end
    end
end
function P.load(saved)
    local state = { entries = {}, nextID = 1 }
    if type(saved) ~= "table" then return state end
    local used, highest = {}, 0
    for i = 1, P.LIMIT do
        local value = type(saved.entries) == "table" and saved.entries[i]
        if type(value) == "table" and integer(value.id, 2147483646) and not used[value.id] then
            local textColour = integer(value.textColour, #P.COLOURS) and value.textColour or 7
            local valid = fields(state, value.id, value.name, value.label, value.colour, textColour)
            if valid then
                local preset = { id = value.id, name = valid.name, label = valid.label, colour = valid.colour,
                                 textColour = textColour, enabled = value.enabled ~= false, items = {} }
                local visited, count = 0, 0
                for id, marked in pairs(type(value.items) == "table" and value.items or {}) do
                    visited = visited + 1
                    if visited > P.ITEM_LIMIT * 2 then break end
                    local key = itemKey(id)
                    if key and marked == true and not preset.items[key] and count < P.ITEM_LIMIT then
                        preset.items[key], count = true, count + 1
                    end
                end
                state.entries[#state.entries + 1], used[value.id] = preset, true
                highest = math.max(highest, value.id)
            end
        end
    end
    state.nextID = math.max(highest + 1, integer(saved.nextID, 2147483647) and saved.nextID or 1)
    if P.find(state, saved.focus) then state.focus = saved.focus end
    return state
end
return P
