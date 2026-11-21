local _, ns = ...
local WFC = WFC

-- Atlas-style legend: while the world map shows a dungeon's own map, a box in its top-left
-- corner lists the dungeon's level range, bosses, and your quests for it (with progress).
-- Uses the game's own dungeon maps; no images are shipped. QuestieDB has no positions
-- inside dungeons, so bosses are listed rather than pinned.

local Dungeons = ns.Dungeons
local DB, Compat, Colors, Player = WFC.DB, WFC.Compat, WFC.Colors, WFC.Player
local P = Colors.palette

local DungeonMap = {}
ns.DungeonMap = DungeonMap

local MAX_BOSSES, MAX_QUESTS = 10, 8

--- { title, lines = {...} } for a dungeon (pure apart from DB reads; used by specs).
function DungeonMap.Lines(dungeonId)
    local card = DB:GetDungeon(dungeonId)
    if not card then return nil end
    local d = DB:GetDungeonDetails(dungeonId)
    local lines = {}
    if d and #d.bosses > 0 then
        lines[#lines + 1] = Colors.Wrap("Bosses", { code = "|cffffd100" })
        for i, npc in ipairs(d.bosses) do
            if i > MAX_BOSSES then
                lines[#lines + 1] = Colors.Wrap(("  +%d more"):format(#d.bosses - MAX_BOSSES), P.TEXT_MUTED)
                break
            end
            local level = npc.maxLevel or npc.minLevel
            lines[#lines + 1] = "  " .. Colors.Wrap(npc.name, Colors.ForLevel(level, Player.level))
                .. Colors.Wrap("  " .. tostring(level or "?"), P.TEXT_MUTED)
        end
    end
    local inLog, available = {}, 0
    for _, questId in ipairs(DB:GetDungeonQuests(dungeonId) or {}) do
        local group = Dungeons.Classify(questId)
        if group == "log" then inLog[#inLog + 1] = questId elseif group == "available" then available = available + 1 end
    end
    if #inLog > 0 then
        lines[#lines + 1] = Colors.Wrap("Your quests", { code = "|cffffd100" })
        for i, questId in ipairs(inLog) do
            if i > MAX_QUESTS then break end
            local brief = DB:GetQuestBrief(questId)
            lines[#lines + 1] = "  " .. ns.Panel.QuestName(brief or { id = questId }, true)
            for _, o in ipairs(Compat.GetQuestObjectives(questId)) do
                if not o.finished and o.text and o.text ~= "" then
                    lines[#lines + 1] = "    - " .. Colors.Progress(o.have, o.need) .. o.text .. "|r"
                end
            end
        end
    end
    if available > 0 then
        lines[#lines + 1] = Colors.Wrap(("%d more quest%s to pick up first (Dungeons tab)"):format(available,
            available == 1 and "" or "s"), P.TEXT_MUTED)
    end
    return { title = Dungeons.Title(card, d), lines = lines }
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local box, watcher, title, body
local shownFor

local function create()
    box = CreateFrame("Frame", "WFC_DungeonLegend", WorldMapFrame, "BackdropTemplate")
    if box.SetBackdrop then
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        box:SetBackdropColor(0.086, 0.094, 0.11, 0.92)
        box:SetBackdropBorderColor(0.23, 0.25, 0.28, 1)
    end
    box:SetPoint("TOPLEFT", WorldMapFrame.ScrollContainer or WorldMapFrame, "TOPLEFT", 8, -8)
    box:SetFrameLevel((WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer:GetFrameLevel() or 1) + 60)
    box:SetWidth(230)
    title = box:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(WFC.Fonts:Get("subheader"))
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetPoint("RIGHT", -8, 0)
    title:SetJustifyH("LEFT")
    body = box:CreateFontString(nil, "OVERLAY")
    body:SetFontObject(WFC.Fonts:Get("small"))
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    body:SetPoint("RIGHT", -8, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    box:Hide()
    DungeonMap.box = box
end

--- Shows the legend for the displayed map when it is a dungeon map; hides it otherwise.
function DungeonMap:Update()
    if not box then return end
    local dungeonId = DB.Dungeons:ForMap(WorldMapFrame:GetMapID())
    local content = dungeonId and DungeonMap.Lines(dungeonId)
    if not content then
        box:Hide()
        shownFor = nil
        return
    end
    title:SetText(content.title)
    body:SetText(table.concat(content.lines, "\n"))
    box:SetHeight(30 + 13 * #content.lines)
    box:Show()
    shownFor = dungeonId
    self.shownFor = dungeonId
end

local lastMap, elapsedSince = nil, 0
local function onUpdate(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.25 then return end
    elapsedSince = 0
    local mapId = WorldMapFrame:GetMapID()
    if mapId ~= lastMap then
        lastMap = mapId
        DungeonMap:Update()
    end
end

local function init()
    if box or not WorldMapFrame then return end
    create()
    -- Map changes are polled (4x a second) only while the map is open.
    watcher = CreateFrame("Frame", nil, WorldMapFrame)
    WorldMapFrame:HookScript("OnShow", function()
        lastMap = nil
        watcher:SetScript("OnUpdate", onUpdate)
    end)
    WorldMapFrame:HookScript("OnHide", function() watcher:SetScript("OnUpdate", nil) end)
    if WorldMapFrame:IsShown() then watcher:SetScript("OnUpdate", onUpdate) end
end

WFC:RegisterEvent("PLAYER_LOGIN", init)
WFC:RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then init() end
end)
WFC:On("WFC_PLAYER_CHANGED", function()
    if shownFor then DungeonMap:Update() end
end)
