local _, ns = ...
local WFC = ns.WFC

-- Items. Card(id) is the DENORMALIZED "everything about this item" record a
-- tooltip needs in one lookup: quest uses, quest rewards, recipe uses (with
-- profession/count/product copied in), crafted-by, vendors and drop sources.
-- It is built from the item's own QuestieDB row (which already carries reverse
-- links) plus the Recipes indexes, so no whole-database scan is ever needed.
--
-- Client(id) adds what only the game client knows (quality, sell price, bind,
-- stack, icon). It is async: nil now, then WFC_ITEM_LOADED(itemId) fires.

local Source = WFC.DB.Source
local Compat = WFC.Compat
local Data = ns.Data
local Util = WFC.Util
local Nz, EMPTY = Util.Nz, Util.EMPTY

local Items = WFC.DB:NewSection("Items")

local I
local cards, client, pending = {}, {}, {}

local FIELDS = {
    "name", "npcDrops", "objectDrops", "itemDrops", "startQuest", "questRewards", "itemLevel",
    "requiredLevel", "class", "subClass", "vendors", "relatedQuests", "teachesSpell", "flags",
}

function Items:Init()
    I = Source.I
end

function Items:Invalidate()
    cards = {}
end

--- Always returns a card (items unknown to QuestieDB still get recipe data).
--- {
---   id, known, name, ilvl, reqLevel, class, subClass, flags,
---   startsQuest, usedByQuests = {questIds}, rewardOf = {questIds},
---   vendors = {npcIds}, dropNpcs = {npcIds}, dropObjects = {objectIds}, dropItems = {itemIds},
---   teachesRecipe = spellId,
---   reagentFor = { {spellId, prof, profName, count, product, learn}, ... },
---   craftedBy = { spellIds },
---   isNew,
--- }
local NO_ITEM = { known = false, reagentFor = EMPTY, craftedBy = EMPTY, isNew = false }

function Items:Card(id)
    if type(id) ~= "number" then return NO_ITEM end
    local c = cards[id]
    if c then return c end
    local Recipes = WFC.DB.Recipes
    local known = I ~= nil and I.Exists(id) == true
    c = { id = id, known = known }
    if known then
        local v = I.GetAll(id, FIELDS)
        c.name = v[1]
        c.dropNpcs = v[2]
        c.dropObjects = v[3]
        c.dropItems = v[4]
        c.startsQuest = Nz(v[5])
        c.rewardOf = v[6]
        c.ilvl = Nz(v[7])
        c.reqLevel = Nz(v[8])
        c.class = v[9]
        c.subClass = v[10]
        c.vendors = v[11]
        c.usedByQuests = v[12]
        c.teachesRecipe = Nz(v[13])
        c.flags = v[14]
    end
    c.teachesRecipe = c.teachesRecipe or Recipes:TaughtBy(id)
    c.reagentFor = Recipes:UsingReagent(id)
    c.craftedBy = Recipes:Producing(id)
    local fix = Data.Corrections.item[id]
    if fix then
        for k, val in pairs(fix) do c[k] = val end
    end
    c.isNew = WFC.DB.New:Evaluate("item", id, nil, known)
    cards[id] = c
    return c
end

--- True if any quest (active or not) uses or starts with this item. Hot-path helper.
function Items:IsQuestItem(id)
    local c = self:Card(id)
    return c.startsQuest ~= nil or (c.usedByQuests ~= nil and #c.usedByQuests > 0)
end

---------------------------------------------------------------------------
-- Client data (async)
---------------------------------------------------------------------------
local function readClient(id)
    local name, link, quality, ilvl, minLevel, itemType, subType, stack, equipLoc, icon,
        sellPrice, classId, subClassId, bindType = Compat.GetItemInfo(id)
    if not name then return nil end
    return {
        name = name, link = link, quality = quality, ilvl = ilvl, minLevel = minLevel,
        type = itemType, subType = subType, stack = stack, equipLoc = equipLoc, icon = icon,
        sellPrice = sellPrice or 0, classId = classId, subClassId = subClassId, bindType = bindType,
    }
end

--- Client item info or nil (then WFC_ITEM_LOADED(id) fires once it arrives).
function Items:Client(id)
    local info = client[id]
    if info then return info end
    info = readClient(id)
    if info then
        client[id] = info
        return info
    end
    if not pending[id] then
        pending[id] = true
        Compat.RequestItem(id)
    end
end

WFC:RegisterEvent(Compat.ITEM_LOAD_EVENT, function(_, itemId, success)
    if not itemId or not pending[itemId] then return end
    pending[itemId] = nil
    if success == false then return end
    local info = readClient(itemId)
    if info then
        client[itemId] = info
        WFC:Fire("WFC_ITEM_LOADED", itemId)
    end
end)

function Items:Stats()
    return { cards = Util.Count(cards), client = Util.Count(client), pending = Util.Count(pending) }
end

WFC:On("WFC_RECIPES_CHANGED", function()
    cards = {}
end)
