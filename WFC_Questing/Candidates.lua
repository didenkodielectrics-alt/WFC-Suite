local _, ns = ...
local WFC = WFC

-- Glue between WFC.DB / the quest log and the pure Scorer: gathers candidate quests,
-- converts their map points to world yards (memoized per quest), runs the Scorer in a
-- time-sliced background job, and publishes the ranking (WFC_QUESTS_SCORED).
-- Re-scoring is debounced (2 s) and never runs in combat (plan.md §4.3).

local Questing, Scorer, Bridge = ns.Questing, ns.Scorer, ns.Bridge
local DB, Compat, Player = WFC.DB, WFC.Compat, WFC.Player

local MAX_POINTS = 40 -- per entity: plenty for a nearest-point estimate, bounded cost
local JOB = "questing:score"

local ranked = {}
local skipped = {}
local byId = {}
local worldPoints = WFC.Util.WeakCache() -- [questId] = { starts, ends, groups = {[kind:id] = points} }
local dirty, timer = false, nil
Questing.scoredAt = nil

local function toWorld(p)
    local c, x, y = Compat.MapToWorld(p.map, p.x, p.y)
    return { c = c, x = x or 0, y = y or 0, map = p.map, mx = p.x, my = p.y } -- mx/my: Travel places islands
end

