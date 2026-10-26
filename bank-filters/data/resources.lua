-- Skilling resources: herbs, bones, gems, ores, bars, logs and other materials a player trains with.
-- Each line is a Lua pattern matched against the item's name.

return {
    "^Grimy ", "^Clean ", "^Raw ",                                   -- herbs, fish and meat
    " bones$", "^Bones$", " ashes$",                                 -- Prayer
    "^Uncut ", "^Opal$", "^Jade$", "^Red topaz$", "^Sapphire$", "^Emerald$", "^Ruby$", "^Diamond$", "^Dragonstone$",
    "^Onyx$", "^Hydrix$",                                            -- gems
    " ore$", " bar$", "^Coal$", "^Luminite$", "^Drakolith$", "^Phasmatite$", "^Light animica$", "^Dark animica$",
    "^Limestone$", "^Sandstone ", "^Granite ",                       -- Mining and Smithing
    " logs$", "^Logs$", " plank$", "^Plank$", " wood spirit$", " stone spirit$", " seedling$",
    "dragonhide$", "^Cowhide$", " leather$", "^Snake hide$",         -- Crafting
    " essence$", "^Flax$", "^Bowstring$", "^Feather$", "^Soft clay$", "^Molten glass$", "^Vial of water$",
    " charm$", " charms$", "^Spirit shards$",                        -- Summoning
    "necroplasm$", "^Ectoplasm$", "ghostly ink$", "ritual candle",   -- Necromancy
    " urn$", " urn %(r%)$",                                          -- skilling urns
}
