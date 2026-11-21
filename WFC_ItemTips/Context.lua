local _, ns = ...
local WFC = WFC

-- Glue between WFC.DB and the pure Advisor: builds the Advisor's `ctx` for an item
-- and memoizes the result until something it depends on changes (quest log,
-- professions, prices, recipes, item data, settings). A hover is one table lookup.

local Tips, Advisor = ns.Tips, ns.Advisor
local DB, Compat = WFC.DB, WFC.Compat

local results = {}

function Tips:Invalidate()
    results = {}
end

local function questCard(id) return DB:GetQuest(id) end
local function check(card, opts) return DB.Quests.Check(card, WFC.Player, opts) end
local function recipe(spellId) return DB:GetRecipe(spellId) end
local function difficulty(spellId, rank) return DB.Recipes:Difficulty(spellId, rank) end
local function price(itemId) return DB:GetPrice(itemId) end
local function isNew(kind, id) return DB:IsNew(kind, id) end

--- have, need for the objective of `questId` that collects `itemName`.
local function progress(questId, itemName)
    local objectives = Compat.GetQuestObjectives(questId)
    local onlyItem, items = nil, 0
    for i = 1, #objectives do
        local o = objectives[i]
        if o.type == "item" then
            items = items + 1
            onlyItem = o
            if itemName and o.text and o.text:find(itemName, 1, true) then return o.have, o.need end
        end
    end
    if items == 1 then return onlyItem.have, onlyItem.need end
end

local function shortName(charKey)
    return (charKey:match("^([^-]+)")) or charKey
end

--- Current character first (live professions), then same-faction alts from the account cache.
local function characters(useAlts)
    local P = WFC.Player
    local chars = WFC_DB_Global and WFC_DB_Global.chars or {}
    local mine = P.charKey and chars[P.charKey]
    local list = { {
        key = P.charKey, name = P.charKey and shortName(P.charKey), isCurrent = true,
        professions = P.professions or {}, recipes = mine and mine.recipes or {},
    } }
    if useAlts then
        local keys = {}
        for key, t in pairs(chars) do
            if key ~= P.charKey and t.faction == P.faction and t.professions then keys[#keys + 1] = key end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            list[#list + 1] = {
                key = key, name = shortName(key), isCurrent = false,
                professions = chars[key].professions, recipes = chars[key].recipes or {},
            }
        end
    end
    return list
end

--- How many of an item the player holds, bags + bank.
local function heldCount(itemId)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not get then return 1 end
    local ok, n = pcall(get, itemId, true)
    return (ok and type(n) == "number" and n > 0) and n or 1
end

function Tips:BuildContext(itemId, count)
    return {
        itemId = itemId,
        count = count or heldCount(itemId),
        item = DB:GetItem(itemId),
        client = DB:GetItemClient(itemId),
        player = WFC.Player,
        chars = characters(self.settings.useAlts),
        settings = self:AdvisorSettings(),
        quest = questCard, check = check, progress = progress,
        recipe = recipe, difficulty = difficulty, price = price, isNew = isNew,
    }
end

--- Memoized Advisor result for an item. A result built before the client knew the
--- item (no quality/sell price yet) is replaced once WFC_ITEM_LOADED arrives.
function Tips:Evaluate(itemId)
    -- The held count changes the AUCTION verdict, so it is part of the cache key.
    local count = heldCount(itemId)
    local key = itemId .. ":" .. count
    local r = results[key]
    if r then return r end
    local ctx = self:BuildContext(itemId, count)
    r = Advisor.Evaluate(ctx)
    r.complete = ctx.client ~= nil
    results[key] = r
    return r
end

function Tips:PrintWhy(itemId)
    local r = self:Evaluate(itemId)
    local card = DB:GetItem(itemId)
    WFC:Print(("item %d %s%s: %d verdict(s)"):format(itemId, card.name or "?", r.isNew and WFC:NewTag(" ") or "", #r.entries))
    for i, e in ipairs(r.entries) do
        local detail = e.quest and ("quest " .. e.quest.id) or e.spellId and ("spell " .. e.spellId .. " " .. tostring(e.color))
            or e.why or (e.net and ("net " .. math.floor(e.net))) or ""
        print(("  %d. %s%s %s"):format(i, e.verdict, e.kind and ("/" .. e.kind) or "", detail))
    end
    local p = r.prices
    print(("  prices: ah %s · vendor %s · net %s · source %s"):format(tostring(p.ah), tostring(p.vendor),
        tostring(p.net and math.floor(p.net)), tostring(p.provider)))
end

---------------------------------------------------------------------------
-- Invalidation
---------------------------------------------------------------------------
WFC:On("WFC_PLAYER_CHANGED", function() Tips:Invalidate() end)
WFC:On("WFC_PRICES_UPDATED", function() Tips:Invalidate() end)
WFC:On("WFC_RECIPES_CHANGED", function() Tips:Invalidate() end)
WFC:On("WFC_DB_READY", function() Tips:Invalidate() end)
WFC:On("WFC_ITEM_LOADED", function(_, itemId)
    -- Results for other items may reference this one (product / reagent prices), so drop all.
    if itemId then results = {} end
end)
