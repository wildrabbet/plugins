local familiar = {}

-- Warnings: the time left under which to renew, the special-move points under which the bar turns gold and red, the
-- share of points under which the whole bar flashes, and the scrolls under which to restock. The player's own choices
-- are kept by main.lua.
familiar.DEFAULTS = { renewBelow = 120, pointsHalf = 30, pointsLow = 10, flashBelow = 0.5, scrollsBelow = 20 }

-- "59:00" -> 3540 seconds; "1:05:00" -> 3900; nil for anything else.
function familiar.seconds(text)
    if type(text) ~= "string" then return nil end
    local h, m, s = text:match("^(%d+):(%d%d):(%d%d)$")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) end
    m, s = text:match("^(%d+):(%d%d)$")
    if m then return tonumber(m) * 60 + tonumber(s) end
    return nil
end

function familiar.points(text)
    if type(text) ~= "string" then return nil end
    local now, most = text:match("^(%d+)/(%d+)$")
    if now then return tonumber(now), tonumber(most) end
    return nil
end

function familiar.count(text)
    if type(text) ~= "string" then return nil end
    local digits, unit = text:gsub(",", ""):match("^(%d+%.?%d*)([KkMm]?)$")
    if not digits then return nil end
    local scale = (unit == "K" or unit == "k") and 1000 or (unit == "M" or unit == "m") and 1000000 or 1
    return math.floor(tonumber(digits) * scale + 0.5)
end

-- "61:00" or "45s" for the HUD.
function familiar.clock(seconds)
    if not seconds then return "--:--" end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function familiar.read(shown, settings)
    if not shown or not shown.name or shown.name == "" then return nil end
    local state = { name = shown.name }
    state.seconds = familiar.seconds(shown.time)
    state.points, state.pointsMax = familiar.points(shown.points)
    state.scrolls = familiar.count(shown.scrolls)
    state.pouches = familiar.count(shown.pouches)

    state.band = "normal"
    if state.points and state.points <= settings.pointsLow then state.band = "low"
    elseif state.points and state.points < settings.pointsHalf then state.band = "half" end

    state.flash = state.points ~= nil and state.pointsMax ~= nil and state.pointsMax > 0
        and state.points / state.pointsMax < settings.flashBelow
    state.renew = state.seconds ~= nil and state.seconds <= settings.renewBelow
    state.restock = state.scrolls ~= nil and state.scrolls < settings.scrollsBelow
    return state
end

return familiar
