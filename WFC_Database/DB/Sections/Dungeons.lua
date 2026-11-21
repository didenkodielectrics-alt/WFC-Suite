local _, ns = ...
local WFC = ns.WFC

-- Dungeon details for the Dungeons tab and the map legend (an Atlas-style view built from
-- QuestieDB): level range, bosses, the uiMap of the dungeon itself, and its entrances.
-- Built from the npcsByArea / questsByDungeon indexes, so nil, "pending" until they exist.

local Util = WFC.Util

local Dungeons = WFC.DB:NewSection("Dungeons")

local details = {}

function Dungeons:Invalidate()
    details = {}
end

local function hostile(card)
    return card.aggro.A or card.aggro.H or not card.friendly
end

--- { id, name, isNew, map (dungeon uiMap or nil), entrances, minLevel, maxLevel,
---   bosses = { npc cards, by level }, mobs (count) } or nil, "pending" / nil, "unknown".
--- The level range spans its hostile mobs and its quests.
function Dungeons:Details(dungeonId)
    local d = details[dungeonId]
    if d then return d end
    local DB = WFC.DB
    local card = DB.Zones:GetDungeon(dungeonId)
    if not card then return nil, "unknown" end
    local byArea = DB.Indexes:Get("npcsByArea")
    local quests = DB.Indexes:Get("questsByDungeon")
    if not (byArea and quests) then return nil, "pending" end

    local areas = { dungeonId }
    for _, a in ipairs(card.altAreas or {}) do areas[#areas + 1] = a end
    local seen, bosses, mobs = {}, {}, 0
    local minLevel, maxLevel
    local function widen(lo, hi)
        if lo and lo > 0 then minLevel = math.min(minLevel or lo, lo) end
        if hi and hi > 0 then maxLevel = math.max(maxLevel or hi, hi) end
    end
    for _, area in ipairs(areas) do
        for _, npcId in ipairs(byArea[area] or Util.EMPTY) do
            if not seen[npcId] then
                seen[npcId] = true
                local npc = DB:GetNpc(npcId)
                if npc and hostile(npc) then
                    mobs = mobs + 1
                    widen(npc.minLevel, npc.maxLevel)
                    if npc.rank == "boss" then bosses[#bosses + 1] = npc end
                end
            end
        end
    end
    for _, questId in ipairs(quests[dungeonId] or Util.EMPTY) do
        local brief = DB:GetQuestBrief(questId)
        if brief and brief.level and brief.level > 0 then widen(nil, brief.level) end
    end
    table.sort(bosses, function(a, b)
        if (a.maxLevel or 0) ~= (b.maxLevel or 0) then return (a.maxLevel or 0) < (b.maxLevel or 0) end
        return (a.name or "") < (b.name or "")
    end)
    -- Only a real dungeon map counts: AreaToUiMap walks up to the parent zone (the Deadmines
    -- would give Westfall), and Forever has no dungeon maps at all.
    local map = DB.Zones:AreaToUiMap(dungeonId)
    if not WFC.Compat.IsDungeonMap(map) then map = nil end
    d = {
        id = dungeonId, name = card.name, isNew = card.isNew, entrances = card.entrances,
        map = map, minLevel = minLevel, maxLevel = maxLevel,
        bosses = bosses, mobs = mobs, questCount = #(quests[dungeonId] or Util.EMPTY),
    }
    details[dungeonId] = d
    return d
end

--- Dungeon whose own dungeon map is `uiMapId` (for the world-map legend), or nil.
function Dungeons:ForMap(uiMapId)
    if not WFC.Compat.IsDungeonMap(uiMapId) then return nil end
    for _, card in ipairs(WFC.DB.Zones:GetDungeons()) do
        if WFC.DB.Zones:AreaToUiMap(card.id) == uiMapId then return card.id end
    end
    local area = WFC.DB.Zones:UiMapToArea(uiMapId)
    return area and WFC.DB.Zones:DungeonForArea(area) or nil
end

WFC:On("WFC_INDEX_READY", function(_, name)
    if name == "npcsByArea" or name == "questsByDungeon" then details = {} end
end)
