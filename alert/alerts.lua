local Alerts = {}

Alerts.TICKS_PER_SECOND = 50
Alerts.PULSE_TICKS = 100          -- one slow pulse: 2 seconds
Alerts.RING_TICKS = 500           -- a timer alert pulses for 10 seconds after it ends, then goes away
Alerts.FLASH_TICKS = 24           -- a game-tick flash fades out in 0.48 seconds (a game tick is 0.6)
Alerts.MIN_FLASH_GAP = 20         -- no new flash until 0.4 seconds after the last one
Alerts.MAX_ALERTS = 28            -- one per backpack slot
Alerts.MAX_SECONDS = 24 * 60 * 60 -- the longest timer: a day
Alerts.MINUTE_TICKS = 3000        -- the tick check measures one minute at a time

local PEAK = 0.7                  -- the brightest a pulse gets (0 = clear, 1 = solid white)
local FLOOR = 0.1                 -- the dimmest point of a slow pulse
local HINT = "Try 30s, 5m, 2h or 1h30m."

-- Reading the time ------------------------------------------------------------------------------------------------

-- "30s", "5m", "2h", "1h30m", "1h 30m 10s" -> seconds. Hours, then minutes, then seconds, each at most once.
-- Returns nil and a short message the player can read when the text is not a time.
function Alerts.parseTime(text)
    local s = (tostring(text or ""):lower():gsub("%s+", ""))
    if s == "" then
        return nil, "Type a time first. " .. HINT
    end
    local rank = { h = 1, m = 2, s = 3 }
    local worth = { h = 3600, m = 60, s = 1 }
    local total, last, pos = 0, 0, 1
    while pos <= #s do
        local digits, unit, after = s:match("^(%d+)([hms])()", pos)
        if not digits or #digits > 5 or rank[unit] <= last then
            return nil, HINT
        end
        last = rank[unit]
        total = total + tonumber(digits) * worth[unit]
        pos = after
    end
    if total < 1 then
        return nil, "That is no time at all. " .. HINT
    end
    if total > Alerts.MAX_SECONDS then
        return nil, "The longest is 24h."
    end
    return total
end

-- The alerts ------------------------------------------------------------------------------------------------------

local Model = {}
Model.__index = Model

function Alerts.new()
    return setmetatable({ byKey = {}, order = {}, lastServerAt = nil, minuteStart = nil, serverCount = 0,
                          minGap = nil, maxGap = nil, check = nil }, Model)
end

function Model:count()
    return #self.order
end

function Model:get(key)
    return self.byKey[key]
end

-- Every alert, in the order they were set (do not change the list)
function Model:all()
    return self.order
end

function Model:add(key, kind, now, seconds, label, info, colour)
    local old = self.byKey[key]
    if not old and #self.order >= Alerts.MAX_ALERTS then
        return nil, "Every backpack slot already has an alert."
    end
    local alert = { key = key, kind = kind, label = label, info = info, setAt = now, colour = colour or { 1, 1, 1 } }
    if kind == "timer" then
        alert.state = "waiting"
        alert.dueAt = now + seconds * Alerts.TICKS_PER_SECOND
    else
        alert.state = "ticking"          -- flashes from the next server tick
    end
    if old then
        for i, existing in ipairs(self.order) do
            if existing == old then
                self.order[i] = alert
            end
        end
    else
        self.order[#self.order + 1] = alert
    end
    self.byKey[key] = alert
    return alert
end

function Model:clear(key)
    local alert = self.byKey[key]
    if not alert then
        return false
    end
    self.byKey[key] = nil
    for i, existing in ipairs(self.order) do
        if existing == alert then
            table.remove(self.order, i)
            break
        end
    end
    return true
end

function Model:clearAll()
    self.byKey = {}
    self.order = {}
end

-- Called every logic tick. Timers that have just ended start pulsing, and pulses that have run their 10 seconds go
-- away. Returns the alerts that just started pulsing, then the ones that just went away.
function Model:step(now)
    local rang, expired = {}, {}
    local snapshot = {}                  -- clearing an alert changes self.order, so walk a copy
    for i, alert in ipairs(self.order) do
        snapshot[i] = alert
    end
    for _, alert in ipairs(snapshot) do
        if alert.state == "waiting" and now >= alert.dueAt then
            alert.state = "ringing"
            alert.ringAt = alert.dueAt
            rang[#rang + 1] = alert
        end
        if alert.state == "ringing" and now - alert.ringAt >= Alerts.RING_TICKS then
            self:clear(alert.key)
            expired[#expired + 1] = alert
        end
    end
    return rang, expired
end

-- How bright an alert's white pulse is right now, 0 to 0.7 (0 = nothing drawn)
function Model:alpha(alert, now)
    if alert.state == "ringing" then
        local phase = ((now - alert.ringAt) % Alerts.PULSE_TICKS) / Alerts.PULSE_TICKS
        return FLOOR + (PEAK - FLOOR) * (0.5 - 0.5 * math.cos(2 * math.pi * phase))
    end
    if alert.state == "ticking" and alert.lastPulse then
        local age = now - alert.lastPulse
        if age >= 0 and age < Alerts.FLASH_TICKS then
            return PEAK * (1 - age / Alerts.FLASH_TICKS)
        end
    end
    return 0
end

-- Seconds left on a waiting timer (0 once it has ended)
function Model:secondsLeft(alert, now)
    if alert.state ~= "waiting" then
        return 0
    end
    return math.max(0, (alert.dueAt - now) / Alerts.TICKS_PER_SECOND)
end

function Model:serverTick(now)
    local gap = self.lastServerAt and (now - self.lastServerAt) or nil
    self.lastServerAt = now
    if not self.minuteStart then
        self.minuteStart, self.serverCount = now, 0
    elseif now - self.minuteStart >= Alerts.MINUTE_TICKS then
        self.check = { ticks = self.serverCount, span = now - self.minuteStart, minGap = self.minGap, maxGap = self.maxGap }
        self.minuteStart, self.serverCount, self.minGap, self.maxGap = now, 0, nil, nil
    end
    self.serverCount = self.serverCount + 1
    if gap then
        self.minGap = self.minGap and math.min(self.minGap, gap) or gap
        self.maxGap = self.maxGap and math.max(self.maxGap, gap) or gap
    end
    if self.lastFlashAt and now - self.lastFlashAt < Alerts.MIN_FLASH_GAP then
        return
    end
    self.lastFlashAt = now
    for _, alert in ipairs(self.order) do
        if alert.kind == "tick" then
            alert.lastPulse = now
        end
    end
end

-- Starts the tick check again (after a logout, when no server ticks arrive)
function Model:resetCheck()
    self.lastServerAt, self.lastFlashAt = nil, nil
    self.minuteStart, self.serverCount, self.minGap, self.maxGap, self.check = nil, 0, nil, nil, nil
end

-- The tick check in words: server ticks counted over the last whole minute, and the shortest and longest gaps between
-- two of them. A perfect minute is 100 server ticks, with every gap 30 logic ticks. (A gap of 0 to 19 is a packet that
-- came close behind another one: it is counted here but does not flash.)
function Model:checkText()
    local c = self.check
    if not c then
        return "Tick check: counting the first minute..."
    end
    local seconds = c.span / Alerts.TICKS_PER_SECOND
    return string.format("Tick check: %d server ticks in %.1f s (100 in 60 is perfect). Gaps %s to %s logic ticks (30 is exact).",
                         c.ticks, seconds, tostring(c.minGap or "?"), tostring(c.maxGap or "?"))
end

return Alerts
