-- Bank Filters' local item marks. Pure client-side data; no game calls or item actions.
local M = { LIMIT = 4096 }

local function key(id)
    local number = tonumber(id)
    if number and number >= 0 and number <= 2147483647 and number == math.floor(number) then
        return string.format("%.0f", number)
    end
end

function M.load(saved)
    saved = type(saved) == "table" and saved or {}
    local result = { favourites = {}, keeps = {} }
    for kind, output in pairs(result) do
        local count, visited, source = 0, 0, saved[kind]
        if type(source) == "table" then
            for id, value in pairs(source) do
                visited = visited + 1
                if visited > M.LIMIT * 2 then break end
                local item = key(id)
                if item and value == true and not output[item] and count < M.LIMIT then
                    output[item], count = true, count + 1
                end
            end
        end
    end
    return result
end

function M.has(marks, kind, id)
    local item = key(id)
    return item ~= nil and marks[kind] ~= nil and marks[kind][item] == true
end

function M.toggle(marks, kind, id)
    local item, list = key(id), marks[kind]
    if not item or type(list) ~= "table" then return false end
    if list[item] then list[item] = nil; return true end
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    if count >= M.LIMIT then return false end
    list[item] = true
    return true
end

return M
