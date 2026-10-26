local items = {}
for id, price in pairs(require("data/prices_01")) do
    items[id] = price
end
for id, price in pairs(require("data/prices_02")) do
    items[id] = price
end
for id, price in pairs(require("data/prices_03")) do
    items[id] = price
end
return {
    date = "2026-10-19",
    source = "https://runescape.wiki/w/Module:GEPrices/data.json?action=raw",
    taxRate = 0.02,
    items = items,
}
