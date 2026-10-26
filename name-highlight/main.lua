-- Name Highlight 0.1.2
-- Your name, and any nicknames you add, light up in chat when someone says them.

local VERSION = "0.1.2"
local RetroUI = require("retro_ui")
local C = RetroUI.COLOURS

local function get(fn)               -- read a game value; nil if it is not there
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

-- Chat that counts (ChatType numbers): people talking. Outgoing private messages and your own lines never count.
local PLAYER_CHAT = { [1] = "Public", [2] = "Public", [17] = "Public", [3] = "Private", [7] = "Private", [18] = "Private",
                      [9] = "Friends", [20] = "Friends", [22] = "Group", [23] = "Group", [24] = "Group", [25] = "Group",
                      [41] = "Clan", [42] = "Clan", [44] = "Guest", [45] = "Guest" }
-- with Game messages on: news and broadcasts that name you (a rare drop, a level)
local GAME_CHAT = { [0] = "Game", [115] = "News", [125] = "News", [126] = "News", [127] = "News", [137] = "News",
                    [138] = "News", [139] = "News" }
local PLUGIN_CHAT = 33
local STEPS = { "ppr name-highlight", "ppe name-highlight chatAccess", "prf, then prl name-highlight" }

-- 16 colours a click on a colour square goes through ("#rrggbb" typed after a nickname gives any other)
local PALETTE = { { "Gold", "ffd54a" }, { "Green", "5ee07a" }, { "Pink", "ff6ec7" }, { "Cyan", "5cfff2" },
                  { "Orange", "ffa040" }, { "Red", "ff4d4d" }, { "White", "ffffff" }, { "Purple", "b388ff" },
                  { "Blue", "4da6ff" }, { "Lime", "c6ff00" }, { "Yellow", "fff176" }, { "Coral", "ff8a65" },
                  { "Teal", "26c6da" }, { "Magenta", "e040fb" }, { "Sky", "81d4fa" }, { "Silver", "bdbdbd" } }
local OLD_COLOURS = { gold = "ffd54a", green = "5ee07a", pink = "ff6ec7", cyan = "5cfff2", orange = "ffa040",
                      red = "ff4d4d", white = "ffffff" }
local SOUNDS = { { "off", "Off" }, { "popup", "Popup", "ARCH_INFO_POPUP" }, { "sparkle", "Sparkle", "LEVEL_UP_SPARKLE" },
                 { "task", "Task done", "TASK_COMPLETE_01" }, { "coins", "Coins", "GE_COLLECT_COINS" },
                 { "bell", "Bell", "BELL_1" }, { "chime", "Chime", "TARDDIAD_SINGLE_CHIME_1" },
                 { "ding", "Ding", "MTXFEST17_CAROUSEL_DING_01" }, { "whistle", "Whistle", "WHISTLE_CALL" } }
local WHEN = { "unfocused", "always" }
local KEEP = 50                      -- mentions kept
local MAX_NICKS = 5
local GLOW_TICKS = 150               -- 3 s
local PING_GAP = 100                 -- client ticks between two sounds (2 s)

local function isHex(s) return type(s) == "string" and #s == 6 and s:find("^%x+$") ~= nil end
local function paletteName(hex)
    for _, p in ipairs(PALETTE) do if p[2] == hex then return p[1] end end
    return "#" .. hex
