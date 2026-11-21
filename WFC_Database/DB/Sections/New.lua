local _, ns = ...
local WFC = ns.WFC

-- The "new!" rule (plan.md §2.4). Cards call New:Evaluate while they are built,
-- so IsNew is a field read afterwards. New:IsNew(kind, id) is the public entry.
--
--   1. Data/NewOverrides[kind][id]       (true / false)
--   2. the record's area is a new Forever region
--   3. the id is not in the Classic Era snapshot (Data/EraIds)
--
-- Items/NPCs/objects use rule 3 only when QuestieDB knows the entity (its Era
-- snapshot only covers quest-relevant entities, so "unknown" != "new").

local Data = ns.Data
local Util = WFC.Util

local New = WFC.DB:NewSection("New")

local overrides = Data.NewOverrides
local eraIds = Data.EraIds or {}

--- kind: "quest" | "item" | "npc" | "object" | "recipe"; area: AreaID or nil;
--- known: whether QuestieDB has the entity (rule 3 needs it for non-quests).
function New:Evaluate(kind, id, area, known)
    local o = overrides[kind] and overrides[kind][id]
    if o ~= nil then return o end
    if area and WFC.DB.Zones:IsNewArea(area) then return true end
    local era = eraIds[kind]
    if era and (known or kind == "quest") then
        return not Util.InRanges(era, id)
    end
    return false
end

--- Public entry for every addon. kind adds "zone" and "dungeon".
function New:IsNew(kind, id)
    if not id then return false end
    local DB = WFC.DB
    if kind == "quest" then
        local brief = DB.Quests:Brief(id)
        return brief ~= nil and brief.isNew
    elseif kind == "item" then
        return DB.Items:Card(id).isNew
    elseif kind == "npc" then
        local card = DB.Npcs:Card(id)
        return card ~= nil and card.isNew
    elseif kind == "object" then
        local card = DB.Objects:Card(id)
        return card ~= nil and card.isNew
    elseif kind == "recipe" then
        local recipe = DB.Recipes:Get(id)
        return recipe ~= nil and recipe.isNew == true
    elseif kind == "zone" then
        return DB.Zones:IsNewArea(id)
    elseif kind == "dungeon" then
        return DB.Zones:IsNewDungeon(id)
    end
    return false
end

--- Background audit: quests whose new! verdict disagrees with the ID hint.
--- onDone(list) receives { {questId, isNew}, ... }.
function New:Audit(onDone)
    local Q = WFC.DB.Source.Q
    WFC.Jobs:Add("new-audit", function()
        local hint = Data.NEW_QUEST_ID_HINT
        local mismatches = {}
        local ids = Q.GetAllIds()
        for i = 1, #ids do
            local id = ids[i]
            local brief = WFC.DB.Quests:Brief(id)
            if brief and brief.isNew ~= (id >= hint) then
                mismatches[#mismatches + 1] = { id, brief.isNew }
            end
            WFC.Jobs:Checkpoint()
        end
        return mismatches
    end, function(ok, result)
        if ok and onDone then onDone(result) end
    end)
end
