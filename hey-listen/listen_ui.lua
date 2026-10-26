local ListenUI = {}

function ListenUI.make(RetroUI, layer, api)
    local C = RetroUI.COLOURS
    local s = { tab = "list", scroll = 0, picker = nil, query = "", results = {}, note = "", shown = "" }
    local groups = {}                -- the click areas of the current size, by group
    local field = nil
    local window

    -- Search ----------------------------------------------------------------------------------------------------------
    local data, idName = nil, nil
    local function loadData()        -- the name list, read the first time it's needed
        if data then return data end
        data = { names = {}, lower = {}, ids = {} }
        local ok, list = pcall(api.names)
        if ok and type(list) == "table" then
            for _, line in ipairs(list) do
                local name, ids = tostring(line):match("^(.*)|([%d,]*)$")
                if name then
                    data.names[#data.names + 1] = name
                    data.lower[#data.lower + 1] = name:lower()
                    data.ids[#data.ids + 1] = ids
                end
            end
        end
        return data
    end
    local function nameOfId(n)
        local d = loadData()
        if not idName then
            idName = {}
            for i, ids in ipairs(d.ids) do
                for v in ids:gmatch("%d+") do idName[tonumber(v)] = d.names[i] end
            end
        end
        return idName[n] or api.liveName(n)
    end
    local function search(q)
        s.query, s.results, s.scroll = q, {}, 0
        q = q:gsub("^%s+", ""):gsub("%s+$", "")
        if q == "" then return end
        local n = tonumber(q:match("^#?(%d+)$") or "")
        if n then
            local name = nameOfId(n)
            if name then s.results[1] = { name = name, id = n } end
            return
        end
        local d, lq = loadData(), q:lower()
        local first, rest = {}, {}
        for i, l in ipairs(d.lower) do
            local at = l:find(lq, 1, true)
            if at == 1 then first[#first + 1] = i elseif at then rest[#rest + 1] = i end
        end
        for _, list in ipairs({ first, rest }) do
            for _, i in ipairs(list) do
                if #s.results >= 300 then return end
                local count = 1
                for _ in d.ids[i]:gmatch(",") do count = count + 1 end
                s.results[#s.results + 1] = { name = d.names[i], count = count }
            end
        end
    end

    -- Layout ----------------------------------------------------------------------------------------------------------
    local function geometry(state)
        if state == "big" then
            return { X = 21, LW = 378, lcdH = 27, glass = 123, glassH = 231, rowsY = 147, rowH = 30, rows = 6, searchY = 157 }
        end
        return { X = 21, LW = 228, lcdH = 24, glass = 90, glassH = 141, rowsY = 96, rowH = 27, rows = 5 }
    end
    local PICKER = { "off" }
    for _, snd in ipairs(api.sounds) do PICKER[#PICKER + 1] = snd[1] end
    PICKER[#PICKER + 1] = "close"
    local PICK_H = 16

    local function rowsFor()
        if s.tab == "near" then return api.near() end
        if s.tab == "search" then return s.results end
        return api.list()
    end
    local function clampScroll(state)
        local g = geometry(state or window:GetState())
        local most = math.max(0, #rowsFor() - g.rows)
        s.scroll = math.max(0, math.min(most, s.scroll))
    end
    local function big() return window and window:GetState() == "big" end
    -- which areas can be clicked now: those of the tab on show, only on rows that have something in them
    local function setVisible()
        local tab = big() and s.tab or "list"
        local list = rowsFor()
        for name, group in pairs(groups) do
            for r, set in ipairs(group) do
                local on
                if name == "list" then on = tab == "list" and s.picker == nil and list[s.scroll + r] ~= nil
                elseif name == "picker" then on = s.picker ~= nil and tab == "list"
                elseif name == "near" then on = tab == "near" and list[s.scroll + r] ~= nil
                elseif name == "search" then on = tab == "search" and list[s.scroll + r] ~= nil
                else on = true end
                for _, a in ipairs(set) do a.hidden = not on end
            end
        end
        if field then field.hidden = tab ~= "search" end
    end
    local function refresh()
        if not window then return end
        clampScroll()
        setVisible()
        window:Redraw()
    end
    local function setTab(tab)
        s.tab, s.scroll, s.picker, s.note = tab, 0, nil, ""
        api.wantNear(tab == "near" and big())
        refresh()
    end
    local function wheel(delta)
        if type(delta) ~= "number" or delta == 0 then return end
        s.scroll = s.scroll + (delta > 0 and 1 or -1)
        refresh()
    end

    local function build(w, state)
        groups, field = {}, nil
        local g = geometry(state)
        local X, LW = g.X, g.LW
        groups.glass = { { w:Area(X, g.glass, LW, g.glassH, nil, wheel) } }
        groups.list = {}
        for r = 1, g.rows do
            local y = g.rowsY + (r - 1) * g.rowH
            local function entry() return s.scroll + r end
            local set = { w:Area(X + 3, y, 24, 24, function() api.cycleColour(entry()) end, wheel) }
            if state == "big" then
                for k, key in ipairs({ "arrow", "outline", "dot" }) do
                    set[#set + 1] = w:Area(X + 160 + (k - 1) * 38, y + 1, 34, 20, function() api.toggle(entry(), key) end, wheel)
                end
                set[#set + 1] = w:Area(X + 276, y + 1, 54, 20, function() s.picker = entry(); refresh() end, wheel)
                set[#set + 1] = w:Area(X + 334, y + 1, 21, 20, function() api.removeAt(entry()) end, wheel)
            else
                set[#set + 1] = w:Area(X + LW - 27, y + 1, 21, 20, function() api.removeAt(entry()) end, wheel)
            end
            groups.list[r] = set
        end
        if state ~= "big" then return end
        groups.tabs = { {} }
        local tw = math.floor((LW - 12) / 3)
        for i, tab in ipairs({ "list", "near", "search" }) do
            groups.tabs[1][i] = w:Area(X + (i - 1) * (tw + 6), 93, tw, 24, function() setTab(tab) end)
        end
        groups.bottom = { {} }
        local bw = math.floor((LW - 12) / 3)
        local actions = {
            function()                                               -- COPY LIST: into the box, ready for Ctrl+C
                local text = api.copyText()
                setTab("search")
                if field then pcall(function() field.content = text end) end
                s.query, s.results = text, {}
                s.note = text == "" and "Your list is empty." or "Your list is in the box: select it and press Ctrl+C."
                refresh()
            end,
            function()                                               -- ADD TYPED: every name or #ID in the box
                local n = api.addTyped(s.query, nameOfId)
                s.note = n == 0 and "Type names or IDs, with commas between." or ("Added " .. n .. ".")
                refresh()
            end,
            function() api.setMaster("ping"); refresh() end,         -- SOUNDS: on / off for all
        }
        for i, act in ipairs(actions) do groups.bottom[1][i] = w:Area(X + (i - 1) * (bw + 6), 360, bw, 27, act) end
        groups.picker = {}
        for i, key in ipairs(PICKER) do
            groups.picker[i] = { w:Area(X + 153, 126 + (i - 1) * PICK_H, 198, PICK_H, function()
                if key == "close" then s.picker = nil else api.setSound(s.picker, key) end
                refresh()
            end) }
        end
        groups.near, groups.search = {}, {}
        for r = 1, g.rows do
            groups.near[r] = { w:Area(X + 3, g.rowsY + (r - 1) * g.rowH - 3, LW - 6, g.rowH, function()
                local row = api.near()[s.scroll + r]
                if not row then return end
                local at = api.indexOf(row.name, nil)
                if at then api.removeAt(at) else api.add(row.name, nil) end
            end, wheel) }
            groups.search[r] = { w:Area(X + 3, g.searchY + (r - 1) * g.rowH - 3, LW - 6, g.rowH, function()
                local row = s.results[s.scroll + r]
                if not row then return end
                local at = api.indexOf(row.name, row.id)
                if at then api.removeAt(at) else api.add(row.name, row.id) end
            end, wheel) }
        end
        field = w:Field(X + 30, 126, LW - 112, s.query, function(text) search(text); refresh() end)
    end

    -- Drawing ---------------------------------------------------------------------------------------------------------
    local RAINBOW = C.BULBS
    local function chip(paint, x, y, colour)
        paint:Rect(x, y, 18, 18, C.INK)
        if colour == "rainbow" then
            for i = 0, 5 do paint:Rect(x + 3, y + 3 + i * 2, 12, 2, RAINBOW[i + 1]) end
        else
            paint:Rect(x + 3, y + 3, 12, 12, colour)
        end
    end
    local function lcd(paint, g, state)
        local count, tiles = api.status()
        paint:LCD(g.X, 60, g.LW, g.lcdH)
        local left, right
        if #api.list() == 0 then left, right = "ADD AN NPC", ""
        elseif count == 0 then left, right = "NONE NEAR", ""
        elseif state == "big" then left, right = count .. " NEAR YOU", tiles and ("NEAREST " .. tiles .. " TILES") or ""
        else left, right = count .. " NEAR", tiles and (tiles .. " TILES") or "" end
        paint:Text(g.X + 9, 60, g.LW - 18, g.lcdH, left, C.GREEN)
        paint:Text(g.X + 9, 60, g.LW - 18, g.lcdH, right, C.NUMBER, { align = "right" })
    end
    local function scrollMarks(paint, g, count)
        if s.scroll > 0 then paint:Arrow(g.X + g.LW - 12, g.glass + 12, "up", C.FADED, 2) end
        if s.scroll + g.rows < count then paint:Arrow(g.X + g.LW - 12, g.glass + g.glassH - 12, "down", C.FADED, 2) end
    end
    local function drawList(paint, g, state)
        local list = api.list()
        local X = g.X
        if state == "big" then
            paint:Text(X + 30, g.glass + 3, 126, 18, "NPC", C.FADED)
            paint:Text(X + 160, g.glass + 3, 114, 18, "ARW  OUT  DOT", C.FADED)
            paint:Text(X + 276, g.glass + 3, 60, 18, "SOUND", C.FADED)
        end
        for r = 1, g.rows do
            local i = s.scroll + r
            local e = list[i]
            if not e then break end
            local y = g.rowsY + (r - 1) * g.rowH
            chip(paint, X + 6, y + 2, api.chip(e))
            if state == "big" then
                paint:Text(X + 30, y, 126, 22, api.label(e), C.CREAM)
                for k, key in ipairs({ "arrow", "outline", "dot" }) do paint:Button(X + 160 + (k - 1) * 38, y + 1, 34, 20, "", e[key]) end
                paint:Arrow(X + 177, y + 11, "down", e.arrow and C.DARK or C.CHROME_DARK, 2)
                paint:Rect(X + 209, y + 6, 12, 10, e.outline and C.DARK or C.CHROME_DARK)
                paint:Rect(X + 212, y + 9, 6, 4, e.outline and C.GOLD or C.CHROME)
                paint:Rect(X + 249, y + 8, 6, 6, e.dot and C.DARK or C.CHROME_DARK)
                paint:Button(X + 276, y + 1, 54, 20, api.soundLabel(e.sound), e.sound ~= "off" or s.picker == i)
                paint:Button(X + 334, y + 1, 21, 20, "x", false)
            else
                paint:Text(X + 30, y, g.LW - 66, 22, api.label(e), C.CREAM)
                paint:Button(X + g.LW - 27, y + 1, 21, 20, "x", false)
            end
        end
        if #list < g.rows then
            local y = g.rowsY + #list * g.rowH + 3
            if state == "big" then
                paint:Text(X + 9, y, g.LW - 18, 22, "Alt + right-click any NPC, or use SEARCH, to add one.", C.FADED)
            elseif #list < g.rows - 1 then                       -- two short lines in the small window
                paint:Text(X + 9, y, g.LW - 18, 22, "Alt + right-click an NPC,", C.FADED)
                paint:Text(X + 9, y + 20, g.LW - 18, 22, "or press [] to search.", C.FADED)
            end
        end
        scrollMarks(paint, g, #list)
        if state == "big" and s.picker and list[s.picker] then
            local cur = list[s.picker].sound
            paint:Block(X + 150, 123, 204, #PICKER * PICK_H + 6, C.GLASS, C.GLASS_LIGHT)
            for i, key in ipairs(PICKER) do
                local lit = key == cur
                local label = key == "close" and "Close" or (key == "off" and "Off" or api.soundLabel(key))
                paint:Row(X + 153, 126 + (i - 1) * PICK_H, 198, PICK_H, label, lit and key ~= "off" and "PLAY" or nil, lit)
            end
        end
    end
    local function drawRows(paint, g, rows, top, info)
        for r = 1, g.rows do
            local row = rows[s.scroll + r]
            if not row then break end
            local y = top + (r - 1) * g.rowH
            local added = api.indexOf(row.name, row.id) ~= nil
            paint:Text(g.X + 9, y, 180, 22, row.name, C.CREAM)
            paint:Text(g.X + 190, y, 100, 22, info(row), C.NUMBER)
            paint:Button(g.X + g.LW - 82, y + 1, 72, 20, added and "ADDED" or "+ ADD", added)
        end
    end
    local function draw(paint, w, state)
        local g = geometry(state)
        lcd(paint, g, state)
        if state ~= "big" then
            paint:Glass(g.X, g.glass, g.LW, g.glassH)
            drawList(paint, g, state)
            return
        end
        local tw = math.floor((g.LW - 12) / 3)
        for i, t in ipairs({ { "list", "MY LIST" }, { "near", "NEAR ME" }, { "search", "SEARCH" } }) do
            paint:Button(g.X + (i - 1) * (tw + 6), 93, tw, 24, t[2], s.tab == t[1])
        end
        paint:Glass(g.X, g.glass, g.LW, g.glassH)
        if s.tab == "list" then
            drawList(paint, g, state)
        elseif s.tab == "near" then
            local rows = api.near()
            paint:Text(g.X + 9, g.glass + 3, g.LW - 18, 18, "AROUND YOU (20 TILES)", C.FADED)
            drawRows(paint, g, rows, g.rowsY, function(row) return row.count .. "x, " .. row.tiles .. " tiles" end)
            if #rows == 0 then paint:Text(g.X + 9, g.rowsY, g.LW - 18, 22, "Nothing around you yet.", C.FADED) end
            scrollMarks(paint, g, #rows)
        else
            paint:Magnifier(g.X + 9, g.glass + 9)
            paint:Text(g.X + 9, g.glass + 3, g.LW - 18, 25, #s.results > 0 and (#s.results >= 300 and "300+" or #s.results) ..
                " NPC" .. (#s.results == 1 and "" or "s") or "", C.NUMBER, { align = "right" })
            drawRows(paint, g, s.results, g.searchY, function(row)
                return row.id and ("#" .. row.id) or (row.count .. (row.count == 1 and " version" or " versions"))
            end)
            local hint = s.note ~= "" and s.note or (s.query == "" and "Type a name, or a number for one exact NPC." or
                (#s.results == 0 and "No NPC by that name." or ""))
            if #s.results < g.rows and hint ~= "" then
                paint:Text(g.X + 9, g.glass + g.glassH - 27, g.LW - 18, 22, hint, C.FADED)
            end
            scrollMarks(paint, g, #s.results)
        end
        local bw = math.floor((g.LW - 12) / 3)
        for i, label in ipairs({ "COPY LIST", "ADD TYPED", "SOUNDS: " .. (api.master("ping") and "ON" or "OFF") }) do
            paint:Button(g.X + (i - 1) * (bw + 6), 360, bw, 27, label, false)
        end
    end

    window = RetroUI.ProgramWindow(layer, {
        title = "HEY, LISTEN!", small = { 270, 252 }, big = { 420, 408 }, state = api.win.state, x = api.win.x, y = api.win.y,
        build = function(w, state) build(w, state) end,
        draw = draw,
        onState = function(state)
            s.picker = nil
            api.wantNear(state == "big" and s.tab == "near")
            setVisible()
            api.onState(state)
        end,
        onMove = api.onMove,
    })
    setVisible()
    window:Redraw()

    local made = { window = window }
    function made.Refresh() refresh() end
    -- once per server tick: redraw only when what's shown changed (the counts, or what's near)
    function made.Tick()
        if window:GetState() ~= "small" and window:GetState() ~= "big" then return end
        local count, tiles = api.status()
        local key = count .. "|" .. tostring(tiles)
        if s.tab == "near" and big() then
            for _, row in ipairs(api.near()) do key = key .. "|" .. row.name .. row.count .. ":" .. row.tiles end
        end
        if key ~= s.shown then
            s.shown = key
            refresh()
        end
    end
    function made.Animate() window:Animate() end
    function made.Destroy() window:Destroy() end
    made.nameOfId = nameOfId
    return made
end

return ListenUI
