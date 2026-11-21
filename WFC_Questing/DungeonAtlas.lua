local _, ns = ...
local WFC = WFC

-- Dungeon Map window (an Atlas-style view). Forever ships Blizzard's dungeon map tiles but no
-- map entries for them, so we draw the tiles ourselves, by file ID, from the player's install
-- (Data/DungeonMaps.lua lists them; nothing is shipped). On top: skull pins for bosses and
-- Questie-icon pins for your quest objectives, placed from Data/DungeonSpawns.lua (CMaNGOS
-- spawn positions), with hover tooltips. Floor buttons on the right (with how many of your
-- objectives each floor has), then the legend: level range, bosses and your quests. No
-- player position.

local Questing, Dungeons = ns.Questing, ns.Dungeons
local DB, Colors = WFC.DB, WFC.Colors
local P = Colors.palette

local Atlas = {}
ns.Atlas = Atlas

local NAME = "WFC_DungeonMap"
local ART_W, ART_H = 1002, 668 -- the visible part of a 4 x 3 grid of 256 px tiles
local MAP_W = 600
local SCALE = MAP_W / ART_W
local MAP_H = math.floor(ART_H * SCALE + 0.5)
local SIDE_W, PAD = 220, 10

local byArea -- [dungeon AreaID] = DungeonMaps entry

--- DungeonMaps entries keyed by the database's dungeon ids (AreaIDs). Matches through
--- QuestieDB's instance -> area table, then by name.
local function index()
    if byArea then return byArea end
    byArea = {}
    local cards = DB:GetDungeons()
    local function norm(s) return (s or ""):lower():gsub("^the ", "") end
    for instanceId, entry in pairs(ns.Data.DungeonMaps or {}) do
        local area = entry.area or DB.Zones:InstanceToArea(instanceId)
        if not area then
            for _, card in ipairs(cards) do
                if norm(card.name) == norm(entry[1]) then area = card.id break end
            end
        end
        if area then byArea[area] = entry end
    end
    return byArea
end

function Atlas:Has(dungeonId)
    return index()[dungeonId] ~= nil
end

--- Floors of a dungeon: { { uiMap, name, rows, cols, fileIds }, ... } or nil.
function Atlas:Floors(dungeonId)
    local entry = index()[dungeonId]
    return entry and entry.floors
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame, mapArea, tiles, floorButtons, title, legend
Atlas.state = { dungeon = nil, floor = 1 }

local function font(fs, key)
    local f = WFC.Fonts:Get(key)
    if f then fs:SetFontObject(f) end
end

local function create()
    local ok
    ok, frame = pcall(CreateFrame, "Frame", NAME, UIParent, "ButtonFrameTemplate")
    if not ok then
        frame = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
        if frame.SetBackdrop then
            frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            frame:SetBackdropColor(0.086, 0.094, 0.11, 0.95)
            frame:SetBackdropBorderColor(0.23, 0.25, 0.28, 1)
        end
    elseif ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(frame)
    end
    frame:Hide()
    frame:SetSize(PAD + MAP_W + PAD + SIDE_W + PAD, 30 + MAP_H + PAD + 8)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, NAME)
    if frame.SetTitle then frame:SetTitle("Dungeon Map") end
    if frame.TitleText then font(frame.TitleText, "header") end

    -- The map: tiles inside a clipping frame (the grid is 1024 x 768; only 1002 x 668 is art).
    mapArea = CreateFrame("Frame", nil, frame)
    mapArea:SetPoint("TOPLEFT", PAD, -30)
    mapArea:SetSize(MAP_W, MAP_H)
    if mapArea.SetClipsChildren then mapArea:SetClipsChildren(true) end
    tiles = {}

    -- Side panel: name, floors, legend.
    title = frame:CreateFontString(nil, "OVERLAY")
    font(title, "subheader")
    title:SetPoint("TOPLEFT", mapArea, "TOPRIGHT", PAD, 0)
    title:SetWidth(SIDE_W)
    title:SetJustifyH("LEFT")
    floorButtons = {}
    Atlas.floorButtons = floorButtons
    legend = frame:CreateFontString(nil, "OVERLAY")
    font(legend, "small")
    legend:SetWidth(SIDE_W)
    legend:SetJustifyH("LEFT")
    legend:SetJustifyV("TOP")
    Atlas.frame = frame
end

local function tile(i)
    local t = tiles[i]
    if not t then
        t = mapArea:CreateTexture(nil, "ARTWORK")
        tiles[i] = t
    end
    return t
