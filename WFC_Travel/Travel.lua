local _, ns = ...
local WFC = WFC

-- Travel core (plan.md §5.5/§5.8): target, route, next-leg waypoint, arrival, and the
-- public API other addons use:
--   WFC.Travel:SetTarget(uiMapID, x, y, label)   :ClearTarget()   :GetRoute()   :GetTarget()
--   WFC.Travel:PathToQuest(questId)              :PathToDungeon(dungeonId)
--   WFC.Travel:EstimateTime(fromPoint, toPoint)  -- seconds (Questing's scorer)
--   WFC.Travel:IsTaxiKnown(taxiNodeId)
-- Messages: WFC_TRAVEL_ROUTE (route or nil), WFC_FLIGHTPOINTS_CHANGED.

local Travel, Graph, Router = ns.Travel, ns.Graph, ns.Router
local Compat, DB, Player = WFC.Compat, WFC.DB, WFC.Player

local HEARTHSTONE = 6948
local HEARTH_SECONDS = 10 + 20 -- cast + loading screen
local CELL = 50 -- yards: EstimateTime reuses one search for starts within the same cell
local LEG_DONE_YARDS = 40
local SHORT_WALK = 120 -- seconds: walks this short are returned without a search
local MAX_TREES = 64

local graph
local target, route, legIndex
local trees, treeCount = {}, 0 -- [startCellKey] = Router tree (EstimateTime cache)
local ticker

---------------------------------------------------------------------------
-- Graph and options
---------------------------------------------------------------------------
function Travel:GetGraph()
    if not graph then graph = Graph.Build() end
    return graph
end

function Travel:RebuildGraph()
    graph = nil
    self:Invalidate()
end

--- Drops cached searches (flight points, level, settings or hearthstone changed).
function Travel:Invalidate()
    trees, treeCount = {}, 0
end

local function speed()
    local level = Player.level or 1
    if Travel.settings.assumeMount and level >= 60 then return 14 end
    if Travel.settings.assumeMount and level >= 40 then return 11.2 end
    return 7
end

--- Hearth leg: the recorded bind point, else the flight master named like the bind location.
local function hearthOption(g)
    local s = Travel.settings
    if not s.allowHearth or Compat.GetItemCount(HEARTHSTONE) == 0 or not Compat.IsItemReady(HEARTHSTONE) then return nil end
    local bind = Travel.char.bind
    local location = Compat.GetBindLocation()
    if bind.map and (not location or bind.name == location) then
        local node = g.byId["bind"]
        if not node then
            node = Graph.Point(bind.map, bind.x, bind.y, bind.name or "Hearth")
            node.id, node.kind = "bind", "bind"
            g.nodes[#g.nodes + 1] = node
            g.byId.bind = node
        end
        return { node = "bind", seconds = HEARTH_SECONDS }
    end
    local node = Graph.TaxiByName(g, location)
    if node then return { node = node.id, seconds = HEARTH_SECONDS } end
end

function Travel:Options()
    local g = self:GetGraph()
    local s = self.settings
    return {
        speed = speed(), detour = s.detour, faction = Player.side,
        known = self.char.knownTaxi, hearth = hearthOption(g),
        getZone = function(p) return Graph.GetZone(p) end,
        crossZoneDetour = s.crossZoneDetour or (s.detour * 1.6),
        zoneTransition = s.zoneTransition or 120,
    }
end

--- The player's position as a Router point, or nil (instances, loading).
function Travel:PlayerPoint()
    local map, x, y = Compat.GetPlayerMapPosition()
    if not (map and x) then return nil end
    return Graph.Point(map, x, y, "you")
end

---------------------------------------------------------------------------
-- Estimates (Questing)
---------------------------------------------------------------------------
local function cellKey(p)
    return tostring(p.c) .. ":" .. math.floor(p.x / CELL) .. ":" .. math.floor(p.y / CELL)
end

--- Seconds from one point to another along the best route, or nil if unreachable.
function Travel:EstimateTime(from, to)
    from, to = Graph.Normalize(from), Graph.Normalize(to)
    if not (from and to) then return nil end
    local za = Graph.GetZone(from)
    local zb = Graph.GetZone(to)
    local sameZone = (za and zb and za == zb)
    -- Short hops (objective to objective in the same zone) never beat walking: skip the search.
    if from.c == to.c and sameZone then
        local walk = math.sqrt((from.x - to.x) ^ 2 + (from.y - to.y) ^ 2) * self.settings.detour / speed()
        if walk <= SHORT_WALK then return walk end
    end
    local key = cellKey(from)
    local tree = trees[key]
    local g, opts = self:GetGraph(), self:Options()
    if not tree then
        if treeCount >= MAX_TREES then trees, treeCount = {}, 0 end
        tree = Router.Tree(g, from, opts)
        trees[key] = tree
        treeCount = treeCount + 1
    end
    return (Router.TimeTo(g, tree, to, opts))
end

---------------------------------------------------------------------------
-- Target and route
---------------------------------------------------------------------------
local function legEnd(leg) return leg and leg.to end

--- Map position for a route point: its own, or (flight masters, which only have world
--- coordinates) projected onto the player's current map, then the target's map.
local function mapPosition(p)
    if p.map and p.mx then return p.map, p.mx, p.my end
    if type(p.c) ~= "number" then return nil end
    local maps = { (Compat.GetPlayerMapPosition()), target and target.map }
    for _, map in ipairs(maps) do
        local x, y = Compat.WorldToMap(p.c, p.x, p.y, map)
        if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return map, x, y end
    end
end

local function pinLeg()
    if not (route and Travel.settings.waypoint) then return end
    local leg = route.legs[legIndex]
    local p = legEnd(leg)
    local map, x, y
    if p then map, x, y = mapPosition(p) end
    if map then
        local label = leg.toName or (target and target.name) or "Target"
        Compat.SetWaypoint(map, x, y, label)
    end
end

--- Recomputes the route from the player's current position (out of combat).
function Travel:Reroute()
    WFC:RunOutOfCombat("travel:route", function()
        if not target then return end
        local from = self:PlayerPoint()
        if not from then
            route, self.reason = nil, "no position (inside an instance?)"
        else
            local g, opts = self:GetGraph(), self:Options()
            local r, reason
            self.fallback = nil
            if self:GetMode() == "safe" then
                r, reason = ns.SafeRoute:Route(g, from, target, opts)
                if not r then
                    -- Every way is too dangerous: show the direct route and say so.
                    r, reason = Router.Route(g, from, target, opts)
                    self.fallback = r ~= nil
                end
            else
                r, reason = Router.Route(g, from, target, opts)
            end
            if r then
                -- A flight you've taken before uses its measured time.
                for _, leg in ipairs(r.legs) do
                    local learned = leg.mode == "flight" and leg.from.taxi and leg.to.taxi
                        and ns.Flights:LearnedTime(leg.from.taxi, leg.to.taxi)
                    if learned then
                        r.total = r.total - leg.seconds + learned
                        leg.seconds, leg.learned = learned, true
                    end
                end
                ns.SafeRoute:Annotate(r)
            end
            route, self.reason = r, reason
        end
        legIndex = 1
        pinLeg()
        WFC:Fire("WFC_TRAVEL_ROUTE", route)
    end)
end

local function startTicker()
    if ticker or not C_Timer.NewTicker then return end
    ticker = C_Timer.NewTicker(2, function() Travel:Track() end)
end

local function stopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end

function Travel:SetTarget(uiMapId, x, y, label)
    target = Graph.Point(uiMapId, x, y, label or "Target")
    target.label = label
    self:Reroute()
    startTicker()
    WFC:Fire("WFC_TRAVEL_TARGET", target)
    return target
end

function Travel:ClearTarget()
    target, route, legIndex, self.reason = nil, nil, nil, nil
    stopTicker()
    if C_Map and C_Map.ClearUserWaypoint and Travel.settings.waypoint then C_Map.ClearUserWaypoint() end
    WFC:Fire("WFC_TRAVEL_TARGET", nil)
    WFC:Fire("WFC_TRAVEL_ROUTE", nil)
end

function Travel:GetTarget() return target end
function Travel:GetRoute() return route, legIndex end

--- Arrival and leg advancement (every 2 s while a target is set; never in combat).
function Travel:Track()
    if not target or WFC:InCombat() then return end
    local pos = self:PlayerPoint()
    if not pos or pos.c ~= target.c then return end
    local function near(p, yards)
        return p and p.c == pos.c and math.sqrt((p.x - pos.x) ^ 2 + (p.y - pos.y) ^ 2) <= yards
    end
    if near(target, self.settings.arrivalYards) then
        WFC:Print("arrived at", target.name or "target")
        self:ClearTarget()
        return
    end
    if route and legIndex < #route.legs and near(legEnd(route.legs[legIndex]), LEG_DONE_YARDS) then
        legIndex = legIndex + 1
        pinLeg()
        WFC:Fire("WFC_TRAVEL_ROUTE", route)
    end
end

---------------------------------------------------------------------------
-- Quest and dungeon targets
---------------------------------------------------------------------------
--- Picks the point (from a list of {map, x, y}) that is fastest to reach.
function Travel:Closest(points)
    local from = self:PlayerPoint()
    local best, bestT
    for _, p in ipairs(points) do
        local t = from and self:EstimateTime(from, Graph.Point(p.map, p.x, p.y)) or 0
        if t and (not bestT or t < bestT) then best, bestT = p, t end
    end
    return best or points[1]
end

local function openMapAt(map)
    WFC:RunOutOfCombat("travel:openmap", function() Compat.OpenWorldMap(map) end)
end

--- Target = what the quest needs next: the giver if not accepted, the turn-in when
--- complete, otherwise the fastest-to-reach objective.
function Travel:PathToQuest(questId)
    local info = Player.active[questId]
    local role = not info and "start" or info.isComplete and "end" or "objective"
    local points = {}
    for _, p in ipairs(DB:GetQuestPositions(questId)) do
        if p.role == role then points[#points + 1] = p end
    end
    if #points == 0 then
        for _, p in ipairs(DB:GetQuestPositions(questId)) do points[#points + 1] = p end
    end
    local brief = DB:GetQuestBrief(questId)
    local name = brief and brief.name or ("Quest " .. questId)
    if #points == 0 then
        WFC:Print("no location known for", name)
        return false
    end
    local p = self:Closest(points)
    self:SetTarget(p.map, p.x, p.y, name)
    openMapAt(p.map)
    return true
end

function Travel:PathToDungeon(dungeonId)
    local d = DB:GetDungeon(dungeonId)
    if not (d and #d.entrances > 0) then
        WFC:Print("no entrance known for that dungeon")
        return false
    end
    local p = self:Closest(d.entrances)
    self:SetTarget(p.map, p.x, p.y, d.name)
    openMapAt(p.map)
    return true
end

---------------------------------------------------------------------------
-- Step text (popup and chat)
---------------------------------------------------------------------------
local VERB = { flight = "Fly", boat = "Boat", zeppelin = "Zeppelin", tram = "Tram", portal = "Portal", hearth = "Hearth" }

function Travel.FormatTime(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    if seconds < 60 then return seconds .. "s" end
    local m, s = math.floor(seconds / 60), seconds % 60
    if m >= 60 then return ("%dh %dm"):format(math.floor(m / 60), m % 60) end
    return s > 0 and ("%dm %ds"):format(m, s) or (m .. "m")
end

--- "Run to Thelsamar", "Fly Thelsamar to Ironforge", "Boat to Theramore (~2m wait)".
--- (Our fonts have no "→" glyph.)
function Travel.StepText(leg, isLast, targetName)
    local to = isLast and (targetName or "target") or (leg.toName or "next stop")
    if leg.mode == "walk" then
        local verb = (speed() > 7) and "Ride to " or "Run to "
        local za = leg.from and Graph.GetZone(leg.from)
        local zb = leg.to and Graph.GetZone(leg.to)
        local suffix = ""
        if za and zb and za ~= zb and C_Map and C_Map.GetMapInfo then
            local info = C_Map.GetMapInfo(zb)
            if info and info.name and not to:find(info.name, 1, true) then
                suffix = " (" .. info.name .. ")"
            end
        end
        return verb .. to .. suffix
    elseif leg.mode == "flight" then
        return ("Fly %s to %s"):format(leg.fromName or "?", leg.toName or "?")
    elseif leg.mode == "hearth" then
        return "Hearth to " .. (leg.toName or "your inn")
    end
    local text = (VERB[leg.mode] or leg.mode) .. " to " .. (leg.toName or "?")
    if leg.wait and leg.wait >= 30 then text = text .. (" (~%s wait)"):format(Travel.FormatTime(leg.wait)) end
    return text
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
WFC:On("WFC_FLIGHTPOINTS_CHANGED", function()
    Travel:Invalidate()
    if target then Travel:Reroute() end
end)
WFC:On("WFC_PLAYER_CHANGED", function(_, field)
    if field == "level" or field == "identity" then Travel:Invalidate() end
end)
WFC:RegisterEvent("HEARTHSTONE_BOUND", function()
    local map, x, y = Compat.GetPlayerMapPosition()
    if map and x then
        local bind = Travel.char.bind
        bind.map, bind.x, bind.y, bind.name = map, x, y, Compat.GetBindLocation()
        Travel:RebuildGraph()
    end
end)
WFC:RegisterEvent("BAG_UPDATE_COOLDOWN", function() Travel:Invalidate() end)
WFC:On("WFC_COMBAT_END", function()
    if target then Travel:Reroute() end
end)
