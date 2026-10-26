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

function M.new(types, tracker, ground)
    local pending = {}
    local P = {}

    local function bagCount(id)
        local ok, count = pcall(function()
            local bag = Inventory.Find(93) -- Public backpack inventory; no other inventory is inspected.
            if bag and bag.valid then return bag:GetTotal(id) end
        end)
        if ok and quantity(count) then return count end
    end

    function P.take(data, now, player)
        local item = data and data.config and types.item(data.config.id)
        local stack = data and data.entity
        if not item or not stack then return end
        local ok, target = pcall(function()
            if not stack.isValid then return end
            local p = stack.coordGrid
            if not p or not integer(p.x) or not integer(p.z) or not integer(p.level) then return end
            return { x = p.x, z = p.z, plane = p.level }
        end)
        if not ok or not target then return end
        local trap = tracker.traps[key(target)]
        if not trap or trap.state ~= 'collapsed' or trap.family ~= item.family or player.plane ~= target.plane then
            return
        end
        -- A saved menu may refer to equipment that has already left this selected stack.
        local selected = ground.itemCount(stack, target, data.config.id)
        if not selected or selected <= 0 then return end
        local before, onGround = bagCount(data.config.id), ground.count(target, item.family)
        if before == nil or onGround == nil or onGround < selected then return end
        if #pending == 16 then table.remove(pending, 1) end
        pending[#pending + 1] = {
            target = target, trap = trap, id = data.config.id, family = item.family, before = before, at = now,
        }
    end

    function P.tick(now, player)
        for index = #pending, 1, -1 do
            local request = pending[index]
            local target = request.target
            local current = tracker.traps[key(target)]
            if now - request.at > 15000 or current ~= request.trap or player.plane ~= target.plane
                or current.state ~= 'collapsed' or current.family ~= request.family then
                table.remove(pending, index)
            elseif math.max(math.abs(player.x - target.x), math.abs(player.z - target.z)) <= 2 then
                local count = bagCount(request.id)
                if count and count > request.before and ground.count(target, request.family) == 0 then
                    tracker.traps[key(target)] = nil
                    table.remove(pending, index)
                end
            end
        end
    end

    function P.clear()
        pending = {}
    end

    return P
end

return M
