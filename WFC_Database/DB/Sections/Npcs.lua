local _, ns = ...
local WFC = ns.WFC

-- NPCs. Card(id) is small and memoized (levels, rank, hostility, flags, quests).
-- Spawns(id) is large, so it is cached weakly and converted once to
-- { [uiMapId] = { {x, y}, ... } } in 0-1 map coordinates.
-- HostileNear() serves Travel's safety model from lazily built per-map grids.

local Source = WFC.DB.Source
local Data = ns.Data
local Util = WFC.Util
local Nz = Util.Nz

local Npcs = WFC.DB:NewSection("Npcs")

local N
local cards = {}
local spawns = Util.WeakCache()
local grids = {}            -- [uiMapId] = { [cellKey] = { {npcId, x, y}, ... } }
local factionTemplate = {}  -- [templateId] = EnemyGroup mask (1 players, 2 Alliance, 4 Horde, 8 monsters)
local flagBits = {}

local CELL = 0.02 -- grid cell size in map units (~2% of a zone)

local RANKS = { [0] = "normal", [1] = "elite", [2] = "rareelite", [3] = "boss", [4] = "rare" }

function Npcs:Init()
    N = Source.N
    local support = Source:Support("QuestieDB")
    factionTemplate = support and support.factionTemplate or {}
    flagBits = Source:NpcFlags()
end

function Npcs:Invalidate()
    cards, grids = {}, {}
    spawns = Util.WeakCache()
end

local FIELDS = {
    "name", "subName", "minLevel", "maxLevel", "rank", "zoneID", "questStarts", "questEnds",
    "factionID", "friendlyToFaction", "npcFlags",
}

--- { id, name, subName, minLevel, maxLevel, rank, elite, area, questStarts, questEnds,
---   friendly = "A"|"H"|"AH"|nil, aggro = {A = bool, H = bool}, flags = {name = bool}, isNew } or nil
function Npcs:Card(id)
    if type(id) ~= "number" then return nil end
    local c = cards[id]
    if c ~= nil then return c or nil end
    if not (N and N.Exists(id)) then
        cards[id] = false
        return nil
    end
    local v = N.GetAll(id, FIELDS)
    local rank = RANKS[v[5]] or "normal"
    local enemy = factionTemplate[v[9]] or 0
    local friendly = v[10]
    local flags = {}
    local npcFlags = v[11] or 0
    for name, bitValue in pairs(flagBits) do
        if type(bitValue) == "number" and bitValue > 0 and Util.HasBit(npcFlags, bitValue) then
            flags[name] = true
        end
    end
    c = {
        id = id,
        name = v[1],
        subName = v[2],
        minLevel = Nz(v[3]),
        maxLevel = Nz(v[4]) or Nz(v[3]),
        rank = rank,
        elite = rank == "elite" or rank == "rareelite" or rank == "boss",
        area = Nz(v[6]),
        questStarts = v[7],
        questEnds = v[8],
        friendly = friendly,
        -- Attacks on sight: hostile to all players (1) or to that faction (2 / 4).
        aggro = {
            A = Util.HasBit(enemy, 1) or Util.HasBit(enemy, 2),
            H = Util.HasBit(enemy, 1) or Util.HasBit(enemy, 4),
        },
        flags = flags,
    }
    local fix = Data.Corrections.npc[id]
    if fix then
        for k, val in pairs(fix) do c[k] = val end
    end
    c.isNew = WFC.DB.New:Evaluate("npc", id, c.area, true)
    cards[id] = c
    return c
end

