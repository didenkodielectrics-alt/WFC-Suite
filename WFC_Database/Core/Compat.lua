local _, ns = ...
local WFC = ns.WFC

-- The ONLY file that probes client APIs and picks fallbacks (CoreRules R2/R3).
-- Everything else calls WFC.Compat.X, so a Forever API change is a one-file fix.
local Compat = {}
WFC.Compat = Compat

local _, build, _, interface = GetBuildInfo()
Compat.interface = interface or 0
Compat.build = build

function Compat.IsForever()
    return Compat.interface >= 16000 and Compat.interface < 17000
end

---------------------------------------------------------------------------
-- Secret values (Midnight model, CoreRules R4)
---------------------------------------------------------------------------
local issecretvalue = issecretvalue

function Compat.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

---------------------------------------------------------------------------
-- AddOns
---------------------------------------------------------------------------
local C_AddOns = C_AddOns
Compat.GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
Compat.IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local C_Item = C_Item
local legacyGetItemInfo = GetItemInfo

function Compat.GetItemInfo(itemId)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemId)
    elseif legacyGetItemInfo then
        return legacyGetItemInfo(itemId)
    end
end

function Compat.GetItemIcon(itemId)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemId) end
    if GetItemIcon then return GetItemIcon(itemId) end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function Compat.RequestItem(itemId)
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemId)
    end
end

-- Forever fires ITEM_DATA_LOAD_RESULT(itemID, success); older clients GET_ITEM_INFO_RECEIVED.
Compat.ITEM_LOAD_EVENT = (C_Item and C_Item.RequestLoadItemDataByID) and "ITEM_DATA_LOAD_RESULT"
    or "GET_ITEM_INFO_RECEIVED"

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local C_QuestLog = C_QuestLog

--- Returns a set {[questId] = true} of every completed quest.
function Compat.GetCompletedQuests()
    local set = {}
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        local list = C_QuestLog.GetAllCompletedQuestIDs()
        if list then
            for i = 1, #list do set[list[i]] = true end
        end
    elseif GetQuestsCompleted then
        GetQuestsCompleted(set)
    end
    return set
end

function Compat.IsQuestCompleted(questId)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questId)
    end
    return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(questId) or false
end

