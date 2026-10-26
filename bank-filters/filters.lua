local loot = require("data/loot")             -- { ["Dragon helm"] = true, ... }: drops to sell or alch
local artefacts = require("data/artefacts")   -- restored Archaeology artefacts, to hand in
local storage = require("data/storage")       -- items with a storage of their own (seed bag, metal bank ...)
local resources = require("data/resources")   -- name patterns of skilling resources (herbs, bones, ores ...)
local mtx = require("data/mtx")
local potions = require("data/potions")       -- verified capacity, including combinations without a full one banked
local market = require("data/market")         -- dated daily top 100; optional reference, not a cleanup rule

local filters = {}

-- The filters a player can switch on and off. CLEAN means all of these at once: everything worth tidying.
filters.KINDS = { "loot", "sell", "decant", "junk", "low", "repair", "turnin", "store" }
-- More with switches of their own, outside CLEAN: MTX items to use up before Jagex removes them, skilling resources
-- (kept, not tidied), equipment and a dated most-traded reference view.
filters.EXTRAS = { "mtx", "resource", "gear", "traded" }

filters.LOOK = {
    loot   = { label = "LOOT",   colour = { 1.00, 0.89, 0.24, 1 } },   -- yellow
    sell   = { label = "SELL",   colour = { 1.00, 0.55, 0.12, 1 } },   -- orange
    decant = { label = "DECANT", colour = { 0.71, 0.35, 1.00, 1 } },   -- purple
    junk   = { label = "JUNK",   colour = { 0.86, 0.20, 0.16, 1 } },   -- red
    low    = { label = "LOW",    colour = { 1.00, 0.31, 0.31, 1 } },   -- pink-red
    repair = { label = "REPAIR", colour = { 0.88, 0.63, 0.25, 1 } },   -- amber
    turnin = { label = "TURNIN", colour = { 0.94, 0.82, 0.38, 1 } },   -- pale gold
    store  = { label = "STORE",  colour = { 0.24, 0.78, 0.82, 1 } },   -- teal (the button; each storage has its own)
    resource = { label = "SKILL", colour = { 0.35, 0.78, 0.63, 1 }, button = "RESOURCES" }, -- sea green
    mtx    = { label = "MTX",    colour = { 1.00, 0.35, 0.85, 1 } },
    gear   = { label = "GEAR",   colour = { 0.45, 0.68, 1.00, 1 } }, -- blue: wearable equipment and weapons
    keep   = { label = "KEEP",   colour = { 0.46, 0.91, 0.65, 1 } }, -- personal annotation, independent of cleanup switches
    favourite = { label = "FAV", colour = { 1.00, 0.82, 0.30, 1 } },
    traded = { label = "TOP100", colour = { 0.45, 0.78, 1.00, 1 }, button = "TRADED", setting = market.caption },
}

-- Things players usually sell for gold rather than keep: alchemy and crafting stock.
local SELL_STOCK = {
    "^Battlestaff$", "^Potion flask$", "^Crystal flask$", "^Dragonstone necklace$", "arrowheads$",
    "^Crystal weapon seed$", "^Crystal armour seed$", "^Crystal tool seed$",
}

filters.JUNK_BELOW = 10000      -- a loot or sell stack worth less than this in total is junk
filters.SHELF_SLOTS = 20        -- the first slots of the bank are the player's supply shelf...
filters.SHELF_LOW = 50          -- ...and a stack there at or under this count is running low

local function matchesAny(name, patterns)
    for _, pattern in ipairs(patterns) do
        if name:find(pattern) then return true end
    end
    return false
end

-- "Super restore (3)" -> "Super restore", 3; nil for anything without a dose count.
function filters.doses(name)
    local base, doses = name:match("^(.-)%s+%((%d+)%)$")
    return base, tonumber(doses)
end

-- A suffix alone might be jewellery charges. Only the public potion catalogue establishes container capacity.
function filters.potion(name)
    local base, doses = filters.doses(name)
    local full = potions[base]
    if full and doses >= 1 and doses <= full then return doses, full end
end

-- Read the item's own inventory actions, not its bank-withdraw menu or a guess from its name.
function filters.isGear(options)
    for _, option in pairs(options or {}) do
        if type(option) == "string" then
            local action = option:lower()
            if action == "wear" or action == "wield" or action == "equip" then return true end
        end
    end
    return false
end

-- The tag for one bank slot, or nil for none.
--   item     = { name = "Onyx bolts (e)", count = 120, value = 9000 (each), slot = 37, gear = true }
--   switches = { loot = true, sell = true, ..., misc = true }
-- Returns the kind ("loot", "store", ...), the label to draw and its colour.
function filters.tagFor(item, switches)
    local name, count = item.name, item.count
    if not name or not count then return nil end
    if item.keep then return "keep", "KEEP", filters.LOOK.keep.colour end
    if count <= 0 then
        if item.favourite then return "favourite", "FAV", filters.LOOK.favourite.colour end
        return nil
    end

    if switches.gear and item.gear then return "gear", "GEAR", filters.LOOK.gear.colour end

    -- This view matches exact game IDs. Wiki display names can include variant suffixes.
    -- It is off by default and leaves CLEAN, custom presets and personal KEEP marks alone.
    if switches.traded and market.ids[item.id] then
        return "traded", filters.LOOK.traded.label, filters.LOOK.traded.colour
    end

    local kind, place
    local doses, full = filters.potion(name)
    if mtx[name] then
        kind = "mtx"
    elseif doses and doses < full then
        kind = "decant"
    elseif item.slot <= filters.SHELF_SLOTS and count > 0 and count <= filters.SHELF_LOW then
        kind = "low"
    elseif count > 0 and storage.find(name, count) then
        kind, place = "store", storage.find(name, count)
    elseif matchesAny(name, resources) then
        kind = "resource"
    elseif name:find(" %(damaged%)$") then
        kind = "repair"
    elseif artefacts[name] then
        kind = "turnin"
    elseif loot[name] or matchesAny(name, SELL_STOCK) then
        local worth = (item.value or 0) * count
        if worth < filters.JUNK_BELOW then
            kind = "junk"
        elseif loot[name] then
            kind = "loot"
        else
            kind = "sell"
        end
    end

    if not kind or not switches[kind] then
        if item.favourite then return "favourite", "FAV", filters.LOOK.favourite.colour end
        return nil
    end
    if place then return kind, place.label, place.colour end
    return kind, filters.LOOK[kind].label, filters.LOOK[kind].colour
end

return filters
