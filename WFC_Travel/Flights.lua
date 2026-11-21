local _, ns = ...
local WFC = WFC

-- Known flight points (plan.md §5.4, CoreRules R14). Re-synced from the taxi map at every
-- flight master visit, so losing SavedVariables costs one visit. Also marks the closest
-- flight master as known when the game announces a newly discovered flight path.

local Travel, Graph = ns.Travel, ns.Graph
local Compat = WFC.Compat

local Flights = {}
ns.Flights = Flights

local DISCOVER_YARDS = 80

function Travel:IsTaxiKnown(taxiNodeId)
    return self.char ~= nil and self.char.knownTaxi[taxiNodeId] == true
end

function Flights:KnownCount()
    local n = 0
    for _ in pairs(Travel.char and Travel.char.knownTaxi or {}) do n = n + 1 end
    return n
end

local function changed()
    WFC:Fire("WFC_FLIGHTPOINTS_CHANGED")
end

--- Reads the open taxi map. Returns how many nodes are known afterwards.
function Flights:Sync()
    local known = Travel.char.knownTaxi
    local graph = Travel:GetGraph()
    local added = 0
    for _, n in ipairs(Compat.GetTaxiNodes()) do
        local id = n.id
        if not id then
            local node = Graph.TaxiByName(graph, n.name)
            id = node and node.taxi
        end
        if id and n.known and not known[id] then
            known[id] = true
            added = added + 1
        end
    end
    if added > 0 then
        WFC:Log("INFO", "travel", ("flight points: +%d (%d known)"):format(added, self:KnownCount()))
        changed()
    end
    return self:KnownCount()
end

--- Marks the flight master closest to the player (within 80 yd) as known.
function Flights:DiscoverNearest()
    local pos = Travel:PlayerPoint()
    if not pos then return end
    local best, bestD
    for _, n in ipairs(Travel:GetGraph().nodes) do
        if n.taxi and n.c == pos.c then
            local d = math.sqrt((n.x - pos.x) ^ 2 + (n.y - pos.y) ^ 2)
            if d <= DISCOVER_YARDS and (not bestD or d < bestD) then best, bestD = n, d end
        end
    end
    if best and not Travel.char.knownTaxi[best.taxi] then
        Travel.char.knownTaxi[best.taxi] = true
        WFC:Print("learned flight path:", best.fullName or best.name)
        changed()
    end
end

---------------------------------------------------------------------------
-- Learned flight times (plan.md §5.4): time every flight, keep an average per route, and
-- scale all estimates by how real flights compare with them (factor 0.6-1.6).
---------------------------------------------------------------------------
local LEARN_RATE = 0.3 -- weight of the newest flight in the running averages
local trip

local function nearestTaxi()
    local pos = Travel:PlayerPoint()
    if not pos then return nil end
    local best, bestD
    for _, n in ipairs(Travel:GetGraph().nodes) do
        if n.taxi and n.c == pos.c then
            local d = math.sqrt((n.x - pos.x) ^ 2 + (n.y - pos.y) ^ 2)
            if d <= 150 and (not bestD or d < bestD) then best, bestD = n, d end
        end
    end
    return best
end

--- Generated (unscaled) flight time between two flight masters, over direct flight hops.
function Flights:Estimate(fromTaxi, toTaxi)
    local graph = Travel:GetGraph()
    local start, goal = "taxi:" .. fromTaxi, "taxi:" .. toTaxi
    local dist, done = { [start] = 0 }, {}
    while true do
        local u, best
        for id, s in pairs(dist) do
            if not done[id] and (not best or s < best) then u, best = id, s end
        end
        if not u then return nil end
        if u == goal then return best end
        done[u] = true
        for _, e in ipairs(graph.edges[u] or {}) do
            if e.mode == "flight" and not done[e.to] then
                local s = best + (e.base or e.seconds) + ns.Router.TAKEOFF
                if not dist[e.to] or s < dist[e.to] then dist[e.to] = s end
            end
        end
    end
end

--- Records one flight: per-route average, and the account-wide correction factor.
function Flights:Learn(fromTaxi, toTaxi, seconds)
    local learned = Travel.learned
    local key = fromTaxi .. ":" .. toTaxi
    local old = learned.pairs[key]
    learned.pairs[key] = old and (old + (seconds - old) * LEARN_RATE) or seconds
    local estimate = self:Estimate(fromTaxi, toTaxi)
    if estimate and estimate > 0 then
        local ratio = math.max(0.6, math.min(1.6, seconds / estimate))
        learned.factor = learned.samples == 0 and ratio or (learned.factor + (ratio - learned.factor) * LEARN_RATE)
        learned.samples = learned.samples + 1
    end
    WFC:Log("INFO", "travel", ("learned flight %s: %ds (factor %.2f)"):format(key, seconds, learned.factor))
    Travel:RebuildGraph()
    changed()
end

--- Learned time for a whole flight leg (one or more hops), or nil.
function Flights:LearnedTime(fromTaxi, toTaxi)
    return Travel.learned and Travel.learned.pairs[fromTaxi .. ":" .. toTaxi]
end

WFC:RegisterEvent("PLAYER_CONTROL_LOST", function()
    -- The taxi flag is set a moment after control is lost.
    C_Timer.After(0.5, function()
        if Compat.UnitOnTaxi() then
            local from = nearestTaxi()
            trip = from and { from = from.taxi, t0 = GetTime() } or nil
        end
    end)
end)

WFC:RegisterEvent("PLAYER_CONTROL_GAINED", function()
    if not trip or Compat.UnitOnTaxi() then return end
    local t = trip
    trip = nil
    local to = nearestTaxi()
    if to and to.taxi ~= t.from then Flights:Learn(t.from, to.taxi, GetTime() - t.t0) end
end)

WFC:RegisterEvent("TAXIMAP_OPENED", function()
    WFC:RunOutOfCombat("travel:taxisync", function() Flights:Sync() end)
end)

-- "New flight path discovered" (ERR_NEWTAXIPATH); the event payload differs by client, so
-- compare against the global string when it exists.
WFC:RegisterEvent("UI_INFO_MESSAGE", function(_, _, message)
    if message and ERR_NEWTAXIPATH and message == ERR_NEWTAXIPATH then
        WFC:RunOutOfCombat("travel:discover", function() Flights:DiscoverNearest() end)
    end
end)
