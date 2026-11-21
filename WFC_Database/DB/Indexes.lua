local _, ns = ...
local WFC = ns.WFC

-- Whole-database reverse indexes: the only places that must visit every entity.
-- They are built ONCE, in background jobs (time-sliced, paused in combat), then
-- saved in WFC_DB_Cache so later logins load them instantly. The cache is keyed by
-- QuestieDB version + WFC.DATA_VERSION + locale + client build; any change rebuilds.
--
--   questsByArea     [areaId]    = { questIds }  quest's zone (zoneOrSort > 0)
--   questsByDungeon  [dungeonId] = { questIds }  quest zone inside a dungeon
--   questsStartingIn [areaId]    = { questIds }  where the quest giver stands
--   questRewardItems [questId]   = { itemIds }   reward items (reverse of Item.questRewards)
--   npcsByArea       [areaId]    = { npcIds }    every area an NPC spawns in
--   questsByLevel    [minLevel]  = { questIds }  required level (quest level when none)
--
-- Readers:  Indexes:Get(name) -> data or nil (still building)
--           Indexes:WhenReady(name, fn)   fn(data) now or when built
--           Indexes:BuildNow(name)        finish synchronously (slash commands, tests)

local Source = WFC.DB.Source
local Util = WFC.Util
local Push = Util.Push

local Indexes = {}
WFC.DB.Indexes = Indexes

local defs, order = {}, {}
local data = {}
local waiting = {}

