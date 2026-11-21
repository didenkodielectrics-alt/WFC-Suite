local _, ns = ...
local WFC = ns.WFC

-- Quests. Two memoized views per quest:
--   Brief(id) -> small record for lists/scoring (6 QuestieDB fields)
--   Card(id)  -> everything, normalized (objectives, starters, chains, rewards...)
-- Plus the availability check (pure; also used by the Dungeon tab for reasons).

local Source = WFC.DB.Source
local Data = ns.Data
local Util = WFC.Util
local Nz, EMPTY = Util.Nz, Util.EMPTY

local Quests = WFC.DB:NewSection("Quests")

local Q                     -- LibQuestieDB.Quest, bound in Init
local xpDb = EMPTY          -- [questId] = { level, xp }
local factionMasks = EMPTY  -- { Alliance = mask, Horde = mask }
local briefs, cards, tags = {}, {}, {}
local positions = Util.WeakCache()

local REPEATABLE = 1 -- specialFlags bit

function Quests:Init()
    Q = Source.Q
    local questXP = Source:Support("QuestXP")
    xpDb = questXP and questXP.db or EMPTY
    factionMasks = Source:FactionRaceMasks()
end

function Quests:Invalidate()
    briefs, cards, tags = {}, {}, {}
    positions = Util.WeakCache()
end

local function sideOf(raceMask)
    if not raceMask or raceMask == 0 then return "B" end
    local a = factionMasks.Alliance and Util.MaskIntersects(raceMask, factionMasks.Alliance)
    local h = factionMasks.Horde and Util.MaskIntersects(raceMask, factionMasks.Horde)
    if a and not h then return "A" end
    if h and not a then return "H" end
    return "B"
end

local function applyCorrections(record, id)
    local fix = Data.Corrections.quest[id]
    if fix then
        for k, v in pairs(fix) do record[k] = v end
    end
    return record
end

---------------------------------------------------------------------------
-- Brief
---------------------------------------------------------------------------
--- { id, name, level, minLevel, side, area, dungeon, repeatable, xp, isNew } or nil.
function Quests:Brief(id)
    if type(id) ~= "number" then return nil end
    local b = briefs[id]
    if b ~= nil then return b or nil end
    if not (Q and Q.Exists(id)) then
        briefs[id] = false
        return nil
    end
    local zoneOrSort = Q.zoneOrSort(id)
    local area = zoneOrSort > 0 and zoneOrSort or nil
    local level = Q.questLevel(id)
    local xp = xpDb[id]
    b = applyCorrections({
        id = id,
        name = Q.name(id),
        level = level ~= 0 and level or nil, -- -1 = scales with the player
        minLevel = Nz(Q.requiredLevel(id)),
        side = sideOf(Q.requiredRaces(id)),
        area = area,
        sort = zoneOrSort < 0 and zoneOrSort or nil,
        dungeon = WFC.DB.Zones:DungeonForArea(area),
        repeatable = Util.HasBit(Q.specialFlags(id), REPEATABLE),
        xp = xp and xp[2] or nil,
    }, id)
    b.isNew = WFC.DB.New:Evaluate("quest", id, b.area, true)
    briefs[id] = b
    return b
end

---------------------------------------------------------------------------
-- Card
---------------------------------------------------------------------------
local CARD_FIELDS = {
    "startedBy", "finishedBy", "requiredMaxLevel", "requiredRaces", "requiredClasses",
    "objectivesText", "triggerEnd", "objectives", "sourceItemId", "preQuestGroup",
    "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo", "requiredSkill",
    "requiredMinRep", "requiredMaxRep", "requiredSourceItems", "nextQuestInChain",
    "questFlags", "parentQuest", "reputationReward", "breadcrumbForQuestId", "breadcrumbs",
    "requiredSpell", "availableUntilCompleted", "availableStartingWith", "disabledByQuest",
}