--- Converts QuestieDB spawns ({[areaId] = {{x, y}}}, 0-100) to {[uiMapId] = {{x, y}}}, 0-1.
--- Instance-presence sentinels (-1, -1) are collected under `instances`.
function Npcs.ConvertSpawns(raw)
    local out = {}
    if not raw then return out end
    local Zones = WFC.DB.Zones
    for areaId, points in pairs(raw) do
        for i = 1, #points do
            local p = points[i]
            if p[1] == -1 then
                out.instances = out.instances or {}
                out.instances[#out.instances + 1] = areaId
            else
                local uiMap = Zones:AreaToUiMap(areaId)
                if uiMap then
                    local list = out[uiMap]
                    if not list then
                        list = {}
                        out[uiMap] = list
                    end
                    list[#list + 1] = { p[1] / 100, p[2] / 100 }
                end
            end
        end
    end
    return out
end

function Npcs:Spawns(id)
    local s = spawns[id]
    if s then return s end
    if not N then return Util.EMPTY end
    s = Npcs.ConvertSpawns(N.spawns(id))
    spawns[id] = s
    return s
end

---------------------------------------------------------------------------
-- Spatial queries (Travel safety)
---------------------------------------------------------------------------
local function cellKey(x, y)
    return math.floor(x / CELL) * 1000 + math.floor(y / CELL)
end

--- Patrol path points on a map (0-1), from QuestieDB's waypoints:
--- { [areaId] = { { {x, y}, ... }, ... } } in 0-100. Empty for NPCs that stand still.
function Npcs:Patrol(npcId, uiMapId)
    local out = {}
    if not N then return out end
    local ok, raw = pcall(N.waypoints, npcId)
    if not ok or type(raw) ~= "table" then return out end
    local Zones = WFC.DB.Zones
    for areaId, paths in pairs(raw) do
        if type(areaId) == "number" and Zones:AreaToUiMap(areaId) == uiMapId and type(paths) == "table" then
            for _, path in ipairs(paths) do
                for _, p in ipairs(type(path) == "table" and path or {}) do
                    if type(p) == "table" and p[1] and p[1] >= 0 then out[#out + 1] = { p[1] / 100, p[2] / 100 } end
                end
            end
        end
    end
    return out
end

-- Builds the grid for one map from the npcsByArea index. Returns nil until it is ready.
local function grid(uiMapId)
    local g = grids[uiMapId]
    if g then return g end
    local byArea = WFC.DB.Indexes:Get("npcsByArea")
    if not byArea then return nil end
    local Zones = WFC.DB.Zones
    g = {}
    local seen = {}
    for areaId, npcIds in pairs(byArea) do
        if Zones:AreaToUiMap(areaId) == uiMapId then
            for i = 1, #npcIds do
                local npcId = npcIds[i]
                if not seen[npcId] then
                    seen[npcId] = true
                    local card = Npcs:Card(npcId)
                    if card and (card.aggro.A or card.aggro.H) then
                        local points = Npcs:Spawns(npcId)[uiMapId]
                        if points then
                            for p = 1, #points do
                                Util.Push(g, cellKey(points[p][1], points[p][2]), { npcId, points[p][1], points[p][2] })
                            end
                        end
                        -- Patrols: every point of the NPC's walking path counts too.
                        for _, p in ipairs(Npcs:Patrol(npcId, uiMapId)) do
                            Util.Push(g, cellKey(p[1], p[2]), { npcId, p[1], p[2], patrol = true })
                        end
                    end
                end
            end
        end
    end
    grids[uiMapId] = g
    return g
end

--- Aggressive NPC spawns within `radius` (map units) of x,y on a map, for side "A"/"H".
--- Returns a list of { npcId, x, y }, or nil while the npcsByArea index is still building.
function Npcs:HostileNear(uiMapId, x, y, radius, side)
    local g = grid(uiMapId)
    if not g then return nil end
    local result = {}
    local r2 = radius * radius
    local cx0, cx1 = math.floor((x - radius) / CELL), math.floor((x + radius) / CELL)
    local cy0, cy1 = math.floor((y - radius) / CELL), math.floor((y + radius) / CELL)
    for cx = cx0, cx1 do
        for cy = cy0, cy1 do
            local cell = g[cx * 1000 + cy]
            if cell then
                for i = 1, #cell do
                    local e = cell[i]
                    local dx, dy = e[2] - x, e[3] - y
                    if dx * dx + dy * dy <= r2 then
                        local card = Npcs:Card(e[1])
                        if card and (not side or card.aggro[side]) then
                            result[#result + 1] = e
                        end
                    end
                end
            end
        end
    end
    return result
end

function Npcs:Stats()
    return { cards = Util.Count(cards), grids = Util.Count(grids) }
end
