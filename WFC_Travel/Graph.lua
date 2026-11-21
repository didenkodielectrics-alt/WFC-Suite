local _, ns = ...
local WFC = WFC

-- Builds the Router's graph (plan.md §5.2/§5.3) from:
--   Data/Taxi.lua        flight masters (world coordinates) and direct flights (generated)
--   Data/Transports.lua  boats, zeppelins, tram (hand-authored map coordinates)
--   authored nodes/links recorded in game with /wfc travel addnode / link (Authoring.lua)
-- and turns map positions into Router points (continent frame in world yards, or a
-- per-map frame for detached islands).

local Travel = ns.Travel
local Compat, DB = WFC.Compat, WFC.DB

local Graph = {}
ns.Graph = Graph

local ISLAND_YARDS = 1000 -- assumed size of a detached island map when the client can't say

--- Zone map ID (uiMapID) of any point, resolving from coordinates if missing.
function Graph.GetZone(p)
    if not p then return nil end
    if p.map and type(p.map) == "number" then return p.map end
    if type(p.c) == "string" then
        local map = tonumber(p.c:match("^map:(%d+)"))
        if map then p.map = map return map end
    end
    if type(p.c) == "number" and p.x and p.y and Compat and Compat.WorldToZone then
        local map = Compat.WorldToZone(p.c, p.x, p.y)
        if map then p.map = map return map end
    end
    return p.map
end

--- Router point for a map position (x, y in 0-1). Islands get their own frame "map:<id>".
function Graph.Point(map, x, y, name)
    local c, wx, wy = Compat.MapToWorld(map, x, y)
    if c then return { c = c, x = wx, y = wy, map = map, mx = x, my = y, name = name } end
    local w, h = Compat.GetMapWorldSize(map)
    return { c = "map:" .. map, x = x * (w or ISLAND_YARDS), y = y * (h or ISLAND_YARDS), map = map, mx = x, my = y, name = name }
end

--- Accepts a Router point, a Questing/Scorer point ({c, x, y, map, mx, my}) or {map, x, y}.
function Graph.Normalize(p)
    if not p then return nil end
    if p.c ~= nil then
        if not p.map then Graph.GetZone(p) end
        return p
    end
    if p.map and p.mx then return Graph.Point(p.map, p.mx, p.my) end
    if p.map and p.x and p.x <= 1 then return Graph.Point(p.map, p.x, p.y) end
    return nil
end

local function shortName(name)
    return (name:match("^([^,]+)")) or name
end

local function eraToForever(map, x, y)
    return DB.Source:EraToForeverByUiMapId(map, x, y)
end

function Graph.Build()
    local data = ns.Data
    local nodes, byId, edges = {}, {}, {}
    local function add(node)
        nodes[#nodes + 1] = node
        byId[node.id] = node
        return node
    end
    local function link(a, b, edge)
        edges[a] = edges[a] or {}
        edge.to = b
        table.insert(edges[a], edge)
    end

    -- Flight masters
    for taxiId, t in pairs(data.Taxi.nodes) do
        local map = Compat.WorldToZone and Compat.WorldToZone(t[2], t[3], t[4])
        add({ id = "taxi:" .. taxiId, kind = "flight", taxi = taxiId, name = shortName(t[1]), fullName = t[1],
            c = t[2], x = t[3], y = t[4], faction = t[5], isNew = t[6], map = map })
    end
    -- Flight times: the generated estimate, scaled by what this account's real flights took.
    local factor = Travel.learned and Travel.learned.factor or 1
    for _, f in ipairs(data.Taxi.flights) do
        local a, b = "taxi:" .. f[1], "taxi:" .. f[2]
        if byId[a] and byId[b] then link(a, b, { mode = "flight", seconds = f[3] * factor, base = f[3] }) end
    end

    -- Boats, zeppelins, tram
    for _, t in ipairs(data.Transports) do
        local id, mode, faction, crossing, cycle = t[1], t[2], t[3], t[4], t[5]
        local ends = {}
        for i = 6, 7 do
            local e = t[i]
            local x, y = eraToForever(e[1], e[2], e[3])
            local p = Graph.Point(e[1], x / 100, y / 100, e[4])
            p.id, p.kind, p.faction = id .. ":" .. (i - 5), mode, faction
            if type(p.c) ~= "number" then
                -- A dock on a normal zone map must have world coordinates, or it is cut off.
                WFC:Log("WARN", "travel", ("%s: uiMap %d has no world position; dock unreachable"):format(p.id, e[1]))
            end
            ends[#ends + 1] = add(p)
        end
        local edge = { mode = mode, seconds = crossing, wait = math.floor(cycle / 2), faction = faction }
        link(ends[1].id, ends[2].id, edge)
        link(ends[2].id, ends[1].id, { mode = mode, seconds = crossing, wait = edge.wait, faction = faction })
    end

    -- Authored in game: shipped (Data/Authored.lua) plus this account's recordings (SV).
    -- Positions are Forever map coordinates already. Same-named SV nodes replace shipped ones.
    for _, authored in ipairs({ data.Authored or { nodes = {}, links = {} }, Travel.authored or { nodes = {}, links = {} } }) do
        for name, n in pairs(authored.nodes) do
            local id = "user:" .. name
            if byId[id] then
                for i, existing in ipairs(nodes) do
                    if existing.id == id then table.remove(nodes, i) break end
                end
            end
            local p = Graph.Point(n.map, n.x, n.y, name)
            p.id, p.kind, p.faction, p.isNew = id, n.kind or "node", n.faction, n.isNew
            add(p)
        end
    end
    for _, authored in ipairs({ data.Authored or { links = {} }, Travel.authored or { links = {} } }) do
        for _, l in ipairs(authored.links) do
            local a, b = "user:" .. l.a, "user:" .. l.b
            if byId[a] and byId[b] and l.mode ~= "walk" then
                local edge = { mode = l.mode or "portal", seconds = l.seconds or 10, wait = l.wait, faction = l.faction }
                link(a, b, edge)
                if not l.oneWay then link(b, a, { mode = edge.mode, seconds = edge.seconds, wait = edge.wait, faction = edge.faction }) end
            end
        end
    end
    table.sort(nodes, function(p, q) return tostring(p.id) < tostring(q.id) end)
    return { nodes = nodes, byId = byId, edges = edges }
end

--- Flight master node for a Blizzard taxi node name ("Thelsamar, Loch Modan" or just "Thelsamar").
function Graph.TaxiByName(graph, name)
    if not name then return nil end
    local short = shortName(name)
    for _, n in ipairs(graph.nodes) do
        if n.taxi and (n.fullName == name or n.name == short) then return n end
    end
end
