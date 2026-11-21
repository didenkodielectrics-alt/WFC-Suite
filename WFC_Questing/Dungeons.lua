local _, ns = ...
local WFC = WFC

-- The Dungeons tab (plan.md §4.5, design.md §4.5) plus its Atlas-style pieces: pick a
-- dungeon, see every quest for it grouped by status, its bosses, its level range,
-- open its own map, or path to the entrance.

local Questing = ns.Questing
local DB, Compat, Colors, Player = WFC.DB, WFC.Compat, WFC.Colors, WFC.Player
local P = Colors.palette

local Dungeons = {}
ns.Dungeons = Dungeons

Dungeons.GROUPS = {
    { key = "log", label = "In log" },
    { key = "available", label = "Available" },
    { key = "prereq", label = "Needs prerequisite" },
    { key = "ineligible", label = "Not eligible" },
    { key = "bosses", label = "Bosses" },
}
Dungeons.collapsed = { ineligible = true }
Dungeons.selected = nil   -- dungeon id
Dungeons.userPicked = false

local REASONS = {
    level = function(detail) return "Requires level " .. tostring(detail) end,
    maxlevel = function() return "Too high level" end,
    side = function(detail) return detail == "H" and "Horde only" or "Alliance only" end,
    race = function() return "Other races only" end,
    class = function() return "Other classes only" end,
    completed = function() return "Completed" end,
    exclusive = function() return "Chose another quest" end,
    ["next"] = function() return "Already moved on" end,
    breadcrumb = function() return "Already moved on" end,
    parent = function() return "Part of another quest" end,
    skill = function() return "Needs a profession" end,
}

--- Group key and reason text for a quest, from the availability check.
function Dungeons.Classify(questId)
    if Player.active[questId] then return "log" end
    local card = DB:GetQuest(questId)
    local ok, reason, detail = DB.Quests.Check(card, Player)
    if ok then return "available" end
    if reason == "prereq" then return "prereq", nil, detail end
    local text = REASONS[reason]
    return "ineligible", text and text(detail) or "Not available"
end

