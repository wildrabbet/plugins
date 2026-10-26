local M = {}

local function integer(value)
    return type(value) == 'number' and value == math.floor(value) and math.abs(value) ~= math.huge
end

local function quantity(value)
    return integer(value) and value >= 0 and value <= 9007199254740991
end

local function key(p)
    return p.x .. ',' .. p.z .. ',' .. p.plane
end

local function stackCount(stack, target, matches)
    if not stack.isValid then return 0 end
    local p = stack.coordGrid
    if not p or not integer(p.x) or not integer(p.z) or not integer(p.level) then return end
    if p.x ~= target.x or p.z ~= target.z or p.level ~= target.plane then return 0 end
    local size = stack.stackSize
    if not quantity(size) or size > 64 then return end
    local total = 0
    for index = 1, size do
        local entry = stack:GetEntry(index)
        if not entry then return end
        local id, count = entry.configID, entry.count
        if not quantity(id) or not quantity(count) then return end
        if matches(id) then
            total = total + count
            if not quantity(total) then return end
        end
    end
    return total
end

function M.new(types, tracker)
    local G = {}
    local previous, counts, missing = {}, {}, {}

    function G.itemCount(stack, target, itemID)
        local ok, count = pcall(stackCount, stack, target, function(id) return id == itemID end)
        if ok then return count end
    end

    function G.count(target, family)
        local ok, count = pcall(function()
            local grid = CoordGrid.new(target.plane, math.floor(target.x / 64), math.floor(target.z / 64),
                target.x % 64, target.z % 64)
            local stacks = ObjStackList.ByDistance(grid, 0)
            if not stacks or #stacks > 16 then return end
            local total = 0
            for _, stack in ipairs(stacks) do
                local amount = stackCount(stack, target, function(id)
                    local item = types.item(id)
                    return item and item.family == family
                end)
                if amount == nil then return end
                total = total + amount
                if not quantity(total) then return end
            end
            return total
        end)
        if ok then return count end
    end

    function G.before(rows, now, player, limited)
        counts = {}
        local occupied, deferred = {}, {}
        for _, row in ipairs(rows) do
            local own = tracker.traps[key(row)]
            local info = types.classify(row, own and own.family)
            if own and info and info.family == own.family and info.state ~= 'idle' then
                occupied[key(row)] = true
            end
        end
        for k, trap in pairs(tracker.traps) do
            if trap.plane == player.plane
                and math.max(math.abs(trap.x - player.x), math.abs(trap.z - player.z)) <= 20 then
                local count = G.count(trap, trap.family)
                if count == nil then
                    counts[k] = false
                else
                    counts[k] = count
                end
                local old = previous[k]
                local state
                if not occupied[k] and trap.state ~= 'collapsed' and count == nil then
                    -- Do not let the short missing-scenery grace period turn a read failure into disappearance.
                    state = 'unknown'
                    deferred[k] = true
                    missing[k] = nil
                elseif not limited and not occupied[k] and trap.state ~= 'collapsed'
                    and old and old.trap == trap and old.family == trap.family and now - old.at <= 3600 then
                    if count > old.count then
                        state = 'collapsed'
                        missing[k] = nil
                    else
                        missing[k] = missing[k] or now
                        if now - missing[k] < 2400 then
                            state = 'unknown'
                            deferred[k] = true
                        end
                    end
                else
                    missing[k] = nil
                end
                if state then
                    tracker:observe({
                        x = trap.x, z = trap.z, plane = trap.plane, id = trap.id,
                        family = trap.family, state = state,
                    }, now, true)
                end
            end
        end
        return deferred
    end

    function G.after(now, player)
        local nextPrevious = {}
        for k, trap in pairs(tracker.traps) do
            if trap.state ~= 'collapsed' and trap.plane == player.plane
                and math.max(math.abs(trap.x - player.x), math.abs(trap.z - player.z)) <= 20 then
                if (missing[k] or counts[k] == false) and previous[k] and previous[k].trap == trap then
                    nextPrevious[k] = previous[k]
                else
                    local count = counts[k]
                    if count == nil then count = G.count(trap, trap.family) end
                    if type(count) == 'number' then
                        nextPrevious[k] = { trap = trap, family = trap.family, count = count, at = now }
                    end
                end
            end
        end
        previous = nextPrevious
        for k in pairs(missing) do
            if not tracker.traps[k] then missing[k] = nil end
        end
    end

    function G.clear()
        previous, counts, missing = {}, {}, {}
    end

    return G
end

return M
