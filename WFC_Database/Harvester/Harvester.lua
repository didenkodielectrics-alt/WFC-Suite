local _, ns = ...
local WFC = ns.WFC

-- Harvester: records facts QuestieDB lacks (mostly new Forever content) while you play.
-- Runs ONLY out of combat and outside instances (CoreRules R4), and guards every GUID
-- with WFC.Safe. Data goes to WFC_DB_Global.harvest; `/wfc harvest flush` turns it
-- into an export string because SavedVariables may not survive a cold start (R8).
--
-- harvest = {
--   loot        = { [itemId] = { [npcId] = count } },
--   corpses     = { [npcId] = lootedCorpses },
--   vendors     = { [npcId] = { itemIds } },
--   recipes     = { [spellId] = { prof, profName, name, product, reagents, difficulty } },
--   questGivers = { [questId] = { kind, id, map, x, y } },
--   questEnders = { [questId] = { kind, id, map, x, y } },
-- }

local Compat = WFC.Compat
local Safe = WFC.Safe

local Harvester = {}
WFC.Harvester = Harvester

local lootedGuids = {} -- this session; avoids double-counting a re-opened corpse

local function enabled()
    local g = WFC_DB_Global
    return g and g.settings.harvest and not InCombatLockdown() and not IsInInstance()
end

local function store()
    return WFC_DB_Global.harvest
end

