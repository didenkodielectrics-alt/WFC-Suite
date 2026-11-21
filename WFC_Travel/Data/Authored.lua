local _, ns = ...

-- Nodes and links recorded in game with /wfc travel addnode / link, then pasted here from
-- /wfc travel exportgraph so they ship with the addon (SavedVariables can be lost, R8).
-- Positions are Forever map coordinates (0-1). Use this for Forever's new regions
-- (Hyjal, Riverglades, Shen'dralas, Zephras Isle, Darkspear Islands) once their boats,
-- portals and paths are known.
--
-- nodes = { ["Name"] = { map = uiMapID, x = 0.5, y = 0.5, kind = "dock", faction = "B", isNew = true } }
-- links = { { a = "Name", b = "Other", mode = "boat"|"zeppelin"|"tram"|"portal", seconds = 90, wait = 120, oneWay = false } }

ns.Data = ns.Data or {}
ns.Data.Authored = {
    nodes = {},
    links = {},
}