--- World points of a quest's givers, objectives (grouped by entity) and turn-ins.
local function pointsFor(questId)
    local w = worldPoints[questId]
    if w then return w end
    w = { starts = {}, ends = {}, groups = {} }
    local counts = {}
    for _, p in ipairs(DB:GetQuestPositions(questId)) do
        local key = p.role == "objective" and (p.kind .. ":" .. p.id) or p.role
        counts[key] = (counts[key] or 0) + 1
        if counts[key] <= MAX_POINTS then
            local list
            if p.role == "start" then
                list = w.starts
            elseif p.role == "end" then
                list = w.ends
            else
                list = w.groups[key]
                if not list then
                    list = {}
                    w.groups[key] = list
                end
            end
            list[#list + 1] = toWorld(p)
        end
    end
    worldPoints[questId] = w
    return w
end

local OBJECTIVE_KIND = { kill = "kill", killcredit = "kill", item = "item", object = "object" }
local CLIENT_KIND = { monster = "kill", item = "item", object = "object" }

--- Candidate record for one quest (see Scorer.lua for the shape).
function Questing:BuildCandidate(questId, state)
    local card = DB:GetQuest(questId)
    if not card then return nil end
    local tag = DB.Quests:Tag(questId)
    local w = pointsFor(questId)
    local c = {
        id = questId, name = card.name, level = card.level, minLevel = card.minLevel, xp = card.xp,
        area = card.area, dungeon = card.dungeon, repeatable = card.repeatable, isNew = card.isNew,
        state = state, starts = w.starts, ends = w.ends, objectives = {},
        elite = tag and (tag.isElite or tag.name == "Elite") or false,
        group = tag and (tag.id == 1 or tag.name == "Group") or false,
    }
    if state == "active" then
        -- The client knows the real counts; spread them over the objective locations.
        local remaining, kind = 0, "other"
        for _, o in ipairs(Compat.GetQuestObjectives(questId)) do
            if not o.finished then
                remaining = remaining + math.max(1, (o.need or 1) - (o.have or 0))
                kind = CLIENT_KIND[o.type] or kind
            end
        end
        local groups = {}
        for _, points in pairs(w.groups) do groups[#groups + 1] = points end
        if #groups == 0 then groups[1] = false end
        for i, points in ipairs(groups) do
            c.objectives[i] = { kind = kind, remaining = math.ceil(remaining / #groups), points = points or nil }
        end
    else
        for _, o in ipairs(card.objectives) do
            local kind = OBJECTIVE_KIND[o.type] or "other"
            local key = (kind == "object" and "object:" or "npc:") .. tostring(o.id)
            c.objectives[#c.objectives + 1] = { kind = kind, points = w.groups[key] }
        end
    end
    local nextBrief = card.next and DB:GetQuestBrief(card.next)
    c.chainXp = nextBrief and nextBrief.xp or 0
    -- Reputation points, and the most valuable reward item (the one you'd pick).
    c.repValue = 0
    for _, rep in ipairs(card.repRewards or {}) do
        if (rep[2] or 0) > 0 then c.repValue = c.repValue + rep[2] end
    end
    c.rewardCopper = 0
    for _, itemId in ipairs((DB:GetQuestRewards(questId)) or {}) do
        local ah, vendor = DB:GetPrice(itemId)
        c.rewardCopper = math.max(c.rewardCopper, ah and ah * 0.95 or 0, vendor or 0)
    end
    return c
end

local function currentPlayerZone()
    local mapId = Compat.GetPlayerMapPosition()
    if not mapId then return nil, nil end
    local areaId = DB.Zones and DB.Zones:UiMapToArea(mapId)
    if not areaId and C_Map and C_Map.GetMapInfo then
        local m = mapId
        for _ = 1, 4 do
            local info = C_Map.GetMapInfo(m)
            if not info or not info.parentMapID or info.parentMapID == 0 then break end
            m = info.parentMapID
            areaId = DB.Zones and DB.Zones:UiMapToArea(m)
            if areaId then
                mapId = m
                break
            end
        end
    end
    return mapId, areaId
end

function Questing:CurrentZoneInfo()
    local mapId, areaId = currentPlayerZone()
    local name = (areaId and Compat.GetAreaName(areaId))
        or (mapId and DB.Zones and DB.Zones:MapName(mapId))
        or (GetRealZoneText and GetRealZoneText())
        or "Current Zone"
    return mapId, areaId, name
end

--- Quest ids worth scoring: the log, plus available quests near the player's level
--- (in the current zone only by default, or all zones when anyZone is enabled).
local function gather(level, settings)
    local list = {}
    for questId, info in pairs(Player.active) do
        list[#list + 1] = { questId, info.isComplete and "complete" or "active" }
    end
    local below = (settings.below or Compat.GetGreenRange(level)) + 5 -- required level trails quest level
    local ids = DB:GetQuestsByLevel(level - below, level)
    if ids then
        local showIgnored = Questing.settings.showIgnored
        local anyZone = Questing.settings.anyZone == true
        local mapId, areaId
        local startingHere
        if not anyZone then
            mapId, areaId = currentPlayerZone()
            if areaId then
                local starts = DB:GetQuestsStartingIn(areaId)
                if starts then
                    startingHere = {}
                    for i = 1, #starts do startingHere[starts[i]] = true end
                end
            end
        end
        local checked = 0
        for i = 1, #ids do
            local id = ids[i]
            if not Player.active[id] and (showIgnored or not Questing:IsIgnored(id)) then
                local inZone = true
                if not anyZone and mapId then
                    local brief = DB:GetQuestBrief(id)
                    local qArea = brief and brief.area
                    inZone = (areaId ~= nil and qArea == areaId)
                        or (qArea ~= nil and qArea > 0 and DB:AreaToUiMap(qArea) == mapId)
                        or (startingHere ~= nil and startingHere[id] == true)
                end
                if inZone then
                    local ok = DB.Quests.Check(DB:GetQuest(id), Player)
                    if ok then list[#list + 1] = { id, "available" } end
                    checked = checked + 1
                    if checked % 25 == 0 then WFC.Jobs:Checkpoint() end
                end
            end
        end
    end
    return list, ids ~= nil
end

local function playerPoint()
    local map, x, y = Compat.GetPlayerMapPosition()
    if not (map and x) then return nil end
    local c, wx, wy = Compat.MapToWorld(map, x, y)
    return { c = c, x = wx or 0, y = wy or 0, map = map, mx = x, my = y }
end

local function travelEstimate()
    local Travel = WFC.Travel
    if Travel and Travel.EstimateTime then
        return function(a, b) return Travel:EstimateTime(a, b) end
    end
end

--- Runs inside the background job.
local function score()
    local level = Player.level
    local inGroup = IsInGroup ~= nil and IsInGroup() == true
    local settings = Questing:ScorerSettings(level, inGroup)
    local pairsList, complete = gather(level, settings)
    local activeAreas = {}
    for questId in pairs(Player.active) do
        local brief = DB:GetQuestBrief(questId)
        if brief and brief.area then activeAreas[brief.area] = (activeAreas[brief.area] or 0) + 1 end
    end
    local candidates = {}
    for i, pair in ipairs(pairsList) do
        local c = Questing:BuildCandidate(pair[1], pair[2])
        if c then
            -- Batching: other active quests share this quest's zone.
            local shared = c.area and activeAreas[c.area] or 0
            c.batched = shared - (pair[2] ~= "available" and 1 or 0) > 0
            candidates[#candidates + 1] = c
        end
        if i % 10 == 0 then WFC.Jobs:Checkpoint() end
    end
    local env = {
        level = level, pos = playerPoint(), greenRange = Compat.GetGreenRange(level),
        settings = settings, travel = travelEstimate(),
        checkpoint = function() WFC.Jobs:Checkpoint() end,
    }
    local rankedNow = Scorer.Rank(candidates, env)
    return { ranked = rankedNow, skip = Scorer.SkipList(candidates, env, rankedNow), complete = complete }
end

local function finished(ok, result)
    if not ok then
        WFC:Log("ERROR", "questing", "scoring failed: " .. tostring(result))
        return
    end
    ranked = result.ranked
    skipped = result.skip or {}
    byId = {}
    for _, entry in ipairs(ranked) do byId[entry.candidate.id] = entry end
    Questing.scoredAt = GetTime()
    Questing.partial = not result.complete -- questsByLevel index still building
    WFC:Fire("WFC_QUESTS_SCORED")
    if dirty then
        dirty = false
        Questing:RequestScore("queued", 0)
    end
end

local function start()
    if not DB.ready then return end
    if WFC.Jobs:IsQueued(JOB) then
        dirty = true
        return
    end
    WFC.Jobs:Add(JOB, score, finished, 40)
end

--- Schedules a re-score after `delay` seconds (default 2), coalescing bursts of events.
function Questing:RequestScore(reason, delay)
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(delay or 2, function()
        timer = nil
        WFC:RunOutOfCombat(JOB, start)
    end)
end

--- Finishes a pending score synchronously (slash commands, specs).
function Questing:ScoreNow()
    start()
    WFC.Jobs:RunNow(JOB)
end

---------------------------------------------------------------------------
-- Public reads
---------------------------------------------------------------------------
function Questing:GetRanked() return ranked end

function Questing:GetEntry(questId) return byId[questId] end

--- Quests in your quest log that are not optimal to do right now, with entry.reasons (worst first).
--- Only accepted quests in Player.active are included.
function Questing:GetSkip()
    local out = {}
    for _, entry in ipairs(skipped) do
        local c = entry.candidate
        if Player.active and Player.active[c.id] and c.state == "active"
            and (self.settings.showIgnored or not self:IsIgnored(c.id)) then
            out[#out + 1] = entry
        end
    end
    return out
end

--- Best quests to pick up next: never ones already in the log (those live on the Active
--- tab) or completed, except repeatables, which compete on score like any other quest.
--- Ignored ones only when "Show ignored" is on.
function Questing:GetNextUp(n)
    local out = {}
    local completed = Player.completed
    local anyZone = self.settings and self.settings.anyZone == true
    local mapId, areaId
    if not anyZone then
        mapId, areaId = currentPlayerZone()
    end
    for _, entry in ipairs(ranked) do
        if #out >= (n or self.settings.nextUpCount) then break end
        local c = entry.candidate
        if c.state == "available" and (c.repeatable or not completed[c.id])
            and (self.settings.showIgnored or not self:IsIgnored(c.id)) then
            local inZone = true
            if not anyZone and mapId then
                local qArea = c.area
                inZone = (areaId ~= nil and qArea == areaId)
                    or (qArea ~= nil and qArea > 0 and DB:AreaToUiMap(qArea) == mapId)
                if not inZone and c.starts then
                    for i = 1, #c.starts do
                        if c.starts[i].map == mapId then
                            inZone = true
                            break
                        end
                    end
                end
            end
            if inZone then
                out[#out + 1] = entry
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Triggers
---------------------------------------------------------------------------
WFC:On("WFC_DB_READY", function()
    Questing:RequestScore("ready", 0)
    Bridge:OnQuestUpdate(function() Questing:RequestScore("questie") end)
end)
WFC:On("WFC_INDEX_READY", function(_, name)
    if name == "questsByLevel" or name == "questsStartingIn" then Questing:RequestScore("index", 0) end
end)
WFC:On("WFC_PLAYER_CHANGED", function(_, field)
    if field == "active" or field == "completed" or field == "level" or field == "professions" then
        Questing:RequestScore(field)
    end
end)
WFC:On("WFC_FLIGHTPOINTS_CHANGED", function() Questing:RequestScore("flightpoints") end)
WFC:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() Questing:RequestScore("zone") end)