end

local function floorButton(i)
    local b = floorButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(SIDE_W, 20)
    b:SetScript("OnClick", function(self) Atlas:ShowFloor(self.floor) end)
    floorButtons[i] = b
    return b
end

---------------------------------------------------------------------------
-- Pins: bosses and your quest objectives (Questie's icons), with hover tooltips
---------------------------------------------------------------------------
local decoded = setmetatable({}, { __mode = "v" })

--- Spawns on a floor: { n = { [npcId] = { x, y, x, y, ... } }, o = { [objectId] = {...} } } (0-1000).
function Atlas:Spawns(uiMap)
    local s = decoded[uiMap]
    if s then return s end
    local raw = ns.Data.DungeonSpawns and ns.Data.DungeonSpawns[uiMap]
    s = { n = {}, o = {} }
    for kind in pairs(s) do
        for id, coords in ((raw and raw[kind]) or ""):gmatch("(%d+):([%d,]+)") do
            local list = {}
            for v in coords:gmatch("%d+") do list[#list + 1] = tonumber(v) end
            s[kind][tonumber(id)] = list
        end
    end
    decoded[uiMap] = s
    return s
end

local PIN_SIZE, BOSS_SIZE, MAX_PER_TARGET = 14, 18, 40
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

--- The objectives of your quests that point at things: { {questId, kind = "npc"|"object",
--- id, icon, text, have, need} }. Finished objectives and completed quests are skipped.
local function objectiveTargets()
    local out = {}
    for questId, info in pairs(WFC.Player.active) do
        local card = not info.isComplete and DB:GetQuest(questId)
        if card then
            local client = WFC.Compat.GetQuestObjectives(questId)
            local function progress(name)
                for _, o in ipairs(client) do
                    if o.text and name and o.text:find(name, 1, true) then return o end
                end
            end
            local function add(kind, id, icon, label)
                local o = progress(label)
                if not (o and o.finished) then
                    out[#out + 1] = { questId = questId, kind = kind, id = id, icon = icon,
                        text = o and o.text or label, have = o and o.have, need = o and o.need }
                end
            end
            for _, o in ipairs(card.objectives) do
                if o.type == "kill" then
                    local npc = DB:GetNpc(o.id)
                    add("npc", o.id, "slay", o.text or (npc and npc.name))
                elseif o.type == "killcredit" then
                    for _, npcId in ipairs(o.ids or {}) do add("npc", npcId, "slay", o.text) end
                elseif o.type == "object" then
                    local object = DB:GetObject(o.id)
                    add("object", o.id, "object", o.text or (object and object.name))
                elseif o.type == "item" then
                    local item = DB:GetItem(o.id)
                    local name = item.name or (DB:GetItemClient(o.id) or {}).name
                    for _, npcId in ipairs(item.dropNpcs or {}) do add("npc", npcId, "loot", name) end
                    for _, objectId in ipairs(item.dropObjects or {}) do add("object", objectId, "loot", name) end
                end
            end
        end
    end
    return out
end

--- Pins for one floor: { { x, y (0-1000), icon, size, lines = { {text, color} } } }.
function Atlas:Pins(dungeonId, uiMap)
    local spawns = self:Spawns(uiMap)
    local pins, byKey = {}, {}
    local function pin(kind, id, icon, size, line)
        local coords = spawns[kind == "npc" and "n" or "o"][id]
        if not coords then return 0 end
        local n = 0
        for i = 1, math.min(#coords, MAX_PER_TARGET * 2), 2 do
            local key = kind .. id .. ":" .. coords[i] .. "," .. coords[i + 1]
            local p = byKey[key]
            if not p then
                p = { x = coords[i], y = coords[i + 1], icon = icon, size = size, lines = {} }
                byKey[key] = p
                pins[#pins + 1] = p
            elseif size > p.size then
                p.icon, p.size = icon, size -- a boss that is also an objective keeps the skull
            end
            p.lines[#p.lines + 1] = line
            n = n + 1
        end
        return n
    end
    local d = DB:GetDungeonDetails(dungeonId)
    for _, npc in ipairs(d and d.bosses or {}) do
        local level = npc.maxLevel or npc.minLevel
        pin("npc", npc.id, SKULL, BOSS_SIZE, { npc.name .. "  Lv " .. tostring(level or "?") .. " · Boss",
            Colors.ForLevel(level, WFC.Player.level) })
    end
    local objectives = 0
    for _, t in ipairs(objectiveTargets()) do
        local brief = DB:GetQuestBrief(t.questId)
        local progress = (t.have and t.need) and (Colors.Progress(t.have, t.need) .. t.text .. "|r") or (t.text or "")
        local added = pin(t.kind, t.id, ns.Bridge:Icon(t.icon), PIN_SIZE,
            { ns.Panel.QuestName(brief or { id = t.questId }, true) .. "\n   " .. progress, P.TEXT })
        if added > 0 then objectives = objectives + 1 end
    end
    return pins, objectives
end

local pinFrames = {}

local function pinFrame(i)
    local b = pinFrames[i]
    if b then return b end
    b = CreateFrame("Button", nil, mapArea)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints()
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for n, line in ipairs(self.pin.lines) do
            local c = line[2] or P.TEXT
            if n == 1 then GameTooltip:AddLine(line[1], c.r, c.g, c.b) else GameTooltip:AddLine(line[1], c.r, c.g, c.b, true) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pinFrames[i] = b
    return b
end

local function drawPins(dungeonId, uiMap)
    local pins = Atlas:Pins(dungeonId, uiMap)
    for i, p in ipairs(pins) do
        local b = pinFrame(i)
        b.pin = p
        b.icon:SetTexture(p.icon)
        b:SetSize(p.size, p.size)
        b:SetFrameLevel((mapArea:GetFrameLevel() or 1) + (p.size == BOSS_SIZE and 3 or 2))
        b:ClearAllPoints()
        b:SetPoint("CENTER", mapArea, "TOPLEFT", p.x / 1000 * MAP_W, -(p.y / 1000 * MAP_H))
        b:Show()
    end
    for i = #pins + 1, #pinFrames do pinFrames[i]:Hide() end
    Atlas.shownPins = pins
end

--- Draws one floor's tiles.
function Atlas:ShowFloor(index)
    local floors = self:Floors(self.state.dungeon)
    local f = floors and floors[index]
    if not f then return end
    self.state.floor = index
    local rows, cols, ids = f[3], f[4], f[5]
    local size = 256 * SCALE
    for i = 1, #tiles do tiles[i]:Hide() end
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local n = r * cols + c + 1
            local t = tile(n)
            t:SetTexture(ids[n])
            t:SetSize(size, size)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", mapArea, "TOPLEFT", c * size, -r * size)
            t:Show()
        end
    end
    for i, b in ipairs(floorButtons) do
        if i == index then b:LockHighlight() else b:UnlockHighlight() end
    end
    self.shownTiles = ids
    drawPins(self.state.dungeon, f[1])
end

--- Opens the window on a dungeon. Returns false when there is no map for it.
function Atlas:Open(dungeonId, floor)
    local floors = self:Floors(dungeonId)
    if not floors then return false end
    if not frame then create() end
    self.state.dungeon = dungeonId
    local card = DB:GetDungeon(dungeonId)
    title:SetText(card and Dungeons.Title(card, (DB:GetDungeonDetails(dungeonId))) or "")
    -- Floor buttons (only when there is more than one floor).
    local y = -30 - 22
    for i = 1, #floorButtons do floorButtons[i]:Hide() end
    if #floors > 1 then
        for i, f in ipairs(floors) do
            local b = floorButton(i)
            b.floor = i
            -- Show how many of your objectives are on each floor, so you know where to look.
            local _, objectives = Atlas:Pins(dungeonId, f[1])
            b:SetText(f[2] .. (objectives > 0 and (" (" .. objectives .. ")") or ""))
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", mapArea, "TOPRIGHT", PAD, y + 30)
            b:Show()
            y = y - 22
        end
    end
    local content = ns.DungeonMap.Lines(dungeonId)
    legend:ClearAllPoints()
    legend:SetPoint("TOPLEFT", mapArea, "TOPRIGHT", PAD, y + 30 - 6)
    legend:SetText(content and table.concat(content.lines, "\n") or "")
    self:ShowFloor(floor or 1)
    frame:Show()
    return true
end

function Atlas:Hide()
    if frame then frame:Hide() end
end

function Atlas:IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Quest progress and level changes update the legend while the window is open.
WFC:On("WFC_PLAYER_CHANGED", function()
    if Atlas:IsShown() then Atlas:Open(Atlas.state.dungeon, Atlas.state.floor) end
end)
WFC:On("WFC_INDEX_READY", function(_, name)
    if name == "npcsByArea" or name == "questsByDungeon" then byArea = nil end
end)
