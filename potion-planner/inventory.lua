-- Read both official containers without moving items or storing client objects.
-- Two complete passes reject stock changes during a read while preserving totals
-- when a stack moves between the bank and backpack.
local InventoryReader = {}

local function whole(value, maximum)
    return type(value) == "number"
        and value == value
        and value >= 0
        and value <= maximum
        and value == math.floor(value)
end

-- The official reference names isValid in its safety guidance and valid in its
-- property table. Client proxies can also reject an unknown member instead of
-- returning nil. Read each spelling independently and prefer isValid.
local function member(object, key)
    local ok, value = pcall(function() return object[key] end)
    if ok then
        return value
    end
end

local function validity(inv)
    local current = member(inv, "isValid")
    if type(current) == "boolean" then
        return current, "isValid"
    end
    local legacy = member(inv, "valid")
    if type(legacy) == "boolean" then
        return legacy, "valid"
    end
    return nil, "unavailable"
end

local function findContainer(invType, label, diagnostics)
    local found = Inventory.Find(invType)
    diagnostics.resultType = type(found)
    if type(found) == "table" and type(member(found, "GetSlots")) ~= "function" then
        found = found[1]
        diagnostics.listResult = true
    end
    if not found then
        return nil, label .. " is not loaded or is no longer valid."
    end
    local valid, spelling = validity(found)
    diagnostics.validityMember = spelling
    diagnostics.valid = valid
    if valid == false then
        return nil, label .. " is not loaded or is no longer valid."
    end
    if valid == nil then
        return nil, label .. " did not provide a readable inventory status. Your stock is unchanged."
    end
    return found
end

local function readContainer(invType, label, report)
    local diagnostics = { container = label }
    report.containers[#report.containers + 1] = diagnostics
    local inv, problem = findContainer(invType, label, diagnostics)
    if not inv then
        return nil, problem
    end
    local used = inv.usedSlotCount
    local size = inv.slotCount
    diagnostics.usedSlotCount = used
    diagnostics.slotCount = size
    if not whole(used, 10000) or not whole(size, 10000) or used > size then
        return nil, label .. " contents are still loading."
    end

    local slots = inv:GetSlots()
    if type(slots) ~= "table" then
        return nil, label .. " contents are unavailable."
    end

    local counts = {}
    local occupied = 0
    diagnostics.emptySlots = 0
    diagnostics.placeholders = 0
    for index, slot in pairs(slots) do
        if not whole(index, size) or index < 1 then
            return nil, label .. " slot list is incomplete. Try again."
        end
        if slot ~= nil then
            local count = slot.count
            local object = slot.obj
            if not whole(count, 2147483647) then
                return nil, label .. " quantity is still loading."
            end
            if object then
                local objectID = member(object, "id")
                if not whole(objectID, 2147483647) or objectID < 1 then
                    -- Empty slots can contain an invalid ObjType proxy rather
                    -- than nil. Zero quantity is never owned stock; an unknown
                    -- positive stack still blocks the complete snapshot.
                    if count > 0 then
                        diagnostics.failedSlot = index
                        diagnostics.failedCount = count
                        diagnostics.itemIDType = type(objectID)
                        return nil, label .. " item data is still loading."
                    end
                    diagnostics.emptySlots = diagnostics.emptySlots + 1
                else
                    occupied = occupied + 1
                    if count == 0 then
                        diagnostics.placeholders = diagnostics.placeholders + 1
                    else
                        counts[objectID] = (counts[objectID] or 0) + count
                    end
                end
            elseif count > 0 then
                diagnostics.failedSlot = index
                diagnostics.failedCount = count
                return nil, label .. " item data is still loading."
            else
                diagnostics.emptySlots = diagnostics.emptySlots + 1
            end
        end
    end
    diagnostics.occupiedSlots = occupied

    -- GetSlots returns a copy. Verify the proxy survived the copy and its
    -- occupied-slot metadata did not change while that copy was being read.
    if validity(inv) ~= true or used ~= inv.usedSlotCount or size ~= inv.slotCount then
        return nil, label .. " changed during the read. Try again."
    end
    if occupied < used then
        return nil, label .. " slot list is incomplete. Try again."
    end
    return counts
end

local function readPass(report)
    local bank, bankProblem = readContainer(config.Inv.BANK, "Bank", report)
    if not bank then
        return nil, bankProblem
    end
    local backpack, backpackProblem = readContainer(config.Inv.INV, "Backpack", report)
    if not backpack then
        return nil, backpackProblem
    end
    local combined = {}
    for objectID, count in pairs(bank) do
        combined[objectID] = (combined[objectID] or 0) + count
    end
    for objectID, count in pairs(backpack) do
        combined[objectID] = (combined[objectID] or 0) + count
    end
    return combined
end

local function sameCounts(first, second)
    for objectID, count in pairs(first) do
        if (second[objectID] or 0) ~= count then
            return false
        end
    end
    for objectID, count in pairs(second) do
        if (first[objectID] or 0) ~= count then
            return false
        end
    end
    return true
end

local function itemOwners(items)
    local owners = {}
    for key, item in pairs(items or {}) do
        local ids = item.ids or (item.id and { item.id }) or {}
        for _, itemID in ipairs(ids) do
            if whole(itemID, 2147483647) and itemID > 0 then
                if owners[itemID] == nil then
                    owners[itemID] = key
                elseif owners[itemID] ~= key then
                    owners[itemID] = false
                end
            end
        end
    end
    return owners
end

function InventoryReader.read(items)
    -- Only container status and counts are retained for diagnosing client API
    -- differences. No client proxies or item contents go into the report.
    local report = { version = 2, containers = {} }
    local ok, result, problem = pcall(function()
        local first, firstProblem = readPass(report)
        if not first then
            return nil, firstProblem
        end
        local second, secondProblem = readPass(report)
        if not second then
            return nil, secondProblem
        end
        if not sameCounts(first, second) then
            return nil, "Bank or backpack changed during the read. Try again."
        end

        local owners = itemOwners(items)
        local stock = {}
        local ambiguous = 0
        for itemID, count in pairs(second) do
            local key = owners[itemID]
            if key and count > 0 then
                stock[key] = (stock[key] or 0) + count
            elseif key == false and count > 0 then
                ambiguous = ambiguous + 1
            end
        end
        return stock, ambiguous > 0
            and (tostring(ambiguous) .. " ambiguous item IDs excluded; enter their stock manually.")
            or "Loaded bank and backpack totals. Read again after changing your stock."
    end)
    if not ok then
        report.ok = false
        report.problem = tostring(result)
        return nil, "Bank or backpack could not be read. Your entered stock is unchanged.", report
    end
    report.ok = result ~= nil
    report.message = problem
    return result, problem, report
end

return InventoryReader