local function normalizeObjectives(raw, triggerEnd)
    local list = {}
    local groups = raw or EMPTY
    local function each(group, kind)
        local rows = groups[group]
        if not rows then return end
        for i = 1, #rows do
            local row = rows[i]
            list[#list + 1] = { type = kind, id = row[1], text = row[2] }
        end
    end
    each(1, "kill")
    each(2, "object")
    each(3, "item")
    local rep = groups[4]
    if rep and rep[1] then
        list[#list + 1] = { type = "rep", id = rep[1], value = rep[2] }
    end
    local credits = groups[5]
    if credits then
        for i = 1, #credits do
            local row = credits[i]
            list[#list + 1] = { type = "killcredit", ids = row[1], id = row[2], text = row[3] }
        end
    end
    local spells = groups[6]
    if spells then
        for i = 1, #spells do
            local row = spells[i]
            list[#list + 1] = { type = "spell", id = row[1], text = row[2], item = Nz(row[3]) }
        end
    end
    if triggerEnd and triggerEnd[1] then
        list[#list + 1] = { type = "event", text = triggerEnd[1], points = triggerEnd[2] }
    end
    return list
end

--- Full normalized quest record or nil. Shares the Brief's fields.
function Quests:Card(id)
    if type(id) ~= "number" then return nil end
    local c = cards[id]
    if c ~= nil then return c or nil end
    local b = self:Brief(id)
    if not b then
        cards[id] = false
        return nil
    end
    local v = Q.GetAll(id, CARD_FIELDS)
    local startedBy, finishedBy = v[1] or EMPTY, v[2] or EMPTY
    local skill, minRep, maxRep = v[15], v[16], v[17]
    c = {}
    for k, val in pairs(b) do c[k] = val end
    c.maxLevel = Nz(v[3])
    c.raceMask = Nz(v[4])
    c.classMask = Nz(v[5])
    c.description = v[6]
    c.objectives = normalizeObjectives(v[8], v[7])
    c.starts = { npc = startedBy[1], object = startedBy[2], item = startedBy[3] and startedBy[3][1] }
    c.ends = { npc = finishedBy[1], object = finishedBy[2] }
    c.sourceItem = Nz(v[9])
    c.prereqAll = v[10]
    c.prereqAny = v[11]
    c.children = v[12]
    c.groupWith = v[13]
    c.exclusive = v[14]
    c.requiredSkill = skill and { id = skill[1], value = skill[2] } or nil
    c.requiredMinRep = minRep and { id = minRep[1], value = minRep[2] } or nil
    c.requiredMaxRep = maxRep and { id = maxRep[1], value = maxRep[2] } or nil
    c.requiredItems = v[18]
    c.next = Nz(v[19])
    c.questFlags = v[20]
    c.parent = Nz(v[21])
    c.repRewards = v[22]
    c.breadcrumbFor = Nz(v[23])
    c.breadcrumbs = v[24]
    c.requiredSpell = Nz(v[25])
    c.availableUntilCompleted = Nz(v[26])
    c.availableStartingWith = Nz(v[27])
    c.disabledBy = Nz(v[28])
    cards[id] = applyCorrections(c, id)
    return c
end

--- Client quest tag { id, name, isElite } (Elite, Dungeon, Raid, ...) or nil. Cached.
function Quests:Tag(id)
    local t = tags[id]
    if t == nil then
        local info = WFC.Compat.GetQuestTagInfo(id)
        t = info and { id = info.tagID, name = info.tagName, isElite = info.isElite == true } or false
        tags[id] = t
    end
    return t or nil
end

---------------------------------------------------------------------------
-- Availability (pure: card + player snapshot -> ok, reason, detail)
---------------------------------------------------------------------------
-- Reasons: "unknown" "completed" "active" "level" "maxlevel" "side" "race" "class"
--          "prereq" "exclusive" "next" "breadcrumb" "parent" "skill" "until" "startingwith" "disabled"

local function anyDoneOrActive(ids, player)
    if not ids then return nil end
    for i = 1, #ids do
        local q = ids[i]
        if player.completed[q] or player.active[q] then return q end
    end
end

--- opts.levelSlack: treat quests up to N levels above the player as level-OK (for "soon" lists).
function Quests.Check(card, player, opts)
    if not card then return false, "unknown" end
    local id = card.id
    local slack = opts and opts.levelSlack or 0
    if player.active[id] then return false, "active" end
    if player.completed[id] and not card.repeatable then return false, "completed" end
    if card.minLevel and player.level + slack < card.minLevel then return false, "level", card.minLevel end
    if card.maxLevel and player.level > card.maxLevel then return false, "maxlevel", card.maxLevel end
    if card.side ~= "B" and player.side and card.side ~= player.side then return false, "side", card.side end
    if card.raceMask and player.raceMask and not Util.HasBit(card.raceMask, player.raceMask) then
        return false, "race"
    end
    if card.classMask and player.classMask and not Util.HasBit(card.classMask, player.classMask) then
        return false, "class"
    end
    local all = card.prereqAll
    if all then
        for i = 1, #all do
            if not player.completed[all[i]] then return false, "prereq", all[i] end
        end
    end
    local any = card.prereqAny
    if any and #any > 0 then
        local met = false
        for i = 1, #any do
            if player.completed[any[i]] then met = true break end
        end
        if not met then return false, "prereq", any[1] end
    end
    local blocker = anyDoneOrActive(card.exclusive, player)
    if blocker then return false, "exclusive", blocker end
    if card.next and (player.completed[card.next] or player.active[card.next]) then
        return false, "next", card.next
    end
    if card.breadcrumbFor and (player.completed[card.breadcrumbFor] or player.active[card.breadcrumbFor]) then
        return false, "breadcrumb", card.breadcrumbFor
    end
    if card.parent and not player.active[card.parent] then return false, "parent", card.parent end
    if card.availableUntilCompleted and player.completed[card.availableUntilCompleted] then
        return false, "until", card.availableUntilCompleted
    end
    local startWith = card.availableStartingWith
    if startWith and not (player.completed[startWith] or player.active[startWith]) then
        return false, "startingwith", startWith
    end
    if card.disabledBy and player.active[card.disabledBy] then return false, "disabled", card.disabledBy end
    local skill = card.requiredSkill
    if skill and skill.id and skill.id ~= 0 then
        local prof = player.professions[skill.id]
        if not prof or (prof.rank or 0) < (skill.value or 0) then return false, "skill", skill.id end
    end
    return true
end

function Quests:IsAvailable(id, opts)
    return Quests.Check(self:Card(id), WFC.Player, opts)
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
local function addPoints(out, role, kind, entityId, spawns)
    if not spawns then return end
    for uiMap, points in pairs(spawns) do
        -- Skip `instances` (the dungeon AreaIDs an NPC lives in): those have no map position.
        if type(uiMap) == "number" then
            for i = 1, #points do
                out[#out + 1] = { role = role, kind = kind, id = entityId, map = uiMap, x = points[i][1], y = points[i][2] }
            end
        end
    end
end

--- Flat list of { role = "start"|"objective"|"end", kind = "npc"|"object", id, map, x, y }.
function Quests:Positions(id)
    local list = positions[id]
    if list then return list end
    local c = self:Card(id)
    if not c then return EMPTY end
    local Npcs, Objects = WFC.DB.Npcs, WFC.DB.Objects
    list = {}
    local function entities(role, ids, kind, section)
        if not ids then return end
        for i = 1, #ids do addPoints(list, role, kind, ids[i], section:Spawns(ids[i])) end
    end
    entities("start", c.starts.npc, "npc", Npcs)
    entities("start", c.starts.object, "object", Objects)
    for i = 1, #c.objectives do
        local o = c.objectives[i]
        if o.type == "kill" then
            entities("objective", { o.id }, "npc", Npcs)
        elseif o.type == "object" then
            entities("objective", { o.id }, "object", Objects)
        elseif o.type == "item" then
            local item = WFC.DB.Items:Card(o.id)
            entities("objective", item.dropNpcs, "npc", Npcs)
            entities("objective", item.dropObjects, "object", Objects)
        end
    end
    entities("end", c.ends.npc, "npc", Npcs)
    entities("end", c.ends.object, "object", Objects)
    positions[id] = list
    return list
end

function Quests:Stats()
    return { briefs = Util.Count(briefs), cards = Util.Count(cards), total = Q and #Q.GetAllIds() or 0 }
end
