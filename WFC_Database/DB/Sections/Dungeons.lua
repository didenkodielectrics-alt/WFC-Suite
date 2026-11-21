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

-- Recommended level ranges, by dungeon area id. They win over the range computed from the mobs
-- and quests inside (which runs too wide: trash, critters, follow-up quests).
local LEVELS = {
    -- Classic dungeons
    [2437] = { 13, 18 },  -- Ragefire Chasm
    [718] = { 17, 24 },   -- Wailing Caverns
    [1581] = { 17, 26 },  -- The Deadmines
    [209] = { 22, 30 },   -- Shadowfang Keep
    [719] = { 24, 32 },   -- Blackfathom Deeps
    [717] = { 24, 32 },   -- The Stockade
    [721] = { 29, 38 },   -- Gnomeregan
    [491] = { 29, 38 },   -- Razorfen Kraul
    [796] = { 28, 45 },   -- Scarlet Monastery (Graveyard 28-38, Library 29-39, Armory 32-42, Cathedral 35-45)
    [722] = { 37, 46 },   -- Razorfen Downs
    [1337] = { 41, 51 },  -- Uldaman
    [1176] = { 44, 54 },  -- Zul'Farrak
    [2100] = { 46, 55 },  -- Maraudon
    [1477] = { 50, 60 },  -- The Temple of Atal'Hakkar
    [1584] = { 52, 60 },  -- Blackrock Depths
    [1583] = { 55, 60 },  -- Blackrock Spire (Lower 55-60, Upper 58-60)
    [2557] = { 55, 60 },  -- Dire Maul
    [2057] = { 58, 60 },  -- Scholomance
    [2017] = { 58, 60 },  -- Stratholme
    -- Classic raids
    [2717] = { 60, 60 }, [2159] = { 60, 60 }, [1977] = { 60, 60 }, [2677] = { 60, 60 },
    [3429] = { 60, 60 }, [3428] = { 60, 60 }, [3456] = { 60, 60 },
    -- Battlegrounds
    [3277] = { 10, 60 },  -- Warsong Gulch
    [3358] = { 20, 60 },  -- Arathi Basin
    [2597] = { 51, 60 },  -- Alterac Valley
    -- The Burning Crusade
    [3562] = { 60, 62 }, [3713] = { 61, 63 }, [3717] = { 62, 64 }, [3716] = { 63, 65 }, [3792] = { 64, 66 },
    [3790] = { 65, 67 }, [2367] = { 66, 68 }, [3791] = { 67, 69 }, [3715] = { 70, 70 }, [3789] = { 70, 70 },
    [3714] = { 70, 70 }, [2366] = { 70, 70 }, [3849] = { 70, 70 }, [3847] = { 70, 70 }, [3848] = { 70, 70 },
    [4131] = { 70, 70 },
    [3457] = { 70, 70 }, [3923] = { 70, 70 }, [3836] = { 70, 70 }, [3607] = { 70, 70 }, [3845] = { 70, 70 },
    [3606] = { 70, 70 }, [3959] = { 70, 70 }, [3805] = { 70, 70 }, [4075] = { 70, 70 },
    -- Wrath of the Lich King
    [206] = { 70, 72 }, [4265] = { 71, 73 }, [4196] = { 74, 76 }, [4264] = { 77, 79 },
    [1196] = { 80, 80 }, [4228] = { 80, 80 }, [4100] = { 80, 80 },
}
local NO_RANGE = { [2257] = true, [2917] = true, [2918] = true } -- Deeprun Tram, the PvP halls

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
    local fixed = LEVELS[dungeonId]
    if fixed then
        minLevel, maxLevel = fixed[1], fixed[2]
    elseif NO_RANGE[dungeonId] then
        minLevel, maxLevel = nil, nil
    end
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
