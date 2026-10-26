local M = {}

local GAP_CAP = 120 * 50              -- client ticks (50 a second): the longest gap counted as active time
local INVENTION = 26

-- XP needed for each level, 1-120 (the standard table: a quarter of the sum of floor(l + 300 * 2^(l / 7)))
local TABLE = { [1] = 0 }
do
    local points = 0
    for level = 1, 119 do
        points = points + math.floor(level + 300 * 2 ^ (level / 7))
        TABLE[level + 1] = math.floor(points / 4)
    end
end
M.TABLE = TABLE

function M.levelFor(xp)
    local level = 1
    for l = 2, 120 do
        if xp >= TABLE[l] then level = l else break end
    end
    return level
end

-- The goals the last column can count down to, in the order a click goes round them, and their column headings
M.GOALS = { "next", "99", "120", "200M" }
M.GOAL_HEADING = { next = "TO LEVEL", ["99"] = "TO 99", ["120"] = "TO 120", ["200M"] = "TO 200M" }
local MAX_XP = 200000000

-- The XP a goal needs, for a skill at this XP; nil when it has none (Invention's levels, the level after 120)
local function goalXP(goal, skill, xp)
    if goal == "200M" then return MAX_XP end
    if skill == INVENTION then return nil end
    if goal == "99" then return TABLE[99] end
    if goal == "120" then return TABLE[120] end
    local level = M.levelFor(xp)
    return level < 120 and TABLE[level + 1] or nil
end

-- levelOf(skill) -> the level the game reports for a skill (or nil)
function M.new(levelOf)
    local X = { skills = {}, order = 0, scale = nil }

    -- The game's XP for a skill, in whole XP
    function X:whole(skill, raw)
        if not self.scale and skill ~= INVENTION then
            local level = levelOf(skill)
            if type(level) == "number" and level >= 2 and level <= 119 then
                if M.levelFor(raw) == level then
                    self.scale = 1
                elseif M.levelFor(raw / 10) == level then
                    self.scale = 10
                end
            end
        end
        return raw / (self.scale or 1)
    end

    -- An XP drop: skill number, old and new XP as the game sent them, client tick
    function X:gain(skill, oldRaw, newRaw, now)
        if type(oldRaw) ~= "number" or type(newRaw) ~= "number" or newRaw <= oldRaw then return end
        local s = self.skills[skill]
        local xp = self:whole(skill, newRaw)
        local gained = xp - self:whole(skill, oldRaw)
        if not s then
            s = { skill = skill, gained = 0, active = 0, first = now, last = now, drops = 0 }
            self.skills[skill] = s
        else
            s.active = s.active + math.min(now - s.last, GAP_CAP)
        end
        s.gained = s.gained + gained
        s.xp = xp
        s.last = now
        s.drops = s.drops + 1
        self.order = self.order + 1
        s.order = self.order
    end

    -- One skill's numbers now: gained, perHour (nil until there's active time), toGoal seconds (nil if unknown), done
    -- (already at the goal). goal: one of M.GOALS, the next level when left out
    function X:stats(s, now, goal)
        local active = s.active + math.min(now - s.last, GAP_CAP)
        local perHour = (s.drops >= 2 and active > 0) and s.gained / (active / 50) * 3600 or nil
        local toGoal, done = nil, false
        local need = s.xp and goalXP(goal or "next", s.skill, s.xp)
        if need and s.xp >= need then
            done = true
        elseif need and perHour and perHour > 0 then
            toGoal = (need - s.xp) / perHour * 3600
        end
        return { gained = s.gained, perHour = perHour, toGoal = toGoal, done = done, level = M.levelFor(s.xp or 0) }
    end

    function X:recent(n)
        local list = {}
        for _, s in pairs(self.skills) do list[#list + 1] = s end
        table.sort(list, function(a, b) return a.order > b.order end)
        while #list > n do table.remove(list) end
        return list
    end

    function X:reset()
        self.skills, self.order = {}, 0
    end

    return X
end

-- 12345 -> "12.3k"; 3725 seconds -> "1h 02m"; under an hour "45m" (not "1:02", which reads like a time of day)
function M.short(n)
    if n >= 1e6 then return (string.format("%.2fM", n / 1e6):gsub("%.?0+M$", "M")) end
    if n >= 1e3 then return (string.format("%.1fk", n / 1e3):gsub("%.0k", "k")) end
    return tostring(math.floor(n + 0.5))
end

function M.duration(seconds)
    if not seconds then return "-" end
    if seconds < 60 then return "<1m" end
    local m = math.floor(seconds / 60 + 0.5)
    if m < 60 then return m .. "m" end
    return math.floor(m / 60) .. "h " .. string.format("%02d", m % 60) .. "m"
end

return M