--- Returns a list of {questId, title, level, isComplete} for quests in the log.
function Compat.GetQuestLog()
    local quests = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and info.questID > 0 then
                quests[#quests + 1] = {
                    questId = info.questID,
                    title = info.title,
                    level = info.level,
                    isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false,
                }
            end
        end
    elseif GetNumQuestLogEntries then
        for i = 1, GetNumQuestLogEntries() do
            local title, level, _, isHeader, _, isComplete, _, questId = GetQuestLogTitle(i)
            if not isHeader and questId then
                quests[#quests + 1] = { questId = questId, title = title, level = level, isComplete = isComplete == 1 }
            end
        end
    end
    return quests
end

function Compat.GetQuestTagInfo(questId)
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        return C_QuestLog.GetQuestTagInfo(questId)
    end
end

--- Client-side difficulty category (Enum.RelativeContentDifficulty) or nil.
function Compat.GetQuestDifficulty(questId)
    if C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer then
        return C_PlayerInfo.GetContentDifficultyQuestForPlayer(questId)
    end
end

--- How many levels below the player a quest stays green.
function Compat.GetGreenRange(playerLevel)
    if C_QuestLog and C_QuestLog.GetTrivialRange then
        local range = C_QuestLog.GetTrivialRange()
        if type(range) == "number" then return range end
    end
    if GetQuestGreenRange then
        return GetQuestGreenRange()
    end
    -- Vanilla grey-level formula.
    local level = playerLevel or UnitLevel("player")
    local grey
    if level <= 5 then
        grey = 0
    elseif level <= 39 then
        grey = level - 5 - math.floor(level / 10)
    else
        grey = level - 1 - math.floor(level / 5)
    end
    return level - grey - 1
end

--- Client objectives of a quest in the log: { {text, type, have, need, finished}, ... }.
function Compat.GetQuestObjectives(questId)
    local list = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local objectives = C_QuestLog.GetQuestObjectives(questId)
        if objectives then
            for i = 1, #objectives do
                local o = objectives[i]
                list[i] = {
                    text = o.text, type = o.type, finished = o.finished == true,
                    have = o.numFulfilled, need = o.numRequired,
                }
            end
        end
    end
    return list
end

--- Opens a quest from the log in the native quest details (CoreRules R11). Returns true on success.
function Compat.OpenQuestInLog(questId)
    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        if C_QuestLog.GetLogIndexForQuestID and not C_QuestLog.GetLogIndexForQuestID(questId) then return false end
        C_QuestLog.SetSelectedQuest(questId)
        if QuestMapFrame_OpenToQuestDetails then
            QuestMapFrame_OpenToQuestDetails(questId)
        elseif QuestMapFrame_ShowQuestDetails then
            QuestMapFrame_ShowQuestDetails(questId)
        end
        return true
    elseif GetQuestLogIndexByID and SelectQuestLogEntry then
        local index = GetQuestLogIndexByID(questId)
        if not index or index == 0 then return false end
        SelectQuestLogEntry(index)
        if ShowUIPanel and QuestLogFrame then ShowUIPanel(QuestLogFrame) end
        return true
    end
    return false
end

function Compat.IsQuestWatched(questId)
    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        return C_QuestLog.GetQuestWatchType(questId) ~= nil
    elseif GetQuestLogIndexByID and IsQuestWatched then
        local index = GetQuestLogIndexByID(questId)
        return index ~= nil and index > 0 and IsQuestWatched(index) == true
    end
    return false
end

--- Adds (on = true) or removes a quest watch. Adding is idempotent on Forever.
function Compat.SetQuestWatched(questId, on)
    if C_QuestLog and C_QuestLog.AddQuestWatch then
        if on then C_QuestLog.AddQuestWatch(questId) else C_QuestLog.RemoveQuestWatch(questId) end
        return true
    elseif GetQuestLogIndexByID and AddQuestWatch then
        local index = GetQuestLogIndexByID(questId)
        if not index or index == 0 then return false end
        if on then AddQuestWatch(index) else RemoveQuestWatch(index) end
        return true
    end
    return false
end

--- Abandons an active quest from the log (prompts native confirmation popup).
function Compat.AbandonQuest(questId)
    if not questId then return false end

    local lastQuest = GetQuestLogSelection and GetQuestLogSelection()
    local index = (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questId))
        or (GetQuestLogIndexByID and GetQuestLogIndexByID(questId))

    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(questId)
    end
    if SelectQuestLogEntry and index and index > 0 then
        SelectQuestLogEntry(index)
    end

    if SetAbandonQuest then
        SetAbandonQuest()
    elseif C_QuestLog and C_QuestLog.SetAbandonQuest then
        C_QuestLog.SetAbandonQuest()
    end

    local items
    if GetAbandonQuestItems then
        items = GetAbandonQuestItems()
    elseif C_QuestLog and C_QuestLog.GetAbandonQuestItems then
        local names = {}
        for _, itemID in ipairs(C_QuestLog.GetAbandonQuestItems() or {}) do
            local name = Compat.GetItemInfo(itemID)
            if name then names[#names + 1] = name end
        end
        if #names > 0 then items = table.concat(names, ", ") end
    end

    local questTitle = (GetAbandonQuestName and GetAbandonQuestName())
        or (C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(C_QuestLog.GetSelectedQuest()))
        or (WFC.DB and WFC.DB:GetQuestBrief(questId) and WFC.DB:GetQuestBrief(questId).name)
        or "Quest"

    if items then
        if StaticPopup_Hide then StaticPopup_Hide("ABANDON_QUEST") end
        if StaticPopup_Show then StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", questTitle, items) end
    else
        if StaticPopup_Hide then StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS") end
        if StaticPopup_Show then StaticPopup_Show("ABANDON_QUEST", questTitle) end
    end

    if lastQuest and SelectQuestLogEntry then
        SelectQuestLogEntry(lastQuest)
    end

    local qf = QuestLogExFrame or ClassicQuestLog or QuestLogFrame
    if qf and qf:IsShown() and QuestLog_Update then
        QuestLog_Update()
    end

    return true
end

--- Rewards of a quest in the log: { xp, money, items = { {id, count, choice} }, complete } or nil.
function Compat.GetQuestLogRewards(questId)
    if not (GetNumQuestLogRewards and GetQuestLogRewardInfo) then return nil end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID and not C_QuestLog.GetLogIndexForQuestID(questId) then return nil end
    local r = { items = {} }
    r.xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questId) or nil
    r.money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questId) or nil
    local function add(count, getInfo, choice)
        for i = 1, count or 0 do
            local _, _, n, _, _, itemId = getInfo(i, questId)
            if itemId then r.items[#r.items + 1] = { id = itemId, count = n or 1, choice = choice } end
        end
    end
    add(GetNumQuestLogRewards(questId), GetQuestLogRewardInfo, false)
    if GetNumQuestLogChoices and GetQuestLogChoiceInfo then
        add(GetNumQuestLogChoices(questId, true), GetQuestLogChoiceInfo, true)
    end
    return r
end

function Compat.GetFactionName(factionId)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(factionId)
        return data and data.name
    elseif GetFactionInfoByID then
        return (GetFactionInfoByID(factionId))
    end
end

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------
--- Returns {[skillLineId] = {name, rank, max}} for the current character.
--- Classic Era has no GetProfessions: its skill list is matched by (English) profession name.
function Compat.GetProfessions()
    local result = {}
    if not GetProfessions and GetNumSkillLines and GetSkillLineInfo then
        local names = WFC.DB and WFC.DB.Recipes and WFC.DB.Recipes.PROFESSION_NAMES or {}
        local idByName = {}
        for id, name in pairs(names) do idByName[name] = id end
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
            local id = not isHeader and idByName[name]
            if id then result[id] = { name = name, rank = rank or 0, max = max or 0 } end
        end
        return result
    end
    if GetProfessions and GetProfessionInfo then
        -- prof1, prof2, archaeology, fishing, cooking (any may be nil)
        local list = { GetProfessions() }
        for i = 1, 5 do
            local index = list[i]
            if index then
                local name, _, rank, max, _, _, skillLine = GetProfessionInfo(index)
                if skillLine then
                    result[skillLine] = { name = name, rank = rank or 0, max = max or 0 }
                end
            end
        end
    end
    return result
end

---------------------------------------------------------------------------
-- Map / position
---------------------------------------------------------------------------
function Compat.GetPlayerMapPosition()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local mapId = C_Map.GetBestMapForUnit("player")
    if not mapId or Compat.IsSecret(mapId) then return end
    local pos = C_Map.GetPlayerMapPosition(mapId, "player")
    if not pos then return mapId end
    local x, y = pos:GetXY()
    if Compat.IsSecret(x) then return mapId end
    return mapId, x, y
end

--- Map position (0-1) -> continentId, worldX, worldY in yards, or nil (detached islands,
--- instances). CoreRules R10: Forever uses Classic uiMapIDs and C_Map transforms directly.
function Compat.MapToWorld(uiMapId, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMapId, CreateVector2D(x, y))
    if not ok or not continent or not pos then return nil end
    local wx, wy = pos:GetXY()
    if Compat.IsSecret(wx) then return nil end
    return continent, wx, wy
end

--- World yards (continent frame) -> position on a displayed map (0-1, may fall outside), or nil.
function Compat.WorldToMap(continentId, wx, wy, uiMapId)
    if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, a, b = pcall(C_Map.GetMapPosFromWorldPos, continentId, CreateVector2D(wx, wy), uiMapId)
    if not ok then return nil end
    local pos = type(b) == "table" and b or a -- returns (uiMapID, pos) on modern clients
    if type(pos) ~= "table" or not pos.GetXY then return nil end
    return pos:GetXY()
end

--- Classic continent uiMaps by continent (instance) id: Eastern Kingdoms, Kalimdor.
Compat.CONTINENT_MAPS = { [0] = 1415, [1] = 1414 }

--- The zone map under a world position and the position on it: uiMapID, x, y (0-1), or nil.
function Compat.WorldToZone(continentId, wx, wy)
    local continent = Compat.CONTINENT_MAPS[continentId]
    if not (continent and C_Map and C_Map.GetMapInfoAtPosition) then return nil end
    local cx, cy = Compat.WorldToMap(continentId, wx, wy, continent)
    if not cx then return nil end
    local info = C_Map.GetMapInfoAtPosition(continent, cx, cy)
    local map = info and info.mapID
    if not map or map == continent then return nil end
    local x, y = Compat.WorldToMap(continentId, wx, wy, map)
    if not x then return nil end
    return map, x, y
end

--- A map's size in yards (detached islands have no world frame), or nil.
function Compat.GetMapWorldSize(uiMapId)
    if C_Map and C_Map.GetMapWorldSize then
        local w, h = C_Map.GetMapWorldSize(uiMapId)
        if w and w > 0 then return w, h end
    end
end

--- Flight masters on the open taxi map: { {id, name, known} }. Retail-style clients give
--- node IDs; Classic Era only names (id = nil, matched by name by the caller).
function Compat.GetTaxiNodes()
    local list = {}
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        local mapId = GetTaxiMapID and GetTaxiMapID() or nil
        local nodes = C_TaxiMap.GetAllTaxiNodes(mapId)
        local states = Enum and Enum.FlightPathState
        local unreachable = states and states.Unreachable or 2
        for _, n in ipairs(nodes or {}) do
            list[#list + 1] = { id = n.nodeID, name = n.name, known = n.state ~= unreachable }
        end
    elseif NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
        for i = 1, NumTaxiNodes() do
            local kind = TaxiNodeGetType(i)
            list[#list + 1] = { name = TaxiNodeName(i), known = kind == "CURRENT" or kind == "REACHABLE" }
        end
    end
    return list
end

--- True while the player is on a flight path.
function Compat.UnitOnTaxi()
    return UnitOnTaxi ~= nil and UnitOnTaxi("player") == true
end

function Compat.GetItemCount(itemId)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemId) or 0 end
    if GetItemCount then return GetItemCount(itemId) or 0 end
    return 0
end

--- True when an item's cooldown is over (e.g. the hearthstone, 6948).
function Compat.IsItemReady(itemId)
    local start, duration
    if C_Container and C_Container.GetItemCooldown then
        start, duration = C_Container.GetItemCooldown(itemId)
    elseif GetItemCooldown then
        start, duration = GetItemCooldown(itemId)
    else
        return false
    end
    if Compat.IsSecret(start) then return false end
    return not start or start == 0 or start + (duration or 0) <= GetTime()
end

function Compat.GetBindLocation()
    return GetBindLocation and GetBindLocation() or nil
end

--- True when a uiMap exists on this client and is a dungeon interior map. (Forever has none:
--- its map list is zones, continents and battlegrounds only.)
function Compat.IsDungeonMap(uiMapId)
    if not (uiMapId and C_Map and C_Map.GetMapInfo) then return false end
    local info = C_Map.GetMapInfo(uiMapId)
    local dungeon = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
    return info ~= nil and info.mapType == dungeon
end

function Compat.GetAreaName(areaId)
    if areaId and C_Map and C_Map.GetAreaInfo then return C_Map.GetAreaInfo(areaId) end
end

--- Opens the world map (never WorldMapFrame:Show(), CoreRules R6), optionally at a map.
function Compat.OpenWorldMap(uiMapId)
    if OpenWorldMap then
        OpenWorldMap(uiMapId)
    elseif ShowUIPanel and WorldMapFrame then
        ShowUIPanel(WorldMapFrame)
        if uiMapId and WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(uiMapId) end
    end
end

--- Places the native map pin (C_Map user waypoint, not C_SuperTrack: CoreRules R10),
--- or a TomTom arrow where the client has no user waypoints (Classic Era). Returns the method used.
function Compat.SetWaypoint(uiMapId, x, y, title)
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(uiMapId)) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMapId, x, y))
        return "waypoint"
    end
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(uiMapId, x, y, { title = title, persistent = false })
        return "tomtom"
    end
    return nil