--- "Creature-0-...-<npcId>-<spawnUid>" -> "npc", npcId ; "GameObject-..." -> "object", id
local function parseGuid(guid)
    guid = Safe(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if not id then return nil end
    if unitType == "Creature" or unitType == "Vehicle" then return "npc", id end
    if unitType == "GameObject" then return "object", id end
end

local function itemIdFromLink(link)
    link = Safe(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function here()
    local map, x, y = Compat.GetPlayerMapPosition()
    return map, x, y
end

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------
local function onLoot()
    if not enabled() or not GetNumLootItems then return end
    local h = store()
    local corpsesSeen = {}
    local touchedItems
    for slot = 1, GetNumLootItems() do
        local itemId = itemIdFromLink(GetLootSlotLink(slot))
        if itemId then
            local sources = { GetLootSourceInfo(slot) }
            for i = 1, #sources, 2 do
                local guid, qty = sources[i], sources[i + 1]
                local kind, npcId = parseGuid(guid)
                if kind == "npc" then
                    local safeGuid = Safe(guid)
                    if safeGuid and not lootedGuids[safeGuid] then
                        lootedGuids[safeGuid] = true
                        corpsesSeen[npcId] = (corpsesSeen[npcId] or 0) + 1
                        local perItem = h.loot[itemId]
                        if not perItem then
                            perItem = {}
                            h.loot[itemId] = perItem
                        end
                        perItem[npcId] = (perItem[npcId] or 0) + (tonumber(qty) or 1)
                        touchedItems = touchedItems or {}
                        touchedItems[itemId] = true
                    end
                end
            end
        end
    end
    local anyCorpse = false
    for npcId, n in pairs(corpsesSeen) do
        anyCorpse = true
        h.corpses[npcId] = (h.corpses[npcId] or 0) + n
        WFC:Log("DEBUG", "harvest", ("looted npc %d (%d corpses total)"):format(npcId, h.corpses[npcId]))
    end
    if anyCorpse or touchedItems then
        WFC:Fire("WFC_HARVEST_LOOT", touchedItems)
    end
end

---------------------------------------------------------------------------
-- Vendors
---------------------------------------------------------------------------
local function onMerchant()
    if not enabled() or not GetMerchantNumItems then return end
    local kind, npcId = parseGuid(UnitGUID("npc"))
    if kind ~= "npc" then return end
    local items = {}
    for i = 1, GetMerchantNumItems() do
        local itemId = GetMerchantItemID and GetMerchantItemID(i)
        if itemId then items[#items + 1] = itemId end
    end
    store().vendors[npcId] = items
    WFC:Log("DEBUG", "harvest", ("vendor %d sells %d items"):format(npcId, #items))
end

---------------------------------------------------------------------------
-- Recipes (profession window)
---------------------------------------------------------------------------
local DIFFICULTY = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }

local function scanRecipes()
    local TS = C_TradeSkillUI
    if not (enabled() and TS and TS.GetAllRecipeIDs and TS.GetRecipeInfo) then return end
    local prof = TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo()
    local profId = prof and (prof.professionID or prof.parentProfessionID)
    local profName = prof and prof.professionName
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local recipes = store().recipes
    local known = {}
    local ids = TS.GetAllRecipeIDs() or {}
    -- Forever's window reports professionID 0 (and no name) for some professions, e.g.
    -- Leatherworking and Tailoring. Recover the skill line another way, never store 0.
    local NAMES = WFC.DB.Recipes.PROFESSION_NAMES or {}
    if not (type(profId) == "number" and NAMES[profId]) then
        profId = nil
        if TS.GetTradeSkillLineForRecipe and ids[1] then
            local ok, lineId, lineName, parentId = pcall(TS.GetTradeSkillLineForRecipe, ids[1])
            if ok then
                profId = (NAMES[parentId or -1] and parentId) or (NAMES[lineId or -1] and lineId) or nil
                profName = profName or lineName
            end
        end
        if not profId and profName then
            for id, name in pairs(NAMES) do if name == profName then profId = id end end
        end
        if not profId then -- majority vote from the shipped recipe data
            local votes, best, bestN = {}, nil, 0
            for i = 1, math.min(#ids, 60) do
                local seed = ns.Data.Recipes and ns.Data.Recipes[ids[i]]
                if seed and seed.prof then
                    votes[seed.prof] = (votes[seed.prof] or 0) + 1
                    if votes[seed.prof] > bestN then best, bestN = seed.prof, votes[seed.prof] end
                end
            end
            profId = best
        end
        profName = profName or (profId and NAMES[profId]) or nil
    end
    for i = 1, #ids do
        local recipeId = ids[i]
        local info = TS.GetRecipeInfo(recipeId)
        if info then
            local entry = recipes[recipeId] or {}
            entry.prof, entry.profName, entry.name = profId, profName, info.name
            entry.difficulty = DIFFICULTY[info.relativeDifficulty]
            local schematic = TS.GetRecipeSchematic and TS.GetRecipeSchematic(recipeId, false)
            if schematic then
                if schematic.outputItemID then
                    entry.product = { schematic.outputItemID, schematic.quantityMin, schematic.quantityMax }
                end
                local reagents = {}
                for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                    local r = slot.reagents and slot.reagents[1]
                    if r and r.itemID and (basic == nil or slot.reagentType == basic) then
                        reagents[#reagents + 1] = { r.itemID, slot.quantityRequired or 1 }
                    end
                end
                entry.reagents = reagents
            end
            recipes[recipeId] = entry
            if info.learned then known[#known + 1] = recipeId end
        end
    end
    WFC.DB.Recipes:RecordKnown(known)
    local unknown = 0
    for i = 1, #ids do
        if not (ns.Data.Recipes and ns.Data.Recipes[ids[i]]) then unknown = unknown + 1 end
    end
    WFC:Log(unknown > 0 and "WARN" or "INFO", "harvest", ("%s: %d recipes scanned, %d known, %d missing from Data/Recipes.lua")
        :format(tostring(profName), #ids, #known, unknown))
    WFC:Fire("WFC_HARVEST_RECIPES")
end

local recipeTimer
local function onTradeSkill()
    if recipeTimer then recipeTimer:Cancel() end
    recipeTimer = C_Timer.NewTimer(1, function()
        recipeTimer = nil
        WFC:RunOutOfCombat("harvest:recipes", scanRecipes)
    end)
end

---------------------------------------------------------------------------
-- Quest givers / enders
---------------------------------------------------------------------------
local function recordQuestNpc(field)
    if not enabled() then return end
    local questId = GetQuestID and GetQuestID()
    if not questId or questId == 0 then return end
    local kind, id = parseGuid(UnitGUID("questnpc") or UnitGUID("npc"))
    if not kind then return end
    local map, x, y = here()
    store()[field][questId] = { kind = kind, id = id, map = map, x = x, y = y }
    local known = WFC.DB.Quests:Brief(questId) ~= nil
    WFC:Log(known and "DEBUG" or "WARN", "harvest", ("%s quest %d at %s %d%s"):format(
        field == "questGivers" and "giver of" or "ender of", questId, kind, id,
        known and "" or " - quest missing from QuestieDB (new content?)"))
end

WFC:RegisterEvent("LOOT_OPENED", onLoot)
WFC:RegisterEvent("MERCHANT_SHOW", onMerchant)
WFC:RegisterEvent("TRADE_SKILL_SHOW", onTradeSkill)
WFC:RegisterEvent("TRADE_SKILL_LIST_UPDATE", onTradeSkill)
WFC:RegisterEvent("QUEST_DETAIL", function() recordQuestNpc("questGivers") end)
WFC:RegisterEvent("QUEST_COMPLETE", function() recordQuestNpc("questEnders") end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
function Harvester:Stats()
    local h = store()
    local Count = WFC.Util.Count
    return {
        enabled = WFC_DB_Global.settings.harvest,
        lootItems = Count(h.loot), vendors = Count(h.vendors), recipes = Count(h.recipes),
        questGivers = Count(h.questGivers), questEnders = Count(h.questEnders),
    }
end

function Harvester:ExportString()
    return "WFCH1:" .. WFC.Serialize.Encode(store())
end

function Harvester:Wipe()
    local h = store()
    for k in pairs(h) do h[k] = {} end
    WFC:Fire("WFC_HARVEST_RECIPES")
    WFC:Fire("WFC_HARVEST_LOOT")
end
