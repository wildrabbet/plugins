local Model = {}
local Planner = {}
Planner.__index = Planner

Model.MAX_BATCHES = 100000
Model.MAX_QUANTITY = 1000000000000
Model.MAX_TOTAL = 9007199254740991
Model.MAX_DEPTH = 48
Model.MAX_REQUESTS = 20000

local function wholeNumber(value, minimum, maximum)
    return type(value) == "number"
        and value == value
        and value >= minimum
        and value <= maximum
        and value == math.floor(value)
end

local function finiteNumber(value, minimum, maximum)
    return type(value) == "number"
        and value == value
        and value >= minimum
        and value <= maximum
end

local function sortedKeys(values)
    local keys = {}
    if type(values) ~= "table" then
        return keys
    end
    for key in pairs(values) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function itemName(item, key)
    if type(item) == "table" and type(item.name) == "string" then
        return item.name
    end
    return tostring(key)
end

local function priceId(item)
    if type(item) ~= "table" then
        return nil
    end
    if wholeNumber(item.priceId, 0, Model.MAX_TOTAL) then
        return item.priceId
    end
    if wholeNumber(item.id, 0, Model.MAX_TOTAL) then
        return item.id
    end
    if type(item.ids) == "table" and #item.ids == 1 then
        if wholeNumber(item.ids[1], 0, Model.MAX_TOTAL) then
            return item.ids[1]
        end
    end
    return nil
end

local function mappedValue(values, key, item)
    if type(values) ~= "table" then
        return nil
    end
    if values[key] ~= nil then
        return values[key]
    end
    local id = priceId(item)
    if id ~= nil then
        if values[id] ~= nil then
            return values[id]
        end
        return values[tostring(id)]
    end
    return nil
end

local function safeAdd(left, right, maximum)
    if left > maximum - right then
        return nil
    end
    return left + right
end

local function safeMultiply(left, right, maximum)
    if left ~= 0 and right > maximum / left then
        return nil
    end
    return left * right
end

local function addIssue(plan, code, message, key)
    local identity = code .. ":" .. tostring(key or "")
    if plan._issues[identity] then
        return
    end
    plan._issues[identity] = true
    plan.blockers[#plan.blockers + 1] = {
        code = code,
        message = message,
        item = key,
    }
    plan.ok = false
end

