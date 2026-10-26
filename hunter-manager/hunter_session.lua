local M = {}

local function key(row)
    return row.x .. ',' .. row.z .. ',' .. (row.plane or 0)
end

local function distance(a, b)
    return math.max(math.abs(a.x - b.x), math.abs(a.z - b.z))
end

local function signature(row)
    return row.family .. ':' .. tostring(row.id) .. ':' .. row.state
end

function M.new(types, tracker)
    local S = {
        types = types,
        tracker = tracker,
        seen = {},
        rows = {},
        range = 20,
        notice = 'Lay a trap, or open its menu and choose Track.',
    }

    function S.intent(family, tile, now, target)
        if not tile then return end
        S.pending = { family = family, tile = tile, at = now, target = target, uncertain = S.limited == true }
    end

    function S.scan(rows, now, tile, truncated, deferred)
        local groups, nextSeen, candidates, visible = {}, {}, {}, {}
        local pending = S.pending
        if pending and (now - pending.at > 10000 or pending.tile.plane ~= tile.plane) then
            S.pending = nil
            pending = nil
        end
        if pending and truncated then pending.uncertain = true end
        S.rows = {}

        -- Keep all recognised objects until their tile is resolved. A support tree may share a net's tile.
        for index = 1, math.min(#rows, 256) do
            local row = rows[index]
            local k = key(row)
            local old = tracker.traps[k]
            local info = types.classify(row, old and old.family or pending and pending.family)
            if info then
                local current = {
                    x = row.x, z = row.z, plane = row.plane, id = row.id,
                    state = info.state, family = info.family, species = info.species,
                    label = info.label, detail = info.detail,
                }
                S.rows[#S.rows + 1] = current
                groups[k] = groups[k] or {}
                groups[k][#groups[k] + 1] = current
                nextSeen[k] = nextSeen[k] or {}
                nextSeen[k][signature(current)] = true
            end
        end

        for k, group in pairs(groups) do
            local old = tracker.traps[k]
            if old then
                local active, idle = {}, {}
                for _, row in ipairs(group) do
                    if row.family == old.family then
                        local list = row.state == 'idle' and idle or active
                        list[#list + 1] = row
                    end
                end
                local matching = #active > 0 and active or idle
                if #matching == 1 then
                    local row = matching[1]
                    if old.state ~= 'collapsed' or row.state == 'collapsed' then
                        visible[k] = true
                        if row.state == 'idle' then
                            if not (deferred and deferred[k]) then
                                tracker:removed(row.x, row.z, row.plane, now, tile)
                            end
                        else
                            tracker:observe(row, now, true)
                        end
                    end
                elseif #matching > 1 and old.state ~= 'collapsed' then
                    -- Public object IDs cannot identify which of two stacked traps is owned.
                    visible[k] = true
                    tracker:observe({
                        x = old.x, z = old.z, plane = old.plane, id = old.id,
                        family = old.family, state = 'unknown',
                    }, now, true)
                end
            end

            if pending and not pending.uncertain and (not old or old.state == 'collapsed') then
                for _, row in ipairs(group) do
                    local seen = S.seen[k]
                    local changed = not (seen and seen[signature(row)])
                    if row.state ~= 'idle' and (not pending.family or pending.family == row.family)
                        and row.plane == pending.tile.plane and distance(row, pending.target or pending.tile) <= 2
                        and (not pending.target or key(pending.target) == k) and changed then
                        candidates[#candidates + 1] = row
                    end
                end
            end
        end

        -- A scan gap cannot prove disappearance or which trap changed while it was out of view.
        if not truncated then
            local missing = {}
            for k, trap in pairs(tracker.traps) do
                local inRange = trap.plane == tile.plane and distance(trap, tile) <= S.range
                if inRange and trap.state ~= 'collapsed' and not visible[k] and not (deferred and deferred[k]) then
                    missing[#missing + 1] = trap
                end
            end
            for _, trap in ipairs(missing) do
                if #missing == 1 then
                    tracker:removed(trap.x, trap.z, trap.plane, now, tile)
                else
                    tracker.traps[key(trap)] = nil
                end
            end
            if pending and pending.uncertain then
                S.notice = 'A scan was incomplete. Open your trap menu and choose Track.'
            elseif #candidates == 1 then
                if tracker:observe(candidates[1], now, true) then
                    S.pending = nil
                    S.notice = 'Tracking your ' .. candidates[1].label .. '.'
                end
            elseif #candidates > 1 then
                S.notice = 'Several traps changed. Open your trap menu and choose Track.'
            end
        else
            S.notice = 'Busy area: scan limited. Move closer to your traps.'
        end
        S.seen = nextSeen
        S.limited = truncated == true
        tracker:forget(now, tile)
    end

    function S.track(now, tile)
        local nearest, best, tied = nil, 3, false
        for _, row in ipairs(S.rows) do
            if row.plane == tile.plane and row.state ~= 'idle' then
                local d = distance(row, tile)
                if d < best then
                    nearest, best, tied = row, d, false
                elseif d == best then
                    tied = true
                end
            end
        end
        if nearest and not tied and tracker:observe(nearest, now, true) then
            S.notice = 'Marked nearest trap as yours.'
            return true
        end
        S.notice = tied and 'Two equally close traps: move beside yours.' or 'No recognised trap within two tiles.'
        return false
    end

    function S.clear()
        tracker.traps = {}
        tracker.pend = nil
        tracker.last_removed = nil
        tracker.collapse_at = nil
        tracker.dismantle_at = nil
        S.pending = nil
        S.notice = 'Trap marks cleared.'
    end

    return S
end

return M
