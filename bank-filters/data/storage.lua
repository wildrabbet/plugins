local function set(list)
    local out = {}
    for _, name in ipairs(list) do out[name] = true end
    return out
end

local storage = {}

storage.list = {
    { label = "GIZMO", colour = { 0.24, 0.78, 0.82, 1 }, where = "gizmo bag",
      names = set({ "Weapon gizmo", "Armour gizmo", "Tool gizmo", "Ancient weapon gizmo", "Ancient armour gizmo",
                    "Ancient tool gizmo" }) },
    { label = "SPIRIT", colour = { 0.59, 0.90, 0.39, 1 }, where = "Golrana", names = set({ "Spirit seed" }) },
    { label = "SEEDS", colour = { 0.27, 0.82, 0.27, 1 }, where = "seed bag", pattern = " seeds?$" },
    { label = "HERBS", colour = { 0.55, 0.82, 0.24, 1 }, where = "herb bag", pattern = "^Grimy ", most = 50 },
    { label = "GEMS", colour = { 1.00, 0.39, 0.71, 1 }, where = "gem bag", most = 60,
      names = set({ "Uncut opal", "Uncut jade", "Uncut red topaz", "Uncut sapphire", "Uncut emerald", "Uncut ruby",
                    "Uncut diamond", "Uncut dragonstone" }) },
    { label = "METAL", colour = { 0.67, 0.71, 0.78, 1 }, where = "metal bank (any furnace)",
      names = set({ "Copper ore", "Tin ore", "Iron ore", "Coal", "Mithril ore", "Adamantite ore", "Luminite", "Runite ore",
                    "Orichalcite ore", "Drakolith", "Necrite ore", "Phasmatite", "Banite ore", "Light animica",
                    "Dark animica", "Silver ore", "Gold ore", "Platinum ore", "Novite ore", "Bathus ore", "Marmaros ore",
                    "Kratonium ore", "Fractite ore", "Zephyrium ore", "Argonite ore", "Katagon ore", "Gorgonite ore",
                    "Promethium ore", "Bronze bar", "Iron bar", "Steel bar", "Mithril bar", "Adamant bar", "Rune bar",
                    "Orikalkum bar", "Necronium bar", "Bane bar", "Elder rune bar", "Silver bar", "Gold bar",
                    "Platinum bar", "Primal bar", "Concentrated alloy bar", "Enriched alloy bar",
                    "Immaculate alloy bar", "Glorious bar", "Primed glorious bar" }) },
    { label = "ARCH", colour = { 0.82, 0.63, 0.35, 1 }, where = "material storage (dig sites)",
      names = set({ "Third Age iron", "Zarosian insignia", "Samite silk", "Imperial steel", "White oak", "Goldrune",
                    "Orthenglass", "Vellum", "Cadmium red", "Ancient vis", "Tyrian purple", "Leather scraps",
                    "Chaotic brimstone", "Demonhide", "Eye of Dagon", "Hellfire metal", "Keramos", "White marble",
                    "Cobalt blue", "Everlight silvthril", "Star of Saradomin", "Banded limestone", "Ivory", "Triskelion",
                    "Blood of Orcus", "Soapstone", "Burnt umber", "Cashmere", "Stormguard steel", "Wings of War",
                    "Dragon metal", "Orgone", "Animal furs", "Armadylean yellow", "Malachite green",
                    "Mark of the Kyzaj", "Vulcanised rubber", "Warforged bronze", "Compass rose", "Carbon black", "Felt",
                    "Fossilised bone", "Yu'biusk clay", "Aetherium alloy", "Quintessence", "Imperial iron",
                    "Purpleheart wood" }) },
    { label = "SOIL", colour = { 0.63, 0.47, 0.29, 1 }, where = "soil box", most = 500,
      names = set({ "Ancient gravel", "Fiery brimstone", "Saltwater mud", "Aerated sediment", "Earthen clay",
                    "Volcanic ash", "Senntisten soil" }) },
    { label = "CLUES", colour = { 0.94, 0.63, 0.24, 1 }, where = "Charos' clue carrier",
      names = set({ "Sealed clue scroll (easy)", "Sealed clue scroll (medium)", "Sealed clue scroll (hard)",
                    "Sealed clue scroll (elite)", "Sealed clue scroll (master)", "Reward casket (easy)",
                    "Reward casket (medium)", "Reward casket (hard)", "Reward casket (elite)", "Reward casket (master)" }) },
    { label = "TELE", colour = { 0.31, 0.63, 1.00, 1 }, where = "Globetrotter arm guards", most = 1000,
      names = set({ "Grand Exchange teleport", "Bandit camp teleport", "Clocktower teleport", "Gu'Tanoth teleport",
                    "Lighthouse teleport", "Fort Forinthry teleport", "Miscellania teleport", "Phoenix lair teleport",
                    "Pollnivneach teleport", "Tai Bwo Wannai teleport" }) },
    { label = "FARM", colour = { 0.39, 0.75, 0.47, 1 }, where = "tool leprechaun",
      limits = { ["Compost"] = 255, ["Supercompost"] = 2000, ["Ultracompost"] = 2000, ["Plant cure"] = 255,
                 ["Bucket"] = 255, ["Scarecrow"] = 5, ["Liquid patch bomb"] = 2000 } },
    { label = "PLANKS", colour = { 0.78, 0.59, 0.35, 1 }, where = "plank box", most = 100,
      names = set({ "Plank", "Oak plank", "Teak plank", "Mahogany plank" }) },
    { label = "LOGS", colour = { 0.71, 0.51, 0.24, 1 }, where = "wood box", most = 70,
      names = set({ "Logs", "Achey tree logs", "Oak logs", "Willow logs", "Teak logs", "Maple logs", "Acadia logs",
                    "Arctic pine logs", "Eucalyptus logs", "Mahogany logs", "Yew logs", "Blisterwood logs", "Magic logs",
                    "Cursed magic logs", "Elder logs", "Eternal magic logs" }) },
    { label = "SPORES", colour = { 0.78, 0.47, 0.31, 1 }, where = "Polypore Dungeon merchant",
      limits = { ["Neem oil"] = 1, ["Polypore spore"] = 8191, ["Fungal flakes"] = 8191, ["Grifolic flakes"] = 8191,
                 ["Ganodermic flakes"] = 8191 } },
    { label = "STORE", colour = { 0.90, 0.78, 0.31, 1 }, where = "Elnock (Puro-Puro)",
      limits = { ["Impling jar"] = 127, ["Imp repellent"] = 1, ["Butterfly net"] = 1, ["Magic butterfly net"] = 1 } },
    { label = "NEXUS", colour = { 0.55, 0.47, 1.00, 1 }, where = "Deathwarden nexus",
      names = set({ "Spirit rune", "Bone rune", "Flesh rune", "Miasma rune" }) },
    { label = "SIPHON", colour = { 0.47, 0.86, 0.86, 1 }, where = "mechanised siphon", most = 50,
      names = set({ "Equipment siphon", "Crystal tool siphon" }) },
    { label = "EFFIGY", colour = { 0.90, 0.90, 0.63, 1 }, where = "Brooch of the Gods", most = 1000,
      names = set({ "Starved ancient effigy", "Nourished ancient effigy", "Sated ancient effigy",
                    "Gorged ancient effigy" }) },
    { label = "ROCKS", colour = { 0.78, 0.78, 0.71, 1 }, where = "statue collection bag", pattern = "^Strange rock" },
    { label = "ROCKS", colour = { 0.78, 0.78, 0.71, 1 }, where = "statue collection bag", pattern = "^Golden rock" },
}

-- Seed-named items that are not farming seeds, or that have a keeper of their own.
local NOT_SEED = set({ "Spirit seed", "Seed", "Seeds", "Bag of seeds", "Marker seeds", "Odd bird seed", "Vibrating seed",
    "Tainted seed", "Consecration seed", "Harvest festival seeds", "Novtumber festival seed", "Black seeds",
    "Blue seeds", "Gold seeds", "Green seeds", "Red seeds", "Mithril seeds", "Bone seeds" })

-- The storage an item belongs in (one entry of storage.list), or nil.
function storage.find(name, count)
    if NOT_SEED[name] and name ~= "Spirit seed" then return nil end
    if name:find("^Crystal .*seed$") then return nil end
    for _, place in ipairs(storage.list) do
        local fits
        if place.names then fits = place.names[name]
        elseif place.limits then fits = place.limits[name] and count <= place.limits[name]
        else fits = name:find(place.pattern) ~= nil end
        if fits and (not place.most or count <= place.most) then return place end
    end
    return nil
end

return storage
