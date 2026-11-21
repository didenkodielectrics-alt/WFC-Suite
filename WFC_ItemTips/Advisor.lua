local _, ns = ...

-- The decision engine (plan.md §3.3). PURE: no WoW API and no WFC.DB calls.
-- Everything it needs arrives in `ctx` (built by Context.lua, or by hand in specs):
--
--   ctx.itemId, ctx.item (WFC.DB item card), ctx.client (client info or nil)
--   ctx.player   = { level, active = {[q]=info}, completed = {[q]=true}, charKey }
--   ctx.chars    = { {key, name, isCurrent, professions = {[skillLine]={rank}}, recipes = {[spellId]=true}}, ... }
--                  current character first; alts only when the user allows them
--   ctx.settings = { minProfit, margin, depositRate, learnWindow }
--   ctx.quest(id) -> quest card | nil          ctx.check(card, opts) -> ok, reason, detail
--   ctx.progress(questId, itemName) -> have, need
--   ctx.recipe(spellId) -> recipe | nil        ctx.difficulty(spellId, rank) -> "orange"|...
--   ctx.price(itemId) -> auctionCopper|nil, vendorCopper|nil, providerKey, ageDays
--   ctx.isNew(kind, id) -> bool
--   ctx.count    = how many the player holds (bags + bank), for the minimum-profit check
--
-- Evaluate(ctx) returns { isNew, entries = {...sorted by priority}, prices = {...} }.
-- Entry verdicts: "keep" (kind "active" | "starts" | "upcoming"), "craft", "disenchant", "auction", "vendor".
-- Disenchanting uses ns.Disenchant (Disenchant.lua, also pure).

local Advisor = {}
ns.Advisor = Advisor

Advisor.PRIORITY = { keep = 1, upcoming = 2, craft = 3, disenchant = 3.5, auction = 4, vendor = 5 }

local AH_CUT = 0.05
local SKILL_RANK = { orange = 4, yellow = 3, green = 2, grey = 1 }

local function list(t) return t or {} end

---------------------------------------------------------------------------
-- 1. KEEP: active quests, and quests this item starts
---------------------------------------------------------------------------
local function keepRules(ctx, out)
    local item, player = ctx.item, ctx.player
    local itemName = (ctx.client and ctx.client.name) or item.name
    for _, questId in ipairs(list(item.usedByQuests)) do
        if player.active[questId] then
            local card = ctx.quest(questId)
            if card then
                local have, need = ctx.progress(questId, itemName)
                out[#out + 1] = {
                    verdict = "keep", kind = "active", priority = Advisor.PRIORITY.keep,
                    quest = card, have = have, need = need, isNew = ctx.isNew("quest", questId),
                }
            end
        end
    end
    if item.startsQuest then
        local card = ctx.quest(item.startsQuest)
        if card and ctx.check(card) then
            out[#out + 1] = {
                verdict = "keep", kind = "starts", priority = Advisor.PRIORITY.keep,
                quest = card, isNew = ctx.isNew("quest", card.id),
            }
        end
    end
end

---------------------------------------------------------------------------
-- 2. KEEP (upcoming): available within +3 levels, or one prerequisite away
---------------------------------------------------------------------------
local function upcomingRule(ctx, out)
    local player = ctx.player
    local best
    for _, questId in ipairs(list(ctx.item.usedByQuests)) do
        if not player.active[questId] then
            local card = ctx.quest(questId)
            if card and not (player.completed[questId] and not card.repeatable) then
                local ok, reason, detail = ctx.check(card, { levelSlack = 3 })
                local via
                if not ok and reason == "prereq" and detail then
                    -- One step away: the missing prerequisite is itself in the log or available now.
                    local pre = ctx.quest(detail)
                    if pre and (player.active[detail] or ctx.check(pre, { levelSlack = 3 })) then
                        ok, via = true, pre
                    end
                end
                if ok and (not best or (card.minLevel or 0) < (best.quest.minLevel or 0)) then
                    best = {
                        verdict = "keep", kind = "upcoming", priority = Advisor.PRIORITY.upcoming,
                        quest = card, via = via,
                        needsLevel = card.minLevel and card.minLevel > player.level and card.minLevel or nil,
                        isNew = ctx.isNew("quest", questId),
                    }
                end
            end
        end
    end
    if best then out[#out + 1] = best end
end

---------------------------------------------------------------------------
-- 3. CRAFT: a character on the account knows (or can soon learn) a worthwhile recipe
---------------------------------------------------------------------------
local function priceOf(ctx, itemId)
    local ah, vendor = ctx.price(itemId)
    return ah or vendor
end

--- Product value minus reagent cost per craft, or nil when a price is missing.
local function profitOf(ctx, recipe)
    if not recipe or not recipe.product then return nil end
    local value = priceOf(ctx, recipe.product.id)
    if not value then return nil end
    local made = ((recipe.product.min or 1) + (recipe.product.max or 1)) / 2
    local cost = 0
    for _, r in ipairs(recipe.reagents or {}) do
        local p = priceOf(ctx, r.id)
        if not p then return nil end
        cost = cost + p * r.count
    end
    return value * made - cost
end

local function knowsRecipe(char, recipe, rank, learn)
    if char.recipes[recipe.spellId] or recipe.auto then return "known" end
    -- No profession-window scan for this character yet: assume trainer recipes at rank are trained.
    if next(char.recipes) == nil and recipe.trainer and rank >= learn then return "known" end
    return nil
end

local function craftRule(ctx, out)
    local window = ctx.settings.learnWindow or 25
    local crafts = {}
    for _, use in ipairs(list(ctx.item.reagentFor)) do
        local recipe = ctx.recipe(use.spellId)
        if recipe then
            local learn = use.learn or (recipe.skill and recipe.skill[1]) or 1
            local profit -- computed lazily, at most once per recipe
            for _, char in ipairs(ctx.chars) do
                local prof = char.professions[use.prof]
                if prof then
                    local rank = prof.rank or 0
                    local state = knowsRecipe(char, recipe, rank, learn)
                    if not state and learn <= rank + window then state = "learnable" end
                    if state then
                        local color = ctx.difficulty(use.spellId, math.max(rank, learn))
                        local worthIt = color == "orange" or color == "yellow"
                        if not worthIt then
                            if profit == nil then profit = profitOf(ctx, recipe) or false end
                            worthIt = profit and profit > 0
                        end
                        if worthIt then
                            crafts[#crafts + 1] = {
                                verdict = "craft", priority = Advisor.PRIORITY.craft,
                                spellId = use.spellId, recipe = recipe, prof = use.prof, profName = use.profName,
                                count = use.count, product = use.product, color = color, learn = learn,
                                char = char, learnable = state == "learnable", profit = profit or nil,
                                isNew = recipe.isNew == true,
                                score = (char.isCurrent and 100 or 0) + (state == "known" and 50 or 0)
                                    + (SKILL_RANK[color] or 0) * 10,
                            }
                            break -- the first (best-placed) character is enough for this recipe
                        end
                    end
                end
            end
        end
    end
    table.sort(crafts, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.profit or 0) > (b.profit or 0)
    end)
    for i = 1, #crafts do out[#out + 1] = crafts[i] end
