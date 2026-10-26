-- Bounded scheduler for repeated per-sound mute calls.
--
-- Small catalogues are processed completely on every tick. Large catalogues
-- keep the explicitly prioritized IDs hot and rotate through the remainder.

local Scheduler = {}
Scheduler.__index = Scheduler

local FULL_PASS_LIMIT = 3000
local ROUND_ROBIN_LIMIT = 120

local function validId(value)
    if type(value) == "string" then
        return value ~= ""
    end
    return type(value) == "number"
       and value == value
       and value ~= math.huge
       and value ~= -math.huge
       and value >= 0
       and value == math.floor(value)
end

local function idKey(value)
    return type(value) .. ":" .. tostring(value)
end

local function idLess(left, right)
    local leftType = type(left)
    local rightType = type(right)
    if leftType ~= rightType then
        return leftType == "number"
    end
    return left < right
end

local function collectIds(values, label)
    if type(values) ~= "table" then
        return nil, label .. " must be a table"
    end

    local result = {}
    local seen = {}
    for _, value in pairs(values) do
        if not validId(value) then
            return nil, label .. " contains an invalid ID"
        end
        local key = idKey(value)
        if not seen[key] then
            seen[key] = true
            result[#result + 1] = value
        end
    end
    table.sort(result, idLess)
    return result, seen
end

local function summary(self)
    return {
        count = #self.ids,
        priorityCount = #self.priority,
        roundRobinCount = #self.roundRobin,
        mode = self.mode,
        callsLastTick = self.callsLastTick,
        failuresLastTick = self.failuresLastTick,
        cursor = self.cursor,
        fullPassLimit = FULL_PASS_LIMIT,
        roundRobinLimit = ROUND_ROBIN_LIMIT,
        excludedLastTick = self.excludedLastTick,
    }
end

function Scheduler.new()
    return setmetatable({
        ids = {},
        priority = {},
        roundRobin = {},
        mode = "empty",
        cursor = 1,
        callsLastTick = 0,
        failuresLastTick = 0,
        excludedLastTick = nil,
    }, Scheduler)
end

function Scheduler:set(ids, priorityIDs)
    local sorted, seenOrError = collectIds(ids, "IDs")
    if not sorted then
        return false, seenOrError
    end

    local priorities, priorityError = collectIds(priorityIDs or {}, "priority IDs")
    if not priorities then
        return false, priorityError
    end
    local idSet = seenOrError
    local prioritySet = {}
    for _, value in ipairs(priorities) do
        local key = idKey(value)
        if idSet[key] then
            prioritySet[key] = true
        end
    end

    local nextPriority = {}
    local nextRoundRobin = {}
    for _, value in ipairs(sorted) do
        if prioritySet[idKey(value)] then
            nextPriority[#nextPriority + 1] = value
        else
            nextRoundRobin[#nextRoundRobin + 1] = value
        end
    end

    self.ids = sorted
    self.priority = nextPriority
    self.roundRobin = nextRoundRobin
    self.cursor = 1
    self.callsLastTick = 0
    self.failuresLastTick = 0
    self.excludedLastTick = nil
    if #sorted == 0 then
        self.mode = "empty"
    elseif #sorted <= FULL_PASS_LIMIT then
        self.mode = "full"
    else
        self.mode = "roundRobin"
    end
    return true
end

local function callStop(stopFn, id)
    local ok, result = pcall(stopFn, id)
    if not ok or result == false then
        return false
    end
    return true
end

function Scheduler:run(stopFn, excludedID)
    if type(stopFn) ~= "function" then
        return false, "stopFn must be a function"
    end
    if excludedID ~= nil and not validId(excludedID) then
        return false, "excluded ID is invalid"
    end

    local calls = 0
    local failures = 0

    local function stopOnce(id)
        if id == excludedID then
            return
        end
        calls = calls + 1
        if not callStop(stopFn, id) then
            failures = failures + 1
        end
    end

    if self.mode == "full" then
        for _, id in ipairs(self.ids) do
            stopOnce(id)
        end
    elseif self.mode == "roundRobin" then
        for _, id in ipairs(self.priority) do
            stopOnce(id)
        end

        local count = #self.roundRobin
        local examined = 0
        local roundCalls = 0
        while count > 0 and examined < count and roundCalls < ROUND_ROBIN_LIMIT do
            local index = self.cursor
            local id = self.roundRobin[index]
            self.cursor = index + 1
            if self.cursor > count then
                self.cursor = 1
            end
            examined = examined + 1
            if id ~= excludedID then
                stopOnce(id)
                roundCalls = roundCalls + 1
            end
        end
    end

    self.callsLastTick = calls
    self.failuresLastTick = failures
    self.excludedLastTick = excludedID
    return true, {
        mode = self.mode,
        calls = calls,
        failures = failures,
        count = #self.ids,
    }
end

function Scheduler:status()
    return summary(self)
end

return Scheduler
