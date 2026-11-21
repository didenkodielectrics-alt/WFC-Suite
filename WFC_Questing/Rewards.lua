local _, ns = ...
local WFC = WFC

-- "Show rewards" popup (plan.md §4.4, design.md §4.4): XP and money, reputation, and
-- reward item buttons whose tooltips carry the WFC_ItemTips verdict. The best choice
-- (highest of AH net / vendor value) gets a green outline and a "best" label below it.
-- Quests in the log use the client's reward APIs; other quests use the database.

local Questing, Panel = ns.Questing, ns.Panel
local Compat, Colors = WFC.Compat, WFC.Colors
local P = Colors.palette

local Rewards = {}
Questing.Rewards = Rewards
ns.Rewards = Rewards

local AH_CUT = 0.05
local ICON, GAP = 32, 6

--- { questId, name, xp, money, reps = { {name, value} }, items = { {id, count, choice} }, source, pending }
function Rewards.Data(questId)
    local brief = WFC.DB:GetQuestBrief(questId)
    local card = WFC.DB:GetQuest(questId)
    local data = { questId = questId, name = brief and brief.name, reps = {}, items = {} }
    local fromLog = WFC.Player.active[questId] and Compat.GetQuestLogRewards(questId)
    if fromLog then
        data.source, data.xp, data.money, data.items = "log", fromLog.xp, fromLog.money, fromLog.items
    else
        data.source = "db"
        data.xp = brief and brief.xp
        local items, state = WFC.DB:GetQuestRewards(questId)
        data.pending = state == "pending"
        for _, id in ipairs(items or {}) do
            -- QuestieDB does not say which rewards are choices; with several, treat them as a choice.
            data.items[#data.items + 1] = { id = id, count = 1, choice = #items > 1 }
        end
    end
    for _, rep in ipairs(card and card.repRewards or {}) do
        local factionId, value = rep[1], rep[2]
        if factionId and value and value ~= 0 then
            data.reps[#data.reps + 1] = { name = Compat.GetFactionName(factionId) or ("Faction " .. factionId), value = value }
        end
    end
    return data
end

local function itemValue(id)
    local ah, vendor = WFC.DB:GetPrice(id)
    return math.max(ah and ah * (1 - AH_CUT) or 0, vendor or 0)
end

--- Index of the most valuable choice item, or nil when there is no choice to make.
function Rewards.Best(items)
    local best, bestValue
    for i, item in ipairs(items) do
        if item.choice then
            local v = itemValue(item.id)
            if v > 0 and (not bestValue or v > bestValue) then best, bestValue = i, v end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local frame, header, summary, repText
local buttons = {}

local function create()
    local ok
    ok, frame = pcall(CreateFrame, "Frame", "WFC_QuestRewards", UIParent, "ButtonFrameTemplate")
    if not ok then
        frame = CreateFrame("Frame", "WFC_QuestRewards", UIParent, "BackdropTemplate")
        if frame.SetBackdrop then
            frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            frame:SetBackdropColor(0.086, 0.094, 0.11, 0.95)
            frame:SetBackdropBorderColor(0.23, 0.25, 0.28, 1)
        end
    elseif ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(frame)
    end
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "WFC_QuestRewards")
    if frame.SetTitle then frame:SetTitle("Rewards") end
    if frame.TitleText then frame.TitleText:SetFontObject(WFC.Fonts:Get("header")) end

    header = frame:CreateFontString(nil, "OVERLAY")
    header:SetFontObject(WFC.Fonts:Get("subheader"))
    header:SetPoint("TOPLEFT", 12, -30)
    header:SetPoint("RIGHT", -12, 0)
    header:SetJustifyH("LEFT")
    summary = frame:CreateFontString(nil, "OVERLAY")
    summary:SetFontObject(WFC.Fonts:Get("body"))
    summary:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    summary:SetJustifyH("LEFT")
    repText = frame:CreateFontString(nil, "OVERLAY")
    repText:SetFontObject(WFC.Fonts:Get("small"))
    repText:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -4)
    repText:SetJustifyH("LEFT")
    Rewards.frame = frame
end