end

--- Visible quest log frame to dock next to (CoreRules R11), or nil.
--- Order: addon logs first (they replace the native one when installed).
Compat.QUEST_LOG_FRAMES = { "ClassicQuestLog", "QuestLogFrame", "QuestMapFrame" }

function Compat.GetQuestLogFrame()
    for _, name in ipairs(Compat.QUEST_LOG_FRAMES) do
        local frame = _G[name]
        if frame and frame.IsVisible and frame:IsVisible() then
            -- The native log lives inside the world map: dock to the map's edge.
            if name == "QuestMapFrame" and WorldMapFrame then return WorldMapFrame, name end
            return frame, name
        end
    end
end

function Compat.HasContextMenu()
    return MenuUtil ~= nil and MenuUtil.CreateContextMenu ~= nil
end

---------------------------------------------------------------------------
-- Money, modifiers
---------------------------------------------------------------------------
--- Copper -> coin-icon string (design §1.2: never plain text).
function Compat.FormatMoney(copper)
    copper = math.floor((copper or 0) + 0.5)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    elseif GetCoinTextureString then
        return GetCoinTextureString(copper)
    end
    return GetMoneyString(copper)
end

function Compat.IsShiftKeyDown()
    return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true
end

---------------------------------------------------------------------------
-- Item tooltips (CoreRules R9)
---------------------------------------------------------------------------
--- Calls fn(tooltip, itemId) after the client fills an item tooltip. Uses
--- TooltipDataProcessor where it exists, else OnTooltipSetItem (Classic Era).
--- `frames` = list of tooltip frames to hook in the fallback path.
function Compat.HookItemTooltips(fn, frames)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            local id = data and data.id
            if not id and tooltip.GetPrimaryTooltipData then
                local primary = tooltip:GetPrimaryTooltipData()
                id = primary and primary.id
            end
            fn(tooltip, id)
        end)
        return "TooltipDataProcessor"
    end
    for _, tooltip in ipairs(frames) do
        tooltip:HookScript("OnTooltipSetItem", function(self)
            local _, link = self:GetItem()
            fn(self, link and tonumber(link:match("item:(%d+)")))
        end)
    end
    return "OnTooltipSetItem"
