local _, ns = ...
local WFC = ns.WFC

-- Zones: AreaID <-> UiMapID mapping, parent zones, dungeons and "new region" tests.
-- QuestieDB ships these maps as Lua source strings; each is materialized once,
-- on first use, and then every lookup is a plain table index.

local Source = WFC.DB.Source
local Data = ns.Data

local Zones = WFC.DB:NewSection("Zones")

local maps          -- lazily built, see load()
local dungeonCards  -- lazily built, see Zones:GetDungeons()
local newAreaCache = {}
local areaNames, mapNames = {}, {}

local function merge(base, override)
    for k, v in pairs(override) do base[k] = v end
    return base
end

local function load()
    if maps then return maps end
    local zoneDB = Source:Support("ZoneDB") or {}
    local p = zoneDB.private or {}
    maps = {
        areaToUi = merge(Source.Materialize(p.areaIdToUiMapId), Source.Materialize(p.areaIdToUiMapIdOverride)),
        uiToArea = merge(Source.Materialize(p.uiMapIdToAreaId), Source.Materialize(p.uiMapIdToAreaIdOverride)),
        parent = Source.Materialize(p.subZoneToParentZone),
        instanceToArea = Source.Materialize(p.instanceIdToAreaId),
        dungeons = type(p.dungeons) == "table" and p.dungeons or {},
        dungeonByArea = {},
    }
    for dungeonId, entry in pairs(maps.dungeons) do
        maps.dungeonByArea[dungeonId] = dungeonId
        local alternatives = entry[2]
        if alternatives then
            for i = 1, #alternatives do maps.dungeonByArea[alternatives[i]] = dungeonId end
        end
    end
    return maps
end

function Zones:Invalidate()
    maps = nil
    dungeonCards = nil
    newAreaCache = {}
end

---------------------------------------------------------------------------
-- Mapping
---------------------------------------------------------------------------
function Zones:ParentArea(areaId)
    return load().parent[areaId]
end

--- UiMapID for an AreaID, walking up parent zones. nil if unmapped or suppressed (0).
function Zones:AreaToUiMap(areaId)
    local m = load()
    local id, hops = areaId, 0
    while id and hops < 8 do
        local ui = m.areaToUi[id]
        if ui then return ui ~= 0 and ui or nil end
        id = m.parent[id]
        hops = hops + 1
    end
end

function Zones:UiMapToArea(uiMapId)
    return load().uiToArea[uiMapId]
end

function Zones:InstanceToArea(instanceId)
    return load().instanceToArea[instanceId]
end

function Zones:AreaName(areaId)
    local name = areaNames[areaId]
    if name == nil then
        name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaId) or false
        areaNames[areaId] = name
    end
    return name or nil
end

function Zones:MapName(uiMapId)
    local name = mapNames[uiMapId]
    if name == nil then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapId)
        name = info and info.name or false
        mapNames[uiMapId] = name
    end
    return name or nil
end

---------------------------------------------------------------------------
-- Dungeons
---------------------------------------------------------------------------
--- Dungeon AreaID for any area inside it (including alternative sub-areas), else nil.
function Zones:DungeonForArea(areaId)
    return areaId and load().dungeonByArea[areaId] or nil
end

--- List of dungeon cards: { id, name, altAreas, parentArea, entrances = {{map, x, y}}, isNew }.
function Zones:GetDungeons()
    if dungeonCards then return dungeonCards end
    local list = {}
    for dungeonId, entry in pairs(load().dungeons) do
        local entrances = {}
        local locations = entry[4]
        if locations then
            for i = 1, #locations do
                local loc = locations[i]
                local uiMap = loc and self:AreaToUiMap(loc[1])
                if uiMap then
                    entrances[#entrances + 1] = { map = uiMap, x = loc[2] / 100, y = loc[3] / 100 }
                end
            end
        end
        list[#list + 1] = {
            id = dungeonId,
            name = entry[1],
            altAreas = entry[2],
            parentArea = entry[3],
            entrances = entrances,
            isNew = self:IsNewDungeon(dungeonId),
        }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    dungeonCards = list
    return list
end

function Zones:GetDungeon(dungeonId)
    local list = self:GetDungeons()
    for i = 1, #list do
        if list[i].id == dungeonId then return list[i] end
    end
end

---------------------------------------------------------------------------
-- "new!" regions
---------------------------------------------------------------------------
function Zones:IsNewArea(areaId)
    if not areaId then return false end
    local cached = newAreaCache[areaId]
    if cached ~= nil then return cached end

    local override = Data.NewOverrides.zone[areaId]
    local result
    if override ~= nil then
        result = override
    else
        local regions = Data.NewRegions
        local uiMap = self:AreaToUiMap(areaId)
        result = (uiMap ~= nil and regions.uiMaps[uiMap] == true) or areaId >= regions.firstNewAreaId
        local id, hops = areaId, 0
        while not result and id and hops < 8 do
            result = regions.areas[id] == true
            id = load().parent[id]
            hops = hops + 1
        end
    end
    newAreaCache[areaId] = result
    return result
end

function Zones:IsNewDungeon(dungeonId)
    local override = Data.NewOverrides.dungeon[dungeonId]
    if override ~= nil then return override end
    return Data.NewDungeons[dungeonId] == true or dungeonId >= Data.NewRegions.firstNewAreaId
end

function Zones:Stats()
    local m = load()
    return { areas = WFC.Util.Count(m.areaToUi), dungeons = WFC.Util.Count(m.dungeons) }
end
