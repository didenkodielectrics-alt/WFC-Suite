local _, ns = ...
local WFC = WFC

-- Safe vs Deathrun routing (plan.md §5.6): glue between the pure Safety model, the Router
-- and the database's hostile-NPC lookup.
--
-- Safe mode uses lazy evaluation: route with the walks judged so far (unjudged walks count
-- as harmless), judge the walks on the result, repeat until the route only uses judged
-- walks. Around a dangerous walk it adds detour points to the side of the danger, so the
-- route can bend around a camp. Flights, boats and the tram are always safe.
-- Deathrun ignores danger, but routes are still judged so the risky stretches can be shown.

local Travel, Router, Safety = ns.Travel, ns.Router, ns.Safety
local Compat, DB, Player = WFC.Compat, WFC.DB, WFC.Player

local SafeRoute = {}
ns.SafeRoute = SafeRoute

local MAX_ROUNDS, MAX_DETOURS = 8, 24
local judged = {}       -- [walk key] = Safety result
local zoneCache = {}    -- [cell key] = { map, x, y } | false
local mapYards = {}     -- [uiMap] = yards per map unit (smaller axis)

function Travel:GetMode()
    return self.char and self.char.mode or "safe"
end

function Travel:SetMode(mode)
    if mode ~= "safe" and mode ~= "deathrun" then return end
    self.char.mode = mode
    WFC:Fire("WFC_TRAVEL_MODE", mode)
    if self:GetTarget() then self:Reroute() end
end

function SafeRoute:Invalidate()
    judged = {}
end

---------------------------------------------------------------------------
-- Hostile mobs near a world point (database only)
---------------------------------------------------------------------------
local function yardsPerUnit(map)
    local y = mapYards[map]
    if y == nil then
        local c0, x0, y0 = Compat.MapToWorld(map, 0, 0)
        local c1, x1, y1 = Compat.MapToWorld(map, 1, 1)
        y = (c0 and c1 and math.min(math.abs(x1 - x0), math.abs(y1 - y0))) or false
        mapYards[map] = y
    end
    return y or nil
end

--- Zone map position of a Router point: uiMap, x, y (cached per 60 yd cell).
local function zoneOf(p)
    if type(p.c) == "string" then
        local map = tonumber(p.c:match("^map:(%d+)$"))
        local w = map and Compat.GetMapWorldSize(map) or 1000
        return map, p.x / w, p.y / w
    end
    local key = p.c .. ":" .. math.floor(p.x / 60) .. ":" .. math.floor(p.y / 60)
    local z = zoneCache[key]
    if z == nil then
        local map, x, y = Compat.WorldToZone(p.c, p.x, p.y)
        z = map and { map, x, y } or false
        zoneCache[key] = z
    end
    if not z then return nil end
    -- The cell only picks the map; position it exactly.
    local x, y = Compat.WorldToMap(p.c, p.x, p.y, z[1])
    return z[1], x or z[2], y or z[3]
end