--- builder() runs inside a job; call WFC.Jobs:Checkpoint() in its loops and return the index.
function Indexes:Define(name, version, priority, builder)
    defs[name] = { version = version, priority = priority, builder = builder }
    order[#order + 1] = name
end

local function cacheKey()
    return table.concat({
        Source:VersionKey(), tostring(WFC.DATA_VERSION), GetLocale(), tostring(WFC.Compat.build),
    }, "|")
end

local function publish(name, value)
    data[name] = value
    local def = defs[name]
    WFC_DB_Cache.indexes[name] = { v = def.version, data = value }
    local fns = waiting[name]
    waiting[name] = nil
    if fns then
        for i = 1, #fns do
            local ok, err = pcall(fns[i], value)
            if not ok then geterrorhandler()(err) end
        end
    end
    WFC:Fire("WFC_INDEX_READY", name)
end

local function jobName(name)
    return "index:" .. name
end

local function schedule(name)
    local def = defs[name]
    WFC.Jobs:Add(jobName(name), def.builder, function(ok, result)
        if ok and type(result) == "table" then
            WFC:Log("INFO", "index", ("%s built: %d keys"):format(name, Util.Count(result)))
            publish(name, result)
        elseif ok then
            WFC:Log("ERROR", "index", name .. " builder returned " .. type(result))
        end
    end, def.priority)
end

--- Loads valid cached indexes and schedules builds for the rest. Called at PLAYER_LOGIN.
function Indexes:Start()
    local cache = WFC_DB_Cache
    local key = cacheKey()
    if cache.key ~= key then
        WFC:Log("INFO", "index", "cache key changed, rebuilding: " .. tostring(cache.key) .. " -> " .. key)
        cache.key = key
        cache.indexes = {}
    end
    local loaded, building = {}, {}
    for i = 1, #order do
        local name = order[i]
        local cached = cache.indexes[name]
        if cached and cached.v == defs[name].version and type(cached.data) == "table" then
            data[name] = cached.data
            loaded[#loaded + 1] = name
            WFC:Fire("WFC_INDEX_READY", name)
        else
            building[#building + 1] = name
            schedule(name)
        end
    end
    WFC:Log("INFO", "index", "from cache: " .. (table.concat(loaded, ", ") ~= "" and table.concat(loaded, ", ") or "none")
        .. " | building: " .. (table.concat(building, ", ") ~= "" and table.concat(building, ", ") or "none"))
end

function Indexes:Get(name)
    return data[name]
end

function Indexes:WhenReady(name, fn)
    if data[name] then
        fn(data[name])
    else
        Util.Push(waiting, name, fn)
    end
end

function Indexes:BuildNow(name)
    if data[name] then return data[name] end
    if not WFC.Jobs:IsQueued(jobName(name)) then schedule(name) end
    WFC.Jobs:RunNow(jobName(name))
    return data[name]
end

--- Throws away one (or every) index and rebuilds it in the background.
function Indexes:Rebuild(name)
    for i = 1, #order do
        local n = order[i]
        if not name or n == name then
            data[n] = nil
            WFC_DB_Cache.indexes[n] = nil
            schedule(n)
        end
    end
end

function Indexes:Status()
    local list = {}
    for i = 1, #order do
        local name = order[i]
        list[#list + 1] = { name = name, ready = data[name] ~= nil, entries = data[name] and Util.Count(data[name]) or 0 }
    end
    return list
end

---------------------------------------------------------------------------
-- Definitions
---------------------------------------------------------------------------
local checkpoint = function() WFC.Jobs:Checkpoint() end

Indexes:Define("questsByArea", 1, 30, function()
    local Q = Source.Q
    local byArea, byDungeon = {}, {}
    local Zones = WFC.DB.Zones
    local ids = Q.GetAllIds()
    for i = 1, #ids do
        local id = ids[i]
        local zone = Q.zoneOrSort(id)
        if zone > 0 then
            Push(byArea, zone, id)
            local dungeon = Zones:DungeonForArea(zone)
            if dungeon then Push(byDungeon, dungeon, id) end
        end
        checkpoint()
    end
    -- questsByDungeon is a by-product of the same pass.
    Indexes.pendingDungeon = byDungeon
    return byArea
end)

Indexes:Define("questsByDungeon", 1, 29, function()
    local byDungeon = Indexes.pendingDungeon
    Indexes.pendingDungeon = nil
    if byDungeon then return byDungeon end
    -- questsByArea came from the cache: derive from it instead of rescanning QuestieDB.
    local byArea = Indexes:Get("questsByArea") or Indexes:BuildNow("questsByArea")
    local Zones = WFC.DB.Zones
    byDungeon = {}
    for area, questIds in pairs(byArea) do
        local dungeon = Zones:DungeonForArea(area)
        if dungeon then
            for i = 1, #questIds do Push(byDungeon, dungeon, questIds[i]) end
        end
        checkpoint()
    end
    return byDungeon
end)

Indexes:Define("questsStartingIn", 1, 20, function()
    local Q, N, O = Source.Q, Source.N, Source.O
    local result = {}
    local ids = Q.GetAllIds()
    for i = 1, #ids do
        local id = ids[i]
        local startedBy = Q.startedBy(id)
        local seen = {}
        local npcs, objects = startedBy[1], startedBy[2]
        if npcs then
            for n = 1, #npcs do
                local area = N.zoneID(npcs[n])
                if area and area > 0 and not seen[area] then
                    seen[area] = true
                    Push(result, area, id)
                end
            end
        end
        if objects then
            for n = 1, #objects do
                local area = O.zoneID(objects[n])
                if area and area > 0 and not seen[area] then
                    seen[area] = true
                    Push(result, area, id)
                end
            end
        end
        checkpoint()
    end
    return result
end)

Indexes:Define("questRewardItems", 1, 25, function()
    local I = Source.I
    local result = {}
    local ids = I.GetAllIds()
    for i = 1, #ids do
        local itemId = ids[i]
        local quests = I.questRewards(itemId)
        if quests then
            for q = 1, #quests do Push(result, quests[q], itemId) end
        end
        checkpoint()
    end
    return result
end)

Indexes:Define("npcsByArea", 1, 10, function()
    local N = Source.N
    local result = {}
    local ids = N.GetAllIds()
    for i = 1, #ids do
        local npcId = ids[i]
        local spawns = N.spawns(npcId)
        if spawns then
            for areaId in pairs(spawns) do Push(result, areaId, npcId) end
        end
        checkpoint()
    end
    return result
end)

Indexes:Define("questsByLevel", 1, 28, function()
    local Q = Source.Q
    local result = {}
    local ids = Q.GetAllIds()
    for i = 1, #ids do
        local id = ids[i]
        local level = Q.requiredLevel(id)
        if level <= 0 then level = Q.questLevel(id) end
        if level <= 0 then level = 1 end
        Push(result, level, id)
        checkpoint()
    end
    return result
end)