local function addNote(plan, message)
    if not plan._notes[message] then
        plan._notes[message] = true
        plan.notes[#plan.notes + 1] = message
    end
end

local function newPlan(recipeKey, batches)
    local entries = {}
    return {
        ok = true,
        recipeKey = recipeKey,
        batches = batches,
        entries = entries,
        ingredients = entries,
        directEntries = {},
        steps = {},
        leftovers = {},
        byproducts = {},
        choices = {},
        blockers = {},
        notes = {},
        totals = {
            reasons = {},
            unknownIngredientPrices = 0,
            unknownPurchasePrices = 0,
        },
        _issues = {},
        _notes = {},
    }
end

local function finishPlan(plan)
    plan._issues = nil
    plan._notes = nil
    return plan
end

local function validateRecipe(planner, recipe, plan)
    if type(recipe) ~= "table" then
        addIssue(plan, "recipe_missing", "No recipe is available for this selection.")
        return false
    end
    if recipe.verified ~= true then
        addIssue(plan, "recipe_unverified", "The selected recipe has not been verified.", recipe.key)
        return false
    end
    if type(recipe.output) ~= "table" then
        addIssue(plan, "output_missing", "The recipe has no verified output.", recipe.key)
        return false
    end
    if type(recipe.output.item) ~= "string" or not planner.items[recipe.output.item] then
        addIssue(plan, "output_unknown", "The output item is missing from the catalogue.", recipe.key)
        return false
    end
    if not wholeNumber(recipe.output.quantity, 1, Model.MAX_QUANTITY) then
        addIssue(plan, "output_quantity", "The recipe has an invalid output quantity.", recipe.key)
        return false
    end
    if type(recipe.ingredients) ~= "table" or #recipe.ingredients == 0 then
        addIssue(plan, "ingredients_missing", "The recipe has no verified ingredients.", recipe.key)
        return false
    end
    for _, ingredient in ipairs(recipe.ingredients) do
        if type(ingredient) ~= "table"
            or type(ingredient.item) ~= "string"
            or not planner.items[ingredient.item] then
            addIssue(plan, "ingredient_unknown", "An ingredient is missing from the catalogue.", recipe.key)
            return false
        end
        if not wholeNumber(ingredient.quantity, 1, Model.MAX_QUANTITY) then
            addIssue(plan, "ingredient_quantity", "The recipe has an invalid ingredient quantity.", recipe.key)
            return false
        end
    end
    if recipe.byproducts ~= nil then
        if type(recipe.byproducts) ~= "table" then
            addIssue(plan, "byproducts_invalid", "The recipe byproducts are invalid.", recipe.key)
            return false
        end
        for _, byproduct in ipairs(recipe.byproducts) do
            if type(byproduct) ~= "table"
                or type(byproduct.item) ~= "string"
                or not planner.items[byproduct.item] then
                addIssue(plan, "byproduct_unknown", "A byproduct is missing from the catalogue.", recipe.key)
                return false
            end
            if not wholeNumber(byproduct.quantity, 1, Model.MAX_QUANTITY) then
                addIssue(plan, "byproduct_quantity", "A recipe has an invalid byproduct quantity.", recipe.key)
                return false
            end
        end
    end
    return true
end

function Model.new(data, prices)
    data = type(data) == "table" and data or {}
    prices = type(prices) == "table" and prices or {}
    local planner = setmetatable({
        data = data,
        items = type(data.items) == "table" and data.items or {},
        prices = prices,
        recipes = {},
        recipesByOutput = {},
        duplicates = {},
    }, Planner)
    local sourceRecipes = type(data.recipes) == "table" and data.recipes or {}
    for _, recipe in ipairs(sourceRecipes) do
        if type(recipe) == "table" and type(recipe.key) == "string" then
            if planner.recipes[recipe.key] then
                planner.duplicates[recipe.key] = true
            else
                planner.recipes[recipe.key] = recipe
                if type(recipe.output) == "table" and type(recipe.output.item) == "string" then
                    local key = recipe.output.item
                    planner.recipesByOutput[key] = planner.recipesByOutput[key] or {}
                    local choices = planner.recipesByOutput[key]
                    choices[#choices + 1] = recipe
                end
            end
        end
    end
    for _, recipes in pairs(planner.recipesByOutput) do
        table.sort(recipes, function(left, right)
            if left.cleanHerb == true and right.cleanHerb == true then
                local leftPriority = type(left.cleaningPriority) == "number"
                    and left.cleaningPriority or math.huge
                local rightPriority = type(right.cleaningPriority) == "number"
                    and right.cleaningPriority or math.huge
                if leftPriority ~= rightPriority then
                    return leftPriority < rightPriority
                end
            end
            return left.key < right.key
        end)
    end
    return planner
end

function Planner:unitPrice(key, options)
    local item = self.items[key]
    options = options or {}
    local value = mappedValue(options.priceOverrides, key, item)
    if value == nil then
        value = mappedValue(options.prices, key, item)
    end
    local origin = "manual"
    local date = nil
    if value == nil then
        local snapshot = self.prices
        if type(self.prices.items) == "table" then
            snapshot = self.prices.items
        elseif type(self.prices.prices) == "table" then
            snapshot = self.prices.prices
        end
        local id = priceId(item)
        if id ~= nil and type(snapshot) == "table" then
            value = snapshot[id]
            if value == nil then
                value = snapshot[tostring(id)]
            end
        end
        origin = "guide"
        date = self.prices.date
    end
    if type(value) == "table" then
        date = value.date or date
        value = value.value
    end
    if value == nil then
        return nil, "No saved price for this exact item.", date, origin
    end
    if not wholeNumber(value, 0, Model.MAX_TOTAL) then
        return nil, "The entered price must be a non-negative whole number.", date, origin
    end
    return value, nil, date, origin
end

function Planner:makingCost(itemKey, options)
    options = type(options) == "table" and options or {}
    local item = self.items[itemKey]
    if type(itemKey) ~= "string" or not item then
        return nil, "The requested item is missing from the catalogue."
    end

    local requestedQuantity = options.quantity
    if requestedQuantity == nil then
        requestedQuantity = 1
    end
    if not wholeNumber(requestedQuantity, 1, Model.MAX_QUANTITY) then
        return nil, "Choose a positive whole number of items to make."
    end

    local visited = options._makingCostVisited or {}
    if visited[itemKey] then
        return nil, "A cycle prevents calculating this item's making cost."
    end
    local nextVisited = {}
    for key, value in pairs(visited) do
        nextVisited[key] = value
    end
    nextVisited[itemKey] = true

    local choices = self.recipesByOutput[itemKey] or {}
    local requestedRecipe = mappedValue(options.recipeChoices, itemKey, item)
    local explicitRecipe = requestedRecipe ~= nil
    local name = itemName(item, itemKey):lower()
    local unfinished = name:find("(unf)", 1, true)
        or name:find("(unfinished)", 1, true)
    local cleanHerb = name:match("^clean ")
    if requestedRecipe == nil
        and ((options.buyUnfinished == true and unfinished)
            or (options.cleanHerbs ~= true and cleanHerb)) then
        return nil, "Current preparation preferences leave this item to be bought."
    end

    if requestedRecipe == nil then
        local defaults = type(self.data.defaultRecipes) == "table"
            and self.data.defaultRecipes or {}
        requestedRecipe = defaults[itemKey]
    end

    local rootRecipe = nil
    if requestedRecipe ~= nil then
        rootRecipe = self.recipes[requestedRecipe]
        if not rootRecipe or rootRecipe.output.item ~= itemKey
            or self.duplicates[requestedRecipe] then
            return nil, "The selected method does not make this exact item."
        end
        if rootRecipe.verified ~= true then
            return nil, "The selected method has not been verified."
        end
    else
        for _, candidate in ipairs(choices) do
            if candidate.verified == true and not self.duplicates[candidate.key] then
                rootRecipe = candidate
                break
            end
        end
    end
    if not rootRecipe then
        return nil, "No verified recipe makes this exact item."
    end

    local valuationOptions = {}
    for key, value in pairs(options) do
        valuationOptions[key] = value
    end
    valuationOptions._makingCostVisited = nextVisited
    valuationOptions.stock = {}

    local plan = self:planMany({ {
        recipe = rootRecipe.key,
        quantity = requestedQuantity,
    } }, valuationOptions)
    if not plan.ok then
        local blocker = plan.blockers[1]
        return nil, blocker and blocker.message or "The recipe chain could not be calculated.", plan
    end

    for _, row in ipairs(plan.entries) do
        if row.required > 0
            and row.priceOrigin ~= "manual"
            and row.priceOrigin ~= "making"
            and (type(row.priceDate) ~= "string" or row.priceDate == "") then
            return nil, "A dated exact ingredient quote is missing for " .. row.name .. ".", plan
        end
    end
    local batchCost = plan.totals.ingredientCost
    if batchCost == nil then
        return nil, plan.totals.reasons.ingredientCost
            or "One or more ingredient prices are unavailable.", plan
    end

    local purchasePlan = plan
    if options.stock ~= nil then
        local purchaseOptions = {}
        for key, value in pairs(options) do
            purchaseOptions[key] = value
        end
        purchaseOptions._makingCostVisited = nextVisited
        purchasePlan = self:planMany({ {
            recipe = rootRecipe.key,
            quantity = requestedQuantity,
        } }, purchaseOptions)
        if not purchasePlan.ok then
            local blocker = purchasePlan.blockers[1]
            return nil, blocker and blocker.message
                or "The stock-adjusted purchase calculation could not be completed.", purchasePlan
        end
    end
    local purchaseCost = purchasePlan.totals.buyCost
    if purchaseCost == nil then
        return nil, purchasePlan.totals.reasons.buyCost
            or "One or more purchase prices are unavailable.", purchasePlan
    end

    local output = plan.outputs[1]
    if not output or not wholeNumber(output.quantity, 1, Model.MAX_QUANTITY) then
        return nil, "The selected method has no valid produced quantity.", plan
    end
    local leaves = {}
    local allLeavesDatedGuide = true
    local commonPriceDate = nil
    for _, row in ipairs(plan.entries) do
        leaves[#leaves + 1] = {
            item = row.key,
            name = row.name,
            quantity = row.required,
            owned = row.owned,
            missing = row.missing,
            unitPrice = row.unitPrice,
            priceDate = row.priceDate,
            priceOrigin = row.priceOrigin,
        }
        if row.required > 0 then
            if row.priceOrigin ~= "guide"
                or type(row.priceDate) ~= "string"
                or row.priceDate == "" then
                allLeavesDatedGuide = false
            elseif commonPriceDate == nil then
                commonPriceDate = row.priceDate
            elseif commonPriceDate ~= row.priceDate then
                allLeavesDatedGuide = false
            end
        end
    end

    return {
        kind = "derivedMakingCost",
        item = itemKey,
        recipeKey = rootRecipe.key,
        requestedQuantity = output.requested,
        producedQuantity = output.quantity,
        surplus = output.leftover,
        batches = output.batches,
        batchCost = batchCost,
        unitCost = batchCost / output.quantity,
        requestedUnitCost = batchCost / requestedQuantity,
        purchaseCost = purchaseCost,
        unitPurchaseCost = purchaseCost / output.quantity,
        priceDate = allLeavesDatedGuide and commonPriceDate or nil,
        priceSource = allLeavesDatedGuide and plan.priceSource or nil,
        leaves = leaves,
        plan = plan,
        purchasePlan = purchasePlan,
    }
end

function Planner:search(query, category)
    query = tostring(query or ""):lower()
    local results = {}
    for key, recipe in pairs(self.recipes) do
        local name = recipe.name or itemName(self.items[recipe.output and recipe.output.item], key)
        local matchesCategory = not category or category == "" or category == "all"
            or recipe.category == category
        if matchesCategory and name:lower():find(query, 1, true) then
            results[#results + 1] = recipe
        end
    end
    table.sort(results, function(left, right)
        local leftName = tostring(left.name or left.key):lower()
        local rightName = tostring(right.name or right.key):lower()
        if leftName == rightName then
            return left.key < right.key
        end
        return leftName < rightName
    end)
    return results
end

function Planner:plan(recipeKey, batches, options)
    options = type(options) == "table" and options or {}
    local plan = newPlan(recipeKey, batches)
    plan.recursive = options.recursive == true
    plan.priceDate = self.prices.date
    plan.priceSource = self.prices.source
    if not wholeNumber(batches, 1, Model.MAX_BATCHES) then
        addIssue(plan, "batch_quantity", "Choose a whole number of batches from 1 to 100,000.")
        return finishPlan(plan)
    end
    if self.duplicates[recipeKey] then
        addIssue(plan, "duplicate_recipe", "The catalogue contains a duplicate recipe key.", recipeKey)
        return finishPlan(plan)
    end
    local root = self.recipes[recipeKey]
    if not validateRecipe(self, root, plan) then
        return finishPlan(plan)
    end
    local outputQuantity = safeMultiply(root.output.quantity, batches, Model.MAX_QUANTITY)
    if not outputQuantity then
        addIssue(plan, "quantity_limit", "The requested output exceeds the calculation limit.", root.output.item)
        return finishPlan(plan)
    end
    return self:_planRoots({ {
        recipe = root,
        batches = batches,
        requestedQuantity = outputQuantity,
        quantity = outputQuantity,
        leftover = 0,
    } }, recipeKey, batches, options, false)
end

function Planner:planMany(requests, options)
    options = type(options) == "table" and options or {}
    local plan = newPlan("multiple", 1)
    plan.recursive = options.recursive == true
    plan.priceDate = self.prices.date
    plan.priceSource = self.prices.source
    if type(requests) ~= "table" or #requests == 0 or #requests > 64 then
        addIssue(plan, "request_list", "Choose between 1 and 64 recipe quantities.")
        return finishPlan(plan)
    end

    local grouped = {}
    local ordered = {}
    local outputMethods = {}
    for _, request in ipairs(requests) do
        if type(request) ~= "table" or type(request.recipe) ~= "string"
            or not wholeNumber(request.quantity, 1, Model.MAX_QUANTITY) then
            addIssue(plan, "request_quantity", "Each request needs a recipe and a whole output quantity.")
            return finishPlan(plan)
        end
        local key = request.recipe
        if self.duplicates[key] then
            addIssue(plan, "duplicate_recipe", "The catalogue contains a duplicate recipe key.", key)
            return finishPlan(plan)
        end
        local recipe = self.recipes[key]
        if not validateRecipe(self, recipe, plan) then
            return finishPlan(plan)
        end
        local outputKey = recipe.output.item
        local previousMethod = outputMethods[outputKey]
        if previousMethod and previousMethod ~= key then
            addIssue(plan, "ambiguous_root_recipe",
                "The same output was requested through different recipes; choose one recipe method.", outputKey)
            return finishPlan(plan)
        end
        outputMethods[outputKey] = key

        local entry = grouped[key]
        if not entry then
            entry = { recipe = recipe, requestedQuantity = 0 }
            grouped[key] = entry
            ordered[#ordered + 1] = entry
        end
        local requested = safeAdd(entry.requestedQuantity, request.quantity, Model.MAX_QUANTITY)
        if not requested then
            addIssue(plan, "quantity_limit", "The combined requested output exceeds the calculation limit.", outputKey)
            return finishPlan(plan)
        end
        entry.requestedQuantity = requested
    end

    local roots = {}
    for _, entry in ipairs(ordered) do
        local recipe = entry.recipe
        local batches = math.ceil(entry.requestedQuantity / recipe.output.quantity)
        local quantity = safeMultiply(batches, recipe.output.quantity, Model.MAX_QUANTITY)
        if not quantity or not wholeNumber(batches, 1, Model.MAX_BATCHES) then
            addIssue(plan, "quantity_limit", "The rounded output exceeds the batch calculation limit.", recipe.output.item)
            return finishPlan(plan)
        end
        roots[#roots + 1] = {
            recipe = recipe,
            batches = batches,
            requestedQuantity = entry.requestedQuantity,
            quantity = quantity,
            leftover = quantity - entry.requestedQuantity,
        }
    end
    return self:_planRoots(roots, "multiple", 1, options, true)
end

function Planner:_planRoots(rootRequests, recipeKey, batches, options, isMulti)
    local plan = newPlan(recipeKey, batches)
    plan.recursive = options.recursive == true
    plan.priceDate = self.prices.date
    plan.priceSource = self.prices.source
    local root = rootRequests[1].recipe
    plan.outputs = {}
    for _, request in ipairs(rootRequests) do
        local item = self.items[request.recipe.output.item]
        plan.outputs[#plan.outputs + 1] = {
            recipe = request.recipe.key,
            key = request.recipe.output.item,
            item = request.recipe.output.item,
            name = itemName(item, request.recipe.output.item),
            requested = request.requestedQuantity,
            quantity = request.quantity,
            leftover = request.leftover,
            batches = request.batches,
            tradeable = item.tradeable,
            gePriceable = item.gePriceable,
            xpPerBatch = request.recipe.xp,
            xp = finiteNumber(request.recipe.xp, 0, Model.MAX_TOTAL)
                and safeMultiply(request.recipe.xp, request.batches, Model.MAX_TOTAL) or nil,
            source = request.recipe.source,
        }
    end
    if not isMulti then
        plan.output = plan.outputs[1]
    end
    plan.products = plan.outputs
    if not isMulti then
        plan.recipe = root
    end
    plan.totalXP = 0
    plan.xpKnown = true
    plan.totalXPBySkill = {}
    plan.totalXPBySkillKnown = true
    addNote(plan, "Base recipe quantities only; no outfit, portable, well, cape or saving bonuses are assumed.")
    addNote(plan, "Guide prices are dated estimates. Actual buy and sell prices can differ.")

    local stock = type(options.stock) == "table" and options.stock or options.bank
    local availableStock = {}
    local generated = {}
    local generatedContext = {}
    local generatedByproduct = {}
    local byproductRows = {}
    local ambiguousProductCosts = {}
    local ingredientRows = {}
    local directRows = {}
    local rootCostRows = {}
    local stepRows = {}
    local selectedRecipes = {}
    local active = {}
    local requestCount = 0
    local stockRead = {}
    local hasSkillData = false
    local missingSkillData = false

    local function addGenerated(key, quantity, context, byproduct)
        if quantity <= 0 then
            return true
        end
        local total = safeAdd(generated[key] or 0, quantity, Model.MAX_QUANTITY)
        if not total then
            addIssue(plan, "quantity_limit", "Generated inventory exceeds the calculation limit.", key)
            return false
        end
        local previousContext = generatedContext[key]
        if previousContext and previousContext ~= context then
            ambiguousProductCosts[previousContext] = true
            ambiguousProductCosts[context] = true
        end
        generated[key] = total
        generatedContext[key] = previousContext or context
        if byproduct then
            local byproductTotal = safeAdd(generatedByproduct[key] or 0, quantity, Model.MAX_QUANTITY)
            if not byproductTotal then
                addIssue(plan, "quantity_limit", "Generated byproduct inventory exceeds the calculation limit.", key)
                return false
            end
            generatedByproduct[key] = byproductTotal
            local row = byproductRows[key]
            if not row then
                row = { key = key, item = key, name = itemName(self.items[key], key), produced = 0, used = 0 }
                byproductRows[key] = row
            end
            row.produced = safeAdd(row.produced, quantity, Model.MAX_QUANTITY)
            if not row.produced then
                addIssue(plan, "quantity_limit", "A byproduct total exceeds the calculation limit.", key)
                return false
            end
        end
        return true
    end

    local function readStock(key)
        if not stockRead[key] then
            stockRead[key] = true
            local count = mappedValue(stock, key, self.items[key])
            if count == nil then
                count = 0
            end
            if not wholeNumber(count, 0, Model.MAX_QUANTITY) then
                addIssue(plan, "stock_quantity", "Owned quantities must be non-negative whole numbers.", key)
                availableStock[key] = 0
                return 0
            end
            availableStock[key] = count
        end
        return availableStock[key]
    end

    local function makeRow(key)
        local price, reason, date, origin = self:unitPrice(key, options)
        local item = self.items[key]
        local mustMake = item and (item.tradeable == false
            or item.geTradeable == false
            or item.gePriceable == false)
        if mustMake and (price == nil or origin == "guide") then
            price = nil
            date = nil
            origin = "making"
            local makingOptions = {}
            for optionKey, optionValue in pairs(options) do
                makingOptions[optionKey] = optionValue
            end
            makingOptions.stock = {}
            makingOptions._makingCostVisited = options._makingCostVisited or {}
            local derived, makingReason = self:makingCost(key, makingOptions)
            if derived then
                price = derived.unitCost
                reason = nil
                date = derived.priceDate
                origin = "making"
            else
                reason = makingReason or reason
            end
        end
        return {
            key = key,
            item = key,
            name = itemName(self.items[key], key),
            id = priceId(self.items[key]),
            required = 0,
            owned = 0,
            missing = 0,
            unitPrice = price,
            priceReason = reason,
            priceDate = date,
            priceOrigin = origin,
            tradeable = item and item.tradeable,
            geTradeable = item and item.geTradeable,
            gePriceable = item and item.gePriceable,
        }
    end

    local function addIngredient(key, required, owned, context)
        if required == 0 then
            return
        end
        local row = ingredientRows[key]
        if not row then
            row = makeRow(key)
            ingredientRows[key] = row
            plan.entries[#plan.entries + 1] = row
        end
        local total = safeAdd(row.required, required, Model.MAX_QUANTITY)
        if not total then
            addIssue(plan, "quantity_limit", "An ingredient quantity exceeds the calculation limit.", key)
            return
        end
        row.required = total
        row.owned = row.owned + owned
        row.missing = row.required - row.owned
        local byRoot = rootCostRows[context]
        if not byRoot then
            byRoot = {}
            rootCostRows[context] = byRoot
        end
        local share = byRoot[key]
        if not share then
            share = { required = 0, owned = 0 }
            byRoot[key] = share
        end
        share.required = share.required + required
        share.owned = share.owned + owned
    end

    local function chooseRecipe(key, forceUntradeable)
        if selectedRecipes[key] ~= nil then
            return selectedRecipes[key] or nil
        end
        local choices = self.recipesByOutput[key] or {}
        local requested = mappedValue(options.recipeChoices, key, self.items[key])
        local name = itemName(self.items[key], key):lower()
        -- These preferences stop expansion at an exact ingredient form.
        -- Explicit recipe choices still take precedence over a general preference.
        local unfinished = name:find("(unf)", 1, true)
            or name:find("(unfinished)", 1, true)
        local cleanHerb = name:match("^clean ")
        if requested == nil and not forceUntradeable
            and ((options.buyUnfinished == true and unfinished)
                or (options.cleanHerbs ~= true and cleanHerb)) then
            selectedRecipes[key] = false
            return nil
        end
        local automatic = requested == nil
        local defaultRecipes = type(self.data.defaultRecipes) == "table"
            and self.data.defaultRecipes or {}
        requested = requested or defaultRecipes[key]
        local recipe = nil
        if requested ~= nil then
            recipe = self.recipes[requested]
            if not recipe or recipe.output.item ~= key or self.duplicates[requested] then
                addIssue(plan, "recipe_choice", "The chosen intermediate recipe does not make this exact item.", key)
                selectedRecipes[key] = false
                return nil
            end
        else
            -- Unverified alternatives must never displace an available verified recipe.
            for _, candidate in ipairs(choices) do
                local enabled = candidate.expandIntermediate ~= false
                    or (candidate.cleanHerb == true and options.cleanHerbs == true)
                    or forceUntradeable
                if candidate.verified == true and enabled
                    and not self.duplicates[candidate.key] then
                    recipe = candidate
                    break
                end
            end
        end
        if not recipe then
            selectedRecipes[key] = false
            return nil
        end
        if not validateRecipe(self, recipe, plan) then
            selectedRecipes[key] = false
            return nil
        end
        selectedRecipes[key] = recipe
        plan.choices[#plan.choices + 1] = {
            item = key,
            recipe = recipe.key,
            name = recipe.name or itemName(self.items[key], key),
            automatic = automatic,
            alternatives = #choices,
        }
        if automatic and #choices > 1 then
            addNote(plan, "Intermediate recipe selected: " .. tostring(recipe.name or recipe.key)
                .. ". Other recipes are available.")
        end
        return recipe
    end

    local function recordStep(recipe, count)
        local row = stepRows[recipe.key]
        if not row then
            row = {
                key = recipe.key,
                recipe = recipe.key,
                name = recipe.name or itemName(self.items[recipe.output.item], recipe.output.item),
                item = recipe.output.item,
                batches = 0,
                quantity = 0,
                level = recipe.level,
                xpPerBatch = recipe.xp,
                source = recipe.source,
            }
            stepRows[recipe.key] = row
            plan.steps[#plan.steps + 1] = row
        end
        local stepBatches = safeAdd(row.batches, count, Model.MAX_QUANTITY)
        local made = safeMultiply(count, recipe.output.quantity, Model.MAX_QUANTITY)
        local stepQuantity = made and safeAdd(row.quantity, made, Model.MAX_QUANTITY)
        if not stepBatches or not stepQuantity then
            addIssue(plan, "quantity_limit", "A manufacturing step exceeds the calculation limit.", recipe.output.item)
            return false
        end
        row.batches = stepBatches
        row.quantity = stepQuantity
        if finiteNumber(recipe.xp, 0, Model.MAX_TOTAL) then
            row.xp = safeMultiply(recipe.xp, row.batches, Model.MAX_TOTAL)
            if row.xp == nil then
                addIssue(plan, "cost_limit", "A total XP value exceeds the exact calculation limit.", recipe.key)
                return false
            end
        end
        if type(recipe.skills) ~= "table" or #recipe.skills == 0 then
            if recipe.xpKnown ~= true then
                plan.totalXPBySkillKnown = false
                missingSkillData = true
            end
        else
            hasSkillData = true
        end
        for _, skill in ipairs(type(recipe.skills) == "table" and recipe.skills or {}) do
            local experience = type(skill) == "table" and skill.experience or nil
            if type(experience) == "string" then
                experience = tonumber(experience)
            end
            if type(skill) == "table" and type(skill.name) == "string"
                and finiteNumber(experience, 0, Model.MAX_TOTAL) then
                local gained = safeMultiply(experience, count, Model.MAX_TOTAL)
                local prior = row.xpBySkill and row.xpBySkill[skill.name] or 0
                local skillTotal = gained and safeAdd(prior, gained, Model.MAX_TOTAL)
                if skillTotal == nil then
                    addIssue(plan, "cost_limit", "A skill XP value exceeds the exact calculation limit.", recipe.key)
                    return false
                end
                row.xpBySkill = row.xpBySkill or {}
                row.xpBySkill[skill.name] = skillTotal
                local planTotal = safeAdd(plan.totalXPBySkill[skill.name] or 0, gained, Model.MAX_TOTAL)
                if planTotal == nil then
                    addIssue(plan, "cost_limit", "A combined skill XP value exceeds the exact calculation limit.", skill.name)
                    return false
                end
                plan.totalXPBySkill[skill.name] = planTotal
            else
                plan.totalXPBySkillKnown = false
            end
        end
        return true
    end

    local consume
    local function manufacture(recipe, count, depth, context)
        if depth > Model.MAX_DEPTH then
            addIssue(plan, "depth_limit", "The recipe chain is too deep to calculate safely.", recipe.output.item)
            return false
        end
        if active[recipe.output.item] then
            addIssue(plan, "recipe_cycle", "The recipe chain contains a cycle.", recipe.output.item)
            return false
        end
        if type(recipe.costUnknownReason) == "string" and recipe.costUnknownReason ~= "" then
            addIssue(plan, "cost_unknown", recipe.costUnknownReason, recipe.key)
        end
        active[recipe.output.item] = true
        local completed = true
        for _, ingredient in ipairs(recipe.ingredients) do
            local needed = safeMultiply(ingredient.quantity, count, Model.MAX_QUANTITY)
            if not needed then
                addIssue(plan, "quantity_limit", "An ingredient quantity exceeds the calculation limit.", ingredient.item)
                completed = false
            elseif not consume(ingredient.item, needed, depth + 1, context) then
                completed = false
            end
        end
        active[recipe.output.item] = nil
        if completed then
            if not recordStep(recipe, count) then
                return false
            end
            for _, byproduct in ipairs(recipe.byproducts or {}) do
                local quantity = safeMultiply(byproduct.quantity, count, Model.MAX_QUANTITY)
                if not quantity or not addGenerated(byproduct.item, quantity, context, true) then
                    if quantity == nil then
                        addIssue(plan, "quantity_limit", "A byproduct quantity exceeds the calculation limit.", byproduct.item)
                    end
                    return false
                end
            end
            return true
        end
        return false
    end

    consume = function(key, quantity, depth, context)
        requestCount = requestCount + 1
        if requestCount > Model.MAX_REQUESTS then
            addIssue(plan, "request_limit", "The recipe chain exceeds the calculation limit.", key)
            return false
        end
        if not self.items[key] then
            addIssue(plan, "ingredient_unknown", "An ingredient is missing from the catalogue.", key)
            return false
        end

        -- Use already made spare items before taking more from the bank.
        local spare = math.min(generated[key] or 0, quantity)
        local byproductSpare = math.min(generatedByproduct[key] or 0, spare)
        generated[key] = (generated[key] or 0) - spare
        generatedByproduct[key] = (generatedByproduct[key] or 0) - byproductSpare
        if byproductSpare > 0 then
            byproductRows[key].used = byproductRows[key].used + byproductSpare
        end
        if spare > 0 and generatedContext[key] and generatedContext[key] ~= context then
            ambiguousProductCosts[generatedContext[key]] = true
            ambiguousProductCosts[context] = true
        end
        if generated[key] == 0 then
            generatedContext[key] = nil
        end
        local required = quantity - spare
        local owned = math.min(readStock(key), required)
        availableStock[key] = availableStock[key] - owned
        required = required - owned
        if required == 0 then
            addIngredient(key, owned, owned, context)
            return true
        end

        local recipe = nil
        local forceUntradeable = self.items[key].tradeable == false
            or self.items[key].geTradeable == false
            or self.items[key].gePriceable == false
        local explicitChoice = mappedValue(options.recipeChoices, key, self.items[key]) ~= nil
        if plan.recursive or forceUntradeable or explicitChoice then
            recipe = chooseRecipe(key, forceUntradeable)
        end
        if not recipe then
            addIngredient(key, required + owned, owned, context)
            if self.items[key].tradeable == false
                or self.items[key].geTradeable == false
                or self.items[key].gePriceable == false then
                addIssue(plan, "unobtainable_input",
                    "Obtain " .. Model.formatNumber(required) .. " " .. itemName(self.items[key], key)
                        .. " yourself, or choose a preparation recipe. It is not a verified GE purchase.", key)
                return false
            end
            return true
        end

        addIngredient(key, owned, owned, context)
        local count = math.ceil(required / recipe.output.quantity)
        local made = safeMultiply(count, recipe.output.quantity, Model.MAX_QUANTITY)
        if not made then
            addIssue(plan, "quantity_limit", "An intermediate output exceeds the calculation limit.", key)
            return false
        end
        if not manufacture(recipe, count, depth, context) then
            return false
        end
        local spareMade = made - required
        if spareMade > 0 and (generated[key] or 0) > 0 and generatedContext[key] ~= context then
            ambiguousProductCosts[generatedContext[key]] = true
            ambiguousProductCosts[context] = true
        end
        if not addGenerated(key, made - required, context, false) then
            return false
        end
        return true
    end

    -- Direct inputs remain available to the UI even when it expands intermediates.
    for _, request in ipairs(rootRequests) do
        for _, ingredient in ipairs(request.recipe.ingredients) do
            local required = safeMultiply(ingredient.quantity, request.batches, Model.MAX_QUANTITY)
            if not required then
                addIssue(plan, "quantity_limit", "An ingredient quantity exceeds the calculation limit.", ingredient.item)
            else
                local row = directRows[ingredient.item]
                if not row then
                    row = makeRow(ingredient.item)
                    directRows[ingredient.item] = row
                    plan.directEntries[#plan.directEntries + 1] = row
                end
                local total = safeAdd(row.required, required, Model.MAX_QUANTITY)
                if total then
                    row.required = total
                    row.owned = math.min(readStock(ingredient.item), total)
                    row.missing = total - row.owned
                else
                    addIssue(plan, "quantity_limit", "An ingredient quantity exceeds the calculation limit.", ingredient.item)
                end
            end
        end
    end

    if plan.ok then
        for _, request in ipairs(rootRequests) do
            manufacture(request.recipe, request.batches, 1, request.recipe.key)
        end
    end
    for _, key in ipairs(sortedKeys(generated)) do
        if generated[key] > 0 then
            plan.leftovers[#plan.leftovers + 1] = {
                key = key,
                item = key,
                name = itemName(self.items[key], key),
                quantity = generated[key],
                byproductQuantity = generatedByproduct[key] or 0,
            }
        end
    end
    for _, key in ipairs(sortedKeys(byproductRows)) do
        local row = byproductRows[key]
        row.leftover = generatedByproduct[key] or 0
        plan.byproducts[#plan.byproducts + 1] = row
    end
    if #plan.byproducts > 0 then
        addNote(plan, "Byproducts count as ingredient stock or leftovers; their sale value is excluded from profit.")
    end
    local totalXP = 0
    local xpKnown = true
    for _, step in ipairs(plan.steps) do
        if step.xp == nil then
            xpKnown = false
        elseif xpKnown then
            totalXP = safeAdd(totalXP, step.xp, Model.MAX_TOTAL)
            if totalXP == nil then
                xpKnown = false
                addIssue(plan, "cost_limit", "The combined XP exceeds the exact calculation limit.")
            end
        end
    end
    if hasSkillData then
        if missingSkillData then
            plan.totalHerbloreXP = nil
            plan.totalXP = nil
            plan.xpKnown = false
        else
            plan.totalHerbloreXP = plan.totalXPBySkill.Herblore or 0
            plan.totalXP = plan.totalHerbloreXP
            plan.xpKnown = true
        end
    elseif xpKnown then
        plan.totalXP = totalXP
    else
        plan.totalXP = nil
        plan.xpKnown = false
    end
    if not plan.ok then
        plan.totalHerbloreXP = nil
        plan.totalXP = nil
        plan.xpKnown = false
        plan.totalXPBySkillKnown = false
    end

    local function calculateRows(rows)
        for _, row in ipairs(rows) do
            if row.unitPrice ~= nil then
                row.cost = safeMultiply(row.required, row.unitPrice, Model.MAX_TOTAL)
                row.buyCost = safeMultiply(row.missing, row.unitPrice, Model.MAX_TOTAL)
                if not row.cost or not row.buyCost then
                    addIssue(plan, "cost_limit", "A price total exceeds the exact calculation limit.", row.key)
                end
            elseif row.missing == 0 then
                -- No purchase is needed, but the owned materials still have an unknown value.
                row.buyCost = 0
            end
        end
    end
    calculateRows(plan.entries)
    calculateRows(plan.directEntries)

    local ingredientCost = 0
    local buyCost = 0
    for _, row in ipairs(plan.entries) do
        if row.cost == nil then
            plan.totals.unknownIngredientPrices = plan.totals.unknownIngredientPrices + 1
        elseif ingredientCost ~= nil then
            ingredientCost = safeAdd(ingredientCost, row.cost, Model.MAX_TOTAL)
        end
        if row.buyCost == nil then
            plan.totals.unknownPurchasePrices = plan.totals.unknownPurchasePrices + 1
        elseif buyCost ~= nil then
            buyCost = safeAdd(buyCost, row.buyCost, Model.MAX_TOTAL)
        end
    end
    local totals = plan.totals
    if totals.unknownIngredientPrices > 0 then
        totals.reasons.ingredientCost = "One or more ingredient prices are unknown."
    else
        totals.ingredientCost = ingredientCost
    end
    if totals.unknownPurchasePrices > 0 then
        totals.reasons.buyCost = "One or more missing ingredient prices are unknown."
    else
        totals.buyCost = buyCost
    end
    if ingredientCost == nil or buyCost == nil then
        addIssue(plan, "cost_limit", "The combined price total exceeds the exact calculation limit.")
    end

    local taxRate = options.taxRate
    if taxRate == nil then
        taxRate = self.prices.taxRate
    end
    if taxRate == nil then
        taxRate = self.data.taxRate
    end
    local basketGross = 0
    local basketTax = 0
    local basketSale = 0
    local basketTradeable = true
    local basketSaleKnown = true
    local basketGrossKnown = true
    for _, output in ipairs(plan.outputs) do
        local outputItem = self.items[output.item]
        local unitPrice, priceReason, date, origin = self:unitPrice(output.item, options)
        output.unitPrice = unitPrice
        output.priceDate = date
        output.priceOrigin = origin
        output.tradeable = outputItem.tradeable
        output.gePriceable = outputItem.gePriceable
        local productCost = 0
        local productBuyCost = 0
        local productCostKnown = true
        local productBuyKnown = true
        for key, share in pairs(rootCostRows[output.recipe] or {}) do
            local row = ingredientRows[key]
            if not row or row.unitPrice == nil then
                productCostKnown = false
                if share.required > share.owned then
                    productBuyKnown = false
                end
            else
                local cost = safeMultiply(share.required, row.unitPrice, Model.MAX_TOTAL)
                local purchaseCost = safeMultiply(share.required - share.owned, row.unitPrice, Model.MAX_TOTAL)
                if cost == nil or purchaseCost == nil or productCost == nil or productBuyCost == nil then
                    productCostKnown = false
                    productBuyKnown = false
                else
                    productCost = safeAdd(productCost, cost, Model.MAX_TOTAL)
                    productBuyCost = safeAdd(productBuyCost, purchaseCost, Model.MAX_TOTAL)
                    if productCost == nil or productBuyCost == nil then
                        productCostKnown = false
                        productBuyKnown = false
                    end
                end
            end
        end
        if ambiguousProductCosts[output.recipe] then
            output.costReason = "Shared produced intermediates prevent unambiguous per-product cost allocation."
        elseif productCostKnown then
            output.ingredientCost = productCost
        end
        if not ambiguousProductCosts[output.recipe] and productBuyKnown then
            output.buyCost = productBuyCost
        end
        if output.tradeable ~= true or output.gePriceable ~= true then
            basketTradeable = false
            basketSaleKnown = false
            basketGrossKnown = false
            if output.tradeable == false then
                output.saleReason = "This output is untradeable."
            elseif output.gePriceable == false then
                output.saleReason = "This output cannot be traded on the Grand Exchange."
            else
                output.saleReason = "This output's Grand Exchange priceability is unverified."
            end
        elseif unitPrice == nil then
            basketSaleKnown = false
            basketGrossKnown = false
            output.saleReason = priceReason
        else
            local gross = safeMultiply(unitPrice, output.quantity, Model.MAX_TOTAL)
            output.grossSaleValue = gross
            if gross == nil then
                basketSaleKnown = false
                basketGrossKnown = false
                addIssue(plan, "cost_limit", "A product sale value exceeds the exact calculation limit.", output.item)
                output.saleReason = "The product sale value exceeds the exact calculation limit."
            else
                basketGross = safeAdd(basketGross, gross, Model.MAX_TOTAL)
                if basketGross == nil then
                    basketGrossKnown = false
                    addIssue(plan, "cost_limit", "The combined output sale value exceeds the exact calculation limit.")
                end
                if not finiteNumber(taxRate, 0, 1) then
                    basketSaleKnown = false
                    output.saleReason = "No valid sale tax rate has been supplied."
                elseif taxRate == 0.02 and unitPrice == 50 then
                    -- The current Wiki page and its changelog disagree at exactly 50 GP.
                    basketSaleKnown = false
                    output.saleReason = "The available tax sources disagree about sales at exactly 50 GP."
                else
                    local taxPerItem = math.floor(unitPrice * taxRate)
                    if taxRate == 0.02 then
                        -- The RS3 tax is rounded down separately for every item sold.
                        taxPerItem = math.floor(unitPrice / 50)
                    end
                    output.taxRate = taxRate
                    output.taxPerItem = taxPerItem
                    output.taxCost = taxPerItem * output.quantity
                    output.saleValue = gross - output.taxCost
                    basketTax = safeAdd(basketTax, output.taxCost, Model.MAX_TOTAL)
                    basketSale = safeAdd(basketSale, output.saleValue, Model.MAX_TOTAL)
                    if basketGross == nil or basketTax == nil or basketSale == nil then
                        basketSaleKnown = false
                        addIssue(plan, "cost_limit", "The combined output sale value exceeds the exact calculation limit.")
                    end
                end
            end
        end
        if plan.ok and output.saleValue ~= nil and output.ingredientCost ~= nil
            and output.tradeable == true and output.gePriceable == true then
            output.profit = output.saleValue - output.ingredientCost
        end
        if plan.ok and output.saleValue ~= nil and output.buyCost ~= nil
            and output.tradeable == true and output.gePriceable == true then
            output.cashProfit = output.saleValue - output.buyCost
        end
        if output.saleReason then
            totals.reasons.products = totals.reasons.products or {}
            totals.reasons.products[output.item] = output.saleReason
        end
    end
    if not finiteNumber(taxRate, 0, 1) then
        totals.reasons.saleValue = "No valid sale tax rate has been supplied."
    elseif not basketTradeable then
        totals.reasons.saleValue = "The requested outputs include an untradeable item or an item without verified Grand Exchange priceability."
    elseif not basketSaleKnown then
        if not isMulti and plan.outputs[1].saleReason then
            totals.reasons.saleValue = plan.outputs[1].saleReason
        else
            totals.reasons.saleValue = "One or more product sale values are unknown."
        end
    end
    if basketTradeable and basketGrossKnown then
        totals.grossSaleValue = basketGross
    end
    if finiteNumber(taxRate, 0, 1) and basketTradeable and basketSaleKnown then
        totals.taxRate = taxRate
        totals.taxCost = basketTax
        totals.saleValue = basketSale
    end
    if not isMulti and plan.outputs[1] then
        totals.taxPerItem = plan.outputs[1].taxPerItem
    end
    if plan.ok then
        if totals.saleValue ~= nil and totals.ingredientCost ~= nil then
            totals.profit = totals.saleValue - totals.ingredientCost
        else
            totals.reasons.profit = totals.reasons.saleValue or totals.reasons.ingredientCost
        end
        if totals.saleValue ~= nil and totals.buyCost ~= nil then
            totals.cashProfit = totals.saleValue - totals.buyCost
        end
    else
        -- Partial calculations are useful for diagnosis, not a complete profit estimate.
        totals.ingredientCost = nil
        totals.buyCost = nil
        totals.profit = nil
        totals.cashProfit = nil
        totals.reasons.ingredientCost = "The plan has unresolved recipe or quantity problems."
        totals.reasons.buyCost = totals.reasons.ingredientCost
        totals.reasons.profit = totals.reasons.ingredientCost
    end
    totals.cost = totals.ingredientCost
    totals.proceeds = totals.saleValue
    return finishPlan(plan)
end

function Model.formatNumber(value)
    if not finiteNumber(value, -Model.MAX_TOTAL, Model.MAX_TOTAL) then
        return "?"
    end
    local negative = value < 0
    local number = tostring(math.floor(math.abs(value)))
    -- string.format avoids scientific notation for large, still exact integers.
    number = string.format("%.0f", math.floor(math.abs(value)))
    local first = #number % 3
    if first == 0 then
        first = 3
    end
    local pieces = { number:sub(1, first) }
    for index = first + 1, #number, 3 do
        pieces[#pieces + 1] = number:sub(index, index + 2)
    end
    return (negative and "-" or "") .. table.concat(pieces, ",")
end

return Model
