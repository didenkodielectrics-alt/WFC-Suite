local _, ns = ...

-- Boats, zeppelins and the Deeprun Tram (plan.md §5.3). Hand-authored.
-- Coordinates are Classic Era map coordinates (0-100) and pass through
-- LibQuestieDB.EraToForeverByUiMapId at load time. They are APPROXIMATE (from memory of the
-- Era maps) until checked in game: stand on each dock and run /wfc travel here, then fix the line.
-- Forever's new regions (Hyjal, Riverglades, Shen'dralas, Zephras Isle, Darkspear Islands)
-- get their connections once mapped in game (/wfc travel addnode + link, see Authoring.lua).
--
-- { id, mode, faction ("A"|"H"|"B"), crossing seconds, departure every N seconds,
--   { uiMapID, x, y, "dock name" }, { uiMapID, x, y, "dock name" } }   -- runs both ways

ns.Data = ns.Data or {}
ns.Data.Transports = {
    -- Boats
    { "menethil-theramore", "boat", "B", 110, 330, { 1437, 5.0, 63.5, "Menethil Harbor" }, { 1445, 71.5, 56.3, "Theramore" } },
    { "menethil-auberdine", "boat", "B", 110, 330, { 1437, 4.6, 57.1, "Menethil Harbor" }, { 1439, 32.4, 43.8, "Auberdine" } },
    { "auberdine-ruttheran", "boat", "B", 70, 240, { 1439, 33.2, 40.2, "Auberdine" }, { 1438, 54.9, 96.8, "Rut'theran Village" } },
    { "bootybay-ratchet", "boat", "B", 110, 330, { 1434, 25.8, 73.1, "Booty Bay" }, { 1413, 63.7, 38.6, "Ratchet" } },
    -- Zeppelins
    { "orgrimmar-undercity", "zeppelin", "H", 120, 330, { 1411, 50.8, 13.8, "Orgrimmar" }, { 1420, 60.7, 58.8, "Undercity" } },
    { "orgrimmar-gromgol", "zeppelin", "H", 120, 330, { 1411, 50.6, 12.6, "Orgrimmar" }, { 1434, 31.6, 29.2, "Grom'gol" } },
    { "undercity-gromgol", "zeppelin", "H", 120, 330, { 1420, 61.9, 59.1, "Undercity" }, { 1434, 31.4, 30.2, "Grom'gol" } },
    -- Deeprun Tram (the instance itself is skipped: one edge between the two entrances)
    { "deeprun-tram", "tram", "A", 70, 120, { 1453, 64.9, 31.0, "Stormwind" }, { 1455, 76.6, 51.1, "Ironforge" } },
}
