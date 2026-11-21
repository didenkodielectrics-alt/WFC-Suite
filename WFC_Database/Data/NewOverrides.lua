local _, ns = ...

-- Hand-edited inputs for the "new!" rule (plan.md §2.4):
--   1. NewOverrides[kind][id]  (true = force new!, false = force NOT new)
--   2. record lies in a Forever-new region or dungeon
--   3. id is not in the Classic Era snapshot (Data/EraIds.lua)

ns.Data.NewOverrides = {
    quest = {},
    item = {},
    npc = {},
    object = {},
    recipe = {},
    zone = {},
    dungeon = {},
}

ns.Data.NewRegions = {
    -- AreaIDs of the new Forever regions (and anything parented to them).
    areas = {
        [616] = true,   -- Mount Hyjal (uiMap 2482)
        [16591] = true, -- Riverglades (uiMap 2548)
        [16593] = true, -- Zephras Isle (uiMap 2521, 2665)
        [16606] = true, -- Darkspear Islands (uiMap 2524)
        [16651] = true, -- Shen'dralas (uiMap 2652)
    },
    uiMaps = {
        [2482] = true, [2548] = true, [2521] = true, [2665] = true, [2524] = true, [2652] = true,
    },
    -- AreaIDs added after Era sit at 16000+ (e.g. 16544 City of Dalaran, 16732 Excavation Site: Wetlands).
    firstNewAreaId = 16000,
}

-- Forever dungeons (dungeon AreaIDs). Fill in the rest of the nine at launch.
ns.Data.NewDungeons = {
    [16544] = true, -- City of Dalaran
    [16732] = true, -- Excavation Site: Wetlands
}

-- Review hint only (/wfc db newaudit): beta's new quests had IDs in the 97000-98000s.
ns.Data.NEW_QUEST_ID_HINT = 90000
