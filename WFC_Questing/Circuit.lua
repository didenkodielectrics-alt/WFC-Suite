local _, ns = ...
local WFC = WFC

-- Suggested circuit (plan.md §4.3, batching view): the zone where the best Next Up quests
-- cluster, with your unfinished quests there, in a sensible visiting order (nearest next
-- stop first). Shown as the first row of the Next Up tab; clicking it paths to the first stop.

local Questing = ns.Questing

local Circuit = {}
ns.Circuit = Circuit

Circuit.MAX = 6
Circuit.MIN = 2

--- The point a quest needs next: its giver if not taken, the turn-in when complete, else its first objective.
local function nextPoint(c)
    if c.state == "available" then return c.starts and c.starts[1] end
    if c.state == "complete" then return c.ends and c.ends[1] end
    for _, o in ipairs(c.objectives or {}) do
        if o.points and o.points[1] then return o.points[1] end
    end
    return c.ends and c.ends[1]
end

local function distance(a, b)
    if not (a and b and a.c ~= nil and a.c == b.c) then return math.huge end
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

--- Pure: { area, entries (visiting order), minutes, xp } or nil.
--- `nextUp` = available entries best first; `active` = entries for quests in the log.
function Circuit.Build(nextUp, active, pos)
    -- Pick the zone where the Next Up quests add up to the most XP per minute.
    local byArea, order = {}, {}
    for _, e in ipairs(nextUp) do
        local area = e.candidate.area
        if area then
            if not byArea[area] then
                byArea[area] = { score = 0, entries = {} }
                order[#order + 1] = area
            end
            local g = byArea[area]
            g.score = g.score + (e.score or 0)
            g.entries[#g.entries + 1] = e
        end
    end
    local best
    for _, area in ipairs(order) do
        local g = byArea[area]
        if #g.entries >= Circuit.MIN and (not best or g.score > byArea[best].score) then best = area end
    end
    if not best then return nil end
    local pool = {}
    for _, e in ipairs(byArea[best].entries) do pool[#pool + 1] = e end
    for _, e in ipairs(active) do
        if e.candidate.area == best then pool[#pool + 1] = e end
    end
    -- Visiting order: always the nearest remaining stop.
    local ordered, here = {}, pos
    while #pool > 0 and #ordered < Circuit.MAX do
        local pick, pickD = 1, math.huge
        for i, e in ipairs(pool) do
            local d = distance(here, nextPoint(e.candidate))
            if d < pickD then pick, pickD = i, d end
        end
        local e = table.remove(pool, pick)
        ordered[#ordered + 1] = e
        here = nextPoint(e.candidate) or here
    end
    local minutes, xp = 0, 0
    for _, e in ipairs(ordered) do
        minutes = minutes + (e.minutes or 0)
        xp = xp + (e.xp or 0)
    end
    return { area = best, entries = ordered, minutes = minutes, xp = xp }
end

--- The circuit for the current ranking (nil when nothing clusters).
function Questing:GetCircuit()
    local active = {}
    for _, e in ipairs(self:GetRanked()) do
        if e.candidate.state ~= "available" then active[#active + 1] = e end
    end
    local map, x, y = WFC.Compat.GetPlayerMapPosition()
    local pos
    if map and x then
        local c, wx, wy = WFC.Compat.MapToWorld(map, x, y)
        pos = c and { c = c, x = wx, y = wy } or nil
    end
    return Circuit.Build(self:GetNextUp(), active, pos)
end

--- Starts the circuit: a route to its first stop (Travel), else that quest on the map.
function Questing:StartCircuit()
    local circuit = self:GetCircuit()
    local first = circuit and circuit.entries[1]
    if not first then return false end
    local Travel = WFC.Travel
    if Travel and Travel.PathToQuest then return Travel:PathToQuest(first.candidate.id) end
    return ns.Bridge:ShowQuestOnMap(first.candidate.id)
end
