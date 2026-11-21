local _, ns = ...
local WFC = ns.WFC

-- Drop sources with rates. QuestieDB ships drop rates (for quest-relevant items)
-- as one large Lua source string; it is materialized ONCE, either during the login
-- loading screen (settings.prewarmDrops) or on the first drop lookup.
-- Results merge three inputs per item:
--   * QuestieDB rates     { [npcId] = percent }
--   * QuestieDB npcDrops  (sources without a rate)
--   * harvested loot      (observed: looted count / corpses looted)

local Source = WFC.DB.Source
local Util = WFC.Util

local Drops = WFC.DB:NewSection("Drops")

local rates     -- [itemId] = { [npcId] = percent }, nil until loaded
local merged = {}

function Drops:Load()
    if rates then return rates end
    local module = Source:Support("QuestieClassicItemDrops")
    rates = Source.Materialize(module and module.wowheadData)
    return rates
end

function Drops:IsLoaded()
    return rates ~= nil
end

function Drops:Login()
    if WFC_DB_Global.settings.prewarmDrops then self:Load() end
end

function Drops:Invalidate()
    merged = {}
end

local function observed(itemId)
    local harvest = WFC_DB_Global and WFC_DB_Global.harvest
    if not harvest then return nil end
    return harvest.loot[itemId], harvest.corpses
end

--- Sorted list of { npc = npcId, rate = percent|nil, observed = bool }, best rate first.
function Drops:ForItem(itemId)
    local list = merged[itemId]
    if list then return list end
    local byNpc = {}
    local known = self:Load()[itemId]
    if known then
        for npcId, rate in pairs(known) do byNpc[npcId] = { npc = npcId, rate = rate } end
    end
    local card = WFC.DB.Items:Card(itemId)
    if card.dropNpcs then
        for i = 1, #card.dropNpcs do
            local npcId = card.dropNpcs[i]
            byNpc[npcId] = byNpc[npcId] or { npc = npcId }
        end
    end
    local loot, corpses = observed(itemId)
    if loot then
        for npcId, count in pairs(loot) do
            local looted = corpses and corpses[npcId]
            local entry = byNpc[npcId] or { npc = npcId }
            if not entry.rate and looted and looted >= 5 then
                entry.rate = math.min(100, count / looted * 100)
                entry.observed = true
            end
            byNpc[npcId] = entry
        end
    end
    list = {}
    for _, entry in pairs(byNpc) do list[#list + 1] = entry end
    table.sort(list, function(a, b) return (a.rate or -1) > (b.rate or -1) end)
    merged[itemId] = list
    return list
end

--- Drop percent for one item/NPC pair, or nil.
function Drops:Rate(itemId, npcId)
    local list = self:ForItem(itemId)
    for i = 1, #list do
        if list[i].npc == npcId then return list[i].rate end
    end
end

function Drops:Stats()
    return { loaded = rates ~= nil, items = rates and Util.Count(rates) or 0, merged = Util.Count(merged) }
end

WFC:On("WFC_HARVEST_LOOT", function(_, touchedItems)
    if touchedItems then
        for itemId in pairs(touchedItems) do
            merged[itemId] = nil
        end
    else
        merged = {}
    end
end)
