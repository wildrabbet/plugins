-- Only personal planner preferences are saved. Live stock stays in memory.
-- Saved tables are validated instead of trusting an old or interrupted write.
local State = {}

function State.number(text, maximum, allowBlank)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text == "" and allowBlank then
        return nil
    end
    if text:find(",", 1, true) then
        local groups = {}
        for group in text:gmatch("[^,]+") do
            groups[#groups + 1] = group
        end
        local valid = table.concat(groups, ",") == text
            and #groups > 1
            and #groups[1] >= 1
            and #groups[1] <= 3
        for index, group in ipairs(groups) do
            if not group:match("^%d+$") or (index > 1 and #group ~= 3) then
                valid = false
            end
        end
        if not valid then
            return nil, "Use commas in groups of three digits, such as 1,000."
        end
        text = table.concat(groups)
    end
    if not text:match("^%d+$") then
        return nil, "Enter a whole number, without a minus sign."
    end
    local value = tonumber(text)
    if not value or value > maximum then
        return nil, "The maximum is " .. tostring(maximum) .. "."
    end
    return value
end

function State.load(saved, items, catalogue)
    local result = {
        version = 1,
        favourites = {},
        prices = {},
        batches = 1,
        recursive = true,
        buyUnfinished = false,
        cleanHerbs = false,
        hidden = false,
        position = "left",
    }
    if type(saved) ~= "table" then
        return result
    end
    result.buyUnfinished = saved.buyUnfinished == true
    result.cleanHerbs = saved.cleanHerbs == true
    if type(saved.reopenPosition) == "table" then
        local x = State.number(saved.reopenPosition.x, 2147483647)
        local y = State.number(saved.reopenPosition.y, 2147483647)
        if x and y then
            result.reopenPosition = { x = x, y = y }
        end
    end
    local known = {}
    for _, entry in ipairs(catalogue) do
        known[entry.key] = true
    end
    if type(saved.favourites) == "table" then
        for key, enabled in pairs(saved.favourites) do
            if known[key] and enabled == true then
                result.favourites[key] = true
            end
        end
    end
    if type(saved.prices) == "table" then
        for key, value in pairs(saved.prices) do
            if items[key] and type(value) == "number" then
                local amount = State.number(value, 2147483647)
                if amount then
                    result.prices[key] = amount
                end
            end
        end
    end
    if type(saved.batches) == "number" then
        local amount = State.number(saved.batches, 100000)
        if amount and amount >= 1 then
            result.batches = amount
        end
    end
    if type(saved.hidden) == "boolean" then
        result.hidden = saved.hidden
    end
    if type(saved.recursive) == "boolean" then
        result.recursive = saved.recursive
    end
    if saved.position == "centre" or saved.position == "right" then
        result.position = saved.position
    end
    if known[saved.selected] then
        result.selected = saved.selected
    end
    return result
end

return State
