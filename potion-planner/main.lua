-- Apothecary 0.1.7
-- Plan potion batches, combine ingredients and work out what you need to buy.

local Data = require("data/init")
local Prices = require("data/prices")
local Model = require("model")
local View = require("view")
local State = require("state")
local Bank = require("inventory")
local Scrollbar = require("scrollbar")
local DragButton = require("drag_button")
local planner = Model.new(Data, Prices)
local catalogue = Data.catalogue
local recipes = {}
local byOutput = {}
local byCatalogue = {}

for _, recipe in ipairs(Data.recipes) do
    recipes[recipe.key] = recipe
    local output = recipe.output and recipe.output.item
    if output and recipe.verified then
        byOutput[output] = byOutput[output] or {}
        byOutput[output][#byOutput[output] + 1] = recipe
    end
end
for _, entry in ipairs(catalogue) do
    byCatalogue[entry.key] = entry
end

local function readSaved()
    local ok, value = pcall(function()
        return PersistentDB:GetStructuredData("potionPlanner")
    end)
    return ok and value or nil
end

local saved = readSaved()
local state = State.load(saved, Data.items, catalogue)
if type(saved) == "table" and type(saved.windowPosition) == "table" then
    local x = State.number(saved.windowPosition.x, 2147483647)
    local y = State.number(saved.windowPosition.y, 2147483647)
    if x and y then
        state.windowPosition = { x = x, y = y }
    end
end
state.batch = {}
if type(saved) == "table" and type(saved.batch) == "table" then
    local seen = {}
    for _, entry in ipairs(saved.batch) do
        if type(entry) == "table" and recipes[entry.recipe]
            and recipes[entry.recipe].verified == true and not seen[entry.recipe] then
            local quantity = State.number(entry.quantity, 100000)
            if quantity and quantity > 0 and #state.batch < 50 then
                state.batch[#state.batch + 1] = { recipe = entry.recipe, quantity = quantity }
                seen[entry.recipe] = true
            end
        end
    end
end

local stock = {}
local stockLabel = "No stock entered. Ingredient rows let you enter quantities and prices."
local query = ""
local onlyFavourites = false
local page = 1
local detailPage = 1
local tab = "ingredients"
local methodIndex = 1
local quantity = state.batches
local results = {}
local currentPlan
local visibleDetails = {}
local notice = ""
local inputError
local editKey
local dirty = false
local saveProblem = false
local stopped = false
local view
local reopen
local reopenDrag
local scrollbar
local selected = byCatalogue[state.selected]
local actions = {}
local refresh
local function syncScrollbar()
    if scrollbar then
        local pages = math.max(1, math.ceil(#results / View.ROWS))
        scrollbar:set(page, pages, state.hidden or editKey ~= nil)
    end
end

local function methods(entry)
    return entry and byOutput[entry.key] or {}
end

if not selected then
    for _, entry in ipairs(catalogue) do
        if #methods(entry) > 0 then
            selected = selected or entry
            if entry.name == "Attack potion (3)" or entry.name == "Overload (3)" then
                selected = entry
                break
            end
        end
    end
    selected = selected or catalogue[1]
end

local function currentRecipe()
    return methods(selected)[methodIndex]
end

local function money(value)
    return value ~= nil and (Model.formatNumber(value) .. " GP") or "Unknown"
end

local function compactMoney(value)
    if value == nil then
        return "Unknown"
    end
    local magnitude = math.abs(value)
    if magnitude >= 1000000000 then
        return string.format("%.2fb GP", value / 1000000000)
    elseif magnitude >= 1000000 then
        return string.format("%.2fm GP", value / 1000000)
    elseif magnitude >= 100000 then
        return string.format("%.1fk GP", value / 1000)
    end
    return money(value)
end

local function save()
    if not dirty then
        return
    end
    state.selected = selected and selected.key
    state.batches = quantity
    local ok, accepted = pcall(function()
        return PersistentDB:SetStructuredData("potionPlanner", state)
    end)
    if ok and accepted ~= false then
        dirty = false
        saveProblem = false
    else
        saveProblem = true
    end
end

local function changed()
    dirty = true
    save()
end

local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
local function position()
    local width = parent.width or 1920
    local height = parent.height or 1080
    if state.windowPosition then
        return {
            x = math.max(0, math.min(state.windowPosition.x, math.max(0, width - View.WIDTH))),
            y = math.max(0, math.min(state.windowPosition.y, math.max(0, height - View.HEIGHT))),
        }
    end
    local x = 28
    if state.position == "centre" then
        x = math.floor((width - View.WIDTH) / 2)
    elseif state.position == "right" then
        x = width - View.WIDTH - 28
    end
    return {
        x = math.max(0, math.min(x, width - View.WIDTH)),
        y = math.max(0, math.min(80, height - View.HEIGHT)),
    }
end

local function reopenPosition()
    local location = state.reopenPosition or position()
    return {
        x = math.max(0, math.min(location.x, math.max(0, (parent.width or 1920) - 142))),
        y = math.max(0, math.min(location.y, math.max(0, (parent.height or 1080) - 30))),
    }
end

local function search()
    results = {}
    local words = {}
    for word in query:lower():gmatch("%S+") do
        words[#words + 1] = word
    end
    for _, entry in ipairs(catalogue) do
        local matches = not onlyFavourites or state.favourites[entry.key]
        local haystack = (entry.name .. " " .. (entry.category or "")):lower()
        for _, word in ipairs(words) do
            if not haystack:find(word, 1, true) then
                matches = false
            end
        end
        if matches then
            results[#results + 1] = entry
        end
    end
    table.sort(results, function(left, right)
        local a = #methods(left) > 0
        local b = #methods(right) > 0
        if a ~= b then
            return a
        end
        return left.name < right.name
    end)
    page = math.max(1, math.min(page, math.ceil(#results / View.ROWS)))
end

local function options()
    return {
        stock = stock,
        prices = state.prices,
        recursive = state.recursive,
        buyUnfinished = state.buyUnfinished,
        cleanHerbs = state.cleanHerbs,
    }
end

local function calculate()
    if #state.batch > 0 then
        return planner:planMany(state.batch, options())
    end
    local recipe = currentRecipe()
    if recipe then
        return planner:planMany({ { recipe = recipe.key, quantity = quantity } }, options())
    end
    return nil
end

local function priceDescription(key)
    local guide, _, date = planner:unitPrice(key, {})
    if guide ~= nil then
        return "Guide: " .. money(guide) .. " | " .. tostring(date or "Undated")
    end
    local item = Data.items[key]
    if item and (item.tradeable == false or item.geTradeable == false
        or item.gePriceable == false) then
        local makingOptions = options()
        makingOptions.stock = nil
        local making = planner:makingCost(key, makingOptions)
        if making then
            return "Make: ~" .. money(making.unitCost) .. " | "
                .. tostring(making.priceDate or "Ingredient estimates")
        end
    end
    return "No exact guide quote. An entered price is your own estimate."
end

local function wrapped(lines, value)
    if type(value) == "table" then
        for _, part in ipairs(value) do
            wrapped(lines, part)
        end
        return
    end
    local content = tostring(value or ""):gsub("<[^>]*>", ""):gsub("%s+", " ")
    content = content:gsub("%[%[([^%]|]+)|([^%]]+)%]%]", "%2")
    content = content:gsub("%[%[([^%]]+)%]%]", "%1")
    content = content:gsub("''", "")
    if content == "" then
        return
    end
    local line = ""
    for word in content:gmatch("%S+") do
        if #line + #word > (View.WRAP or 78) then
            lines[#lines + 1] = { name = line, full = true }
            line = ""
        end
        line = line == "" and word or (line .. " " .. word)
    end
    if line ~= "" then
        lines[#lines + 1] = { name = line, full = true }
    end
end

local function details(plan, recipe, making)
    local lines = {}
    if tab == "batch" then
        for index, entry in ipairs(state.batch) do
            local item = recipes[entry.recipe]
            local output = item.output
            local batches = math.ceil(entry.quantity / output.quantity)
            lines[#lines + 1] = {
                name = item.name,
                quantity = "Want " .. Model.formatNumber(entry.quantity),
                price = "Make " .. Model.formatNumber(batches * output.quantity),
                editable = true,
                removable = true,
                queueIndex = index,
            }
        end
        if #state.batch == 0 then
            wrapped(lines, "Choose a potion, enter the number to make, then Add to batch.")
            wrapped(lines, "Add several potions for one combined shopping list.")
        end
    elseif tab == "ingredients" and plan then
        for _, entry in ipairs(plan.entries or {}) do
            lines[#lines + 1] = {
                name = entry.name,
                quantity = Model.formatNumber(entry.required) .. " / " .. Model.formatNumber(entry.missing),
                price = (entry.priceOrigin == "making" and entry.unitPrice and "~" or "")
                    .. compactMoney(entry.unitPrice),
                warning = entry.unitPrice == nil,
                editable = true,
                key = entry.key,
            }
        end
    elseif tab == "steps" and plan then
        for index, step in ipairs(plan.steps or {}) do
            local sourceRecipe = recipes[step.recipe]
            local requirements = {}
            for _, skill in ipairs(sourceRecipe and sourceRecipe.skills or {}) do
                if skill.name and skill.level then
                    requirements[#requirements + 1] = tostring(skill.name) .. " " .. tostring(skill.level)
                end
            end
            if #requirements == 0 and step.level then
                requirements[1] = "Herblore " .. tostring(step.level)
            end
            wrapped(lines, tostring(index) .. ". " .. step.name)
            wrapped(lines, "Make " .. Model.formatNumber(step.quantity) .. " in "
                .. Model.formatNumber(step.batches) .. " whole batches.")
            if #requirements > 0 then
                wrapped(lines, "Requires " .. table.concat(requirements, ", "))
            end
            if sourceRecipe then
                if sourceRecipe.quest then
                    wrapped(lines, "Quest: " .. tostring(sourceRecipe.quest))
                end
                if sourceRecipe.facility then
                    wrapped(lines, "At: " .. tostring(sourceRecipe.facility))
                end
                wrapped(lines, sourceRecipe.tools)
                if sourceRecipe.costUnknownReason then
                    wrapped(lines, "Cost to check: " .. sourceRecipe.costUnknownReason)
                end
            end
        end
        for _, leftover in ipairs(plan.leftovers or {}) do
            wrapped(lines, "Left over: " .. Model.formatNumber(leftover.quantity) .. " " .. leftover.name)
        end
        for _, byproduct in ipairs(plan.byproducts or {}) do
            wrapped(lines, "Byproduct: " .. byproduct.name .. " - made "
                .. Model.formatNumber(byproduct.produced) .. ", reused "
                .. Model.formatNumber(byproduct.used) .. ", left "
                .. Model.formatNumber(byproduct.leftover))
        end
        wrapped(lines, "Base recipe yields only. Personal bonuses are not assumed.")
        wrapped(lines, plan.notes)
        for _, choice in ipairs(plan.choices or {}) do
            if choice.alternatives and choice.alternatives > 1 then
                wrapped(lines, "Intermediate method: " .. choice.name .. ". Check its recipe notes.")
            end
        end
    elseif tab == "sources" then
        wrapped(lines, selected and selected.name or "")
        if making then
            wrapped(lines, "Selected recipe from scratch: " .. money(making.batchCost)
                .. " for " .. Model.formatNumber(making.producedQuantity) .. " produced.")
            wrapped(lines, "Average making cost: ~" .. money(making.unitCost) .. " each.")
            wrapped(lines, "Whole batches may leave spare ingredients. Their cost is included.")
        end
        if recipe then
            wrapped(lines, "Recipe: " .. (recipe.variant or recipe.method or recipe.name or recipe.key))
            for _, skill in ipairs(recipe.skills or {}) do
                if skill.name then
                    wrapped(lines, tostring(skill.name) .. ": level " .. tostring(skill.level or "unknown")
                        .. ", " .. tostring(skill.experience or "unknown") .. " XP per batch.")
                end
            end
            if #(recipe.skills or {}) == 0 and recipe.level then
                wrapped(lines, "Herblore level: " .. tostring(recipe.level))
            end
            wrapped(lines, recipe.notes)
            if recipe.quest then
                wrapped(lines, "Quest: " .. tostring(recipe.quest))
            end
            if recipe.facility then
                wrapped(lines, "Facility: " .. tostring(recipe.facility))
            end
            wrapped(lines, recipe.tools)
            wrapped(lines, recipe.discovery)
            if recipe.members then
                wrapped(lines, "Members: " .. tostring(recipe.members))
            end
        else
            wrapped(lines, selected and (selected.reason or selected.status) or "No potion selected.")
            wrapped(lines, "No verified preparation recipe is bundled for this exact form.")
            wrapped(lines, "Dose and container variants may be obtained by decanting.")
        end
        wrapped(lines, "Prices: " .. tostring(Prices.date or "undated") .. ". Guide estimates; actual trades can differ.")
        wrapped(lines, "Individual items can have older quotes. Open an ingredient to see its exact date.")
        wrapped(lines, "Make: and ~ mean a calculated making value, not a GE quote.")
        wrapped(lines, "Untradeable ingredients use verified preparation chains even with MAKE PARTS off.")
        wrapped(lines, state.buyUnfinished and "Unfinished potions: buy the exact form."
            or "Unfinished potions: make them when intermediate preparation is on.")
        wrapped(lines, state.cleanHerbs and "Herbs: clean grimy herbs using verified cleaning recipes."
            or "Herbs: buy clean herbs.")
        wrapped(lines, "Recipe data: RuneScape Wiki. See bundled sources and coverage report.")
        if plan then
            wrapped(lines, "Owned ingredients retain their value in the full material cost.")
            wrapped(lines, "Full material cost: " .. money(plan.totals.ingredientCost))
            wrapped(lines, "Remaining purchase cost: " .. money(plan.totals.buyCost))
            wrapped(lines, "Sale estimate: " .. money(plan.totals.saleValue))
            wrapped(lines, "Estimated sale tax: " .. money(plan.totals.taxCost))
            wrapped(lines, plan.totals.reasons and plan.totals.reasons.profit)
            for _, output in ipairs(plan.outputs or {}) do
                wrapped(lines, output.name .. ": want " .. Model.formatNumber(output.requested)
                    .. ", make " .. Model.formatNumber(output.produced)
                    .. ", spare " .. Model.formatNumber(output.leftover) .. ".")
                wrapped(lines, "Product profit estimate: " .. money(output.profit))
                if output.unitPrice ~= nil then
                    local origin = output.priceOrigin == "manual" and "your entered estimate"
                        or output.priceDate or "undated estimate"
                    wrapped(lines, "Output price: " .. money(output.unitPrice) .. " / " .. origin)
                else
                    wrapped(lines, "Output price unavailable: " .. tostring(output.priceReason
                        or output.saleReason or "no exact GE quote for this form"))
                end
                wrapped(lines, output.costReason)
            end
            for _, ingredient in ipairs(plan.entries or {}) do
                if ingredient.unitPrice == nil then
                    wrapped(lines, "Missing value: " .. ingredient.name .. ". "
                        .. tostring(ingredient.priceReason or "No exact dated quote."))
                elseif ingredient.priceOrigin == "making" then
                    wrapped(lines, "Making value: " .. ingredient.name .. ", ~"
                        .. money(ingredient.unitPrice) .. " each.")
                elseif ingredient.priceDate and ingredient.priceDate ~= Prices.date then
                    wrapped(lines, "Older quote: " .. ingredient.name .. ", "
                        .. money(ingredient.unitPrice) .. " from " .. ingredient.priceDate)
                end
            end
        end
    end
    if plan and tab ~= "batch" then
        for _, blocker in ipairs(plan.blockers or {}) do
            wrapped(lines, type(blocker) == "table" and blocker.message or blocker)
        end
    end
    return lines
end

refresh = function()
    if stopped or not view then
        return
    end
    search()
    currentPlan = calculate()
    local recipe = currentRecipe()
    local rows = {}
    for index = 1, View.ROWS do
        local entry = results[(page - 1) * View.ROWS + index]
        if entry then
            local count = #methods(entry)
            rows[#rows + 1] = {
                name = entry.name,
                caption = count > 0 and (tostring(count) .. (count == 1 and " recipe method" or " recipe methods"))
                    or "Other form / see recipe notes",
                selected = selected and selected.key == entry.key,
            }
        end
    end
    local making
    if recipe then
        local makingOptions = options()
        makingOptions.stock = nil
        makingOptions.quantity = quantity
        makingOptions.recipeChoices = { [recipe.output.item] = recipe.key }
        making = planner:makingCost(recipe.output.item, makingOptions)
    end
    local allDetails = details(currentPlan, recipe, making)
    detailPage = math.max(1, math.min(detailPage, math.ceil(#allDetails / View.DETAIL_ROWS)))
    visibleDetails = {}
    for index = 1, View.DETAIL_ROWS do
        local entry = allDetails[(detailPage - 1) * View.DETAIL_ROWS + index]
        if entry then
            visibleDetails[#visibleDetails + 1] = entry
        end
    end
    local totals = currentPlan and currentPlan.totals or {}
    local count = #methods(selected)
    local source = recipe and recipe.source or selected and selected.source or ""
    if type(source) ~= "string" then
        source = ""
    end
    local queued = false
    for _, entry in ipairs(state.batch) do
        if recipe and entry.recipe == recipe.key then
            queued = true
        end
    end
    local defaultNotice = #state.batch > 0 and (tostring(#state.batch) .. " recipes in your combined batch.")
        or "Recipe preview. Add it to your batch to combine several potions."
    local reason = totals.reasons and totals.reasons.profit
    if reason then
        defaultNotice = reason
    end
    if currentPlan and currentPlan.blockers and currentPlan.blockers[1] then
        defaultNotice = currentPlan.blockers[1].message or defaultNotice
    end
    local outputLabel = recipe and ("Makes " .. Model.formatNumber(math.ceil(quantity / recipe.output.quantity) * recipe.output.quantity)) or ""
    if making then
        outputLabel = outputLabel .. " | ~" .. compactMoney(making.unitCost) .. " each"
    end
    local subtitles = recipe and ("Base output: " .. tostring(recipe.output.quantity) .. " x " .. (Data.items[recipe.output.item].name))
        or "This form has no verified preparation recipe. Check Recipe notes."
    local headings = {
        batch = "Potion",
        ingredients = "Ingredient",
        steps = "Prepare in this order",
        sources = "Exact recipe, requirements and estimate notes",
    }
    local columns = {
        batch = { "Requested", "Made" },
        ingredients = { "Need / missing", "GP each" },
        steps = { "Batches", "Output" },
    }
    local detailFooter = tab == "ingredients" and "Click an ingredient to edit stock or price."
        or tab == "batch" and "Select a row to edit; X removes it from this batch."
        or tab == "steps" and "Whole batches are rounded up; spare ingredients are retained."
        or "Sources describe the selected potion. Prices are dated estimates."
    local summary = stockLabel
    if currentPlan and currentPlan.ok and currentPlan.totalHerbloreXP then
        summary = "Base Herblore XP: " .. Model.formatNumber(currentPlan.totalHerbloreXP)
            .. "  |  " .. stockLabel
    end
    view:render({
        hidden = state.hidden,
        onlyFavourites = onlyFavourites,
        rows = rows,
        pageLabel = tostring(page) .. " / " .. tostring(math.max(1, math.ceil(#results / View.ROWS))) .. "  (" .. tostring(#results) .. ")",
        title = selected and selected.name or "Select a potion",
        subtitle = subtitles,
        favourite = selected and state.favourites[selected.key],
        recursive = state.recursive,
        outputLabel = outputLabel,
        methodLabel = count > 0 and ("Method " .. tostring(methodIndex) .. "/" .. tostring(count) .. " >") or "No recipe",
        addLabel = queued and "Update batch" or "Add to batch",
        materialCost = compactMoney(totals.ingredientCost),
        buyCost = compactMoney(totals.buyCost),
        profit = totals.profit ~= nil and compactMoney(totals.profit) or "Not available",
        profitColour = totals.profit == nil and "neutral" or totals.profit < 0 and "red" or "green",
        tab = tab,
        detail = visibleDetails,
        detailHeading = headings[tab],
        detailColumns = columns[tab],
        detailFooter = detailFooter .. "  " .. tostring(detailPage) .. "/" .. tostring(math.max(1, math.ceil(#allDetails / View.DETAIL_ROWS))),
        notice = inputError or (saveProblem and "Preferences applied; waiting to save.") or (notice ~= "" and notice) or defaultNotice,
        warning = inputError ~= nil or saveProblem,
        stockLabel = summary,
        xp = currentPlan and currentPlan.ok and currentPlan.totalHerbloreXP
            and (compactMoney(currentPlan.totalHerbloreXP):gsub(" GP$", " XP")) or "XP unknown",
        source = source,
        footer = tostring(#catalogue) .. " forms | Latest snapshot: " .. tostring(Prices.date or "unknown") .. " | Item dates vary",
    })
    if reopen then
        reopen.hidden = not state.hidden
    end
    syncScrollbar()
end

actions.search = function(value)
    query = value:sub(1, 160)
    page = 1
    refresh()
end
actions.filter = function(favourites)
    onlyFavourites = favourites
    page = 1
    refresh()
end
actions.page = function(direction)
    page = page + direction
    refresh()
end
actions.pageTo = function(target)
    local pages = math.max(1, math.ceil(#results / View.ROWS))
    local number = State.number(target, pages)
    if number and number >= 1 then
        page = number
        refresh()
    end
end
actions.wheel = function(delta)
    if type(delta) == "number" and delta ~= 0 then
        actions.page(delta > 0 and 1 or -1)
    end
end
actions.detailPage = function(direction)
    detailPage = detailPage + direction
    refresh()
end
actions.detailWheel = function(delta)
    if type(delta) == "number" and delta ~= 0 then
        actions.detailPage(delta > 0 and 1 or -1)
    end
end
actions.select = function(row)
    local entry = results[(page - 1) * View.ROWS + row]
    if entry then
        selected = entry
        methodIndex = 1
        detailPage = 1
        notice = ""
        inputError = nil
        changed()
        refresh()
    end
end
actions.batches = function(value)
    local amount, problem = State.number(value, 100000)
    inputError = problem
    if amount == 0 then
        inputError = "Enter at least one potion."
    elseif amount then
        quantity = amount
        changed()
    end
    refresh()
end
actions.favourite = function()
    if selected then
        state.favourites[selected.key] = not state.favourites[selected.key] or nil
        changed()
        refresh()
    end
end
actions.method = function()
    local count = #methods(selected)
    if count > 0 then
        methodIndex = methodIndex % count + 1
        notice = "Selected recipe changed. Check its requirements in Recipe notes."
        detailPage = 1
        refresh()
    end
end
actions.recursive = function()
    state.recursive = not state.recursive
    detailPage = 1
    notice = ""
    changed()
    refresh()
end
actions.bank = function()
    local contents, message, report = Bank.read(Data.items)
    pcall(function()
        PersistentDB:SetStructuredData("potionPlannerBankRead", report)
    end)
    if contents then
        stock = contents
        stockLabel = message
    end
    notice = contents and "Bank and backpack counted together. Exact item forms stay separate." or message
    refresh()
end
actions.add = function()
    local recipe = currentRecipe()
    if not recipe or inputError then
        notice = "Choose a verified recipe and enter a valid amount first."
        refresh()
        return
    end
    for _, entry in ipairs(state.batch) do
        if entry.recipe == recipe.key then
            entry.quantity = quantity
            changed()
            refresh()
            return
        end
    end
    if #state.batch >= 50 then
        notice = "A batch can contain up to 50 different recipes."
    else
        state.batch[#state.batch + 1] = { recipe = recipe.key, quantity = quantity }
        notice = "Added to your batch. Shopping list now combines all queued potions."
        tab = "batch"
        detailPage = 1
        changed()
    end
    refresh()
end
actions.tab = function(name)
    tab = name
    detailPage = 1
    refresh()
end
actions.edit = function(row)
    local entry = visibleDetails[row]
    if not entry then
        return
    end
    if entry.queueIndex then
        local queued = state.batch[entry.queueIndex]
        local recipe = recipes[queued.recipe]
        selected = byCatalogue[recipe.output.item]
        for index, method in ipairs(methods(selected)) do
            if method.key == recipe.key then
                methodIndex = index
            end
        end
        quantity = queued.quantity
        view.batches.content = tostring(quantity)
        notice = "Edit the amount, then choose Update batch."
        refresh()
    elseif entry.key then
        editKey = entry.key
        view:editor(Data.items[editKey], stock[editKey], state.prices[editKey], nil, priceDescription(editKey))
        syncScrollbar()
    end
end
actions.remove = function(row)
    local entry = visibleDetails[row]
    if entry and entry.queueIndex then
        table.remove(state.batch, entry.queueIndex)
        notice = "Removed from the batch."
        changed()
        refresh()
    end
end
actions.closeItem = function()
    editKey = nil
    view:editor(nil)
    syncScrollbar()
end
actions.saveItem = function(stockText, priceText)
    if not editKey then
        return
    end
    local amount, stockProblem = State.number(stockText, 2147483647)
    local price, priceProblem = State.number(priceText, 2147483647, true)
    if stockProblem or priceProblem then
        view:editor(Data.items[editKey], stockText, priceText, stockProblem or priceProblem, priceDescription(editKey))
        return
    end
    stock[editKey] = amount
    state.prices[editKey] = price
    stockLabel = "Session stock includes manual entries. Read bank and backpack to replace them."
    changed()
    actions.closeItem()
    notice = "Your stock and price have been applied."
    refresh()
end
actions.resetItem = function()
    if editKey then
        state.prices[editKey] = nil
        changed()
        actions.closeItem()
        notice = "Personal price removed. The dated guide price is used where available."
        refresh()
    end
end
actions.hide = function()
    state.hidden = not state.hidden
    actions.closeItem()
    changed()
    refresh()
end
actions.move = function(x, y)
    local width = parent.width or 1920
    local height = parent.height or 1080
    local validX = State.number(x, 2147483647)
    local validY = State.number(y, 2147483647)
    if not validX or not validY then
        return
    end
    state.windowPosition = {
        x = math.max(0, math.min(validX, math.max(0, width - View.WIDTH))),
        y = math.max(0, math.min(validY, math.max(0, height - View.HEIGHT))),
    }
    changed()
end

view = View.new(parent, actions, position())
view.batches.content = tostring(quantity)
local layout = View.LAYOUT
local trackTop = layout.previous[2] + 33
scrollbar = Scrollbar.new(view.controls.next, {
    x = layout.previous[1],
    y = trackTop,
    width = 30,
    height = layout.next[2] - trackTop,
    thumb = 36,
    pixel = 3,
    arrowHeight = 30,
}, actions.pageTo)

-- Keep the existing view contract and saved plugin identity. These additional
-- controls belong to the controller; view.lua is maintained separately.
local closeX = View.WIDTH - 84
local closeY = 60
local close = ui.Button.new(view.root)
close:SetPos(closeX, closeY)
close:SetSize(27, 27)
close.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
close.label = "X"
close.clickthrough = false
close:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
    if not state.hidden then
        actions.hide()
    end
end)
close:Subscribe(ui.Hook.ONSCROLLWHEEL, function() return false end)

reopen = ui.Button.new(parent)
local collapsedPosition = reopenPosition()
reopen:SetPos(collapsedPosition.x, collapsedPosition.y)
reopen:SetSize(142, 30)
reopen.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
reopen.label = "Apothecary"
reopen.clickthrough = false
reopenDrag = DragButton.new(reopen, parent, collapsedPosition, function(x, y)
    state.reopenPosition = { x = x, y = y }
    changed()
end, actions.hide)
reopen:Subscribe(ui.Hook.ONSCROLLWHEEL, function() return false end)

-- The view guards its original controls. Guard the extended track and the new
-- buttons too. The official menu API appends the highest-priority entry last;
-- the entry is a no-op because the native UI hook performs the click once.
Event.MiniMenuReady.Subscribe("potionPlannerExtraControls", function(event)
    local ok, over = pcall(function()
        local mx = Mouse.GetX()
        local my = Mouse.GetY()
        local function inside(component, x, y, width, height)
            local origin = component.xyGlobal
            local localX = mx - origin.x
            local localY = my - origin.y
            return localX >= x and localY >= y and localX < x + width and localY < y + height
        end
        if state.hidden then
            return inside(reopen, 0, 0, 142, 30)
        end
        return inside(view.root, closeX, closeY, 27, 27)
            or (editKey == nil and inside(view.root, layout.previous[1], trackTop,
                30, layout.next[2] - trackTop))
    end)
    if ok and over then
        event.miniMenu:Add("Apothecary", function() end)
    end
end)

Event.SettingsLayerReady.Subscribe("potionPlannerSettings", function(event)
    local panel = ui.Layer.new(event.component)
    panel:SetPos(10, 10)
    panel:SetSize(380, 350)
    local title = ui.Text.new(panel)
    title:SetPos(0, 0)
    title:SetSize(370, 44)
    title.font = id.Font.MUSEO_SANS_15PT_REGULAR
    title.content = "Apothecary\nRecipes and dated guide estimates."
    title.clickthrough = true
    local function button(label, y, callback)
        local control = ui.Button.new(panel)
        control:SetPos(0, y)
        control:SetSize(340, 28)
        control.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
        control.label = label
        control.clickthrough = false
        control:Subscribe(ui.Hook.ONBUTTONPRESSED, callback)
        return control
    end
    local visibility
    visibility = button(state.hidden and "Show planner" or "Hide planner", 54, function()
        actions.hide()
        visibility.label = state.hidden and "Show planner" or "Hide planner"
    end)
    local placement
    placement = button("Window: " .. state.position, 90, function()
        state.position = state.position == "left" and "centre" or state.position == "centre" and "right" or "left"
        state.windowPosition = nil
        state.reopenPosition = nil
        local location = position()
        view:setPosition(location.x, location.y)
        reopenDrag:setPosition(location.x, location.y)
        placement.label = "Window: " .. state.position
        changed()
    end)
    button("Clear owned stock (keep your batch)", 126, function()
        stock = {}
        stockLabel = "No stock entered."
        notice = "Owned stock cleared."
        refresh()
    end)
    local confirm = false
    local clear
    clear = button("Clear the saved batch", 162, function()
        if not confirm then
            confirm = true
            clear.label = "Confirm: clear this batch"
            return
        end
        state.batch = {}
        clear.label = "Batch cleared"
        changed()
        refresh()
    end)
    local unfinished
    local function unfinishedLabel()
        return state.buyUnfinished and "Unfinished potions: buy" or "Unfinished potions: make"
    end
    unfinished = button(unfinishedLabel(), 198, function()
        state.buyUnfinished = not state.buyUnfinished
        unfinished.label = unfinishedLabel()
        notice = "Preparation preference changed. Your requested amounts are unchanged."
        changed()
        refresh()
    end)
    local herbs
    local function herbLabel()
        return state.cleanHerbs and "Herbs: buy grimy and clean them" or "Herbs: buy clean"
    end
    herbs = button(herbLabel(), 234, function()
        state.cleanHerbs = not state.cleanHerbs
        herbs.label = herbLabel()
        notice = "Herb preference changed. Check Preparation for requirements."
        changed()
        refresh()
    end)
    button("Edit selected potion price / owned stock", 270, function()
        if selected and Data.items[selected.key] then
            editKey = selected.key
            view:editor(Data.items[editKey], stock[editKey], state.prices[editKey], nil,
                priceDescription(editKey))
            syncScrollbar()
        end
    end)
end)

local ticks = 0
Event.Logic.Subscribe("potionPlannerSave", function()
    reopenDrag:tick()
    if scrollbar then
        scrollbar:tick()
    end
    ticks = ticks + 1
    if dirty and ticks % 100 == 0 then
        save()
        refresh()
    end
end)

function onUnload()
    stopped = true
    save()
    Event.Logic.Unsubscribe("potionPlannerSave")
    Event.SettingsLayerReady.Unsubscribe("potionPlannerSettings")
    Event.MiniMenuReady.Unsubscribe("potionPlannerExtraControls")
    if scrollbar then
        scrollbar:destroy()
    end
    reopenDrag:destroy()
    view:destroy()
    reopen.hidden = true
    reopen:Destroy()
end

refresh()
log("Apothecary 0.1.7: Shopping shows ingredients, quantities and prices.")
