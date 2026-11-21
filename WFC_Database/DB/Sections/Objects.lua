local _, ns = ...
local WFC = ns.WFC

-- World objects (chests, quest objects, signposts). Same pattern as Npcs.

local Source = WFC.DB.Source
local Data = ns.Data
local Util = WFC.Util
local Nz = Util.Nz

local Objects = WFC.DB:NewSection("Objects")

local O
local cards = {}
local spawns = Util.WeakCache()

function Objects:Init()
    O = Source.O
end

function Objects:Invalidate()
    cards = {}
    spawns = Util.WeakCache()
end

local FIELDS = { "name", "questStarts", "questEnds", "zoneID" }

--- { id, name, questStarts, questEnds, area, isNew } or nil
function Objects:Card(id)
    if type(id) ~= "number" then return nil end
    local c = cards[id]
    if c ~= nil then return c or nil end
    if not (O and O.Exists(id)) then
        cards[id] = false
        return nil
    end
    local v = O.GetAll(id, FIELDS)
    c = { id = id, name = v[1], questStarts = v[2], questEnds = v[3], area = Nz(v[4]) }
    local fix = Data.Corrections.object[id]
    if fix then
        for k, val in pairs(fix) do c[k] = val end
    end
    c.isNew = WFC.DB.New:Evaluate("object", id, c.area, true)
    cards[id] = c
    return c
end

--- { [uiMapId] = { {x, y}, ... } } in 0-1 coordinates.
function Objects:Spawns(id)
    local s = spawns[id]
    if s then return s end
    if not O then return Util.EMPTY end
    s = WFC.DB.Npcs.ConvertSpawns(O.spawns(id))
    spawns[id] = s
    return s
end

--- Object IDs with this exact (localized) name; for hovered world objects.
function Objects:IdsByName(name)
    return O and O.IdsByName(name) or nil
end

function Objects:Stats()
    return { cards = Util.Count(cards) }
end