--- Mobs within Safety.MAX_RADIUS of a point, hostile to the player. pending = index not built.
local function mobsNear(p, state)
    local map, x, y = zoneOf(p)
    if not map then return {} end
    local area = DB.Zones:UiMapToArea(map)
    if area and DB.Zones:IsNewArea(area) then state.incomplete = true end
    local perUnit = yardsPerUnit(map) or 1000
    local list = DB:GetHostileNpcsNear(map, x, y, Safety.MAX_RADIUS / perUnit, Player.side)
    if not list then
        state.pending = true
        return {}
    end
    local mobs = {}
    for _, e in ipairs(list) do
        local npc = DB:GetNpc(e[1])
        local _, wx, wy = Compat.MapToWorld(map, e[2], e[3])
        if npc and wx then
            mobs[#mobs + 1] = { name = npc.name, level = npc.maxLevel or npc.minLevel, elite = npc.elite, x = wx, y = wy }
        elseif npc then
            mobs[#mobs + 1] = { name = npc.name, level = npc.maxLevel or npc.minLevel, elite = npc.elite,
                x = e[2] * perUnit, y = e[3] * perUnit } -- island frame
        end
    end
    return mobs
end

local function walkKey(a, b)
    return ("%s:%d:%d>%d:%d"):format(tostring(a.c), math.floor(a.x / 10), math.floor(a.y / 10),
        math.floor(b.x / 10), math.floor(b.y / 10))
end

--- Safety result for walking a -> b (cached until level, side or data change).
function SafeRoute:Judge(a, b)
    local key = walkKey(a, b)
    local r = judged[key]
    if r then return r end
    local samples = Safety.Samples(a, b)
    local state = {}
    local near = {}
    r = Safety.Evaluate(samples, function(i)
        local m = near[i]
        if not m then
            m = mobsNear(samples[i], state)
            near[i] = m
        end
        return m
    end, Player.level, Compat.GetGreenRange(Player.level))
    r.samples, r.incomplete, r.pending = samples, state.incomplete, state.pending
    -- Remember the pending state only briefly: judge again once the index exists.
    if not state.pending then judged[key] = r end
    return r
end

---------------------------------------------------------------------------
-- Safe routing
---------------------------------------------------------------------------
--- Four points beside the worst stretch of a dangerous walk (both sides, two distances).
local function detours(a, b, r, list)
    local s = r.stretches[1]
    local mid = s and r.samples[math.floor((s.first + s.last) / 2)] or (r.worst and { x = r.worst.x, y = r.worst.y })
    if not mid then return end
    local dx, dy = b.x - a.x, b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end
    local nx, ny = -dy / len, dx / len
    local reach = Safety.MAX_RADIUS + 60
    for _, k in ipairs({ 1, -1, 2.5, -2.5 }) do
        if #list >= MAX_DETOURS then return end
        list[#list + 1] = { id = "detour:" .. #list, kind = "detour", c = a.c, x = mid.x + nx * reach * k, y = mid.y + ny * reach * k }
    end
end

local function withNodes(graph, extra)
    if #extra == 0 then return graph end
    local nodes, byId = {}, {}
    for _, n in ipairs(graph.nodes) do nodes[#nodes + 1] = n byId[n.id] = n end
    for _, n in ipairs(extra) do nodes[#nodes + 1] = n byId[n.id] = n end
    return { nodes = nodes, byId = byId, edges = graph.edges }
end

--- Safe route, or (nil, reason). Falls back to nothing when every way is too dangerous.
function SafeRoute:Route(graph, from, to, opts)
    local safeOpts = {}
    for k, v in pairs(opts) do safeOpts[k] = v end
    safeOpts.walkCost = function(a, b, seconds)
        return Safety.Cost(seconds, judged[walkKey(a, b)])
    end
    local extra = {}
    for _ = 1, MAX_ROUNDS do
        local g = withNodes(graph, extra)
        local route, reason = Router.Route(g, from, to, safeOpts)
        if not route then return nil, reason end
        local fresh = 0
        for _, h in ipairs(route.hops) do
            if h.mode == "walk" and h.a and h.b and not judged[walkKey(h.a, h.b)] then
                local r = self:Judge(h.a, h.b)
                fresh = fresh + 1
                if r.pending then return route end -- no NPC data yet: nothing to avoid
                if (r.blocked or r.danger > 0.3) and #r.stretches > 0 then detours(h.a, h.b, r, extra) end
            end
        end
        if fresh == 0 then return route end
    end
    return Router.Route(withNodes(graph, extra), from, to, safeOpts)
end

---------------------------------------------------------------------------
-- Annotation (both modes): per-walk safety for colours and the risk summary
---------------------------------------------------------------------------
--- Adds leg.safety = { {a, b, result}, ... } to walk legs and returns
--- { stretches = n, text, incomplete, pending } for the popup.
function SafeRoute:Annotate(route)
    local risk = { stretches = 0 }
    local worst
    for _, leg in ipairs(route.legs) do
        if leg.mode == "walk" then
            leg.safety = {}
            local path = leg.path or { leg.from, leg.to }
            for i = 1, #path - 1 do
                local a, b = path[i], path[i + 1]
                if a and b and a.c == b.c and a.c ~= nil then
                    local r = self:Judge(a, b)
                    leg.safety[#leg.safety + 1] = { a = a, b = b, result = r }
                    risk.stretches = risk.stretches + #r.stretches
                    risk.incomplete = risk.incomplete or r.incomplete
                    risk.pending = risk.pending or r.pending
                    for _, s in ipairs(r.stretches) do
                        if not worst or (s.maxLevel or 0) > (worst.stretch.maxLevel or 0) then
                            worst = { stretch = s, point = r.samples[s.first] }
                        end
                    end
                end
            end
        end
    end
    if worst then
        local map = zoneOf(worst.point)
        local zone = map and DB.Zones:MapName(map)
        local s = worst.stretch
        local levels = s.minLevel == s.maxLevel and tostring(s.minLevel) or (s.minLevel .. "-" .. s.maxLevel)
        risk.text = ("%d risky stretch%s (%slvl %s %s)"):format(risk.stretches, risk.stretches == 1 and "" or "es",
            zone and (zone .. ", ") or "", levels, s.name or "mobs")
    end
    route.risk = risk
    return risk
end

WFC:On("WFC_PLAYER_CHANGED", function(_, field)
    if field == "level" or field == "identity" then judged = {} end
end)
WFC:On("WFC_INDEX_READY", function(_, name)
    if name == "npcsByArea" then
        judged = {}
        if Travel:GetTarget() then Travel:Reroute() end
    end
end)
