local _, ns = ...
local WFC = WFC

-- The ONLY file in the suite that touches Questie (plan.md §4.2, CoreRules R12), and
-- only through its public Questie.API. Everything here also works with Questie
-- disabled: data comes from QuestieDB through WFC.DB, map marks are native.

local Compat = WFC.Compat

local Bridge = {}
ns.Bridge = Bridge

local ICON_DIR = "Interface\\AddOns\\Questie\\Icons\\"
-- Blizzard fallbacks when Questie (and its icon files) are not installed.
local FALLBACK_ICONS = {
    available = "Interface\\GossipFrame\\AvailableQuestIcon",
    available_gray = "Interface\\GossipFrame\\AvailableQuestIcon",
    complete = "Interface\\GossipFrame\\ActiveQuestIcon",
    incomplete = "Interface\\GossipFrame\\IncompleteQuestIcon",
    repeatable = "Interface\\GossipFrame\\DailyQuestIcon",
    repeatable_complete = "Interface\\GossipFrame\\DailyActiveQuestIcon",
    slay = "Interface\\Icons\\Ability_DualWield",
    loot = "Interface\\Icons\\INV_Misc_Bag_08",
    object = "Interface\\Icons\\INV_Misc_Gear_01",
}

local function api()
    return Questie and Questie.API
end

function Bridge:IsAvailable()
    return Compat.IsAddOnLoaded("Questie") == true and api() ~= nil
end

--- fn() once Questie has finished loading (now if it has, or never needed without Questie).
function Bridge:OnReady(fn)
    local a = api()
    if a and not a.isReady and a.RegisterOnReady then
        a.RegisterOnReady(fn)
    else
        fn()
    end
end

--- fn() whenever Questie reports quest changes.
function Bridge:OnQuestUpdate(fn)
    local a = api()
    if a and a.RegisterForQuestUpdates then a.RegisterForQuestUpdates(fn) end
end

--- Texture path for a quest state icon (design §6.1): Questie's when loaded, else Blizzard's.
function Bridge:Icon(name)
    if self:IsAvailable() then return ICON_DIR .. name end
    return FALLBACK_ICONS[name] or FALLBACK_ICONS.available
end

---------------------------------------------------------------------------
-- Show on map (native: world map + user waypoint, or TomTom on clients without one)
---------------------------------------------------------------------------
local function closest(points, mapId, x, y)
    local best, bestD
    for _, p in ipairs(points) do
        local d = (p.map == mapId and x) and ((p.x - x) ^ 2 + (p.y - y) ^ 2) or 10 + (p.map == mapId and 0 or 1)
        if not bestD or d < bestD then best, bestD = p, d end
    end
    return best
end

--- The point a quest needs next: the giver if not accepted, the turn-in when complete,
--- otherwise the closest objective. Returns a position entry from WFC.DB:GetQuestPositions or nil.
function Bridge:TargetPoint(questId)
    local P = WFC.Player
    local role = "objective"
    local info = P.active[questId]
    if not info then
        role = "start"
    elseif info.isComplete then
        role = "end"
    end
    local points = {}
    for _, p in ipairs(WFC.DB:GetQuestPositions(questId)) do
        if p.role == role then points[#points + 1] = p end
    end
    if #points == 0 then
        for _, p in ipairs(WFC.DB:GetQuestPositions(questId)) do points[#points + 1] = p end
    end
    if #points == 0 then return nil end
    return closest(points, Compat.GetPlayerMapPosition())
end

local ROLE_LABEL = { start = "quest giver", objective = "objective", ["end"] = "turn-in" }

local function entityName(p)
    local card = p.kind == "npc" and WFC.DB:GetNpc(p.id) or WFC.DB:GetObject(p.id)
    return card and card.name
end

--- Opens the world map at the quest's next point and pins it. Returns true when a point was found.
function Bridge:ShowQuestOnMap(questId)
    local p = self:TargetPoint(questId)
    local brief = WFC.DB:GetQuestBrief(questId)
    local name = brief and brief.name or ("quest " .. questId)
    if not p then
        WFC:Print("no map location known for", name)
        return false
    end
    local who = entityName(p)
    local title = name .. (who and (": " .. who) or "")
    WFC:RunOutOfCombat("questing:showOnMap", function()
        Compat.OpenWorldMap(p.map)
        local method = Compat.SetWaypoint(p.map, p.x, p.y, title)
        if not method then
            WFC:Print(("%s %s at %.1f, %.1f"):format(name, ROLE_LABEL[p.role] or "", p.x * 100, p.y * 100))
        end
    end)
    WFC:Fire("WFC_QUEST_SHOWN_ON_MAP", questId, p)
    return true
end
