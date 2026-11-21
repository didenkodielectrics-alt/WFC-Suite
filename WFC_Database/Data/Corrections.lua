local _, ns = ...

-- Hand-edited fixes applied on top of WFC's normalized cards (not on QuestieDB itself).
-- Each entry is merged field-by-field into the card when it is built:
--   quest  = { [questId] = { level = 25, dungeon = 1581 } },
--   item   = { [itemId]  = { ... } },
--   npc    = { [npcId]   = { minLevel = 20, maxLevel = 21 } },
--   object = { [objectId] = { ... } },
ns.Data.Corrections = {
    quest = {},
    item = {},
    npc = {},
    object = {},
}