end

---------------------------------------------------------------------------
-- DISENCHANT: an enchanter on the account gets more from the materials than selling would
---------------------------------------------------------------------------
local function disenchantRule(ctx, out)
    local D = ns.Disenchant
    local client = ctx.client
    if not (D and D.Can(client)) then return end
    local need = D.Skill(client.ilvl)
    -- Soulbound items can't be mailed: only this character can disenchant them.
    local soulbound = client.bindType == 1 or client.bindType == 4
    local who
    for _, char in ipairs(ctx.chars) do
        local prof = (char.isCurrent or not soulbound) and char.professions[D.ENCHANTING]
        if prof and (prof.rank or 0) >= need then
            who = char
            break
        end
    end
    if not who then return end
    local results = D.Results(client.quality, client.ilvl, client.classId == D.WEAPON)
    local value, mat = D.Value(results, function(id)
        local ah, vendor = ctx.price(id)
        return ah or vendor
    end)
    if not value then return end
    local ah, vendor = ctx.price(ctx.itemId)
    vendor = vendor or client.sellPrice or 0
    local sell = math.max(vendor, (ah and not soulbound) and ah * (1 - AH_CUT) or 0)
    local s = ctx.settings
    if value > sell * (1 + (s.margin or 0)) and value - sell > (s.minProfit or 0) / 2 then
        out[#out + 1] = { verdict = "disenchant", priority = Advisor.PRIORITY.disenchant, value = value,
            mat = mat, char = who, skill = need }
    end
end

---------------------------------------------------------------------------
-- 4/5. AUCTION or VENDOR
---------------------------------------------------------------------------
local MIN_DEPOSIT = 1 -- copper: Forever dropped the 1s minimum deposit to 1c (Nov 17, 2026 maintenance)
local function moneyRules(ctx, out, hasUse)
    local client = ctx.client or {}
    local s = ctx.settings
    local ah, vendor, provider, age = ctx.price(ctx.itemId)
    vendor = vendor or client.sellPrice
    local prices = { ah = ah, vendor = vendor, provider = provider, age = age }
    -- BoP / quest items are soulbound once owned and can never be auctioned.
    local soulbound = client.bindType == 1 or client.bindType == 4
    if ah and not soulbound then
        prices.cut = ah * AH_CUT
        prices.deposit = math.max(MIN_DEPOSIT, (vendor or 0) * (s.depositRate or 0))
        prices.fee = prices.cut + prices.deposit
        prices.net = ah - prices.fee
    end
    local sellable = vendor and vendor > 0
    if client.quality == 0 and sellable then
        out[#out + 1] = { verdict = "vendor", why = "junk", priority = Advisor.PRIORITY.vendor }
    elseif soulbound and not hasUse and sellable then
        out[#out + 1] = { verdict = "vendor", why = "soulbound", priority = Advisor.PRIORITY.vendor }
    elseif prices.net then
        local v = vendor or 0
        -- The minimum profit is for everything held (one posting), not a single item.
        local count = math.max(1, ctx.count or 1)
        if prices.net > v * (1 + (s.margin or 0)) and (prices.net - v) * count >= (s.minProfit or 0) then
            out[#out + 1] = { verdict = "auction", priority = Advisor.PRIORITY.auction, net = prices.net,
                vendor = v, count = count }
        elseif sellable and v >= prices.net then
            out[#out + 1] = { verdict = "vendor", why = "price", priority = Advisor.PRIORITY.vendor,
                net = prices.net, vendor = v, count = count }
        end
    end
    return prices
end

---------------------------------------------------------------------------
function Advisor.Evaluate(ctx)
    local entries = {}
    keepRules(ctx, entries)
    upcomingRule(ctx, entries)
    craftRule(ctx, entries)
    disenchantRule(ctx, entries)
    local prices = moneyRules(ctx, entries, #entries > 0)
    -- Stable sort by priority (rules already add in a sensible order within a priority).
    for i = 1, #entries do entries[i].order = i end
    table.sort(entries, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.order < b.order
    end)
    return { itemId = ctx.itemId, isNew = ctx.item.isNew == true, entries = entries, prices = prices }
end

return Advisor