---------------------------------------------------------------------------
-- Dungeon list and default pick
---------------------------------------------------------------------------
--- Dungeon cards with details: { card, details|nil } sorted by level (unknown levels last).
function Dungeons.List()
    local list = {}
    for _, card in ipairs(DB:GetDungeons()) do
        list[#list + 1] = { card = card, details = (DB:GetDungeonDetails(card.id)) }
    end
    table.sort(list, function(a, b)
        local la = a.details and a.details.minLevel or 999
        local lb = b.details and b.details.minLevel or 999
        if la ~= lb then return la < lb end
        return a.card.name < b.card.name
    end)
    return list
end

--- The dungeon that best fits the player's level: inside its range, else the next one up.
function Dungeons.BestFit(level)
    local inside, above
    for _, item in ipairs(Dungeons.List()) do
        local d = item.details
        if d and d.minLevel and d.maxLevel then
            if level >= d.minLevel and level <= d.maxLevel then
                if not inside or (d.maxLevel - d.minLevel) < (inside.maxLevel - inside.minLevel) then inside = d end
            elseif d.minLevel > level and (not above or d.minLevel < above.minLevel) then
                above = d
            end
        end
    end
    local pick = inside or above
    if pick then return pick.id end
    local first = DB:GetDungeons()[1]
    return first and first.id
end

function Dungeons:Selected()
    if not self.selected or (not self.userPicked and DB:GetDungeonDetails(self.selected) == nil) then
        self.selected = Dungeons.BestFit(Player.level)
    end
    return self.selected
end

function Dungeons:Select(dungeonId)
    self.selected, self.userPicked = dungeonId, true
    ns.Panel:Refresh()
end

--- "17–26" coloured by the level difference to the range's midpoint, or "".
function Dungeons.LevelChip(d)
    if not (d and d.minLevel and d.maxLevel) then return "" end
    local mid = math.floor((d.minLevel + d.maxLevel) / 2)
    local text = d.minLevel == d.maxLevel and tostring(d.minLevel) or (d.minLevel .. "-" .. d.maxLevel)
    return Colors.Wrap(text, Colors.ForLevel(mid, Player.level))
end

function Dungeons.Title(card, d)
    local chip = Dungeons.LevelChip(d)
    return card.name .. (chip ~= "" and ("  " .. chip) or "") .. (card.isNew and WFC:NewTag("  ") or "")
end

---------------------------------------------------------------------------
-- Rows for the panel
---------------------------------------------------------------------------
local function startedAt(card)
    local npcId = card and card.starts.npc and card.starts.npc[1]
    local npc = npcId and DB:GetNpc(npcId)
    if npc then
        local zone = Compat.GetAreaName(npc.area)
        return npc.name .. (zone and (", " .. zone) or "")
    end
    local objectId = card and card.starts.object and card.starts.object[1]
    local object = objectId and DB:GetObject(objectId)
    return object and object.name or nil
end

local function questRow(questId, group, reason, prereq)
    local card = DB:GetQuest(questId)
    if not card then return nil end
    local c = {}
    for k, v in pairs(card) do c[k] = v end
    c.state = Player.active[questId] and (Player.active[questId].isComplete and "complete" or "active") or "available"
    local sub = {}
    if group == "log" then
        for _, o in ipairs(Compat.GetQuestObjectives(questId)) do
            if o.text and o.text ~= "" then sub[#sub + 1] = "- " .. Colors.Progress(o.have, o.need) .. o.text .. "|r" end
        end
        if c.state == "complete" then sub[#sub + 1] = Colors.Wrap("ready to turn in", P.TEXT_MUTED) end
    elseif group == "available" then
        local where = startedAt(card)
        sub[1] = Colors.Wrap("Pick up: " .. (where or "unknown") .. (card.xp and (" · " .. card.xp .. " xp") or ""), P.TEXT_MUTED)
    elseif group == "prereq" then
        local pre = DB:GetQuestBrief(prereq)
        local zone = pre and Compat.GetAreaName(pre.area)
        sub[1] = Colors.Wrap("Do ", P.TEXT_MUTED) .. (pre and ns.Panel.QuestName(pre, true) or ("quest " .. tostring(prereq)))
            .. Colors.Wrap(" first" .. (zone and (" (" .. zone .. ")") or ""), P.TEXT_MUTED)
    else
        sub[1] = Colors.Wrap(reason or "Not available", P.TEXT_MUTED)
    end
    local icon
    if group == "log" then
        icon = ns.Bridge:Icon(c.state == "complete" and "complete" or "incomplete")
    elseif group == "available" then
        icon = ns.Bridge:Icon(c.repeatable and "repeatable" or "available")
    else
        icon = ns.Bridge:Icon("available_gray")
    end
    return {
        kind = "quest", questId = questId, icon = icon, title = ns.Panel.QuestName(c, true), right = "",
        sub = sub, alpha = group == "ineligible" and 0.5 or 1, entry = { candidate = c, minutes = 0, score = 0 },
        prereq = prereq,
    }
end

local function bossRow(npc)
    local level = npc.maxLevel or npc.minLevel
    local text = Colors.Wrap(npc.name, Colors.ForLevel(level, Player.level))
    return {
        kind = "boss", title = text .. (npc.isNew and WFC:NewTag("  ") or ""),
        right = Colors.Wrap("Lv " .. tostring(level or "?"), P.TEXT_MUTED), sub = {},
        icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    }
end

--- Display rows for the selected dungeon: headers, quest rows and boss rows, plus a summary.
function Dungeons:Rows()
    local id = self:Selected()
    local rows = {}
    if not id then return rows, "No dungeons known." end
    local d, state = DB:GetDungeonDetails(id)
    local questIds = DB:GetDungeonQuests(id)
    if not questIds or state == "pending" then return rows, "Indexing dungeons…" end
    local groups = { log = {}, available = {}, prereq = {}, ineligible = {}, bosses = {} }
    local xp, availableCount = 0, 0
    for _, questId in ipairs(questIds) do
        local group, reason, prereq = Dungeons.Classify(questId)
        local row = questRow(questId, group, reason, prereq)
        if row then
            table.insert(groups[group], row)
            if group == "available" then
                availableCount = availableCount + 1
                xp = xp + (row.entry.candidate.xp or 0)
            end
        end
    end
    for _, npc in ipairs(d and d.bosses or {}) do table.insert(groups.bosses, bossRow(npc)) end
    for _, g in ipairs(Dungeons.GROUPS) do
        local list = groups[g.key]
        if #list > 0 then
            table.sort(list, function(a, b)
                local la = a.entry and (a.entry.candidate.level or 0) or 0
                local lb = b.entry and (b.entry.candidate.level or 0) or 0
                if la ~= lb then return la < lb end
                return tostring(a.title) < tostring(b.title)
            end)
            local collapsed = self.collapsed[g.key]
            rows[#rows + 1] = { kind = "header", group = g.key, title = g.label .. " (" .. #list .. ")", collapsed = collapsed }
            if not collapsed then
                for _, r in ipairs(list) do rows[#rows + 1] = r end
            end
        end
    end
    local summary = ("%d quest%s · %d xp available"):format(availableCount, availableCount == 1 and "" or "s", xp)
    return rows, summary
end

function Dungeons:Toggle(group)
    self.collapsed[group] = not self.collapsed[group]
    ns.Panel:Refresh()
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
--- The Dungeon Map window (Blizzard's tiles from the install), else the client's own dungeon
--- map if it has one, else the entrance zone with a pin.
function Dungeons:ShowMap(dungeonId)
    dungeonId = dungeonId or self:Selected()
    local d = DB:GetDungeonDetails(dungeonId)
    local card = DB:GetDungeon(dungeonId)
    if not card then return false end
    if ns.Atlas:Open(dungeonId) then return true end
    WFC:RunOutOfCombat("questing:dungeonMap", function()
        if d and d.map then
            Compat.OpenWorldMap(d.map)
        elseif card.entrances[1] then
            local e = card.entrances[1]
            Compat.OpenWorldMap(e.map)
            Compat.SetWaypoint(e.map, e.x, e.y, card.name .. " entrance")
        end
    end)
    return true
end

function Dungeons:PathToEntrance(dungeonId)
    dungeonId = dungeonId or self:Selected()
    local Travel = WFC.Travel
    if Travel and Travel.PathToDungeon then return Travel:PathToDungeon(dungeonId) end
    local card = DB:GetDungeon(dungeonId)
    local e = card and card.entrances[1]
    if not e then
        WFC:Print("no entrance known for that dungeon")
        return false
    end
    WFC:RunOutOfCombat("questing:entrance", function()
        Compat.OpenWorldMap(e.map)
        Compat.SetWaypoint(e.map, e.x, e.y, card.name .. " entrance")
    end)
    return true
end

--- Selector menu items: every dungeon with its level chip, the selected one marked.
function Dungeons:MenuItems()
    local items = { { title = "Dungeons" } }
    local selected = self:Selected()
    for _, item in ipairs(Dungeons.List()) do
        local card = item.card
        local isSel = (card.id == selected)
        items[#items + 1] = {
            text = (isSel and "> " or "") .. Dungeons.Title(card, item.details),
            selected = isSel,
            fn = function() Dungeons:Select(card.id) end,
        }
    end
    return items
end

WFC:On("WFC_INDEX_READY", function(_, name)
    if name == "npcsByArea" or name == "questsByDungeon" then
        if not Dungeons.userPicked then Dungeons.selected = nil end
        if ns.Panel.Refresh then ns.Panel:Refresh() end
    end
end)
WFC:On("WFC_PLAYER_CHANGED", function(_, field)
    if field == "level" and not Dungeons.userPicked then Dungeons.selected = nil end
end)
