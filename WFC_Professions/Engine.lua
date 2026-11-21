local _, ns = ...
local WFC = WFC

-- Engine: Core logic for WFC_Professions.
--   1. Cross-character Crafting Materials tracker + Mail routing hints
--   2. Scroll/Pattern Recipes tracker (learned vs unlearned, scroll owned check)
--   3. Craftable Equippable Gear for current character's class & level
--   4. Multi-character Skill-Up Planner using materials already on hand

local Inventory = ns.Inventory
local Professions = ns.Professions -- was an undefined global (no global `Professions` exists on Forever)
local Compat = WFC.Compat
local Colors = WFC.Colors
local P = Colors.palette

local function isSecret(v)
    return Compat and Compat.IsSecret and Compat.IsSecret(v) or false
end

--- True once the client has the item's data cached (tooltips/stats are empty before that).
--- Requests a load when it isn't, so a later WFC_ITEM_LOADED refresh can fill it in.
local function itemDataReady(itemId)
    if not (C_Item and C_Item.IsItemDataCachedByID) then return true end
    local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemId)
    if ok and cached and not isSecret(cached) then return true end
    if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemId) end
    return false
end

local Engine = {}
ns.Engine = Engine
WFC.Professions.Engine = Engine

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Crafting profession order and icons
Engine.CRAFTING_PROFS = {
    { id = 197, name = "Tailoring",      icon = "Interface\\Icons\\Trade_Tailoring" },
    { id = 165, name = "Leatherworking", icon = "Interface\\Icons\\Trade_LeatherWorking" },
    { id = 164, name = "Blacksmithing",  icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { id = 202, name = "Engineering",    icon = "Interface\\Icons\\Trade_Engineering" },
    { id = 333, name = "Enchanting",     icon = "Interface\\Icons\\Trade_Engraving" },
    { id = 171, name = "Alchemy",        icon = "Interface\\Icons\\Trade_Alchemy" },
    { id = 185, name = "Cooking",        icon = "Interface\\Icons\\INV_Misc_Food_15" },
    { id = 129, name = "First Aid",      icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
    { id = 186, name = "Mining",         icon = "Interface\\Icons\\Trade_Mining" },
}

local PROF_ICON = {}
for _, p in ipairs(Engine.CRAFTING_PROFS) do PROF_ICON[p.id] = p.icon end
PROF_ICON[182] = "Interface\\Icons\\Trade_Herbalism"
PROF_ICON[393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"
PROF_ICON[356] = "Interface\\Icons\\Trade_Fishing"

function Engine.ProfIcon(profId)
    return PROF_ICON[profId] or DEFAULT_ICON
end

---------------------------------------------------------------------------
-- Item Info Helpers (merges QuestieDB card + async Client info + Instant icon)
---------------------------------------------------------------------------
local QUALITY_HEX = {
    [0] = "ff9d9d9d",
    [1] = "ffffffff",
    [2] = "ff1eff00",
    [3] = "ff0070dd",
    [4] = "ffa335ee",
    [5] = "ffff8000",
}

function Engine.ItemDisplay(itemId)
    if not itemId then
        return "Unknown", DEFAULT_ICON, nil, nil, nil
    end
    local card = WFC.DB and WFC.DB:GetItem(itemId)
    local client = WFC.DB and WFC.DB:GetItemClient(itemId)
    local icon = client and client.icon
    local equipLoc = client and client.equipLoc
    local classId = (client and client.classId) or (card and card.class)
    local subClassId = (client and client.subClassId) or (card and card.subClass)

    if not icon and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, eq, ic, cId, scId = C_Item.GetItemInfoInstant(itemId)
        icon = ic
        equipLoc = equipLoc or eq
        classId = classId or cId
        subClassId = subClassId or scId
    elseif not icon and GetItemInfoInstant then
        local _, _, _, eq, ic, cId, scId = GetItemInfoInstant(itemId)
        icon = ic
        equipLoc = equipLoc or eq
        classId = classId or cId
        subClassId = subClassId or scId
    end

    local rawName = (client and client.name) or (card and card.name) or ("Item #" .. tostring(itemId))
    local q = client and client.quality
    local coloredName
    if q and QUALITY_HEX[q] then
        coloredName = "|c" .. QUALITY_HEX[q] .. rawName .. "|r"
    else
        coloredName = rawName
    end

    return rawName, icon or DEFAULT_ICON, coloredName, card, client, equipLoc, classId, subClassId
end

function Engine.RecipeDisplay(recipe)
    if not recipe then return "Unknown Recipe", DEFAULT_ICON end
    local name = WFC.DB.Recipes:Name(recipe.spellId)
    local icon = nil
    if recipe.product and recipe.product.id then
        local pName, pIcon = Engine.ItemDisplay(recipe.product.id)
        if not name or name == "" then name = pName end
        icon = pIcon
    end
    if not icon and C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(recipe.spellId)
    elseif not icon and GetSpellTexture then
        icon = GetSpellTexture(recipe.spellId)
    end
    return name or ("Recipe #" .. tostring(recipe.spellId)), icon or Engine.ProfIcon(recipe.prof)
end

---------------------------------------------------------------------------
-- Vendor Reagents (items bought from trade vendors, not gathered/farmed)
---------------------------------------------------------------------------
Engine.VENDOR_REAGENTS = {
    -- Threads
    [2320]  = true, -- Coarse Thread
    [2321]  = true, -- Fine Thread
    [4291]  = true, -- Silken Thread
    [8343]  = true, -- Heavy Silken Thread
    [14341] = true, -- Rune Thread

    -- Dyes & Bleach
    [2324]  = true, -- Bleach
    [2604]  = true, -- Red Dye
    [2605]  = true, -- Green Dye
    [4340]  = true, -- Gray Dye
    [4341]  = true, -- Yellow Dye
    [4342]  = true, -- Purple Dye
    [6260]  = true, -- Blue Dye
    [6261]  = true, -- Orange Dye
    [10290] = true, -- Pink Dye

    -- Flux, Coal, Wood & Stocks
    [2880]  = true, -- Weak Flux
    [3470]  = true, -- Strong Flux
    [3857]  = true, -- Coal
    [4399]  = true, -- Wooden Stock
    [4400]  = true, -- Heavy Stock
    [4470]  = true, -- Simple Wood
    [11291] = true, -- Star Wood
    [2373]  = true, -- Flint and Tinder

    -- Vials
    [3371]  = true, -- Empty Vial
    [3372]  = true, -- Leaded Vial
    [8925]  = true, -- Crystal Vial
    [18256] = true, -- Imbued Vial

    -- Spices, Flour, Salt, Water
    [2678]  = true, -- Mild Spices
    [2692]  = true, -- Hot Spices
    [3713]  = true, -- Soothing Spices
    [30817] = true, -- Simple Flour
    [4471]  = true, -- Rock Salt
    [159]   = true, -- Refreshing Spring Water
    [1179]  = true, -- Ice Cold Milk
    [1708]  = true, -- Sweet Nectar
    [1645]  = true, -- Moonberry Juice / Melon Juice
    [8766]  = true, -- Morning Glory Dew

    -- Parchment
    [10648] = true, -- Blank Parchment
    [10647] = true, -- Common Parchment
    [2609]  = true, -- Heavy Parchment

    -- Fishing / Misc vendor
    [6529]  = true, -- Shiny Bauble
    [6530]  = true, -- Nightcrawlers
    [6532]  = true, -- Bright Baubles
    [17057] = true, -- Shiny Fish Scales
    [17058] = true, -- Fish Oil
}

function Engine.IsVendorReagent(itemId)
    if not itemId then return false end
    if Engine.VENDOR_REAGENTS[itemId] then return true end
    if WFC.DB and WFC.DB.GetItem then
        local card = WFC.DB:GetItem(itemId)
        if card and card.known then
            local nVendors = card.vendors and #card.vendors or 0
            local nDrops = card.dropNpcs and #card.dropNpcs or 0
            local nObjects = card.dropObjects and #card.dropObjects or 0
            local nContainers = card.dropItems and #card.dropItems or 0
            local nCrafted = card.craftedBy and #card.craftedBy or 0
            if nVendors >= 2 and nDrops == 0 and nObjects == 0 and nContainers == 0 and nCrafted == 0 then
                Engine.VENDOR_REAGENTS[itemId] = true
                return true
            end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Item Stats Extraction & Badging (GetItemStats + Tooltip Scanner Fallback)
---------------------------------------------------------------------------
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT             = "str",
    ITEM_MOD_AGILITY_SHORT              = "agi",
    ITEM_MOD_STAMINA_SHORT              = "sta",
    ITEM_MOD_INTELLECT_SHORT            = "int",
    ITEM_MOD_SPIRIT_SHORT               = "spi",
    ITEM_MOD_SPELL_POWER_SHORT          = "sp",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT    = "sp",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT   = "sp",
    ITEM_MOD_ATTACK_POWER_SHORT         = "ap",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT    = "ap",
    ITEM_MOD_CRIT_RATING_SHORT          = "crit_hit",
    ITEM_MOD_CRIT_MELEE_RATING_SHORT    = "crit_hit",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT   = "crit_hit",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT    = "crit_hit",
    ITEM_MOD_HIT_RATING_SHORT           = "crit_hit",
    ITEM_MOD_HIT_MELEE_RATING_SHORT     = "crit_hit",
    ITEM_MOD_HIT_RANGED_RATING_SHORT    = "crit_hit",
    ITEM_MOD_HIT_SPELL_RATING_SHORT     = "crit_hit",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def",
    ITEM_MOD_DODGE_RATING_SHORT         = "def",
    ITEM_MOD_PARRY_RATING_SHORT         = "def",
    ITEM_MOD_BLOCK_RATING_SHORT         = "def",
    ITEM_MOD_BLOCK_VALUE_SHORT          = "def",
    ITEM_MOD_MANA_REGENERATION_SHORT    = "mp5",
}

local statCache = {}
local scanTip = nil

local function getScanTip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "WFC_ProfScanTip", UIParent, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return scanTip
end

--- Readable left-column tooltip lines (2..n) for an item link. Secret lines are skipped.
--- Prefers C_TooltipInfo (no frame needed); falls back to a hidden scanning tooltip.
local function tooltipLines(link)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and type(data) == "table" and not isSecret(data) and type(data.lines) == "table" then
            for i = 2, #data.lines do
                local text = data.lines[i] and data.lines[i].leftText
                if type(text) == "string" and not isSecret(text) and text ~= "" then
                    lines[#lines + 1] = text
                end
            end
            return lines
        end
    end
    local ok = pcall(function()
        local tip = getScanTip()
        tip:SetOwner(UIParent, "ANCHOR_NONE") -- an un-owned GameTooltip ignores SetHyperlink
        tip:ClearLines()
        tip:SetHyperlink(link)
        for i = 2, tip:NumLines() or 0 do
            local fs = _G["WFC_ProfScanTipTextLeft" .. i]
            local text = fs and fs:GetText()
            if type(text) == "string" and not isSecret(text) and text ~= "" then
                lines[#lines + 1] = text
            end
        end
    end)
    return ok and lines or {}
end

function Engine.GetItemStats(itemId)
    if not itemId then return WFC.Util.EMPTY, "" end
    local cached = statCache[itemId]
    if cached then
        return cached.stats, cached.summary
    end

    -- Item data not in the client cache yet: both sources below come back empty.
    -- Don't cache that, or the stat filter would miss this item for the whole session.
    local ready = itemDataReady(itemId)

    local stats = {}

    -- 1. Try Blizzard GetItemStats API (C_Item on Forever; the global is gone)
    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    if getStats then
        local ok, raw = pcall(getStats, "item:" .. itemId)
        if ok and type(raw) == "table" and not isSecret(raw) then
            for k, val in pairs(raw) do
                local mapped = STAT_KEYS[k]
                if mapped and type(val) == "number" and not isSecret(val) and val > 0 then
                    stats[mapped] = (stats[mapped] or 0) + val
                end
            end
        end
    end

    -- 2. Fallback / supplement: tooltip lines
    local lines = tooltipLines("item:" .. itemId)
    if #lines > 0 then
        for _, text in ipairs(lines) do
            do
                -- Primary stats: e.g. "+5 Agility", "+3 Stamina"
                local num, statName = text:match("%+(%d+)%s+([%a%s]+)")
                if num and statName then
                    num = tonumber(num) or 0
                    local sLower = statName:lower():trim()
                    if sLower:find("^str") then
                        stats.str = (stats.str or 0) + num
                    elseif sLower:find("^agi") then
                        stats.agi = (stats.agi or 0) + num
                    elseif sLower:find("^sta") then
                        stats.sta = (stats.sta or 0) + num
                    elseif sLower:find("^int") then
                        stats.int = (stats.int or 0) + num
                    elseif sLower:find("^spi") then
                        stats.spi = (stats.spi or 0) + num
                    elseif sLower:find("resistance") then
                        stats.res = (stats.res or 0) + num
                    elseif sLower:find("attack power") then
                        stats.ap = (stats.ap or 0) + num
                    end
                end

                local lower = text:lower()
                -- Spell power / damage / healing
                if lower:find("damage and healing") or lower:find("healing done") or lower:find("spell power") or lower:find("spell damage") then
                    local spNum = text:match("(%d+)")
                    if spNum then
                        stats.sp = (stats.sp or 0) + (tonumber(spNum) or 0)
                    else
                        stats.sp = (stats.sp or 0) + 1
                    end
                end

                -- Attack power
                if lower:find("attack power") and not stats.ap then
                    local apNum = text:match("(%d+)")
                    if apNum then stats.ap = (stats.ap or 0) + (tonumber(apNum) or 0) end
                end

                -- Crit / Hit
                if lower:find("critical strike") or lower:find("chance to hit") or lower:find("critical hit") then
                    stats.crit_hit = (stats.crit_hit or 0) + 1
                end

                -- Defense / Dodge / Parry / Block
                if lower:find("defense") or lower:find("dodge") or lower:find("parry") or lower:find("block") then
                    stats.def = (stats.def or 0) + 1
                end

                -- MP5 (mana per 5 sec)
                if lower:find("mana per 5 sec") or lower:find("mana every 5 sec") then
                    local mp5Num = text:match("(%d+)")
                    if mp5Num then
                        stats.mp5 = (stats.mp5 or 0) + (tonumber(mp5Num) or 0)
                    else
                        stats.mp5 = (stats.mp5 or 0) + 1
                    end
                end
            end
        end
    end

    -- Build colored summary badges
    local parts = {}
    if stats.str and stats.str > 0 then parts[#parts + 1] = "|cffff8040+" .. stats.str .. " Str|r" end
    if stats.agi and stats.agi > 0 then parts[#parts + 1] = "|cff40ff40+" .. stats.agi .. " Agi|r" end
    if stats.sta and stats.sta > 0 then parts[#parts + 1] = "|cffffd100+" .. stats.sta .. " Sta|r" end
    if stats.int and stats.int > 0 then parts[#parts + 1] = "|cff4dd9ff+" .. stats.int .. " Int|r" end
    if stats.spi and stats.spi > 0 then parts[#parts + 1] = "|cffc0a0ff+" .. stats.spi .. " Spi|r" end
    if stats.sp  and stats.sp > 0  then parts[#parts + 1] = "|cff80c0ff+" .. stats.sp .. " SP|r" end
    if stats.ap  and stats.ap > 0  then parts[#parts + 1] = "|cffff9060+" .. stats.ap .. " AP|r" end
    if stats.crit_hit and stats.crit_hit > 0 then parts[#parts + 1] = "|cffffff60Crit/Hit|r" end
    if stats.def and stats.def > 0 then parts[#parts + 1] = "|cffa0a0a0Def|r" end
    if stats.mp5 and stats.mp5 > 0 then parts[#parts + 1] = "|cff60ffff+" .. stats.mp5 .. " MP5|r" end
    if stats.res and stats.res > 0 then parts[#parts + 1] = "|cffff7070+" .. stats.res .. " Res|r" end

    local summary = table.concat(parts, " ")
    if ready or #lines > 0 then
        statCache[itemId] = { stats = stats, summary = summary }
    end
    return stats, summary
end

---------------------------------------------------------------------------
-- Recipe Learn Rank & Profession Requirement Authority
---------------------------------------------------------------------------
local learnRankCache = {}

function Engine.GetRecipeLearnRank(r)
    if not r then return 1 end
    local spellId = r.spellId
    if spellId and learnRankCache[spellId] then
        return learnRankCache[spellId]
    end

    -- 1. Check if recipe already carries an explicit learn rank > 1
    if r.learnRank and r.learnRank > 1 then
        if spellId then learnRankCache[spellId] = r.learnRank end
        return r.learnRank
    end

    local s = r.skill
    local explicit = s and s[1]
    if explicit and explicit > 1 then
        if spellId then learnRankCache[spellId] = explicit end
        return explicit
    end

    -- 2. Starting/automatic recipes learned with the profession start at 1
    if r.auto then
        if spellId then learnRankCache[spellId] = 1 end
        return 1
    end

    -- 3. If taught by a scroll item (recipeItem), scan the scroll item's tooltip:
    -- e.g. "Requires Tailoring (100)" or "Requires Leatherworking (90)".
    -- Only the "(n)" form is a skill rank: "Requires Level 20" is a character level.
    -- If the scroll's data isn't cached yet, the estimates below are not cached either.
    local cacheable = true
    if r.recipeItem and r.recipeItem > 0 then
        if not itemDataReady(r.recipeItem) then cacheable = false end
        for _, text in ipairs(tooltipLines("item:" .. r.recipeItem)) do
            if text:find("^Requires") and not text:find("^Requires Level") then
                local n = tonumber(text:match("%((%d+)%)"))
                if n and n > 0 then
                    if spellId then learnRankCache[spellId] = n end
                    return n
                end
            end
        end
    end
    local function remember(rank)
        if spellId and cacheable then learnRankCache[spellId] = rank end
        return rank
    end

    -- 4. Calculate from recipe skill thresholds: { learn, orange, yellow, green, grey }
    -- In Classic WoW, recipes with yellow <= 45 are beginner level (rank 1).
    -- Above 45, the orange range is typically ~25 skill points, aligned to standard 5-point trainer tiers.
    local yellow = s and s[3]
    if yellow and yellow > 0 then
        if yellow <= 45 then
            return remember(1)
        else
            local raw = yellow - 25
            local rounded = math.floor((raw + 2) / 5) * 5
            return remember(math.max(1, rounded))
        end
    end

    -- 5. Fallback: estimate from product item's required character level (reqLevel * 5)
    local productId = r.product and r.product.id
    if productId then
        local card = WFC.DB and WFC.DB:GetItem(productId)
        local client = WFC.DB and WFC.DB:GetItemClient(productId)
        local reqLvl = (client and client.minLevel and client.minLevel > 0 and client.minLevel)
            or (card and card.reqLevel and card.reqLevel > 0 and card.reqLevel)
        if reqLvl and reqLvl > 0 then
            return remember(math.max(1, reqLvl * 5))
        end
    end

    return remember((explicit and explicit > 0 and explicit) or (r.learnRank and r.learnRank > 0 and r.learnRank) or 1)
end

function Engine.GetRecipeYellowRank(recipe)
    if not recipe then return nil end
    local s = recipe.skill
    if s and s[3] and type(s[3]) == "number" and s[3] > 0 then
        return s[3]
    end
    return nil
end

function Engine.GetRecipeGreenRank(recipe)
    if not recipe then return nil end
    local s = recipe.skill
    if s and s[4] and type(s[4]) == "number" and s[4] > 0 then
        return s[4]
    end
    return nil
end

function Engine.GetRecipeGreyRank(recipe)
    if not recipe then return nil end
    local s = recipe.skill
    if s and s[5] and type(s[5]) == "number" and s[5] > 0 then
        return s[5]
    end
    return nil
end

function Engine.GetRecipeLearnInfo(recipe, baseTotals)
    if not recipe then return "Unknown", nil, false end
    if recipe.auto then
        return "Auto-learned", nil, false
    end
    if recipe.recipeItem and recipe.recipeItem > 0 and not recipe.trainer then
        local scrollName = Engine.ItemDisplay(recipe.recipeItem)
        local owned = (baseTotals and baseTotals[recipe.recipeItem]) or 0
        if owned > 0 then
            return ("Learn %s (in bags)"):format(scrollName), recipe.recipeItem, true
        else
            return ("Learn %s (scroll)"):format(scrollName), recipe.recipeItem, false
        end
    end
    local learnRank = Engine.GetRecipeLearnRank(recipe)
    return ("Trainer (lvl %d)"):format(learnRank), nil, false
end

---------------------------------------------------------------------------
-- Helper: Which professions do our characters have?
---------------------------------------------------------------------------
function Engine:GetAccountProfessions()
    local chars = Inventory:GetCharacters()
    local byProf = {} -- [profId] = { { char = char, rank = n, max = m }, ... }
    for _, char in ipairs(chars) do
        for profId, pInfo in pairs(char.professions or {}) do
            local list = byProf[profId]
            if not list then
                list = {}
                byProf[profId] = list
            end
            list[#list + 1] = {
                char = char,
                rank = pInfo.rank or 0,
                max = pInfo.max or 75,
                name = pInfo.name or WFC.DB.Recipes.PROFESSION_NAMES[profId] or ("Prof " .. profId),
            }
        end
    end
    for _, list in pairs(byProf) do
        table.sort(list, function(a, b)
            if a.rank ~= b.rank then return a.rank > b.rank end
            return (a.char.level or 0) > (b.char.level or 0)
        end)
    end
    return byProf
end

function Engine.CharKnowsRecipe(char, recipe)
    if not char or not recipe then return false end
    local prof = char.professions and char.professions[recipe.prof]
    if not prof then return false end
    if char.recipes and char.recipes[recipe.spellId] then return true end
    local learn = Engine.GetRecipeLearnRank(recipe)
    local rank = prof.rank or 0
    if recipe.auto and rank >= learn then return true end
    -- If profession window hasn't been scanned yet for this alt, assume trainer recipes at <= rank are known
    if (not char.recipes or next(char.recipes) == nil) and recipe.trainer and rank >= learn then
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- TAB 1: Cross-Character Crafting Materials
---------------------------------------------------------------------------
function Engine:GetMaterials(opts)
    opts = opts or {}
    local profFilter = opts.profFilter or 0 -- 0 = all, -1 = my alts' profs, >0 = specific profId
    local inStockOnly = opts.inStockOnly ~= false
    local search = opts.search and opts.search:lower():trim() or ""
    if search == "" then search = nil end

    local totals, byItem = Inventory:GetItemIndex()
    local acctProfs = self:GetAccountProfessions()

    -- Collect candidate itemIds
    local candidateIds = {}
    if inStockOnly then
        for itemId, count in pairs(totals) do
            if count > 0 then candidateIds[itemId] = true end
        end
    else
        local allRecipes = (WFC.DB and WFC.DB:GetRecipes()) or {}
        for _, r in pairs(allRecipes) do
            for _, reg in ipairs(r.reagents or {}) do
                if reg.id then candidateIds[reg.id] = true end
            end
        end
    end

    local results = {}
    for itemId in pairs(candidateIds) do
        local uses = (WFC.DB and WFC.DB:GetRecipesUsingItem(itemId)) or WFC.Util.EMPTY
        local rawName, icon, coloredName, card, client, equipLoc, classId, subClassId = Engine.ItemDisplay(itemId)
        local isTradeGood = false
        if classId == 7 or classId == 5 or (card and (card.class == 7 or card.class == 5)) then
            isTradeGood = true
        end

        if #uses > 0 or isTradeGood then
            local profSet = {}
            local profNames = {}
            for i = 1, #uses do
                local u = uses[i]
                if u.prof and not profSet[u.prof] then
                    profSet[u.prof] = true
                    profNames[#profNames + 1] = u.profName or WFC.DB.Recipes.PROFESSION_NAMES[u.prof] or ""
                end
            end

            if #uses == 0 and isTradeGood then
                if subClassId == 5 then
                    profSet[197] = true; profNames[#profNames + 1] = "Tailoring"
                elseif subClassId == 6 then
                    profSet[165] = true; profNames[#profNames + 1] = "Leatherworking"
                elseif subClassId == 7 then
                    profSet[164] = true; profNames[#profNames + 1] = "Blacksmithing"
                    profSet[186] = true; profNames[#profNames + 1] = "Mining"
                elseif subClassId == 8 then
                    profSet[185] = true; profNames[#profNames + 1] = "Cooking"
                elseif subClassId == 9 then
                    profSet[171] = true; profNames[#profNames + 1] = "Alchemy"
                elseif subClassId == 12 or subClassId == 14 or subClassId == 15 then
                    profSet[333] = true; profNames[#profNames + 1] = "Enchanting"
                elseif subClassId == 1 or subClassId == 2 or subClassId == 3 then
                    profSet[202] = true; profNames[#profNames + 1] = "Engineering"
                else
                    profNames[#profNames + 1] = "Trade Goods"
                end
            end
            table.sort(profNames)

            local matchesProf = false
            if profFilter == 0 then
                matchesProf = true
            elseif profFilter == -1 then
                if not next(acctProfs) then
                    matchesProf = true
                else
                    for pId in pairs(profSet) do
                        if acctProfs[pId] then matchesProf = true; break end
                    end
                    if not matchesProf and isTradeGood and #profNames == 1 and profNames[1] == "Trade Goods" then
                        matchesProf = true
                    end
                end
            else
                matchesProf = profSet[profFilter] == true
            end

            if matchesProf then
                if not search or rawName:lower():find(search, 1, true) then
                    local totalCount = totals[itemId] or 0
                    local holders = byItem[itemId] or WFC.Util.EMPTY

                    -- Build holder breakdown string and check if any holder doesn't use this mat
                    local holderParts = {}
                    local crafterUsers = {}
                    local crafterSet = {}

                    for pId in pairs(profSet) do
                        for _, entry in ipairs(acctProfs[pId] or {}) do
                            local cKey = entry.char.key
                            if not crafterSet[cKey] then
                                crafterSet[cKey] = entry.char
                                crafterUsers[#crafterUsers + 1] = ("%s (%s %d)"):format(
                                    Inventory.ColorizeName(entry.char.shortName, entry.char.class),
                                    entry.name, entry.rank)
                            end
                        end
                    end

                    local mailHints = {}
                    for _, h in ipairs(holders) do
                        local locParts = {}
                        if h.bags > 0 then locParts[#locParts + 1] = h.bags .. " bags" end
                        if h.bank > 0 then locParts[#locParts + 1] = h.bank .. " bank" end
                        if h.mail > 0 then locParts[#locParts + 1] = h.mail .. " mail" end
                        local locStr = #locParts > 0 and (" (" .. table.concat(locParts, ", ") .. ")") or ""
                        holderParts[#holderParts + 1] = ("%s: |cffffffff%d|r%s"):format(
                            Inventory.ColorizeName(h.char.shortName or h.char.name, h.char.class),
                            h.total, locStr)

                        -- If this holder does NOT have any profession that uses this material,
                        -- and at least one of our alts DOES have a profession that uses it:
                        if h.char.key and not crafterSet[h.char.key] and #crafterUsers > 0 then
                            -- Pick best recipient alt
                            local recipient
                            for pId in pairs(profSet) do
                                local list = acctProfs[pId]
                                if list and list[1] then
                                    recipient = list[1].char
                                    break
                                end
                            end
                            if recipient then
                                mailHints[#mailHints + 1] = ("Mail %d from %s → %s"):format(
                                    h.total,
                                    h.char.shortName or h.char.name,
                                    Inventory.ColorizeName(recipient.shortName or recipient.name, recipient.class))
                            end
                        end
                    end

                    -- Primary profession for grouping
                    local primaryProf = 0
                    for _, p in ipairs(Engine.CRAFTING_PROFS) do
                        if profSet[p.id] then
                            primaryProf = p.id
                            break
                        end
                    end

                    local usedByText
                    if #crafterUsers > 0 then
                        usedByText = "Used by: " .. table.concat(crafterUsers, ", ")
                    elseif #profNames > 0 and profNames[1] ~= "Trade Goods" then
                        usedByText = "Used by: " .. table.concat(profNames, ", ") .. " (no alt)"
                    else
                        usedByText = "General Trade Goods / Reagent"
                    end

                    results[#results + 1] = {
                        itemId = itemId,
                        name = rawName,
                        coloredName = coloredName,
                        icon = icon,
                        total = totalCount,
                        primaryProf = primaryProf,
                        profNames = table.concat(profNames, ", "),
                        holderText = #holderParts > 0 and table.concat(holderParts, " · ") or "None in stock",
                        usedByText = usedByText,
                        mailHint = #mailHints > 0 and table.concat(mailHints, " · ") or nil,
                        recipeCount = #uses,
                    }
                end
            end
        end
    end

    table.sort(results, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)

    return results
end

---------------------------------------------------------------------------
-- TAB 2: Scroll Recipes (Only recipes from scrolls/patterns/plans, NOT trainers)
---------------------------------------------------------------------------
function Engine:GetScrollRecipes(opts)
    opts = opts or {}
    local profFilter = opts.profFilter or -1 -- -1 = my alts' profs, 0 = all, >0 = specific profId
    local stateFilter = opts.stateFilter or "all" -- "all" | "unlearned" | "learned" | "owned"
    local search = opts.search and opts.search:lower():trim() or ""
    if search == "" then search = nil end

    local atLearnedLevel = opts.atLearnedLevel == true
    local searchTokens = nil
    if search and search ~= "" then
        searchTokens = {}
        for token in search:gmatch("%S+") do
            searchTokens[#searchTokens + 1] = token:lower()
        end
        if #searchTokens == 0 then searchTokens = nil end
    end

    local allRecipes = (WFC.DB and WFC.DB:GetRecipes()) or {}
    local acctProfs = self:GetAccountProfessions()
    local totals, byItem = Inventory:GetItemIndex()

    local results = {}
    for spellId, r in pairs(allRecipes) do
        -- Strictly scroll/pattern/plan/formula/schematic recipes, NOT trainer or auto-learned
        if r.recipeItem and not r.trainer and not r.auto and r.prof then
            local matchesProf = false
            if profFilter == 0 then
                matchesProf = true
            elseif profFilter == -1 then
                matchesProf = acctProfs[r.prof] ~= nil
            else
                matchesProf = (r.prof == profFilter)
            end

            if matchesProf then
                local rName, rIcon = Engine.RecipeDisplay(r)
                local scrollName, scrollIcon, scrollColored, scrollCard = Engine.ItemDisplay(r.recipeItem)

                -- Multi-token accurate search: checks recipe name, scroll clean name, product name, prof name, IDs
                local matchesSearch = true
                if searchTokens then
                    local prodName = ""
                    if r.product and r.product.id then
                        prodName = Engine.ItemDisplay(r.product.id) or ""
                    end
                    local scrollClean = scrollName and scrollName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or ""
                    local pName = r.profName or (WFC.DB and WFC.DB.Recipes and WFC.DB.Recipes.PROFESSION_NAMES[r.prof]) or ""
                    local haystack = (rName .. " " .. scrollClean .. " " .. prodName .. " " .. pName .. " " .. tostring(r.recipeItem or "") .. " " .. tostring(spellId)):lower()
                    for _, token in ipairs(searchTokens) do
                        if not haystack:find(token, 1, true) then
                            matchesSearch = false
                            break
                        end
                    end
                end

                if matchesSearch then
                    local learnRank = Engine.GetRecipeLearnRank(r)
                    local profAlts = acctProfs[r.prof] or WFC.Util.EMPTY

                    -- Check which alts have learned it, and which alt has highest skill in this profession
                    local learnedBy = {}
                    local bestAlt = profAlts[1]
                    for _, entry in ipairs(profAlts) do
                        if entry.char.recipes and entry.char.recipes[spellId] then
                            learnedBy[#learnedBy + 1] = entry
                        end
                    end
                    local isLearned = #learnedBy > 0

                    -- Check if we already own the scroll item in any alt's bags/bank/mail
                    local scrollOwnedCount = totals[r.recipeItem] or 0
                    local scrollHolders = byItem[r.recipeItem] or WFC.Util.EMPTY

                    local matchesState = true
                    if stateFilter == "learned" then
                        matchesState = isLearned
                    elseif stateFilter == "unlearned" then
                        matchesState = not isLearned
                    elseif stateFilter == "owned" then
                        matchesState = (scrollOwnedCount > 0 and not isLearned)
                    end

                    -- "At learned level" filter: only show recipes where your characters meet the required skill level
                    if matchesState and atLearnedLevel then
                        local curProf = WFC.Player and WFC.Player.professions and WFC.Player.professions[r.prof]
                        local curRank = curProf and curProf.rank or 0
                        local charSkill = curRank > 0 and curRank or (bestAlt and bestAlt.rank or 0)
                        if charSkill == 0 or learnRank > charSkill then
                            matchesState = false
                        end
                    end

                    if matchesState then
                        -- Source hint for the scroll
                        local sourceParts = {}
                        if scrollCard then
                            if scrollCard.vendors and #scrollCard.vendors > 0 then
                                local vNpc = WFC.DB:GetNpc(scrollCard.vendors[1])
                                sourceParts[#sourceParts + 1] = "Vendor: " .. ((vNpc and vNpc.name) or ("#" .. scrollCard.vendors[1]))
                                    .. (#scrollCard.vendors > 1 and (" (+" .. (#scrollCard.vendors - 1) .. ")") or "")
                            end
                            if scrollCard.dropNpcs and #scrollCard.dropNpcs > 0 then
                                local dNpc = WFC.DB:GetNpc(scrollCard.dropNpcs[1])
                                sourceParts[#sourceParts + 1] = "Drop: " .. ((dNpc and dNpc.name) or ("#" .. scrollCard.dropNpcs[1]))
                                    .. (#scrollCard.dropNpcs > 1 and (" (+" .. (#scrollCard.dropNpcs - 1) .. ")") or "")
                            end
                            if scrollCard.rewardOf and #scrollCard.rewardOf > 0 then
                                local qBrief = WFC.DB:GetQuestBrief(scrollCard.rewardOf[1])
                                sourceParts[#sourceParts + 1] = "Quest: " .. ((qBrief and qBrief.name) or ("#" .. scrollCard.rewardOf[1]))
                            end
                        end
                        if #sourceParts == 0 then
                            sourceParts[1] = "World drop / AH"
                        end

                        local holderNames = {}
                        for _, h in ipairs(scrollHolders) do
                            holderNames[#holderNames + 1] = Inventory.ColorizeName(h.char.shortName or h.char.name, h.char.class)
                        end

                        results[#results + 1] = {
                            spellId = spellId,
                            recipe = r,
                            name = rName,
                            icon = rIcon,
                            prof = r.prof,
                            profName = r.profName or WFC.DB.Recipes.PROFESSION_NAMES[r.prof] or "Profession",
                            learnRank = learnRank,
                            scrollId = r.recipeItem,
                            scrollName = scrollColored or scrollName,
                            scrollIcon = scrollIcon,
                            isLearned = isLearned,
                            learnedBy = learnedBy,
                            bestAlt = bestAlt,
                            scrollOwned = scrollOwnedCount,
                            scrollHolders = table.concat(holderNames, ", "),
                            sourceText = table.concat(sourceParts, " · "),
                        }
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b)
        if a.prof ~= b.prof then return a.prof < b.prof end
        -- Owned unlearned scrolls at the very top of their profession!
        local aOwn = (not a.isLearned and a.scrollOwned > 0)
        local bOwn = (not b.isLearned and b.scrollOwned > 0)
        if aOwn ~= bOwn then return aOwn end
        if a.learnRank ~= b.learnRank then return a.learnRank < b.learnRank end
        return a.name < b.name
    end)

    return results
end

---------------------------------------------------------------------------
-- TAB 3: Craftable Equippable Gear for Current Character's Class & Level
---------------------------------------------------------------------------
-- Armor subclass IDs (classId == 4):
--   0 = Miscellaneous (Rings, Necks, Trinkets, Shirts, Tabards, Held in Off-hand)
--   1 = Cloth, 2 = Leather, 3 = Mail, 4 = Plate, 6 = Shield
-- Weapon subclass IDs (classId == 2):
--   0 = 1H Axe, 1 = 2H Axe, 2 = Bow, 3 = Gun, 4 = 1H Mace, 5 = 2H Mace,
--   6 = Polearm, 7 = 1H Sword, 8 = 2H Sword, 10 = Staff, 13 = Fist,
--   15 = Dagger, 16 = Thrown, 18 = Crossbow, 19 = Wand, 20 = Fishing Pole

local CLASS_ARMOR = {
    WARRIOR = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    PALADIN = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    HUNTER  = { [0] = 1, [1] = 1, [2] = 1, [3] = 40 },
    SHAMAN  = { [0] = 1, [1] = 1, [2] = 1, [3] = 40, [6] = 1 },
    ROGUE   = { [0] = 1, [1] = 1, [2] = 1 },
    DRUID   = { [0] = 1, [1] = 1, [2] = 1 },
    MAGE    = { [0] = 1, [1] = 1 },
    WARLOCK = { [0] = 1, [1] = 1 },
    PRIEST  = { [0] = 1, [1] = 1 },
}

local CLASS_WEAPON = {
    WARRIOR = { [0]=1, [1]=1, [2]=1, [3]=1, [4]=1, [5]=1, [6]=20, [7]=1, [8]=1, [10]=1, [13]=1, [15]=1, [16]=1, [18]=1, [20]=1 },
    PALADIN = { [0]=1, [1]=1, [4]=1, [5]=1, [6]=20, [7]=1, [8]=1, [20]=1 },
    HUNTER  = { [0]=1, [1]=1, [2]=1, [3]=1, [6]=20, [7]=1, [8]=1, [10]=1, [13]=1, [15]=1, [16]=1, [18]=1, [20]=1 },
    SHAMAN  = { [0]=1, [1]=1, [4]=1, [5]=1, [10]=1, [13]=1, [15]=1, [20]=1 },
    ROGUE   = { [2]=1, [3]=1, [4]=1, [7]=1, [13]=1, [15]=1, [16]=1, [18]=1, [20]=1 },
    DRUID   = { [4]=1, [5]=1, [10]=1, [13]=1, [15]=1, [20]=1 },
    MAGE    = { [7]=1, [10]=1, [15]=1, [19]=1, [20]=1 },
    WARLOCK = { [7]=1, [10]=1, [15]=1, [19]=1, [20]=1 },
    PRIEST  = { [4]=1, [10]=1, [15]=1, [19]=1, [20]=1 },
}

local EQUIP_LOC_NAMES = {
    INVTYPE_HEAD           = "Head",
    INVTYPE_NECK           = "Neck",
    INVTYPE_SHOULDER       = "Shoulder",
    INVTYPE_BODY           = "Shirt",
    INVTYPE_CHEST          = "Chest",
    INVTYPE_ROBE           = "Chest",
    INVTYPE_WAIST          = "Waist",
    INVTYPE_LEGS           = "Legs",
    INVTYPE_FEET           = "Feet",
    INVTYPE_WRIST          = "Wrist",
    INVTYPE_HAND           = "Hands",
    INVTYPE_FINGER         = "Finger",
    INVTYPE_TRINKET        = "Trinket",
    INVTYPE_CLOAK          = "Back",
    INVTYPE_WEAPON         = "One-Hand",
    INVTYPE_SHIELD         = "Shield",
    INVTYPE_2HWEAPON       = "Two-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND  = "Off Hand",
    INVTYPE_HOLDABLE       = "Held In Off-hand",
    INVTYPE_RANGED         = "Ranged",
    INVTYPE_THROWN         = "Thrown",
    INVTYPE_RANGEDRIGHT    = "Ranged / Wand",
}

local NON_GEAR_EQUIP = {
    [""]                 = true,
    INVTYPE_NON_EQUIP    = true,
    INVTYPE_BAG          = true,
    INVTYPE_QUIVER       = true,
    INVTYPE_AMMO         = true,
    INVTYPE_TABARD       = true,
}

function Engine.CanPlayerEquip(classFile, playerLevel, classId, subClassId, equipLoc)
    if classId ~= 2 and classId ~= 4 then return false end
    if equipLoc and NON_GEAR_EQUIP[equipLoc] then return false end
    -- Cloaks are wearable by every class even though their item subClassId is Cloth (1)
    if equipLoc == "INVTYPE_CLOAK" then return true end
    -- If equipLoc hasn't arrived from client yet, exclude armor subClass 0 unless we know it's an equipLoc
    if not equipLoc and classId == 4 and (subClassId == 0 or subClassId == nil) then
        return false
    end

    if classId == 4 then
        local map = CLASS_ARMOR[classFile or ""]
        if not map then return true end
        local minLvl = map[subClassId or 0]
        return minLvl ~= nil and playerLevel >= minLvl
    elseif classId == 2 then
        local map = CLASS_WEAPON[classFile or ""]
        if not map then return true end
        local minLvl = map[subClassId or 0]
        return minLvl ~= nil and playerLevel >= minLvl
    end
    return false
end

function Engine:GetCraftableGear(opts)
    opts = opts or {}
    local onlyHaveMats = opts.onlyHaveMats == true
    local includeUnlearned = opts.includeUnlearned ~= false
    local statFilter = opts.statFilter or "all"
    local levelSpan = opts.levelSpan or 12
    local targetChar = opts.targetChar or "player"
    local search = opts.search and opts.search:lower():trim() or ""
    if search == "" then search = nil end

    local chars = Inventory:GetCharacters()
    local targetLevel = (WFC.Player and WFC.Player.level) or UnitLevel("player") or 1
    local targetClass = (WFC.Player and WFC.Player.classFile) or select(2, UnitClass("player")) or "WARRIOR"

    if targetChar ~= "player" and targetChar ~= "all" then
        for _, ch in ipairs(chars) do
            if ch.key == targetChar or ch.name == targetChar or ch.shortName == targetChar then
                targetLevel = ch.level or 1
                targetClass = ch.class or "WARRIOR"
                break
            end
        end
    end

    local minReqLevel = (levelSpan and levelSpan > 0) and math.max(1, targetLevel - levelSpan) or 1

    local allRecipes = (WFC.DB and WFC.DB:GetRecipes()) or {}
    local acctProfs = self:GetAccountProfessions()
    local totals = Inventory:GetItemIndex()

    local results = {}
    for spellId, r in pairs(allRecipes) do
        local productId = r.product and r.product.id
        if productId and r.prof then
            local rawName, icon, coloredName, card, client, equipLoc, classId, subClassId = Engine.ItemDisplay(productId)

            local canEquip = false
            if targetChar == "all" then
                for _, ch in ipairs(chars) do
                    local cClass = ch.class or "WARRIOR"
                    local cLevel = ch.level or 1
                    if Engine.CanPlayerEquip(cClass, cLevel, classId, subClassId, equipLoc) then
                        canEquip = true
                        break
                    end
                end
            else
                canEquip = Engine.CanPlayerEquip(targetClass, targetLevel, classId, subClassId, equipLoc)
            end

            if canEquip then
                local learnRank = Engine.GetRecipeLearnRank(r)
                local reqLevel = (client and client.minLevel and client.minLevel > 0 and client.minLevel)
                    or (card and card.reqLevel and card.reqLevel > 0 and card.reqLevel)
                    or math.max(1, math.floor(learnRank / 5))
                local ilvl = (client and client.ilvl) or (card and card.ilvl) or (reqLevel + 5)

                -- Check level window against target character (or account max 60 if "all")
                local maxLevelAllowed = (targetChar == "all") and 60 or targetLevel
                local minLevelAllowed = (targetChar == "all") and 1 or minReqLevel
                local maxReasonableSkill = maxLevelAllowed * 5 + 35

                if reqLevel <= maxLevelAllowed and reqLevel >= minLevelAllowed and learnRank <= maxReasonableSkill then
                    local stats, statSummary = Engine.GetItemStats(productId)
                    local statMatch = (statFilter == "all") or (stats[statFilter] and stats[statFilter] > 0)

                    if statMatch and (not search or rawName:lower():find(search, 1, true)) then
                        -- Check which of our alts can craft this recipe
                        local profAlts = acctProfs[r.prof] or WFC.Util.EMPTY
                        -- Bind on Pickup: the crafted item is soulbound to whoever makes it, so it
                        -- only counts if the viewed character can craft it themselves.
                        local bop = client and client.bindType == 1
                        if bop and targetChar ~= "all" then
                            local own = {}
                            for _, entry in ipairs(profAlts) do
                                local c = entry.char
                                if (targetChar == "player" and c.isCurrent)
                                    or c.key == targetChar or c.name == targetChar or c.shortName == targetChar then
                                    own[#own + 1] = entry
                                end
                            end
                            profAlts = own
                        end
                        local crafter, state
                        for _, entry in ipairs(profAlts) do
                            if Engine.CharKnowsRecipe(entry.char, r) then
                                crafter = entry
                                state = (entry.rank >= learnRank) and "known" or "known_low_skill"
                                break
                            end
                        end
                        if not crafter and includeUnlearned and #profAlts > 0 then
                            crafter = profAlts[1]
                            if r.recipeItem and not r.trainer then
                                state = (totals[r.recipeItem] or 0) > 0 and "unlearned_have_scroll" or "unlearned_scroll"
                            else
                                state = "unlearned_trainer"
                            end
                        end

                        if crafter and state then
                            -- Check materials across all characters
                            -- "Have Materials" only checks gatherable/farmed reagents, not items you have to buy
                            local maxCrafts = 999
                            local gatherableCount = 0
                            local reagentParts = {}
                            for _, reg in ipairs(r.reagents or {}) do
                                local isVendor = Engine.IsVendorReagent(reg.id)
                                local have = totals[reg.id] or 0
                                local need = reg.count or 1
                                local possible = math.floor(have / need)

                                if not isVendor then
                                    gatherableCount = gatherableCount + 1
                                    if possible < maxCrafts then maxCrafts = possible end
                                end

                                local regName = Engine.ItemDisplay(reg.id)
                                if isVendor then
                                    local col = have >= need and "|cff40ff40" or "|cffa0a0a0"
                                    local buyTag = have < need and " [Buy]" or ""
                                    reagentParts[#reagentParts + 1] = ("%s%d/%d|r %s%s"):format(col, have, need, regName, buyTag)
                                else
                                    local col = have >= need and "|cff40ff40" or "|cffff6060"
                                    reagentParts[#reagentParts + 1] = ("%s%d/%d|r %s"):format(col, have, need, regName)
                                end
                            end
                            if gatherableCount == 0 then
                                if maxCrafts == 999 then maxCrafts = 1 end
                            elseif #(r.reagents or {}) == 0 then
                                maxCrafts = 0
                            end

                            if not onlyHaveMats or maxCrafts >= 1 then
                                local slotLabel = (equipLoc and EQUIP_LOC_NAMES[equipLoc])
                                    or (classId == 2 and "Weapon" or "Armor")
                                results[#results + 1] = {
                                    spellId = spellId,
                                    productId = productId,
                                    recipe = r,
                                    name = rawName,
                                    coloredName = coloredName,
                                    icon = icon,
                                    slotLabel = slotLabel,
                                    equipLoc = equipLoc, -- for the Gear tab's slot view
                                    bop = bop or nil,    -- Bind on Pickup: only the crafter can wear it
                                    reqLevel = reqLevel,
                                    ilvl = ilvl,
                                    learnRank = learnRank,
                                    prof = r.prof,
                                    profName = r.profName or WFC.DB.Recipes.PROFESSION_NAMES[r.prof] or "Profession",
                                    crafter = crafter,
                                    state = state,
                                    maxCrafts = maxCrafts,
                                    stats = stats,
                                    statSummary = statSummary,
                                    reagentText = table.concat(reagentParts, " · "),
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b)
        local aCan = (a.maxCrafts >= 1 and a.state == "known")
        local bCan = (b.maxCrafts >= 1 and b.state == "known")
        if aCan ~= bCan then return aCan end
        if (a.maxCrafts >= 1) ~= (b.maxCrafts >= 1) then return a.maxCrafts >= 1 end
        if a.reqLevel ~= b.reqLevel then return a.reqLevel > b.reqLevel end
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        return a.name < b.name
    end)

    return results
end

---------------------------------------------------------------------------
-- TAB 4 & Banner: Multi-Character Skill-Up Helper ("Next best char to level")
---------------------------------------------------------------------------
local DIFF_WEIGHT = { orange = 1.0, yellow = 0.65, green = 0.25 }
local DIFF_ORDER  = { orange = 1, yellow = 2, green = 3 }

local itemCostCache = {}
function Engine.ItemCost(itemId)
    if not itemId then return 0 end
    local cached = itemCostCache[itemId]
    if cached then return cached end

    local cost = 0
    local guessed = false -- fallback prices aren't cached, so real prices win once they load
    local isVendor = Engine.IsVendorReagent(itemId)
    local ah, vendor = (WFC.DB and WFC.DB.GetPrice and WFC.DB:GetPrice(itemId))
    if not vendor and WFC.DB and WFC.DB.Items and WFC.DB.Items.Client then
        local cl = WFC.DB.Items:Client(itemId)
        vendor = cl and cl.sellPrice
    end

    if isVendor then
        if vendor and vendor > 0 then
            cost = vendor * 4
        elseif ah and ah > 0 then
            cost = ah
        else
            cost = 50 -- 50c fallback
            guessed = true
        end
    else
        if ah and ah > 0 then
            cost = ah
        elseif vendor and vendor > 0 then
            cost = vendor * 2
        else
            cost = 100 -- 1s fallback
            guessed = true
        end
    end

    if not guessed then itemCostCache[itemId] = cost end
    return cost
end

function Engine.RecipeCost(recipe)
    if not recipe or not recipe.reagents then return 0, 0, 0 end
    local totalMatCost = 0
    for _, reg in ipairs(recipe.reagents) do
        local unitCost = Engine.ItemCost(reg.id)
        totalMatCost = totalMatCost + unitCost * (reg.count or 1)
    end

    local productSell = 0
    if recipe.product and recipe.product.id then
        local pId = recipe.product.id
        local _, vendor = (WFC.DB and WFC.DB.GetPrice and WFC.DB:GetPrice(pId))
        if not vendor and WFC.DB and WFC.DB.Items and WFC.DB.Items.Client then
            local cl = WFC.DB.Items:Client(pId)
            vendor = cl and cl.sellPrice
        end
        if vendor and vendor > 0 then
            local yieldCount = recipe.product.min or 1
            productSell = vendor * yieldCount
        end
    end

    local netCost = math.max(0, totalMatCost - productSell)
    return netCost, totalMatCost, productSell
end

function Engine:GetSkillUpPlan(opts)
    opts = opts or {}
    local onlyHaveMats = opts.onlyHaveMats == true
    local targetChar = opts.targetChar or (Professions.settings and Professions.settings.skillUpCharFilter) or "all"
    local chars = Inventory:GetCharacters()
    local allRecipes = (WFC.DB and WFC.DB:GetRecipes()) or {}
    local baseTotals, byItem = Inventory:GetItemIndex()

    local plans = {}

    for _, char in ipairs(chars) do
        local matchesChar = (targetChar == "all")
            or (targetChar == "player" and char.isCurrent)
            or (char.key == targetChar or char.name == targetChar or char.shortName == targetChar)

        if matchesChar then
            for profId, pInfo in pairs(char.professions or {}) do
                local rank = pInfo.rank or 0
                local maxRank = pInfo.max or 75
                -- Only evaluate crafting professions (those that have recipes in DB)
                if rank < maxRank and PROF_ICON[profId] and profId ~= 182 and profId ~= 393 and profId ~= 356 then
                    -- Account material pool copy for simulation
                    local pool = {}
                    for k, v in pairs(baseTotals) do pool[k] = v end

                    local steps = {}
                    local estGain = 0
                    local totalPossibleGain = 0
                    local simRank = rank
                    local iter = 0
                    local maxIterations = 50

                    while simRank < maxRank and iter < maxIterations do
                        iter = iter + 1

                        local curFloor = math.floor(simRank)
                        local orangeYellowList = {}
                        local greenList = {}

                        for spellId, r in pairs(allRecipes) do
                            if r.prof == profId and #(r.reagents or {}) > 0 then
                                local learnRank = Engine.GetRecipeLearnRank(r)
                                if curFloor >= learnRank then
                                    local curDiff = WFC.DB.Recipes:Difficulty(spellId, curFloor)
                                    local greenRank = Engine.GetRecipeGreenRank(r)
                                    local yellowRank = Engine.GetRecipeYellowRank(r)
                                    local isOrangeOrYellow = (curDiff == "orange" or curDiff == "yellow")
                                    if greenRank and curFloor >= greenRank then
                                        isOrangeOrYellow = false
                                    end

                                    local isScroll = (r.recipeItem and r.recipeItem > 0 and not r.trainer and not r.auto)
                                    local knows = Engine.CharKnowsRecipe(char, r)
                                    local haveScroll = isScroll and ((baseTotals[r.recipeItem] or 0) > 0)

                                    -- When onlyHaveMats is checked, you can ONLY craft recipes you actually know (or have scroll in bags)
                                    local canConsider = true
                                    if onlyHaveMats then
                                        if not knows and not haveScroll then
                                            canConsider = false
                                        end
                                    end

                                    if canConsider and (curDiff == "orange" or curDiff == "yellow" or curDiff == "green") then
                                        local weight = DIFF_WEIGHT[curDiff] or (curDiff == "orange" and 1.0 or (curDiff == "yellow" and 0.65 or 0.25))

                                        local canCraft = 999
                                        local gatherableCount = 0
                                        for _, reg in ipairs(r.reagents) do
                                            local isVendor = Engine.IsVendorReagent(reg.id)
                                            if not isVendor then
                                                gatherableCount = gatherableCount + 1
                                                local m = math.floor((pool[reg.id] or 0) / (reg.count or 1))
                                                if m < canCraft then canCraft = m end
                                            end
                                        end
                                        if gatherableCount == 0 and canCraft == 999 then canCraft = 1 end

                                        if not onlyHaveMats or (canCraft > 0 and canCraft < 999) then
                                            local netCost, totalMatCost, productSell = Engine.RecipeCost(r)
                                            local costPerPoint = netCost / math.max(0.1, weight)

                                            local cand = {
                                                spellId = spellId,
                                                recipe = r,
                                                diff = curDiff,
                                                weight = weight,
                                                greenRank = greenRank,
                                                yellowRank = yellowRank,
                                                greyRank = Engine.GetRecipeGreyRank(r),
                                                learnRank = learnRank,
                                                netCost = netCost,
                                                totalMatCost = totalMatCost,
                                                productSell = productSell,
                                                costPerPoint = costPerPoint,
                                                canCraft = canCraft,
                                                knows = knows,
                                                isScroll = isScroll,
                                                haveScroll = haveScroll,
                                            }

                                            if isOrangeOrYellow then
                                                orangeYellowList[#orangeYellowList + 1] = cand
                                            elseif curDiff == "green" then
                                                greenList[#greenList + 1] = cand
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        -- Sort candidates: lowest costPerPoint first, prefer known, prefer have mats
                        local sortFn = function(a, b)
                            if a.costPerPoint ~= b.costPerPoint then
                                return a.costPerPoint < b.costPerPoint
                            end
                            if a.knows ~= b.knows then return a.knows end
                            local aHave = a.canCraft > 0
                            local bHave = b.canCraft > 0
                            if aHave ~= bHave then return aHave end
                            if DIFF_ORDER[a.diff] ~= DIFF_ORDER[b.diff] then
                                return DIFF_ORDER[a.diff] < DIFF_ORDER[b.diff]
                            end
                            return a.spellId < b.spellId
                        end

                        table.sort(orangeYellowList, sortFn)
                        table.sort(greenList, sortFn)

                        -- Strictly prioritize Orange and Yellow recipes over Green
                        local chosen = orangeYellowList[1] or greenList[1]
                        if not chosen then
                            break
                        end

                        -- Determine how many crafts to make:
                        -- For green recipes, cap at greyRank (when it turns grey and gives 0 skill)
                        -- For orange/yellow recipes, cap at greenRank (when it turns green)
                        local targetRank = maxRank
                        if chosen.diff == "green" then
                            if chosen.greyRank and chosen.greyRank > curFloor and chosen.greyRank < targetRank then
                                targetRank = chosen.greyRank
                            end
                        else
                            if chosen.greenRank and chosen.greenRank > curFloor and chosen.greenRank < targetRank then
                                targetRank = chosen.greenRank
                            end
                        end

                        -- Check if any cheaper recipe unlocks before targetRank (only when planning roadmap)
                        if not onlyHaveMats then
                            for _, other in pairs(allRecipes) do
                                if other.prof == profId and #(other.reagents or {}) > 0 then
                                    local lr = Engine.GetRecipeLearnRank(other)
                                    if lr > curFloor and lr < targetRank then
                                        local otherCost = Engine.RecipeCost(other)
                                        if otherCost < chosen.costPerPoint then
                                            targetRank = lr
                                        end
                                    end
                                end
                            end
                        end

                        if targetRank > maxRank then targetRank = maxRank end
                        if targetRank <= curFloor then targetRank = math.min(maxRank, curFloor + 1) end

                        local skillNeeded = math.max(0.1, targetRank - simRank)
                        local craftsNeeded = math.max(1, math.ceil(skillNeeded / chosen.weight))
                        local canMake = craftsNeeded
                        local readyCrafts = math.min(chosen.canCraft, canMake)
                        local needMats = false

                        if onlyHaveMats then
                            if chosen.canCraft <= 0 then
                                break
                            end
                            canMake = math.min(chosen.canCraft, craftsNeeded)
                            readyCrafts = canMake
                        else
                            needMats = (readyCrafts < canMake)
                        end

                        if canMake <= 0 then
                            break
                        end

                        -- Deduct reagents from pool
                        for _, reg in ipairs(chosen.recipe.reagents) do
                            if not Engine.IsVendorReagent(reg.id) then
                                local haveInPool = pool[reg.id] or 0
                                local needInPool = canMake * (reg.count or 1)
                                pool[reg.id] = math.max(0, haveInPool - needInPool)
                            end
                        end

                        local gain = math.min(skillNeeded, canMake * chosen.weight)
                        local readyGain = readyCrafts * chosen.weight
                        local startRank = math.floor(simRank)
                        simRank = simRank + gain
                        local endRank = math.floor(simRank + 0.5)

                        totalPossibleGain = totalPossibleGain + gain
                        estGain = estGain + readyGain

                        local r = chosen.recipe
                        local rName, rIcon = Engine.RecipeDisplay(r)
                        local regParts = {}
                        local mailFrom = {}
                        for _, reg in ipairs(r.reagents) do
                            local isVendor = Engine.IsVendorReagent(reg.id)
                            local regName = Engine.ItemDisplay(reg.id)
                            local perCraft = reg.count or 1
                            local neededTotal = canMake * perCraft
                            local haveTotal = baseTotals[reg.id] or 0
                            local eaStr = canMake > 1 and (" (" .. perCraft .. "/ea)") or ""
                            if isVendor then
                                regParts[#regParts + 1] = ("%dx %s [Buy]%s"):format(neededTotal, regName, eaStr)
                            else
                                local col = haveTotal >= neededTotal and "|cff40ff40" or "|cffff6060"
                                regParts[#regParts + 1] = ("%s%d/%d|r %s%s"):format(col, haveTotal, neededTotal, regName, eaStr)
                                if haveTotal > 0 then
                                    local ownHas = (char.counts and char.counts.total and char.counts.total[reg.id]) or 0
                                    if ownHas < neededTotal then
                                        for _, h in ipairs(byItem[reg.id] or {}) do
                                            if h.char.key ~= char.key then
                                                mailFrom[h.char.shortName or h.char.name] = true
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        local mailList = {}
                        for k in pairs(mailFrom) do mailList[#mailList + 1] = k end
                        table.sort(mailList)

                        local learnSource, learnItem, learnInBags
                        if not chosen.knows then
                            learnSource, learnItem, learnInBags = Engine.GetRecipeLearnInfo(r, baseTotals)
                        end

                        local lastStep = steps[#steps]
                        if lastStep and lastStep.spellId == chosen.spellId then
                            lastStep.crafts = lastStep.crafts + canMake
                            lastStep.readyCrafts = lastStep.readyCrafts + readyCrafts
                            lastStep.estGain = lastStep.estGain + gain
                            lastStep.readyGain = lastStep.readyGain + readyGain
                            lastStep.endRank = endRank
                            lastStep.totalCost = lastStep.totalCost + (chosen.netCost * canMake)
                            lastStep.needMats = (lastStep.readyCrafts < lastStep.crafts)
                            local updatedParts = {}
                            for _, reg in ipairs(r.reagents) do
                                local isVendor = Engine.IsVendorReagent(reg.id)
                                local regName = Engine.ItemDisplay(reg.id)
                                local perCraft = reg.count or 1
                                local neededTotal = lastStep.crafts * perCraft
                                local haveTotal = baseTotals[reg.id] or 0
                                local eaStr = lastStep.crafts > 1 and (" (" .. perCraft .. "/ea)") or ""
                                if isVendor then
                                    updatedParts[#updatedParts + 1] = ("%dx %s [Buy]%s"):format(neededTotal, regName, eaStr)
                                else
                                    local col = haveTotal >= neededTotal and "|cff40ff40" or "|cffff6060"
                                    updatedParts[#updatedParts + 1] = ("%s%d/%d|r %s%s"):format(col, haveTotal, neededTotal, regName, eaStr)
                                end
                            end
                            lastStep.reagentSummary = table.concat(updatedParts, ", ")
                        else
                            steps[#steps + 1] = {
                                spellId = chosen.spellId,
                                recipe = r,
                                name = rName,
                                icon = rIcon,
                                diff = chosen.diff,
                                startRank = startRank,
                                endRank = endRank,
                                greenRank = chosen.greenRank,
                                yellowRank = chosen.yellowRank,
                                crafts = canMake,
                                readyCrafts = readyCrafts,
                                estGain = gain,
                                readyGain = readyGain,
                                needMats = needMats,
                                unitCost = chosen.netCost,
                                totalCost = chosen.netCost * canMake,
                                costPerPoint = chosen.costPerPoint,
                                knows = chosen.knows,
                                learnSource = learnSource,
                                learnItem = learnItem,
                                learnInBags = learnInBags,
                                reagentSummary = table.concat(regParts, ", "),
                                mailFrom = (#mailList > 0) and table.concat(mailList, ", ") or nil,
                            }
                        end
                    end

                    local totalReagents = {}
                    local totalPlanCost = 0
                    local allMatsReady = true

                    for _, st in ipairs(steps) do
                        totalPlanCost = totalPlanCost + (st.totalCost or 0)
                        for _, reg in ipairs(st.recipe.reagents or {}) do
                            local rId = reg.id
                            local perCraft = reg.count or 1
                            local need = st.crafts * perCraft
                            if not totalReagents[rId] then
                                totalReagents[rId] = {
                                    id = rId,
                                    name = Engine.ItemDisplay(rId),
                                    needed = 0,
                                    have = baseTotals[rId] or 0,
                                    isVendor = Engine.IsVendorReagent(rId),
                                }
                            end
                            totalReagents[rId].needed = totalReagents[rId].needed + need
                        end
                    end

                    local gatherParts = {}
                    local vendorParts = {}
                    for _, tReg in pairs(totalReagents) do
                        if tReg.isVendor then
                            vendorParts[#vendorParts + 1] = ("%dx %s [Buy]"):format(tReg.needed, tReg.name)
                        else
                            local diff = tReg.needed - tReg.have
                            if diff > 0 then
                                allMatsReady = false
                                gatherParts[#gatherParts + 1] = ("|cffff6060%d/%d|r %s (|cffff6060need %d|r)"):format(
                                    tReg.have, tReg.needed, tReg.name, diff
                                )
                            else
                                gatherParts[#gatherParts + 1] = ("|cff40ff40%d/%d|r %s"):format(
                                    tReg.have, tReg.needed, tReg.name
                                )
                            end
                        end
                    end
                    table.sort(gatherParts)
                    table.sort(vendorParts)

                    local allParts = {}
                    for _, p in ipairs(gatherParts) do allParts[#allParts + 1] = p end
                    for _, p in ipairs(vendorParts) do allParts[#allParts + 1] = p end
                    local totalReagentsSummary = table.concat(allParts, " · ")

                    if not onlyHaveMats or estGain > 0 or (targetChar ~= "all") then
                        plans[#plans + 1] = {
                            char = char,
                            profId = profId,
                            profName = pInfo.name or WFC.DB.Recipes.PROFESSION_NAMES[profId] or ("Prof " .. profId),
                            profIcon = Engine.ProfIcon(profId),
                            rank = rank,
                            max = maxRank,
                            targetSkill = math.floor(simRank + 0.5),
                            estGain = math.floor(estGain + 0.5),
                            totalPossibleGain = math.floor(totalPossibleGain + 0.5),
                            totalCost = totalPlanCost,
                            totalReagentsSummary = totalReagentsSummary,
                            allMatsReady = allMatsReady,
                            steps = steps,
                        }
                    end
                end
            end
        end
    end

    local mode = opts.sortBy or (Professions.settings and Professions.settings.skillUpSort) or "current"
    table.sort(plans, function(a, b)
        if mode == "current" then
            if a.char.isCurrent ~= b.char.isCurrent then return a.char.isCurrent end
            if a.estGain ~= b.estGain then return a.estGain > b.estGain end
            return a.rank > b.rank
        elseif mode == "gain" then
            if a.estGain ~= b.estGain then return a.estGain > b.estGain end
            if a.char.isCurrent ~= b.char.isCurrent then return a.char.isCurrent end
            return a.rank > b.rank
        elseif mode == "name" then
            if a.char.name ~= b.char.name then return a.char.name < b.char.name end
            return a.profName < b.profName
        end
        if a.char.isCurrent ~= b.char.isCurrent then return a.char.isCurrent end
        return a.estGain > b.estGain
    end)

    return plans
end

---------------------------------------------------------------------------
-- TAB 2 (v2): Scrolls you own + recipes still to learn
---------------------------------------------------------------------------
--- Learn rank, and whether it's an estimate. The recipe data is { learn, ?, yellow, green, grey }
--- with learn = 1 for most recipes, so the real requirement isn't stored; WFC_Database estimates
--- it from the yellow threshold (r.learnRank). Fine Leather Boots: yellow 95, estimate 70, real 65.
function Engine.LearnRankSimple(r)
    local s = r and r.skill
    if not s then return 1, true end
    if s[1] and s[1] > 1 then return s[1], false end
    return r.learnRank or 1, true
end

--- Exact requirement from a recipe item's tooltip ("Requires Leatherworking (65)"), or nil.
local function scrollRequirement(itemId)
    for _, text in ipairs(tooltipLines("item:" .. itemId)) do
        if text:find("^Requires") and not text:find("^Requires Level") then
            local n = tonumber(text:match("%((%d+)%)"))
            if n and n > 0 then return n end
        end
    end
end

local RECIPE_PREFIXES = { "Pattern: ", "Plans: ", "Formula: ", "Schematic: ", "Recipe: ", "Manual: ", "Design: " }
local nameToSpell -- [lower recipe name] = spellId (built once)

local function spellForScroll(itemId, itemName)
    local Rec = WFC.DB and WFC.DB.Recipes
    local id = Rec and Rec.TaughtBy and Rec:TaughtBy(itemId)
    if id then return id end
    if not itemName then return nil end
    if not nameToSpell then
        nameToSpell = {}
        for spellId in pairs(WFC.DB:GetRecipes() or {}) do
            local n = Rec:Name(spellId)
            if type(n) == "string" then nameToSpell[n:lower()] = nameToSpell[n:lower()] or spellId end
        end
    end
    local base = itemName
    for _, p in ipairs(RECIPE_PREFIXES) do
        if base:sub(1, #p) == p then base = base:sub(#p + 1); break end
    end
    return nameToSpell[base:lower()]
end

local function itemNameAndClass(itemId)
    local classId
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, cls = pcall(C_Item.GetItemInfoInstant, itemId)
        if ok then classId = cls end
    end
    local client = WFC.DB and WFC.DB:GetItemClient(itemId)
    local card = WFC.DB and WFC.DB:GetItem(itemId)
    local name = (client and client.name) or (card and card.name)
    classId = classId or (client and client.classId) or (card and card.class)
    return name, classId
end

local function whereToLearn(r, profName)
    if r.recipeItem then return ("pattern: %s"):format((itemNameAndClass(r.recipeItem)) or ("item " .. r.recipeItem)) end
    if r.auto then return "learned automatically" end
    return ("%s trainer (not listed there? then it's a pattern: vendor, drop or AH)"):format(profName)
end

--- Returns owned, toLearn:
---   owned   = { { itemId, name, icon, count, holders, spellId, profId, profName, learn,
---                 verdict = "now"|"later"|"known"|"nobody"|"unknown", who, whoRank } }
---   toLearn = { { char, profId, profName, rank, max, list = { { spellId, name, learn, now, where, color } } } }
function Engine:GetScrollTab(opts)
    opts = opts or {}
    local window = opts.window or 25
    local profFilter = opts.profFilter or -1
    local search = opts.search and opts.search:lower():trim() or ""
    if search == "" then search = nil end
    local chars = Inventory:GetCharacters()
    local _, byItem = Inventory:GetItemIndex()
    local all = (WFC.DB and WFC.DB:GetRecipes()) or {}
    local NAMES = WFC.DB.Recipes.PROFESSION_NAMES

    local function profAllowed(profId)
        if profFilter == 0 then return true end
        if profFilter == -1 then
            for _, c in ipairs(chars) do if c.professions and c.professions[profId] then return true end end
            return false
        end
        return profFilter == profId
    end

    -- 1. Every recipe item held anywhere (bags, bank, mail, any character).
    local owned = {}
    for itemId, holders in pairs(byItem) do
        local name, classId = itemNameAndClass(itemId)
        if classId == 9 then
            local spellId = spellForScroll(itemId, name)
            local r = spellId and all[spellId]
            local profId = r and r.prof
            if not profId or profAllowed(profId) then
                local count, names = 0, {}
                for _, h in ipairs(holders) do
                    count = count + (h.total or 0)
                    names[#names + 1] = Inventory.ColorizeName(h.char.shortName or h.char.name, h.char.class)
                end
                local e = { itemId = itemId, name = name or ("item " .. itemId), count = count,
                    holders = table.concat(names, ", "), spellId = spellId, profId = profId,
                    profName = profId and NAMES[profId] or nil }
                e.icon = select(2, Engine.ItemDisplay(itemId))
                if not r then
                    e.verdict = "unknown"
                else
                    -- Owned scroll: its tooltip states the exact requirement; else the estimate.
                    local exact = scrollRequirement(itemId)
                    if exact then e.learn, e.est = exact, false else e.learn, e.est = Engine.LearnRankSimple(r) end
                    local bestNow, bestLater, anyProf, allKnow = nil, nil, false, true
                    for _, c in ipairs(chars) do
                        local p = c.professions and c.professions[profId]
                        if p then
                            anyProf = true
                            if not (c.recipes and c.recipes[spellId]) then
                                allKnow = false
                                local rank = p.rank or 0
                                if rank >= e.learn then
                                    if not bestNow or rank > bestNow.rank then bestNow = { char = c, rank = rank } end
                                elseif not bestLater or rank > bestLater.rank then
                                    bestLater = { char = c, rank = rank }
                                end
                            end
                        end
                    end
                    local pick = bestNow or bestLater
                    e.verdict = (not anyProf and "nobody") or (allKnow and "known") or (bestNow and "now") or "later"
                    if pick then e.who, e.whoRank = pick.char, pick.rank end
                end
                if not search or e.name:lower():find(search, 1, true) then owned[#owned + 1] = e end
            end
        end
    end
    local ORDER = { now = 1, later = 2, unknown = 3, known = 4, nobody = 5 }
    table.sort(owned, function(a, b)
        if ORDER[a.verdict] ~= ORDER[b.verdict] then return ORDER[a.verdict] < ORDER[b.verdict] end
        return a.name < b.name
    end)

    -- 2. Recipes still to learn, per character and profession (current rank .. rank + window).
    local toLearn = {}
    for _, c in ipairs(chars) do
        for profId, p in pairs(c.professions or {}) do
            if profAllowed(profId) and NAMES[profId] then
                local rank = p.rank or 0
                local maxRank = p.max or 300
                local list = {}
                for spellId, r in pairs(all) do
                    if r.prof == profId and not r.auto and not (c.recipes and c.recipes[spellId]) then
                        local learn, est = Engine.LearnRankSimple(r)
                        if learn <= math.min(rank + window, maxRank) then
                            local name = WFC.DB.Recipes:Name(spellId) or ("spell " .. spellId)
                            if not search or name:lower():find(search, 1, true) then
                                local color = WFC.DB.Recipes:Difficulty(spellId, math.max(rank, learn))
                                if color ~= "grey" then
                                    list[#list + 1] = { spellId = spellId, name = name, learn = learn, est = est,
                                        now = learn <= rank, where = whereToLearn(r, NAMES[profId]), color = color }
                                end
                            end
                        end
                    end
                end
                table.sort(list, function(a, b)
                    if a.now ~= b.now then return a.now end
                    if a.learn ~= b.learn then return a.learn < b.learn end
                    return a.name < b.name
                end)
                if #list > 0 then
                    toLearn[#toLearn + 1] = { char = c, profId = profId, profName = NAMES[profId], rank = rank, max = maxRank, list = list }
                end
            end
        end
    end
    table.sort(toLearn, function(a, b)
        if a.char.isCurrent ~= b.char.isCurrent then return a.char.isCurrent end
        if a.char.name ~= b.char.name then return (a.char.name or "") < (b.char.name or "") end
        return a.profName < b.profName
    end)
    return owned, toLearn
end
