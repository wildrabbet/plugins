local M = {}

local function integer(value)
    return type(value) == 'number' and value == math.floor(value) and math.abs(value) ~= math.huge
end

function M.new(types, session)
    local O = {}

    local function raw(loc)
        local ok, row, incomplete = pcall(function()
            if not loc.isValid or loc.isHidden then return end
            local p = loc.coordGrid
            local objectID = loc.configID
            if not p or not integer(p.x) or not integer(p.z) or not integer(p.level)
                or not integer(objectID) or objectID < 0 then
                return nil, true
            end
            return {
                x = p.x, z = p.z, plane = p.level, id = objectID, parentID = loc.parentConfigID,
                name = loc.displayName, ops = loc.config and loc.config.opNames or {},
            }
        end)
        if not ok then return nil, true end
        return row, incomplete
    end

    function O.near(grid)
        local visited, limited = 0, false
        local list = LocList.Filter({
            coordGrid = grid, range = session.range, sameLevel = true,
            func = function(loc)
                visited = visited + 1
                if visited > 2048 then
                    limited = true
                    return false
                end
                local row, incomplete = raw(loc)
                if incomplete then limited = true end
                if not row then return false end
                local own = session.tracker.traps[row.x .. ',' .. row.z .. ',' .. row.plane]
                return types.classify(row, own and own.family or session.pending and session.pending.family) ~= nil
            end,
        })
        limited = limited or #list > 256
        local rows, protected = {}, {}

        local function key(row)
            return row.x .. ',' .. row.z .. ',' .. row.plane
        end

        local function add(row)
            if row and #rows < 256 then rows[#rows + 1] = row end
        end

        -- Exact reads keep owned traps current during a clipped search, within the same scan radius and level.
        if limited then
            for _, trap in pairs(session.tracker.traps) do
                if trap.plane == grid.level
                    and math.max(math.abs(trap.x - grid.x), math.abs(trap.z - grid.z)) <= session.range then
                    local row = O.at(trap)
                    if row then
                        add(row)
                        protected[key(row)] = true
                    end
                end
            end
        end
        for index = 1, math.min(#list, 256) do
            local row, incomplete = raw(list[index])
            if incomplete then limited = true end
            if row and not protected[key(row)] then add(row) end
        end
        return rows, limited
    end

    function O.at(target, sourceID)
        local grid = CoordGrid.new(target.plane, math.floor(target.x / 64), math.floor(target.z / 64),
            target.x % 64, target.z % 64)
        local list = LocList.ByDistance(grid, 0, true)
        if #list > 32 then return end
        local found
        for _, loc in ipairs(list) do
            local row, incomplete = raw(loc)
            if incomplete then return end
            if row and (sourceID == nil or row.id == sourceID or row.parentID == sourceID) then
                local info = types.classify(row, target.family)
                if info and (not target.family or info.family == target.family) and info.state ~= 'idle' then
                    if found then return end
                    row.state, row.family, row.species = info.state, info.family, info.species
                    row.label, row.detail, row.sourceID = info.label, info.detail, sourceID
                    found = row
                end
            end
        end
        return found
    end

    return O
end

return M