end
local function nextColour(hex)
    for i, p in ipairs(PALETTE) do if p[2] == hex then return PALETTE[i % #PALETTE + 1][2] end end
    return PALETTE[1][2]
end
local function rgba(hex) return (tonumber(hex, 16) or 0xFFD54A) * 256 + 255 end

-- Settings, saved as a table ------------------------------------------------------------------------------------------
local prefs = { me = "ffd54a", nicks = {}, sound = "popup", when = "unfocused", glow = true, game = false, mine = false,
                win = { state = "small", x = 40, y = 420 } }
local function pick(list, key) for _, v in ipairs(list) do if v[1] == key or v == key then return v end end end
do
    local saved = get(function() return PersistentDB:GetStructuredData("nameHighlight") end)
    if type(saved) == "table" then
        if isHex(saved.me) then prefs.me = saved.me
        elseif OLD_COLOURS[saved.colour] then prefs.me = OLD_COLOURS[saved.colour] end
        if type(saved.nicks) == "table" then
            for _, n in ipairs(saved.nicks) do
                if type(n) == "table" and type(n.word) == "string" and n.word ~= "" and #prefs.nicks < MAX_NICKS then
                    prefs.nicks[#prefs.nicks + 1] = { word = n.word, colour = isHex(n.colour) and n.colour or prefs.me }
                end
            end
        elseif type(saved.words) == "string" then
            for word in saved.words:gmatch("[^,]+") do
                word = word:gsub("^%s+", ""):gsub("%s+$", "")
                if word ~= "" and #prefs.nicks < MAX_NICKS then prefs.nicks[#prefs.nicks + 1] = { word = word, colour = prefs.me } end
            end
        end
        if pick(SOUNDS, saved.sound) then prefs.sound = saved.sound end
        if pick(WHEN, saved.when) then prefs.when = saved.when end
        if type(saved.glow) == "boolean" then prefs.glow = saved.glow end
        if type(saved.game) == "boolean" then prefs.game = saved.game end
        if type(saved.mine) == "boolean" then prefs.mine = saved.mine end
        if type(saved.win) == "table" then
            local s = saved.win.state
            if s == "small" or s == "big" or s == "min" or s == "closed" then prefs.win.state = s end
            if tonumber(saved.win.x) then prefs.win.x = math.floor(tonumber(saved.win.x)) end
            if tonumber(saved.win.y) then prefs.win.y = math.floor(tonumber(saved.win.y)) end
        end
    end
end
local function save() pcall(function() PersistentDB:SetStructuredData("nameHighlight", prefs) end) end
local function nextIn(list, key)
    for i, v in ipairs(list) do if (v[1] or v) == key then local n = list[i % #list + 1]; return n[1] or n end end
    return list[1][1] or list[1]
end

local function plain(s)
    return (tostring(s or ""):gsub("<[^>]*>", ""):gsub("\194\160", " "):gsub("[_%-]", " "):gsub("%s+", " ")
        :gsub("^ ", ""):gsub(" $", ""):lower())
end
local GAP = "[%s_%-\194\160]+"
local function patternFor(name)
    local words = {}
    for word in plain(name):gmatch("%S+") do words[#words + 1] = (word:gsub("(%W)", "%%%1")) end
    if #words == 0 then return nil end
    return "%f[%w]" .. table.concat(words, GAP) .. "%f[%W]"
end
local names = { me = nil, list = {}, said = {} }
function names.mine()
    local n = get(function() return Player.GetEntity().displayName end)
    n = type(n) == "string" and n:gsub("<[^>]*>", ""):gsub("\194\160", " ") or nil
    return (n and n ~= "") and n or nil
end
function names.rebuild()
    names.list, names.said = {}, {}
    local all = {}
    if names.me then all[#all + 1] = { names.me, prefs.me } end
    for _, n in ipairs(prefs.nicks) do all[#all + 1] = { n.word, n.colour } end
    local seen = {}
    for _, n in ipairs(all) do
        local p = patternFor(n[1])
        if p and not seen[p] then
            seen[p] = true
            names.list[#names.list + 1] = { pattern = p, colour = n[2], said = plain(n[1]) }
            names.said[#names.said + 1] = plain(n[1])
        end
    end
end
names.rebuild()

local function highlight(text)
    local first, out, current = nil, {}, nil
    local function mark(part)
        if part == "" or #names.list == 0 then return part end
        local low, spans = part:lower(), {}
        for _, n in ipairs(names.list) do
            local from = 1
            while true do
                local s, e = low:find(n.pattern, from)
                if not s then break end
                spans[#spans + 1] = { s, e, n.colour }
                from = e + 1
            end
        end
        if #spans == 0 then return part end
        table.sort(spans, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] > b[2] end)
        local res, at = {}, 1
        for _, sp in ipairs(spans) do
            if sp[1] >= at then
                first = first or sp[3]
                res[#res + 1] = part:sub(at, sp[1] - 1)
                res[#res + 1] = "<col=" .. sp[3] .. ">" .. part:sub(sp[1], sp[2]) .. "</col>" .. (current or "")
                at = sp[2] + 1
            end
        end
        res[#res + 1] = part:sub(at)
        return table.concat(res)
    end
    local pos = 1
    while true do
        local s, e = text:find("<[^>]*>", pos)
        if not s then out[#out + 1] = mark(text:sub(pos)); break end
        out[#out + 1] = mark(text:sub(pos, s - 1))
        local tag = text:sub(s, e)
        out[#out + 1] = tag
        if tag:lower():find("^<col=") then current = tag elseif tag:lower() == "</col>" then current = nil end
        pos = e + 1
    end
    return table.concat(out), first
end

-- A nickname typed in the box: "Rabbit" (next unused colour) or "Rabbit #ff66cc". Returns why not, or nil when added.
local function addNick(typed)
    local word, hex = tostring(typed or ""):match("^%s*(.-)%s+#(%x%x%x%x%x%x)%s*$")
    word = (word or tostring(typed or "")):gsub("^%s+", ""):gsub("%s+$", ""):gsub(",", " ")
    if not patternFor(word) then return "type a nickname first" end
    if #word > 30 then return "30 letters at most" end
    hex = hex and hex:lower()
    for _, n in ipairs(prefs.nicks) do
        if plain(n.word) == plain(word) then n.colour = hex or n.colour; return nil end
    end
    if names.me and plain(names.me) == plain(word) then return "that's your own name: it's always on" end
    if #prefs.nicks >= MAX_NICKS then return MAX_NICKS .. " nicknames at most" end
    if not hex then
        local used = { [prefs.me] = true }
        for _, n in ipairs(prefs.nicks) do used[n.colour] = true end
        for _, p in ipairs(PALETTE) do if not used[p[2]] then hex = p[2]; break end end
        hex = hex or PALETTE[1][2]
    end
    prefs.nicks[#prefs.nicks + 1] = { word = word, colour = hex }
    return nil
end

-- State ---------------------------------------------------------------------------------------------------------------
local layer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local now, focused = 0, true
local state = { mentions = {}, hasChat = false, lastPing = -1e9, glowUntil = -1, glowHex = "ffd54a", testing = false,
                note = nil, ui = nil, chatSeen = false }
local function checkChat(quiet)
    local had = state.hasChat
    state.hasChat = state.chatSeen or get(function() return Plugin.HasPermission(PluginPermissions.chatAccess) end) == true
    if state.hasChat ~= had and not quiet then
        log("Name Highlight: chat access " .. (state.hasChat and "allowed - listening for " .. table.concat(names.said, ", ")
            or "is off. In the console: " .. table.concat(STEPS, ", ")))
        if state.ui then state.ui.refresh() end
    end
end

local missingSaid = {}
local function play(key)
    local s = pick(SOUNDS, key)
    if not s or not s[3] then return end
    local n = get(function() return id.Sound[s[3]] end)
    if n == nil then
        if not missingSaid[key] then missingSaid[key] = true; log("Name Highlight: the game has no sound " .. s[3] .. "; playing Popup") end
        n = get(function() return id.Sound.ARCH_INFO_POPUP end)
    end
    if n == nil then return end
    local played = pcall(function()
        local p = audio.SoundPlaybackParams.new()
        p.type, p.audioBus, p.emitterShape = audio.SoundType.SCRIPT, audio.AudioBus.SFX, audio.EmitterShape.NONE
        audio.Play(n, p)
    end)
    if not played then pcall(audio.Play, n) end
end

local glow = {}
for i = 1, 4 do
    local r = ui.Rectangle.new(layer)
    r.fill, r.clickthrough, r.hidden = true, true, true
    glow[i] = r
end
local function chatBox()
    local c = get(function() return ui.Interfaces:GetComponent(137, 0) end)
    if not c or get(function() return c.visibleGlobal end) == false then return nil end
    local at = get(function() return c.xyGlobal end)
    local w, h = get(function() return c.width end), get(function() return c.height end)
    local base = get(function() return layer.xyGlobal end) or { x = 0, y = 0 }
    if not at or type(at.x) ~= "number" or type(w) ~= "number" or type(h) ~= "number" or w < 20 or h < 20 then return nil end
    return at.x - base.x, at.y - base.y, w, h
end
local function placeGlow()
    if now > state.glowUntil then
        for _, r in ipairs(glow) do if not r.hidden then r.hidden = true end end
        return
    end
    local x, y, w, h = chatBox()
    if not x then return end
    local t = (state.glowUntil - now) / GLOW_TICKS                  -- 1 -> 0
    local alpha = 0.25 + 0.6 * t * (0.6 + 0.4 * math.abs(math.sin(now / 6)))
    local v = tonumber(state.glowHex, 16) or 0xFFD54A
    local red, green, blue = math.floor(v / 65536) / 255, math.floor(v / 256) % 256 / 255, v % 256 / 255
    local spots = { { x - 6, y - 6, w + 12, 6 }, { x - 6, y + h, w + 12, 6 }, { x - 6, y, 6, h }, { x + w, y, 6, h } }
    for i, r in ipairs(glow) do
        local sp = spots[i]
        r:SetPos(math.floor(sp[1]), math.floor(sp[2]))
        r:SetSize(math.floor(sp[3]), math.floor(sp[4]))
        pcall(function() r.colour = Vector4.new(red, green, blue, alpha) end)
        r.hidden = false
    end
end

-- A message came in --------------------------------------------------------------------------------------------------
local function onChat(event)
    if not state.chatSeen then                -- the game only sends chat to a plugin that has chat access
        state.chatSeen = true
        if not state.hasChat then
            state.hasChat = true
            log("Name Highlight: chat is arriving, so chat access is on - listening for " .. table.concat(names.said, ", "))
            if state.ui then state.ui.refresh() end
        end
    end
    local kind = event.chatType
    local where = PLAYER_CHAT[kind] or (prefs.game and GAME_CHAT[kind]) or (kind == PLUGIN_CHAT and state.testing and "Test")
    if not where then return end
    local who = tostring(event.senderNameSimple or ""):gsub("<[^>]*>", "")
    if where ~= "Test" and not prefs.mine and who ~= "" and names.me and plain(who) == plain(names.me) then return end  -- your own line
    local text = event.chatMessage
    if type(text) ~= "string" then return end
    local coloured, hex = highlight(text)
    if not hex then return end
    event.chatMessage = coloured
    if where == "Test" then state.testing = false end
    table.insert(state.mentions, 1, { at = now, where = where, who = who ~= "" and who or where, colour = hex,
                                     text = (text:gsub("<[^>]*>", "")) })
    while #state.mentions > KEEP do table.remove(state.mentions) end
    if prefs.glow then state.glowUntil, state.glowHex = now + GLOW_TICKS, hex end
    if prefs.sound ~= "off" and (prefs.when == "always" or not focused) and now - state.lastPing >= PING_GAP then
        state.lastPing = now
        play(prefs.sound)
    end
    if state.ui then state.ui.refresh() end
end
Event.ChatMessage.Subscribe("nameHighlightChat", function(event)
    local ok, problem = pcall(onChat, event)
    if not ok then log("Name Highlight: " .. tostring(problem)) end
end)
Event.WindowFocusChanged.Subscribe("nameHighlightFocus", function(event) focused = event.hasFocus ~= false end)
-- the moment the console's ppe goes through (docs: OptionalPermissionChanged), not 3 s later
pcall(function() Event.OptionalPermissionChanged.Subscribe("nameHighlightPermission", function(event)
    if event and event.permissionName == "chatAccess" and event.enabled == false then state.chatSeen = false end
    checkChat()
end) end)

-- The window ------------------------------------------------------------------------------------------------------------
local function ago(at)
    local s = math.floor((now - at) / 50)
    if s < 10 then return "now" elseif s < 60 then return s .. "s" elseif s < 3600 then return math.floor(s / 60) .. "m" end
    return math.floor(s / 3600) .. "h"
end
local function buildUI()
    local u = {}
    local field, typed = nil, ""
    local SIZES = { small = { 340, 246 }, big = { 440, 474 } }
    local BIG = { rows = 4, label = 207, names = 231, nameRows = 1 + MAX_NICKS, add = 393, buttons = 426 }
    local function rows(st) return st == "big" and BIG.rows or 5 end
    local function draw(paint, w, st)
        local X, LW = 21, SIZES[st][1] - 42
        paint:LCD(X, 60, LW, 27)
        if not state.hasChat then
            paint:Text(X + 9, 60, LW - 18, 27, "CHAT ACCESS OFF", C.RED)
        else
            local n = #state.mentions
            paint:Text(X + 9, 60, LW - 18, 27, n == 1 and "1 MENTION" or (n .. " MENTIONS"), C.GREEN)
            paint:Text(X + 9, 60, LW - 18, 27, n > 0 and ("LAST " .. ago(state.mentions[1].at):upper()) or "", C.NUMBER, { align = "right" })
        end
        local gy, rowH = 93, 24
        local gh = rows(st) * rowH + 12
        paint:Glass(X, gy, LW, gh)
        if not state.hasChat then
            paint:Text(X + 9, gy + 6, LW - 18, 22, "Allow chat access in the console:", C.CREAM)
            for i, step in ipairs(STEPS) do paint:Text(X + 9, gy + 6 + i * 24, LW - 18, 22, step, C.NUMBER) end
        elseif #state.mentions == 0 then
            paint:Text(X + 9, gy + 6, LW - 18, 22, "Nobody's said it yet.", C.FADED)
            paint:Text(X + 9, gy + 30, LW - 18, 22, "Listening for: " .. table.concat(names.said, ", "), C.FADED)
        else
            for i = 1, rows(st) do
                local m = state.mentions[i]
                if not m then break end
                local y = gy + 6 + (i - 1) * rowH
                local whoW = st == "big" and 150 or 96
                local label = st == "big" and ("[" .. m.where .. "] " .. m.who) or m.who
                paint:Text(X + 9, y, whoW, rowH, label, rgba(m.colour or prefs.me))
                paint:Text(X + 9 + whoW + 6, y, LW - whoW - 60, rowH, m.text, C.CREAM)
                paint:Text(X + LW - 45, y, 36, rowH, ago(m.at), C.NUMBER, { align = "right" })
            end
        end
        if st ~= "big" then return end
        paint:Text(X, BIG.label, LW, 22, state.note or "YOUR NAME AND NICKNAMES - click a colour to change it", state.note and C.RED or C.FADED)
        paint:Glass(X, BIG.names, LW, BIG.nameRows * rowH + 12)
        for i = 1, BIG.nameRows do
            local y = BIG.names + 6 + (i - 1) * rowH
            local word, hex
            if i == 1 then word, hex = names.me and (names.me .. " (you)") or "Your name (once you're logged in)", prefs.me
            elseif prefs.nicks[i - 1] then word, hex = prefs.nicks[i - 1].word, prefs.nicks[i - 1].colour end
            if word then
                paint:Rect(X + 8, y + 2, 20, 20, C.INK)
                paint:Rect(X + 10, y + 4, 16, 16, rgba(hex))
                paint:Text(X + 36, y, LW - 162, rowH, word, rgba(hex))
                paint:Text(X + LW - 120, y, 84, rowH, paletteName(hex), C.FADED, { align = "right" })
                if i > 1 then paint:Text(X + LW - 27, y, 18, rowH, "x", C.RED, { align = "right" }) end
            elseif i == #prefs.nicks + 2 then
                paint:Text(X + 36, y, LW - 45, rowH, "Add one below: Rabbit, or Rabbit #ff66cc", C.FADED)
            end
        end
        paint:Button(X + LW - 96, BIG.add - 1, 96, 27, "ADD", false)
        local bw = math.floor((LW - 12) / 3)
        local snd = pick(SOUNDS, prefs.sound)
        for i, label in ipairs({ "TEST", "CLEAR", "SOUND: " .. (snd and snd[2] or "Off"):upper() }) do
            paint:Button(X + (i - 1) * (bw + 6), BIG.buttons, bw, 27, label, false)
        end
    end
    local function changed()
        save()
        names.rebuild()
        u.refresh()
    end
    local function build(w, st)
        field = nil
        if st ~= "big" then return end
        local X, LW = 21, SIZES.big[1] - 42
        for i = 1, BIG.nameRows do                                    -- every row's colour square and x, used when filled
            local y = BIG.names + 6 + (i - 1) * 24
            w:Area(X + 6, y, 24, 24, function()
                if i == 1 then prefs.me = nextColour(prefs.me)
                elseif prefs.nicks[i - 1] then prefs.nicks[i - 1].colour = nextColour(prefs.nicks[i - 1].colour)
                else return end
                changed()
            end)
            if i > 1 then
                w:Area(X + LW - 30, y, 27, 24, function()
                    if prefs.nicks[i - 1] then table.remove(prefs.nicks, i - 1); state.note = nil; changed() end
                end)
            end
        end
        field = w:Field(X, BIG.add, LW - 102, typed, function(text) typed = text end)
        local function add()
            state.note = addNick(typed)
            if not state.note then
                typed = ""
                pcall(function() field.content = "" end)
            end
            changed()
        end
        w:Area(X + LW - 96, BIG.add - 1, 96, 27, add)
        local bw = math.floor((LW - 12) / 3)
        w:Area(X, BIG.buttons, bw, 27, function()
            local list = {}
            if names.me then list[#list + 1] = names.me end
            if prefs.nicks[1] then list[#list + 1] = prefs.nicks[1].word end
            if #list == 0 then return end
            state.testing = true
            local line = #list == 2 and ("Name Highlight test: this is how " .. list[1] .. " and " .. list[2] .. " look when someone says them.")
                or ("Name Highlight test: this is how " .. list[1] .. " looks when someone says it.")
            pcall(function() Chat.AddMessage(line) end)
        end)
        w:Area(X + bw + 6, BIG.buttons, bw, 27, function() state.mentions = {}; u.refresh() end)
        w:Area(X + 2 * (bw + 6), BIG.buttons, bw, 27, function()
            prefs.sound = nextIn(SOUNDS, prefs.sound)
            save()
            play(prefs.sound)
            u.refresh()
        end)
    end
    u.window = RetroUI.ProgramWindow(layer, {
        title = "NAME HIGHLIGHT", small = SIZES.small, big = SIZES.big, state = prefs.win.state, x = prefs.win.x, y = prefs.win.y,
        build = build, draw = draw,
        onState = function(st) prefs.win.state = st; save() end,
        onMove = function(x, y) prefs.win.x, prefs.win.y = x, y; save() end,
    })
    function u.refresh() u.window:Redraw() end
    return u
end
do
    local ok, made = pcall(buildUI)
    if ok then state.ui = made else log("Name Highlight: window: " .. tostring(made)) end
end

-- Every client tick: the window's drag and bulbs, the glow; every 3 s: your name and chat access; every 10 s: the times
Event.Logic.Subscribe("nameHighlightTick", function()
    pcall(function()
        now = now + 1
        if state.ui then state.ui.window:Animate() end
        placeGlow()
        if now % 150 == 1 then
            local me = names.mine()
            if me and me ~= names.me then names.me = me; names.rebuild(); if state.ui then state.ui.refresh() end end
            checkChat()
        end
        if now % 500 == 0 and #state.mentions > 0 and state.ui then state.ui.refresh() end
    end)
end)

-- The cog ---------------------------------------------------------------------------------------------------------
Event.SettingsLayerReady.Subscribe("nameHighlightCog", function(event)
    pcall(function()
        local panel = ui.Layer.new(event.component)
        panel:SetPos(8, 8)
        panel:SetSize(420, 220)
        if state.ui then RetroUI.ShowWindowButton(panel, state.ui.window, 0, 0) end
        local function button(x, y, label, fn)
            local b = ui.Button.new(panel)
            b:SetPos(x, y); b:SetSize(200, 25)
            pcall(function() b.stylesheetID = id.StyleSheet.BUTTON_DEFAULT end)
            pcall(function() b.text.font = id.Font.MUSEO_SANS_15PT_REGULAR end)
            b.label = label()
            b:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
                fn(); b.label = label(); save(); names.rebuild(); if state.ui then state.ui.refresh() end
            end)
        end
        local function onOff(v) return v and "on" or "off" end
        button(0, 30, function() return "Your name: " .. paletteName(prefs.me) end, function() prefs.me = nextColour(prefs.me) end)
        button(0, 60, function() return "Sound: " .. (pick(SOUNDS, prefs.sound) or SOUNDS[1])[2] end, function()
            prefs.sound = nextIn(SOUNDS, prefs.sound); play(prefs.sound)
        end)
        button(0, 90, function() return "Sound when: " .. (prefs.when == "always" and "always" or "tabbed out") end,
            function() prefs.when = nextIn(WHEN, prefs.when) end)
        button(210, 30, function() return "Chat glow: " .. onOff(prefs.glow) end, function() prefs.glow = not prefs.glow end)
        button(210, 60, function() return "Game messages: " .. onOff(prefs.game) end, function() prefs.game = not prefs.game end)
        button(210, 90, function() return "Your own lines: " .. onOff(prefs.mine) end, function() prefs.mine = not prefs.mine end)
        local note = ui.Text.new(panel)
        note:SetPos(0, 126); note:SetSize(410, 80)
        note.font = id.Font.MUSEO_SANS_15PT_REGULAR
        note.clickthrough = true
        note.content = "Listening for: " .. table.concat(names.said, ", ") .. "\nNicknames and their colours: in the window ([] for the big one)."
    end)
end)

function PluginShutdown()
    Event.ChatMessage.Unsubscribe("nameHighlightChat")
    Event.WindowFocusChanged.Unsubscribe("nameHighlightFocus")
    pcall(function() Event.OptionalPermissionChanged.Unsubscribe("nameHighlightPermission") end)
    Event.Logic.Unsubscribe("nameHighlightTick")
    Event.SettingsLayerReady.Unsubscribe("nameHighlightCog")
    for _, r in ipairs(glow) do pcall(function() r:Destroy() end) end
    if state.ui then pcall(function() state.ui.window:Destroy() end) end
end

names.me = names.mine()
names.rebuild()
checkChat(true)
log("Name Highlight " .. VERSION .. ": on. " .. (names.me and ("Listening for " .. table.concat(names.said, ", ") .. ".")
    or "Your name is read once you're logged in.")
    .. (state.hasChat and "" or (" Chat access is off. In the console: " .. table.concat(STEPS, ", ") .. ".")))
