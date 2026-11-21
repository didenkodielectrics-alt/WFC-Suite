local _, ns = ...

-- Fastest-route search (plan.md §5.5). PURE: no WoW API. Graph.lua builds the graph;
-- specs build fixture graphs by hand.
--
-- point = { c = frame, x, y [, map, mx, my, name] }
--   frame = continent id (world yards), or "map:<uiMapID>" for detached islands
--   (no world coordinates: they connect to the world only through transport edges).
-- graph = {
--   nodes = { node, ... }   node = point + { id, kind, name, taxi = taxiNodeId, faction, isNew }
--   edges = { [nodeId] = { { to = nodeId, mode = "flight"|"boat"|"zeppelin"|"tram"|"portal"|"walk",
--                            seconds, wait, faction }, ... } }
-- }
-- opts = { speed (yd/s), detour (straight-line walk factor), faction ("A"|"H"),
--          known = { [taxiNodeId] = true }, hearth = { node = nodeId, seconds } | nil,
--          walkCost = function(a, b, seconds) -> seconds | nil (nil = don't walk there) }
--          walkCost is how Safe mode (SafeRoute.lua) weighs or forbids dangerous walks.
--
-- Walking is implicit: any two points in the same frame are linked at distance x detour / speed.

local Router = {}
ns.Router = Router

Router.TAKEOFF = 5 -- seconds added per flight

local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function walkSeconds(a, b, opts)
    local d = dist(a, b)
    local detour = opts.detour or 1
    local extra = 0
    local getZone = opts.getZone or (ns.Graph and ns.Graph.GetZone)
    if getZone then
        local za = getZone(a)
        local zb = getZone(b)
        if za and zb and za ~= zb then
            detour = opts.crossZoneDetour or (detour * 1.6)
            extra = opts.zoneTransition or 120
        end
    end
    return d * detour / opts.speed + extra
end

--- Walk cost after the optional Safe-mode weighting; nil when the walk is forbidden.
local function walkCost(a, b, opts)
    local s = walkSeconds(a, b, opts)
    if opts.walkCost then return opts.walkCost(a, b, s) end
    return s
end

local function factionOk(f, opts)
    return f == nil or f == "B" or opts.faction == nil or f == opts.faction
end

--- Whether a fixed edge may be used by this character.
function Router.Usable(graph, fromNode, edge, opts)
    if not factionOk(edge.faction, opts) then return false end
    if edge.mode == "flight" then
        local to = graph.byId[edge.to]
        local known = opts.known or {}
        return known[fromNode.taxi] == true and to ~= nil and known[to.taxi] == true
            and factionOk(fromNode.faction, opts) and factionOk(to.faction, opts)
    end
    return true
end

--- Dijkstra from a point to every node. Returns tree = { from, dist = {[id]=s}, prev = {[id]=hop} }.
--- hop = { from = nodeId|"start", mode, seconds, wait }
function Router.Tree(graph, from, opts)
    local nodes, byId = graph.nodes, graph.byId
    local d, prev, done = {}, {}, {}
    for _, n in ipairs(nodes) do
        if from.c ~= nil and n.c == from.c then
            local s = walkCost(from, n, opts)
            if s then
                d[n.id] = s
                prev[n.id] = { from = "start", mode = "walk", seconds = s }
            end
        end
    end
    local hearth = opts.hearth
    if hearth and byId[hearth.node] and (not d[hearth.node] or hearth.seconds < d[hearth.node]) then
        d[hearth.node] = hearth.seconds
        prev[hearth.node] = { from = "start", mode = "hearth", seconds = hearth.seconds }
    end
    while true do
        local u, best
        for id, s in pairs(d) do
            if not done[id] and (not best or s < best) then u, best = id, s end
        end
        if not u then break end
        done[u] = true
        local node = byId[u]
        -- Walk to every other node in the same frame.
        for _, v in ipairs(nodes) do
            if v.c == node.c and not done[v.id] then
                local w = walkCost(node, v, opts)
                local s = w and best + w
                if s and (not d[v.id] or s < d[v.id]) then
                    d[v.id] = s
                    prev[v.id] = { from = u, mode = "walk", seconds = w }
                end
            end
        end
        for _, e in ipairs(graph.edges[u] or {}) do
            if not done[e.to] and Router.Usable(graph, node, e, opts) then
                local cost = e.seconds + (e.wait or 0) + (e.mode == "flight" and Router.TAKEOFF or 0)
                local s = best + cost
                if not d[e.to] or s < d[e.to] then
                    d[e.to] = s
                    prev[e.to] = { from = u, mode = e.mode, seconds = cost, wait = e.wait }
                end
            end
        end
    end
    return { from = from, dist = d, prev = prev }
end

--- Seconds from the tree's start to a point, and the node it is reached from (nil = walk directly).
function Router.TimeTo(graph, tree, to, opts)
    local best, via
    local from = tree.from
    if from.c ~= nil and from.c == to.c then best = walkCost(from, to, opts) end
    for _, n in ipairs(graph.nodes) do
        local s = tree.dist[n.id]
        if s and n.c == to.c and to.c ~= nil then
            local w = walkCost(n, to, opts)
            if w and (not best or s + w < best) then best, via = s + w, n.id end
        end
    end
    return best, via
end

local function legName(p)
    return p and p.name or nil
end

--- Fastest route: { total, legs = { {mode, from, to, path, seconds, wait, fromName, toName, isNew} },
--- hops } or nil, "unreachable". Consecutive flights (the game chains hops) and walks merge into
--- one leg; `path` keeps every point they pass through, for drawing.
function Router.Route(graph, from, to, opts, tree)
    tree = tree or Router.Tree(graph, from, opts)
    local total, via = Router.TimeTo(graph, tree, to, opts)
    if not total then return nil, "unreachable" end
    -- Walk back from the goal to the start.
    local hops = {}
    local final = { mode = "walk", from = via or "start", to = "goal" }
    final.seconds = walkCost(via and graph.byId[via] or from, to, opts) or 0
    hops[1] = final
    local id = via
    while id and id ~= "start" do
        local p = tree.prev[id]
        table.insert(hops, 1, { mode = p.mode, from = p.from, to = id, seconds = p.seconds, wait = p.wait })
        id = p.from
    end
    local function point(ref)
        if ref == "start" then return from end
        if ref == "goal" then return to end
        return graph.byId[ref]
    end
    local legs = {}
    for _, h in ipairs(hops) do
        h.a, h.b = point(h.from), point(h.to)
    end
    for _, h in ipairs(hops) do
        local a, b = h.a, h.b
        local last = legs[#legs]
        if last and last.mode == h.mode and (h.mode == "flight" or h.mode == "walk") then
            last.to, last.toName = b, legName(b)
            last.path[#last.path + 1] = b
            last.seconds = last.seconds + h.seconds
            last.isNew = last.isNew or (b and b.isNew) or false
            if h.mode == "flight" then last.hops = last.hops + 1 end
        elseif not (h.mode == "walk" and h.seconds < 1) then
            legs[#legs + 1] = {
                mode = h.mode, from = a, to = b, path = { a, b }, seconds = h.seconds, wait = h.wait,
                fromName = legName(a), toName = legName(b), hops = 1,
                isNew = (a and a.isNew) or (b and b.isNew) or false,
            }
        end
    end
    return { total = total, legs = legs, hops = hops }
end

return Router
