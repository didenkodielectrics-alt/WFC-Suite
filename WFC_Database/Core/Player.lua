local _, ns = ...
local WFC = ns.WFC

-- Live snapshot of the current character. Never persisted as a source of truth:
-- it is rebuilt from client APIs at login (CoreRules R8). Other modules read
-- WFC.Player.* directly; it fires WFC_PLAYER_CHANGED(field) when something changes.

local Compat = WFC.Compat
local Util = WFC.Util

local Player = {
    level = 1,
    side = nil,         -- "A" | "H"
    faction = nil,      -- "Alliance" | "Horde"
    raceId = nil,
    raceFile = nil,
    raceMask = nil,     -- QuestieDB race bit (may exceed 2^32 for Skyborne)
    classId = nil,
    classFile = nil,
    classMask = nil,
    completed = {},     -- [questId] = true
    active = {},        -- [questId] = { title, level, isComplete }
    professions = {},   -- [skillLineId] = { name, rank, max }
    charKey = nil,
}
WFC.Player = Player

local function changed(field)
    WFC:Fire("WFC_PLAYER_CHANGED", field)
end

function Player:RefreshIdentity()
    self.level = UnitLevel("player")
    self.faction = UnitFactionGroup("player")
    self.side = (self.faction == "Alliance" and "A") or (self.faction == "Horde" and "H") or nil
    local _, raceFile, raceId = UnitRace("player")
    self.raceFile, self.raceId = raceFile, raceId
    local _, classFile, classId = UnitClass("player")
    self.classFile, self.classId = classFile, classId
    self.charKey = Util.CharKey()

    local Source = WFC.DB and WFC.DB.Source
    -- Never guess a race bit from the race ID (Skyborne uses bits 32/33).
    self.raceMask = Source and Source.available and Source:RaceMask(raceId) or nil
    self.classMask = (Source and Source.available and Source:ClassMask(classFile))
        or (classId and 2 ^ (classId - 1)) or nil
    changed("identity")
end

function Player:RefreshCompleted()
    self.completed = Compat.GetCompletedQuests()
    changed("completed")
end

local lastActiveHash

function Player:RefreshQuestLog()
    local active = {}
    local log = Compat.GetQuestLog()
    local parts = {}
    for i = 1, #log do
        local q = log[i]
        active[q.questId] = q
        local objs = Compat.GetQuestObjectives(q.questId)
        local objSum = 0
        for j = 1, #objs do
            objSum = objSum * 31 + (objs[j].have or 0)
        end
        parts[#parts + 1] = q.questId .. ":" .. (q.isComplete and "1" or "0") .. ":" .. objSum
    end
    self.active = active
    table.sort(parts)
    local hash = table.concat(parts, ",")
    if hash ~= lastActiveHash then
        lastActiveHash = hash
        changed("active")
    end
end

function Player:RefreshProfessions()
    self.professions = Compat.GetProfessions()
    changed("professions")
end

function Player:RefreshAll()
    self:RefreshIdentity()
    self:RefreshCompleted()
    self:RefreshQuestLog()
    self:RefreshProfessions()
end

function Player:IsCompleted(questId)
    return self.completed[questId] == true
end

function Player:IsActive(questId)
    return self.active[questId] ~= nil
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local questLogTimer

local function scheduleQuestLogRefresh()
    if questLogTimer then questLogTimer:Cancel() end
    questLogTimer = C_Timer.NewTimer(0.5, function()
        questLogTimer = nil
        Player:RefreshQuestLog()
    end)
end

WFC:RegisterEvent("PLAYER_LEVEL_UP", function(_, newLevel)
    Player.level = newLevel or UnitLevel("player")
    changed("level")
end)

WFC:RegisterEvent("QUEST_TURNED_IN", function(_, questId)
    if questId then
        Player.completed[questId] = true
        Player.active[questId] = nil
        changed("completed")
    end
end)

WFC:RegisterEvent("QUEST_ACCEPTED", scheduleQuestLogRefresh)
WFC:RegisterEvent("QUEST_REMOVED", scheduleQuestLogRefresh)
WFC:RegisterEvent("QUEST_LOG_UPDATE", scheduleQuestLogRefresh)

WFC:RegisterEvent("SKILL_LINES_CHANGED", function()
    Player:RefreshProfessions()
end)