local function button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame)
    b:SetSize(ICON, ICON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    -- 2 px green outline around (never on top of) the icon, and a label underneath.
    b.outline = {}
    for side, anchors in pairs({
        top = { "BOTTOMLEFT", "TOPLEFT", -2, 0, "BOTTOMRIGHT", "TOPRIGHT", 2, 0, "h" },
        bottom = { "TOPLEFT", "BOTTOMLEFT", -2, 0, "TOPRIGHT", "BOTTOMRIGHT", 2, 0, "h" },
        left = { "TOPRIGHT", "TOPLEFT", 0, 2, "BOTTOMRIGHT", "BOTTOMLEFT", 0, -2, "v" },
        right = { "TOPLEFT", "TOPRIGHT", 0, 2, "BOTTOMLEFT", "BOTTOMRIGHT", 0, -2, "v" },
    }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(P.EASY.r, P.EASY.g, P.EASY.b, 1)
        t:SetPoint(anchors[1], b, anchors[2], anchors[3], anchors[4])
        t:SetPoint(anchors[5], b, anchors[6], anchors[7], anchors[8])
        if anchors[9] == "h" then t:SetHeight(2) else t:SetWidth(2) end
        b.outline[side] = t
    end
    b.best = b:CreateFontString(nil, "OVERLAY")
    b.best:SetFontObject(WFC.Fonts:Get("small"))
    b.best:SetPoint("TOP", b, "BOTTOM", 0, -4)
    b.best:SetText(Colors.Wrap("best", P.EASY))
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemId) -- WFC_ItemTips adds its verdict here
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end

local function setBest(b, on)
    for _, t in pairs(b.outline) do if on then t:Show() else t:Hide() end end
    if on then b.best:Show() else b.best:Hide() end
end

--- Text lines of the popup (also used by specs).
function Rewards.Lines(data)
    local parts = {}
    if data.xp and data.xp > 0 then parts[#parts + 1] = ("%d xp"):format(data.xp) end
    if data.money and data.money > 0 then parts[#parts + 1] = Compat.FormatMoney(data.money) end
    local reps = {}
    for _, r in ipairs(data.reps) do
        reps[#reps + 1] = ("%s%d %s"):format(r.value > 0 and "+" or "", r.value, r.name)
    end
    local summaryText = #parts > 0 and table.concat(parts, " · ") or "no XP or money listed"
    if data.pending then summaryText = summaryText .. " · items still loading" end
    return summaryText, table.concat(reps, "\n")
end

function Rewards:Show(questId, anchor)
    if not frame then create() end
    local data = Rewards.Data(questId)
    Rewards.data = data
    local c = (Questing:GetEntry(questId) or {}).candidate or WFC.DB:GetQuestBrief(questId)
        or { id = questId, name = data.name }
    header:SetText(Panel.QuestName(c, true))
    local summaryText, reps = Rewards.Lines(data)
    summary:SetText(Colors.Wrap(summaryText, P.TEXT))
    repText:SetText(Colors.Wrap(reps, P.TEXT_MUTED))

    local best = Rewards.Best(data.items)
    Rewards.bestIndex = best
    local top = 30 + 20 + 18 + 14 * math.max(#data.reps, 0) + 8
    for i, item in ipairs(data.items) do
        local b = button(i)
        b.itemId = item.id
        b.icon:SetTexture(Compat.GetItemIcon(item.id))
        b.count:SetText(item.count and item.count > 1 and item.count or "")
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 12 + (i - 1) % 6 * (ICON + GAP), -(top + math.floor((i - 1) / 6) * (ICON + 22)))
        setBest(b, i == best)
        b:Show()
    end
    for i = #data.items + 1, #buttons do buttons[i]:Hide() end
    local rowsOfItems = math.ceil(#data.items / 6)
    frame:SetSize(math.max(240, 24 + math.min(#data.items, 6) * (ICON + GAP)), top + rowsOfItems * (ICON + 22) + 16)
    frame:ClearAllPoints()
    local panel = Panel.frame
    if panel and panel:IsShown() then
        frame:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
    elseif anchor then
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
end

function Rewards:Hide()
    if frame then frame:Hide() end
end

-- Item names/icons and prices may arrive after the popup opened.
WFC:On("WFC_INDEX_READY", function(_, name)
    if name == "questRewardItems" and frame and frame:IsShown() and Rewards.data then Rewards:Show(Rewards.data.questId) end
end)