end

--- Re-runs the client's tooltip fill (and so our post-call). Retail-style tooltips only.
function Compat.RefreshTooltip(tooltip)
    if tooltip.RefreshData then
        tooltip:RefreshData()
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Self-test probes (/wfc selftest, CoreRules §6)
---------------------------------------------------------------------------
function Compat.Probe()
    local function has(t, k) return t ~= nil and t[k] ~= nil end
    return {
        { "Forever interface (" .. tostring(Compat.interface) .. ")", Compat.IsForever() },
        { "issecretvalue", issecretvalue ~= nil },
        { "C_Item.GetItemInfo", has(C_Item, "GetItemInfo") },
        { "C_QuestLog.GetAllCompletedQuestIDs", has(C_QuestLog, "GetAllCompletedQuestIDs") },
        { "C_QuestLog.GetQuestTagInfo", has(C_QuestLog, "GetQuestTagInfo") },
        { "C_QuestLog.GetQuestObjectives", has(C_QuestLog, "GetQuestObjectives") },
        { "C_QuestLog.GetTrivialRange", has(C_QuestLog, "GetTrivialRange") },
        { "C_PlayerInfo.GetContentDifficultyQuestForPlayer", has(C_PlayerInfo, "GetContentDifficultyQuestForPlayer") },
        { "C_TaxiMap.GetAllTaxiNodes", has(C_TaxiMap, "GetAllTaxiNodes") },
        { "C_TradeSkillUI.GetRecipeSchematic", has(C_TradeSkillUI, "GetRecipeSchematic") },
        { "C_AuctionHouse.ReplicateItems", has(C_AuctionHouse, "ReplicateItems") },
        { "TooltipDataProcessor", TooltipDataProcessor ~= nil },
        { "MenuUtil", MenuUtil ~= nil },
        { "CreateFontFamily", CreateFontFamily ~= nil },
        { "GetProfessions", GetProfessions ~= nil },
        { "LibQuestieDB", LibQuestieDB ~= nil },
        { "Questie.API", Questie ~= nil and Questie.API ~= nil },
        { "Auctionator.API.v1", Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil },
    }
end
