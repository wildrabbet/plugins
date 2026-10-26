-- Ambient Sound Muffler 0.1.2
-- Turns down or blocks the game's ambient sound, or silences single sounds.

local RetroUI = require("retro_ui")
local Ambient = require("ambience")
local Scheduler = require("scheduler")
local C = RetroUI.COLOURS
local P = RetroUI.P

local SMALL_GROUP_LIMIT = 128        -- priority when a large selection rotates
local ROWS, ROW_H = 9, 24

local function get(fn)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
end

-- The game's sound names, in ID order (line N of the data = sound ID N) ------------------------------------------

local names = {}
for part = 1, 99 do
    local ok, data = pcall(require, string.format("data/sounds%02d", part))
    if not ok or type(data) ~= "table" or type(data[1]) ~= "string" then
        break
    end
    for name in data[1]:gmatch("[^\n]+") do
        names[#names + 1] = name
    end
end

-- Resolve current IDs. A missing name must never target a guessed list position.
local positionOf = {}
for index, name in ipairs(names) do
    positionOf[name] = index
end
local resolvedIDs = {}
local namesByID = {}
local function idOf(name)
    if resolvedIDs[name] ~= nil then
        return resolvedIDs[name] or nil
    end
    local value = get(function() return id.Sound[name] end)
    if type(value) == "number" and value > 0 and value < 2147483648
        and value == math.floor(value) then
        resolvedIDs[name] = value
        namesByID[value] = name
        return value
    end
    resolvedIDs[name] = false
end

-- "CAT_MIAOW_1" -> "Cat miaow 1"
local function pretty(name)
    local text = name:gsub("^_+", ""):gsub("_", " "):lower()
    return (text:gsub("^%l", string.upper))
end

-- Groups: every sound whose name matches one of the patterns ---------------------------------------------------------

-- A group can also match by word: every word in the name (letters only) that contains `word`, except the words in
-- `except` (WIND catches HOWLING_WIND and WHIRLWIND, but not WINDOW or WINDMILL).
local GROUPS = {
    { key = "cats", label = "Cats", patterns = { "^CAT_", "_CAT_", "^KITTEN", "_KITTEN" } },
    { key = "zombies", label = "Zombies", patterns = { "ZOMBIE" } },
    { key = "wind", label = "Wind", word = "WIND",
      except = { WINDOW = true, WINDOWS = true, WINDMILL = true, WINDMILLS = true, WINDUP = true, REWIND = true,
                 WINDCHIME = true, WINDCHIMES = true, WINDTOWNMIK = true } },
    { key = "chimes", label = "Wind chimes", patterns = { "WINDCHIME" } },
    { key = "dogs", label = "Dogs", patterns = { "^DOG_", "_DOG_", "^PUPPY", "_PUPPY" } },
    { key = "birds", label = "Seagulls and birds",
      words = { GULL = true, GULLS = true, SEAGULL = true, SEAGULLS = true },
      patterns = { "SEAGULL", "PIGEON", "^CROW_", "_CROW_", "^BIRD_",
                                                               "_BIRD_", "PARROT" } },
    { key = "farm", label = "Farm animals", patterns = { "^COW_", "_COW_", "^SHEEP", "_SHEEP", "^CHICKEN", "_CHICKEN",
                                                        "^PIG_", "_PIG_", "^DUCK_", "_DUCK_" } },
    { key = "frogs", label = "Frogs", patterns = { "FROG" } },
    { key = "moans", label = "Moans and ghosts", patterns = { "MOAN", "GHOST" } },
    { key = "gulls", label = "Gulls",
      words = { GULL = true, GULLS = true, SEAGULL = true, SEAGULLS = true } },
}
local function inGroup(group, name)
    if group.words then
        for word in name:gmatch("%u+") do
            if group.words[word] then
                return true
            end
        end
    end
    for _, pattern in ipairs(group.patterns or {}) do
        if name:find(pattern) then
            return true
        end
    end
    if group.word then
        for word in name:gmatch("%u+") do
            if word:find(group.word, 1, true) and not group.except[word] then
                return true
            end
        end
    end
    return false
end
for _, group in ipairs(GROUPS) do
    group.names = {}
    for _, name in ipairs(names) do
        if inGroup(group, name) then
            group.names[#group.names + 1] = name
        end
    end
end

-- Saved choices ------------------------------------------------------------------------------------------------------

local state = {
    on = true,
    sounds = {},
    allowSounds = {},
    groups = {},
    hidden = false,
    x = nil,
    y = nil,
    ambience = "normal",
}
local AMBIENCE = { normal = "NORMAL", muffled = "MUFFLED", blocked = "BLOCKED" }
local saved = get(function() return PersistentDB:GetStructuredData("muffler") end)
if type(saved) == "table" then
    if type(saved.on) == "boolean" then state.on = saved.on end
    if AMBIENCE[saved.ambience] then state.ambience = saved.ambience end
    if type(saved.hidden) == "boolean" then state.hidden = saved.hidden end
    if type(saved.x) == "number" and type(saved.y) == "number"
        and math.abs(saved.x) < 100000 and math.abs(saved.y) < 100000 then
        state.x = saved.x
        state.y = saved.y
    end
    for _, name in ipairs(type(saved.sounds) == "table" and saved.sounds or {}) do
        if type(name) == "string" and positionOf[name] then state.sounds[name] = true end
    end
    for _, key in ipairs(type(saved.groups) == "table" and saved.groups or {}) do
        for _, group in ipairs(GROUPS) do
            if key == group.key then
                state.groups[key] = true
            end
        end
    end
    for _, name in ipairs(type(saved.allowSounds) == "table" and saved.allowSounds or {}) do
        if type(name) == "string" and positionOf[name] then
            state.allowSounds[name] = true
            state.sounds[name] = nil
        end
    end
end

local savePending = false
local function save()
    local sounds, groups, allowed = {}, {}, {}
    for name in pairs(state.sounds) do sounds[#sounds + 1] = name end
    for key in pairs(state.groups) do groups[#groups + 1] = key end
    for name in pairs(state.allowSounds) do allowed[#allowed + 1] = name end
    table.sort(sounds)
    table.sort(groups)
    table.sort(allowed)
    local ok, accepted = pcall(function()
        return PersistentDB:SetStructuredData("muffler", {
            on = state.on,
            hidden = state.hidden,
            x = state.x,
            y = state.y,
            sounds = sounds,
            allowSounds = allowed,
            groups = groups,
            ambience = state.ambience,
        })
    end)
    savePending = not ok or accepted == false
end

-- The controller saves a durable recovery value before changing volume.
local ambient = get(function() return game.options.VolumeBackgroundEffects end)
local ambientControl = Ambient.new(ambient, PersistentDB)
local function applyAmbience()
    ambientControl:apply(state.ambience, state.on)
end
applyAmbience()

-- The muted IDs: every muted sound plus every sound in a muted group
local muted = {}                     -- list of IDs
local mutedCount = 0
local mutedNames = {}
local unresolvedCount = 0
local scheduler = Scheduler.new()
local function rebuild()
    local seen = {}
    local priority = {}
    muted = {}
    mutedNames = {}
    unresolvedCount = 0
    local function add(name, isPriority)
        if isPriority and not state.allowSounds[name] then
            local soundID = idOf(name)
            if soundID then
                priority[soundID] = true
            end
        end
        if state.allowSounds[name] or mutedNames[name] then
            return
        end
        mutedNames[name] = true
        local soundID = idOf(name)
        if soundID and not seen[soundID] then
            seen[soundID] = true
            muted[#muted + 1] = soundID
        elseif not soundID then
            unresolvedCount = unresolvedCount + 1
        end
    end
    for name in pairs(state.sounds) do
        add(name, true)
    end
    for _, group in ipairs(GROUPS) do
        if state.groups[group.key] then
            for _, name in ipairs(group.names) do
                add(name, #group.names <= SMALL_GROUP_LIMIT)
            end
        end
    end
    table.sort(muted)
    mutedCount = #muted
    local priorityIDs = {}
    for soundID in pairs(priority) do
        priorityIDs[#priorityIDs + 1] = soundID
    end
    scheduler:set(muted, priorityIDs)
end
rebuild()

local function isMuted(name)
    return mutedNames[name] == true
end

-- Muting: every tick for normal selections, with priority in large sets ------------------------------------------

local stopErrors, firstError, lastFailed = 0, nil, false
local preview
local previewMessage
local previewChanged = false

local function stopPreview()
    if preview and preview.instance then
        pcall(function()
            preview.instance:Stop()
        end)
    end
    preview = nil
    previewMessage = nil
    previewChanged = true
end

local function attemptPreview()
    if not preview then
        return
    end
    preview.tries = preview.tries + 1
    local ok, instance = pcall(audio.Play, preview.id, preview.params)
    if ok and instance then
        preview.instance = instance
        preview.remaining = 250
        previewMessage = "PREVIEW: UP TO 5 SECONDS"
    elseif preview.tries >= 6 then
        preview = nil
        previewMessage = "PREVIEW UNAVAILABLE"
    else
        preview.wait = 25
        previewMessage = "LOADING PREVIEW"
    end
    previewChanged = true
end

local function startPreview(name)
    stopPreview()
    local soundID = idOf(name)
    if not soundID then
        previewMessage = "SOUND ID UNAVAILABLE"
        return
    end
    local params = get(function()
        local value = audio.SoundPlaybackParams.new()
        value.type = audio.SoundType.SCRIPT
        value.audioBus = audio.AudioBus.SFX
        value.emitterShape = audio.EmitterShape.NONE
        value.volume = 1
        value.numLoops = 0
        value.delayTick = 0
        return value
    end)
    if not params then
        previewMessage = "PREVIEW SETTINGS UNAVAILABLE"
        return
    end
    preview = { id = soundID, params = params, tries = 0 }
    attemptPreview()
end

local function updatePreview()
    if not preview then
        return
    end
    if preview.instance then
        preview.remaining = preview.remaining - 1
        if preview.remaining <= 0 then
            stopPreview()
        end
    else
        preview.wait = preview.wait - 1
        if preview.wait <= 0 then
            attemptPreview()
        end
    end
end
local report = { calls = 0, answers = 0, sample = "" }
local function stopSound(soundID)
    local ok, result = pcall(audio.StopSoundsUsingResource, soundID)
    report.calls = report.calls + 1
    if not ok then
        lastFailed = true
        stopErrors = stopErrors + 1
        if not firstError then
            firstError = tostring(result)
            log("Ambient Sound Muffler: " .. firstError)
        end
    elseif result ~= nil then
        report.answers = report.answers + 1
        if report.sample == "" or (result ~= false and result ~= 0) then
            report.sample = tostring(soundID) .. " (" .. tostring(namesByID[soundID]) .. ") -> " .. tostring(result)
        end
    end
    return ok
end
local function muffle()
    lastFailed = false
    if not state.on or mutedCount == 0 then
        return
    end
    scheduler:run(stopSound, preview and preview.id or nil)
end

-- Sounds near you: what the creatures around you can play ---------------------------------------------------------
-- Their background sounds and sound params, each shown as "creature: sound name". Checked again every 2 seconds
-- while the Nearby tab is open.

local NEARBY_RANGE = 24              -- tiles
local nearby = {}                    -- { label, name, count = sound ID }
local nearbyReportSignature
local function scanNearby()
    local rows, seenNPC, seenSound = {}, {}, {}
    local diagnostic = {
        range = NEARBY_RANGE,
        npcsFound = 0,
        configsScanned = 0,
        withBackgroundSound = 0,
        soundParams = 0,
        resolvedSounds = 0,
        samples = {},
    }
    local me = get(function() return Player.GetEntity().coordGrid end)
    local ok, list = pcall(function()
        return me and NPCList.ByDistance(me, NEARBY_RANGE)
    end)
    if not ok then
        diagnostic.error = tostring(list)
        list = {}
    elseif type(list) ~= "table" then
        diagnostic.error = me and "NPC list unavailable" or "Player location unavailable"
        list = {}
    end
    diagnostic.npcsFound = #list
    local function raw(value)
        local kind = type(value)
        if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then
            return "non-finite number"
        end
        if kind == "number" or kind == "string" or kind == "boolean" then
            return value
        end
        return kind == "nil" and "nil" or ("type:" .. kind)
    end
    for _, npc in ipairs(type(list) == "table" and list or {}) do
        local npcConfig = get(function() return npc.config end)
        local configID = get(function() return npc.configID end)
        if npcConfig and configID and not seenNPC[configID] then
            seenNPC[configID] = true
            diagnostic.configsScanned = diagnostic.configsScanned + 1
            local npcName = tostring(get(function() return npc.displayName end) or get(function() return npcConfig.name end)
                or "Creature"):gsub("<[^>]*>", "")
            local sample = {
                name = npcName,
                configID = raw(configID),
                hasBackgroundSound = raw(get(function() return npcConfig.hasBackgroundSound end)),
                ready = raw(get(function() return npcConfig.backgroundSoundReady end)),
                crawl = raw(get(function() return npcConfig.backgroundSoundCrawl end)),
                walk = raw(get(function() return npcConfig.backgroundSoundWalk end)),
                run = raw(get(function() return npcConfig.backgroundSoundRun end)),
                params = {},
            }
            if #diagnostic.samples < 24 then
                diagnostic.samples[#diagnostic.samples + 1] = sample
            end
            local function add(value)
                local name = namesByID[value]
                if not name and type(value) == "number" and names[value]
                    and idOf(names[value]) == value then
                    name = names[value]
                end
                if name and not seenSound[value] then
                    seenSound[value] = true
                    rows[#rows + 1] = { label = npcName .. ": " .. pretty(name), name = name, count = value }
                end
            end
            if get(function() return npcConfig.hasBackgroundSound end) then
                diagnostic.withBackgroundSound = diagnostic.withBackgroundSound + 1
                add(get(function() return npcConfig.backgroundSoundReady end))
                add(get(function() return npcConfig.backgroundSoundCrawl end))
                add(get(function() return npcConfig.backgroundSoundWalk end))
                add(get(function() return npcConfig.backgroundSoundRun end))
            end
            local params = get(function() return npcConfig.params end)
            for _, param in ipairs(type(params) == "table" and params or {}) do
                local paramName = tostring(get(function() return param.configName end) or "")
                if paramName:find("SOUND", 1, true) then
                    local value = get(function() return npcConfig:GetParamValue(param) end)
                    diagnostic.soundParams = diagnostic.soundParams + 1
                    if #sample.params < 16 then
                        sample.params[#sample.params + 1] = { name = paramName, value = raw(value) }
                    end
                    add(value)
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    nearby = rows
    diagnostic.resolvedSounds = #rows
    -- Keep raw values even if no name matched. This is configuration evidence,
    -- not a list of currently audible sounds. Samples are bounded for storage.
    local saved, accepted = pcall(function()
        return PersistentDB:SetStructuredData("mufflerNearbyReport", diagnostic)
    end)
    local savedReport = saved and accepted ~= false
    local signature = tostring(diagnostic.npcsFound) .. "/"
        .. tostring(diagnostic.withBackgroundSound) .. "/"
        .. tostring(diagnostic.soundParams) .. "/" .. tostring(#rows)
        .. "/" .. tostring(diagnostic.error)
        .. "/" .. tostring(savedReport)
    if signature ~= nearbyReportSignature then
        nearbyReportSignature = signature
        log("Muffler Nearby: " .. diagnostic.npcsFound .. " NPCs; "
            .. diagnostic.withBackgroundSound .. " background configs; "
            .. diagnostic.soundParams .. " SOUND params; " .. #rows
            .. " named sounds. " .. (savedReport
                and "Raw values saved in mufflerNearbyReport."
                or "Could not save raw values; will retry."))
    end
end

-- The list on screen ---------------------------------------------------------------------------------------------

local tab, query, offset, selected = "groups", "", 0, nil
local results = {}                   -- { label, name or group, count }
local searchable = nil               -- lower-case names for searching, made on the first search

local function search()
    results = {}
    local words = {}
    for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
    local function matches(text)
        local lower = text:lower()
        for _, word in ipairs(words) do
            if not lower:find(word, 1, true) then return false end
        end
        return true
    end
    if tab == "groups" then
        for _, group in ipairs(GROUPS) do
            if #group.names > 0 and matches(group.label) then
                results[#results + 1] = { label = group.label, group = group, count = #group.names }
            end
        end
    elseif tab == "nearby" then
        for _, row in ipairs(nearby) do
            if matches(row.label) then results[#results + 1] = row end
        end
    elseif tab == "muted" then
        for _, group in ipairs(GROUPS) do
            if state.groups[group.key] and matches(group.label) then
                results[#results + 1] = { label = group.label, group = group, count = #group.names }
            end
        end
        local list = {}
        for name in pairs(state.sounds) do list[#list + 1] = name end
        table.sort(list)
        for _, name in ipairs(list) do
            if matches(name) then results[#results + 1] = { label = pretty(name), name = name, count = idOf(name) } end
        end
    else
        if #words == 0 then
            for index = 1, #names do
                results[#results + 1] = { label = pretty(names[index]), name = names[index], count = index }
            end
        else
            if not searchable then          -- the names in lower case with spaces, made once on the first search
                searchable = {}
                for index, name in ipairs(names) do
                    searchable[index] = name:lower():gsub("_", " ")
                end
            end
            -- best matches first: the exact name, then names that start with the search, then the rest
            local whole = table.concat(words, " ")
            local exact, starts, rest = {}, {}, {}
            for index, text in ipairs(searchable) do
                local hit = true
                for _, word in ipairs(words) do
                    if not text:find(word, 1, true) then
                        hit = false
                        break
                    end
                end
                if hit then
                    local row = { label = pretty(names[index]), name = names[index], count = index }
                    if text == whole then
                        exact[#exact + 1] = row
                    elseif text:sub(1, #whole) == whole then
                        starts[#starts + 1] = row
                    else
                        rest[#rest + 1] = row
                    end
                end
            end
            for _, bucket in ipairs({ exact, starts, rest }) do
                for _, row in ipairs(bucket) do
                    results[#results + 1] = row
                end
            end
        end
    end
    offset = math.max(0, math.min(offset, #results - ROWS))
end

local function rowMuted(row)
    if row.group then
        return state.groups[row.group.key] == true
    end
    return isMuted(row.name)
end

-- The window ---------------------------------------------------------------------------------------------------------

local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local W, H = 384, 567
local screenWidth = get(function() return layer.width end) or 1920
local window = RetroUI.Window(layer, {
    width = W, height = H, title = "MUFFLER",
    program = true,
    x = state.x or (screenWidth - W - 360), y = state.y or 110,
    onMove = function(x, y)
        state.x, state.y = x, y
        save()
    end,
    onHide = function(hidden)
        state.hidden = hidden
        save()
    end,
})
local box = window.inner
local top = box.y + 3
local LIST_X, LIST_W = box.x, box.width - 36
local LIST_Y = top + 75
local TUNER_X = box.x + box.width - 30
local LCD_Y = LIST_Y + ROWS * ROW_H + 18
local BUTTONS_Y = LCD_Y + 36

-- A little speaker (10 x 7 art pixels at 2 units): sound waves beside it when it plays, a red cross when muted
local SPEAKER = { "...kk", "..kWk", "kkWWk", "kWWWk", "kkWWk", "..kWk", "...kk" }
local WAVES = { "......k...", ".......k..", "......k.k.", "......k.k.", "......k.k.", ".......k..", "......k..." }
local CROSS = { "..........", "......r..r", ".......rr.", ".......rr.", "......r..r", "..........", ".........." }

local function draw(paint)
    -- search frame and the three tabs
    paint:Chrome(box.x, top, box.width, 33)
    paint:Magnifier(box.x + 9, top + 6)
    local tabWidth = math.floor((box.width - 18) / 4)
    for i, t in ipairs({ { "groups", "Groups" }, { "sounds", "Sounds" }, { "nearby", "Nearby" }, { "muted", "Muted" } }) do
        paint:Button(box.x + (i - 1) * (tabWidth + 6), top + 39, tabWidth, 27, t[2], tab == t[1])
    end

    -- the list
    paint:Glass(LIST_X, LIST_Y - 6, LIST_W, ROWS * ROW_H + 12)
    for i = 1, ROWS do
        local row = results[offset + i]
        local y = LIST_Y + (i - 1) * ROW_H
        if row then
            local lit = selected and selected.label == row.label and selected.name == row.name
            if lit then
                paint:Rect(LIST_X + 6, y, LIST_W - 12, ROW_H, C.GOLD)
            end
            local mute = rowMuted(row)
            local ink = lit and C.DARK or C.INK
            paint:Sprite(LIST_X + 9, y + 5, SPEAKER, { k = ink, W = mute and 0x7A1E1EFF or C.CHROME }, 2)
            if mute then
                paint:Sprite(LIST_X + 9, y + 5, CROSS, { r = C.RED }, 2)
            else
                paint:Sprite(LIST_X + 9, y + 5, WAVES, { k = lit and C.DARK or C.CHROME }, 2)
            end
            local colour = lit and C.DARK or (mute and C.FADED or C.CREAM)
            paint:Text(LIST_X + 33, y, LIST_W - 99, ROW_H, row.label, colour)
            local displayedID = row.name and (idOf(row.name) or "?") or row.count
            paint:Text(LIST_X + LIST_W - 66, y, 57, ROW_H, tostring(displayedID or ""), lit and C.DARK or C.NUMBER,
                       { align = "right" })
        end
    end
    if #results == 0 then
        paint:Text(LIST_X + 12, LIST_Y + 90, LIST_W - 24, 30,
                   tab == "muted" and "Nothing muted yet." or tab == "nearby" and "No creature sounds near you."
                   or "No matching sounds.", C.FADED, { align = "centre" })
    end

    -- the tuner: up, down and a gold handle
    paint:Block(TUNER_X, LIST_Y - 6, 30, ROWS * ROW_H + 12, C.CHROME_DARK, nil, C.INK)
    paint:Chrome(TUNER_X, LIST_Y - 6, 30, 30)
    paint:Arrow(TUNER_X + 15, LIST_Y + 9, "up")
    paint:Chrome(TUNER_X, LIST_Y + ROWS * ROW_H - 18, 30, 30)
    paint:Arrow(TUNER_X + 15, LIST_Y + ROWS * ROW_H - 3, "down")
    local travel = ROWS * ROW_H - 96
    local share = #results > ROWS and offset / (#results - ROWS) or 0
    paint:Gold(TUNER_X + 3, LIST_Y + 27 + math.floor(travel * share / P) * P, 24, 36)

    -- the readout
    paint:LCD(box.x, LCD_Y, box.width, 30)
    local status
    local ambientStatus = ambientControl:status()
    if ambientStatus.error then
        status = "AMBIENT CHANGE FAILED"
    elseif savePending then
        status = "CHANGES WAITING TO SAVE"
    elseif previewMessage then
        status = previewMessage
    elseif not state.on then
        status = "MUFFLER OFF"
    elseif lastFailed then
        status = "MUTING FAILED - SEE CONSOLE"
    else
        status = "CHOSEN " .. mutedCount .. " SOUNDS"
        if unresolvedCount > 0 then
            status = tostring(unresolvedCount) .. " CHOSEN SOUND IDS UNAVAILABLE"
        end
    end
    paint:Text(box.x + 9, LCD_Y, box.width - 18, 30, status, state.on and C.NUMBER or C.FADED)

    -- buttons: the master switch and Play, then the whole-ambience volume
    local half = math.floor((box.width - 6) / 2)
    paint:Button(box.x, BUTTONS_Y, half, 27, state.on and "MUFFLE: ON" or "MUFFLE: OFF", state.on)
    paint:Button(box.x + half + 6, BUTTONS_Y, half, 27, preview and "STOP PREVIEW" or "PLAY", false)
    local ambientLabel = ambientStatus.available
        and ("ALL AMBIENT SOUND: " .. (state.on and AMBIENCE[state.ambience] or "NORMAL"))
        or "AMBIENT VOLUME UNAVAILABLE"
    if ambientStatus.error then
        ambientLabel = "AMBIENT CHANGE NOT APPLIED"
    end
    paint:Button(box.x, BUTTONS_Y + 33, box.width, 27, ambientLabel, ambient ~= nil and state.ambience ~= "normal")
end

local function redraw()
    window:Redraw(draw)
end

local function toggle(row)
    if row.group then
        state.groups[row.group.key] = not state.groups[row.group.key] or nil
    elseif isMuted(row.name) then
        state.sounds[row.name] = nil
        state.allowSounds[row.name] = nil
        for _, group in ipairs(GROUPS) do
            if state.groups[group.key] and inGroup(group, row.name) then
                state.allowSounds[row.name] = true
                break
            end
        end
    else
        state.allowSounds[row.name] = nil
        state.sounds[row.name] = true
    end
    rebuild()
    save()
    if tab == "muted" then search() end
    redraw()
end

local function scroll(delta)
    local step = delta > 0 and -1 or 1
    offset = math.max(0, math.min(math.max(0, #results - ROWS), offset + step))
    redraw()
end

-- the search box sits inside the chrome frame
window:Field(box.x + 30, top + 4, box.width - 39, "", function(text)
    stopPreview()
    selected = nil
    query = text
    offset = 0
    search()
    redraw()
end)
-- tabs
local tabWidth = math.floor((box.width - 18) / 4)
for i, key in ipairs({ "groups", "sounds", "nearby", "muted" }) do
    window:Area(box.x + (i - 1) * (tabWidth + 6), top + 39, tabWidth, 27, function()
        tab = key
        offset = 0
        selected = nil
        stopPreview()
        if key == "nearby" then scanNearby() end
        search()
        redraw()
    end)
end
-- rows: a click mutes or unmutes the row (and selects it for Play)
for i = 1, ROWS do
    local index = i
    window:Area(LIST_X + 6, LIST_Y + (i - 1) * ROW_H, LIST_W - 12, ROW_H, function()
        local row = results[offset + index]
        if row then
            stopPreview()
            selected = row
            toggle(row)
        end
    end, scroll)
end
-- tuner arrows: a page at a time
window:Area(TUNER_X, LIST_Y - 6, 30, 30, function()
    offset = math.max(0, offset - ROWS)
    redraw()
end, scroll)
window:Area(TUNER_X, LIST_Y + ROWS * ROW_H - 18, 30, 30, function()
    offset = math.max(0, math.min(math.max(0, #results - ROWS), offset + ROWS))
    redraw()
end, scroll)
-- the master switch and Play
local half = math.floor((box.width - 6) / 2)
window:Area(box.x, BUTTONS_Y, half, 27, function()
    state.on = not state.on
    save()
    applyAmbience()
    redraw()
end)
-- the whole ambience: normal -> muffled -> blocked -> normal
window:Area(box.x, BUTTONS_Y + 33, box.width, 27, function()
    if not ambient then
        return
    end
    state.ambience = state.ambience == "normal" and "muffled" or state.ambience == "muffled" and "blocked" or "normal"
    save()
    applyAmbience()
    redraw()
end)
window:Area(box.x + half + 6, BUTTONS_Y, half, 27, function()
    if preview then
        stopPreview()
    elseif selected and selected.name then
        startPreview(selected.name)
    end
    redraw()
end)

search()
redraw()
if state.hidden then
    window:Hide()
end

-- Every client tick: mute, drag, bulbs
local nearbyTicks, reportTicks = 0, 0
local frameSamples = {}
local frameSample
local drawEvent = get(function() return Event.Draw end)
local drawSubscribed = false
if drawEvent then
    drawSubscribed = pcall(function()
        drawEvent.Subscribe("soundMufflerFrames", function(event)
            local delta = event.timeDeltaSecs
            if type(delta) ~= "number" or delta <= 0 or delta ~= delta or delta == math.huge then
                return
            end
            local key = tostring(state.on) .. ":" .. tostring(mutedCount)
                .. ":" .. tostring(reportTicks - reportTicks % 500)
                .. ":" .. state.ambience .. ":" .. tostring(preview ~= nil)
            if not frameSample or frameSample.key ~= key then
                frameSample = {
                    key = key,
                    enabled = state.on,
                    chosen = mutedCount,
                    ambience = state.ambience,
                    preview = preview ~= nil,
                    frames = 0,
                    seconds = 0,
                    maxMilliseconds = 0,
                    over33Milliseconds = 0,
                }
                frameSamples[#frameSamples + 1] = frameSample
                if #frameSamples > 12 then
                    table.remove(frameSamples, 1)
                end
                -- This interval began under the previous selection.
                return
            end
            frameSample.frames = frameSample.frames + 1
            frameSample.seconds = frameSample.seconds + delta
            frameSample.maxMilliseconds = math.max(frameSample.maxMilliseconds, delta * 1000)
            frameSample.meanMilliseconds = frameSample.seconds * 1000 / frameSample.frames
            if delta > 0.033 then
                frameSample.over33Milliseconds = frameSample.over33Milliseconds + 1
            end
        end)
    end)
end
local function saveReports()
    pcall(function()
        PersistentDB:SetString("stopReport", report.calls .. " calls, " .. report.answers .. " answers; " .. report.sample)
        PersistentDB:SetStructuredData("mufflerPerformance", {
            version = "0.1.1",
            logicTicks = reportTicks,
            totalCalls = report.calls,
            stopErrors = stopErrors,
            scheduler = scheduler:status(),
            framesAvailable = drawSubscribed,
            frameSamples = frameSamples,
            measurement = "Whole-frame intervals; not native stop-call duration",
        })
    end)
end
Event.Logic.Subscribe("soundMuffler", function()
    updatePreview()
    local wasFailed = lastFailed
    muffle()
    reportTicks = reportTicks + 1
    if reportTicks % 100 == 0 then
        if savePending then
            save()
        end
        applyAmbience()
        redraw()
    end
    if reportTicks % 500 == 0 then
        saveReports()
    end
    if tab == "nearby" and not window:IsHidden() then
        nearbyTicks = nearbyTicks + 1
        if nearbyTicks % 100 == 0 then
            scanNearby()
            search()
            redraw()
        end
    end
    if previewChanged or wasFailed ~= lastFailed then
        previewChanged = false
        redraw()
    end
    window:Animate()
end)

-- Settings in the Plugin Hub (the cog): show the window, and the master switch
Event.SettingsLayerReady.Subscribe("soundMufflerSettings", function(event)
    local panel = ui.Layer.new(event.component)
    panel:SetPos(8, 8)
    panel:SetSize(360, 190)
    local function button(y, label, fn)
        local b = ui.Button.new(panel)
        b:SetPos(0, y)
        b:SetSize(250, 25)
        b.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
        b.label = label()
        b:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
            fn()
            b.label = label()
        end)
    end
    button(0, function() return "Window: " .. (window:IsHidden() and "hidden" or "shown") end, function()
        if window:IsHidden() then window:Show() else window:Hide() end
    end)
    button(32, function() return "Muffler: " .. (state.on and "on" or "off") end, function()
        state.on = not state.on
        save()
        applyAmbience()
        redraw()
    end)
    button(64, function() return "All ambient sound: " .. AMBIENCE[state.ambience] end, function()
        state.ambience = state.ambience == "normal" and "muffled"
            or state.ambience == "muffled" and "blocked" or "normal"
        save()
        applyAmbience()
        redraw()
    end)
    local note = ui.Text.new(panel)
    note:SetPos(0, 100)
    note:SetSize(350, 80)
    note.font = id.Font.MUSEO_SANS_15PT_REGULAR
    note.clickthrough = true
    note.content = "All ambient sound changes the whole ambient channel.\n"
        .. "Chosen sounds stop each tick; a short onset may remain.\n"
        .. "Play previews for up to five seconds. SFX must be audible."
end)

function PluginShutdown()
    Event.Logic.Unsubscribe("soundMuffler")
    Event.SettingsLayerReady.Unsubscribe("soundMufflerSettings")
    if drawSubscribed then
        drawEvent.Unsubscribe("soundMufflerFrames")
    end
    stopPreview()
    save()
    saveReports()
    ambientControl:shutdown()
    window:Destroy()
end

log("Ambient Sound Muffler 0.1.2: " .. #names .. " sounds, " .. mutedCount
    .. " chosen. Use Gulls for gull sounds, or ALL AMBIENT SOUND for the whole channel.")
