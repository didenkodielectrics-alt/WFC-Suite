local _, ns = ...
local WFC = WFC

-- The quest panel (plan.md §4.4, design.md §4.1/§4.2): our own non-secure window that
-- docks to whichever quest log is visible, or stands alone. Tabs: Active (default) | Next Up |
-- Dungeons (Dungeons.lua). Rows copy Questie's tracker format.
-- Rows are rebuilt only out of combat; nothing here touches protected frames.

local Questing, Bridge = ns.Questing, ns.Bridge
local Compat, Colors = WFC.Compat, WFC.Colors
local P = Colors.palette

local Panel = {}
ns.Panel = Panel

local NAME = "WFC_QuestPanel"
local WIDTH, HEIGHT = 340, 440
local PAD, ROW_GAP, LINE = 10, 4, 13
local TABS = { { key = "active", label = "Active" }, { key = "next", label = "Next Up" }, { key = "dungeons", label = "Dungeons" } }
local BAR = 28 -- height of the Dungeons tab's toolbar
-- Our fonts have no "★" glyph: use the raid-target star icon, present on every client.
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t "
local STAR_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

local frame, scroll, content, status, ignoredCheck, anyZoneBtn, bar
local scrollTop
local rows = {}
local tab = "active" -- opens on your log; Next Up is one click away (kept for the session)
local autoShown, userHidden = false, false
Panel.selected = nil

local function updateAnyZoneButton()
    if not anyZoneBtn or not Questing.settings then return end
    if Questing.settings.anyZone then
        anyZoneBtn:SetText("|cff40ff40Any Zone: On|r")
    else
        anyZoneBtn:SetText("Any Zone: Off")
    end
end

---------------------------------------------------------------------------
-- Row text (pure helpers, also used by the menu and rewards popup)
---------------------------------------------------------------------------
--- "[24+] Name" in the quest's difficulty colour (Questie's GetColoredQuestName format),
--- plus the new! tag for new content when `withNew` is set.
function Panel.QuestName(c, withNew)
    local level = c.level and c.level > 0 and c.level or c.minLevel or "?"
    local suffix = (c.elite and "+" or "") .. (c.dungeon and "D" or "")
    local color = Colors.ForQuest(c.id, tonumber(level), WFC.Player.level)
    local name = Colors.Wrap(("[%s%s] %s"):format(tostring(level), suffix, c.name or ("Quest " .. c.id)), color)
    if withNew and c.isNew then name = name .. WFC:NewTag("  ") end
    return name
end

local function iconFor(entry)
    local c = entry.candidate
    if c.state == "complete" then return Bridge:Icon(c.repeatable and "repeatable_complete" or "complete") end
    if c.state == "active" then return Bridge:Icon("incomplete") end
    if c.repeatable then return Bridge:Icon("repeatable") end
    return Bridge:Icon(entry.grey and "available_gray" or "available")
end

--- Finds the quest giver name, coordinates, and spawn point for an available quest.
function Panel.GetQuestGiver(questId)
    if not questId then return nil end
    local giverName, coords, point
    if Bridge and Bridge.TargetPoint then
        local p = Bridge:TargetPoint(questId)
        if p then
            point = p
            if p.x and p.y then
                coords = ("%.0f, %.0f"):format(p.x * 100, p.y * 100)
            end
            if p.id then
                if p.kind == "npc" and WFC.DB and WFC.DB.GetNpc then
                    local npc = WFC.DB:GetNpc(p.id)
                    giverName = npc and npc.name
                elseif p.kind == "object" and WFC.DB and WFC.DB.GetObject then
                    local obj = WFC.DB:GetObject(p.id)
                    giverName = obj and obj.name
                end
            end
        end
    end
    if not giverName and WFC.DB and WFC.DB.GetQuest then
        local card = WFC.DB:GetQuest(questId)
        if card and card.starts then
            if card.starts.npc and card.starts.npc[1] and WFC.DB.GetNpc then
                local npc = WFC.DB:GetNpc(card.starts.npc[1])
                giverName = npc and npc.name
            elseif card.starts.object and card.starts.object[1] and WFC.DB.GetObject then
                local obj = WFC.DB:GetObject(card.starts.object[1])
                giverName = obj and obj.name
            elseif card.starts.item and WFC.DB.GetItem then
                local item = WFC.DB:GetItem(card.starts.item)
                giverName = item and item.name
            end
        end
    end
    return giverName, coords, point
end

--- { title, right, sub = {lines} } for one ranked entry.
function Panel.RowText(entry, rank)
    local c = entry.candidate
    local title = Panel.QuestName(c, true)
    local right = Colors.Wrap(Compat.GetAreaName(c.area) or "", P.TEXT_MUTED)
    local mins = ("~%d min"):format(math.max(1, math.floor((entry.minutes or 0) + 0.5)))
    local sub = {}
    if c.state == "complete" then
        sub[1] = Colors.Wrap("ready to turn in · " .. mins, P.TEXT_MUTED)
    elseif c.state == "available" then
        local giver, coords = Panel.GetQuestGiver(c.id)
        local pickupStr
        if giver and coords then
            pickupStr = ("Pick up: %s (%s)"):format(giver, coords)
        elseif giver then
            pickupStr = ("Pick up from %s"):format(giver)
        elseif coords then
            pickupStr = ("Pick up at (%s)"):format(coords)
        else
            pickupStr = "Available to pick up"
        end
        sub[1] = Colors.Wrap(pickupStr, P.EASY)
        local line = mins .. (" · " .. STAR .. "%d xp/min"):format(math.floor((entry.score or 0) + 0.5))
        if entry.xp and entry.xp > 0 then
            line = line .. (" · +%d XP"):format(math.floor(entry.xp + 0.5))
        end
        if c.chainXp and c.chainXp > 0 then
            line = line .. " · chain"
        end
        if entry.red then line = line .. " · hard" end
        if Questing:IsIgnored(c.id) then line = line .. " · ignored" end
        sub[2] = Colors.Wrap(line, P.TEXT_MUTED)
    else
        local line = mins .. (" · " .. STAR .. "%d xp/min"):format(math.floor((entry.score or 0) + 0.5))
        if entry.red then line = line .. " · hard" end
        if Questing:IsIgnored(c.id) then line = line .. " · ignored" end
        sub[1] = Colors.Wrap(line, P.TEXT_MUTED)
    end
    if c.state == "active" then
        for _, o in ipairs(Compat.GetQuestObjectives(c.id)) do
            if o.text and o.text ~= "" then
                sub[#sub + 1] = "- " .. Colors.Progress(o.have, o.need) .. o.text .. "|r"
            end
        end
    end
    return { title = title, right = right, sub = sub }
end

---------------------------------------------------------------------------
-- Entries per tab
---------------------------------------------------------------------------
--- Active quests: scored entries first (turn-ins on top), then any not scored yet.
local function activeEntries()
    local list, seen = {}, {}
    for _, entry in ipairs(Questing:GetRanked()) do
        if entry.candidate.state ~= "available" then
            list[#list + 1] = entry
            seen[entry.candidate.id] = true
        end
    end
    for questId, info in pairs(WFC.Player.active) do
        if not seen[questId] then
            local brief = WFC.DB:GetQuestBrief(questId) or { id = questId, name = info.title, level = info.level }
            local c = {}
            for k, v in pairs(brief) do c[k] = v end
            c.state = info.isComplete and "complete" or "active"
            list[#list + 1] = { candidate = c, minutes = 0, score = 0 }
        end
    end
    table.sort(list, function(a, b)
        local ac, bc = a.candidate.state == "complete", b.candidate.state == "complete"
        if ac ~= bc then return ac end
        if a.score ~= b.score then return a.score > b.score end
        return a.candidate.id < b.candidate.id
    end)
    return list
end

function Panel:Entries(which)
    local key = which or tab
    if key == "active" then return activeEntries() end
    if key == "skip" then return Questing:GetSkip() end
    return Questing:GetNextUp()
end

--- Rows for the current tab: { kind = "quest"|"header"|"boss", questId, entry, icon, title, right,
--- sub = {lines}, alpha, group } and, for the Dungeons tab, its summary line.
--- The Next Up tab's first row: the suggested circuit, or nil.
local function circuitRow()
    if not Questing.settings.showCircuit then return nil end
    local circuit = Questing:GetCircuit()
    if not circuit then return nil end
    local zone = Compat.GetAreaName(circuit.area) or "this zone"
    local sub = {}
    for i, e in ipairs(circuit.entries) do
        local c = e.candidate
        local action = c.state == "available" and "pick up" or c.state == "complete" and "turn in" or "finish"
        local giver = c.state == "available" and Panel.GetQuestGiver(c.id)
        local extra = giver and (" (" .. giver .. ")") or ""
        sub[i] = ("%d. "):format(i) .. Panel.QuestName(c, true) .. Colors.Wrap(" · " .. action .. extra, P.TEXT_MUTED)
    end
    return {
        kind = "circuit", icon = STAR_ICON,
        title = Colors.Wrap(("★ Circuit: %s"):format(zone), P.NEW),
        right = Colors.Wrap(("~%d min · %d xp"):format(math.floor(circuit.minutes + 0.5), math.floor(circuit.xp + 0.5)), P.TEXT_MUTED),
        sub = sub,
    }
end

function Panel:DisplayRows()
    if tab == "dungeons" then return ns.Dungeons:Rows() end
    local list = {}
    if false then -- the Skip tab was removed (it didn't work well)
        for _, entry in ipairs(Questing:GetSkip()) do
            local c = entry.candidate
            local sub = {}
            for _, reason in ipairs(entry.reasons or {}) do
                local color = (reason:find("^Too hard") or reason:find("^Dungeon") or reason:find("^Elite")) and P.IMPOSSIBLE
                    or (reason:find("^Outleveled") or reason:find("^Low yield")) and P.TRIVIAL or P.DIFFICULT
                sub[#sub + 1] = Colors.Wrap("- " .. reason, color)
            end
            list[#list + 1] = { kind = "quest", questId = c.id, entry = entry, icon = iconFor(entry),
                title = Panel.QuestName(c, false), right = Colors.Wrap(Compat.GetAreaName(c.area) or "", P.TEXT_MUTED),
                sub = sub, alpha = Questing:IsIgnored(c.id) and 0.5 or 1 }
        end
        return list
    end
    if tab == "next" then list[1] = circuitRow() end
    for i, entry in ipairs(self:Entries()) do
        local text = Panel.RowText(entry, tab == "next" and i or nil)
        local id = entry.candidate.id
        local title = text.title
        if tab == "next" then
            title = Colors.Wrap(("#%d "):format(i), P.NEW) .. title
        end
        list[#list + 1] = { kind = "quest", questId = id, entry = entry, icon = iconFor(entry), title = title,
            right = text.right, sub = text.sub, alpha = Questing:IsIgnored(id) and 0.5 or 1, rank = tab == "next" and i or nil }
    end
    return list
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function font(fs, key)
    local f = WFC.Fonts:Get(key)
    if f then fs:SetFontObject(f) end
end

local function newRow(i)
    local row = CreateFrame("Button", nil, content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("TOPLEFT", 2, -2)
    row.title = row:CreateFontString(nil, "OVERLAY")
    font(row.title, "body")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 1)
    row.title:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY")
    font(row.right, "small")
    row.right:SetPoint("TOPRIGHT", -2, -1)
    row.right:SetJustifyH("RIGHT")
    row.title:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.sub = row:CreateFontString(nil, "OVERLAY")
    font(row.sub, "small")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", -2, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetJustifyV("TOP")
    -- Flat 8% white hover bar and a 2 px accent bar for the selection (design §4.2).
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.08)
    row.hover:Hide()
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT", -4, 0)
    row.accent:SetPoint("BOTTOMLEFT", -4, 0)
    row.accent:SetWidth(2)
    row.accent:SetColorTexture(P.NEW.r, P.NEW.g, P.NEW.b, 1)
    row.accent:Hide()
    row:SetScript("OnEnter", function(self) Panel:OnRowEnter(self) end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button) Panel:OnRowClick(self, button) end)
    rows[i] = row
    return row
end

local function contentWidth()
    local w = Questing.settings.window.w or WIDTH
    return w - 2 * PAD - 26 -- scroll bar
end

local function render()
    if not frame or not frame:IsShown() then return end
    local items, summary = Panel:DisplayRows()
    local y, width = 0, contentWidth()
    for i, item in ipairs(items) do
        local row = rows[i] or newRow(i)
        local header = item.kind == "header"
        row.kind, row.group, row.questId, row.entry, row.item = item.kind, item.group, item.questId, item.entry, item
        row.icon:SetTexture(item.icon)
        font(row.title, header and "subheader" or "body")
        row.title:SetText(header and ((item.collapsed and "+ " or "- ") .. item.title) or item.title)
        row.right:SetText(item.right or "")
        local sub = item.sub or {}
        row.sub:SetText(table.concat(sub, "\n"))
        local height = (header and 20 or 18) + LINE * #sub
        row:SetSize(width, height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetAlpha(item.alpha or 1)
        if row.questId and row.questId == Panel.selected then row.accent:Show() else row.accent:Hide() end
        row:Show()
        y = y + height + ROW_GAP
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    content:SetSize(width, math.max(y, 1))
    Panel.rowCount = #items
    if tab == "dungeons" then Panel:UpdateDungeonBar() end

    if frame.tabButtons then
        local activeCount = 0
        for _ in pairs(WFC.Player.active) do activeCount = activeCount + 1 end
        local nextCount = #Questing:GetNextUp()
        frame.tabButtons[1]:SetText(("Active (%d)"):format(activeCount))
        frame.tabButtons[2]:SetText(("Next Up (%d)"):format(nextCount))
        frame.tabButtons[3]:SetText("Dungeons")
    end

    updateAnyZoneButton()

    local msg
    local _, _, zoneName = Questing:CurrentZoneInfo()
    local isAnyZone = Questing.settings and Questing.settings.anyZone == true
    local scopeLabel = isAnyZone and "Any Zone" or (zoneName or "Current Zone")
    if not WFC.DB.ready then
        msg = "Waiting for QuestieDB…"
    elseif tab == "dungeons" then
        msg = summary or ""
    elseif not Questing.scoredAt then
        msg = "Scoring quests…"
    elseif #items == 0 then
        if tab == "active" then
            msg = "Your quest log is empty."
        elseif not isAnyZone then
            msg = ("No quests in %s. Click 'Any Zone' above."):format(scopeLabel)
        else
            msg = "No quests in range. Try /wfc quests options."
        end
    else
        local count = #items
        if tab == "next" and Questing.settings.showCircuit and items[1] and items[1].kind == "circuit" then
            count = count - 1
        end
        local suffix = (tab == "next") and (" · " .. scopeLabel) or ""
        msg = ("%d quests%s"):format(count, suffix) .. (Questing.partial and " · still indexing" or "")
    end
    status:SetText(Colors.Wrap(msg, P.TEXT_MUTED))
end

function Panel:Refresh()
    WFC:RunOutOfCombat("questing:panel", render)
end

local function selectTab(key)
    tab = key
    if Questing.settings then
        Questing.settings.lastTab = key
    end
    if bar then
        -- The Dungeons tab has a toolbar above its list.
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", PAD, -(scrollTop + (key == "dungeons" and BAR or 0)))
        scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, 34)
        if key == "dungeons" then bar:Show() else bar:Hide() end
        if key == "dungeons" then ignoredCheck:Hide() else ignoredCheck:Show() end
    end
    for i, t in ipairs(TABS) do
        local button = frame.tabButtons[i]
        if PanelTemplates_SetTab and frame.numTabs then
            if t.key == key then PanelTemplates_SetTab(frame, i) end
        elseif t.key == key then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
    Panel:Refresh()
end

local function createTabs()
    frame.tabButtons = {}
    local ok = PanelTemplates_SetNumTabs ~= nil
    for i, t in ipairs(TABS) do
        local button
        if ok then
            local okCreate, b = pcall(CreateFrame, "Button", NAME .. "Tab" .. i, frame, "PanelTabButtonTemplate")
            if okCreate then button = b else ok = false end
        end
        if not button then
            button = CreateFrame("Button", NAME .. "Tab" .. i, frame, "UIPanelButtonTemplate")
            button:SetSize(90, 20)
        end
        button:SetText(t.label)
        button:SetID(i)
        button:SetScript("OnClick", function() selectTab(t.key) end)
        frame.tabButtons[i] = button
    end
    if ok then
        frame.Tabs = frame.tabButtons
        PanelTemplates_SetNumTabs(frame, #TABS)
        frame.tabButtons[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
        for i = 2, #TABS do frame.tabButtons[i]:SetPoint("LEFT", frame.tabButtons[i - 1], "RIGHT", -14, 0) end
    else
        frame.numTabs = nil
        frame.tabButtons[1]:SetPoint("TOPLEFT", PAD, -28)
        for i = 2, #TABS do frame.tabButtons[i]:SetPoint("LEFT", frame.tabButtons[i - 1], "RIGHT", 4, 0) end
    end
    return ok
end

local function savePosition()
    if Questing.settings.dock and Panel.docked then return end
    local point, _, _, x, y = frame:GetPoint(1)
    local w = Questing.settings.window
    w.point, w.x, w.y = point, x, y
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
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(300, 360) elseif frame.SetMinResize then frame:SetMinResize(300, 360) end
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not (Questing.settings.dock and Panel.docked) then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    tinsert(UISpecialFrames, NAME)

    local title = "WFC Quests"
    if frame.SetTitle then
        frame:SetTitle(title)
    elseif not frame.TitleText then
        frame.TitleText = frame:CreateFontString(nil, "OVERLAY")
        frame.TitleText:SetPoint("TOP", 0, -6)
        frame.TitleText:SetText(title)
    else
        frame.TitleText:SetText(title)
    end
    if frame.TitleText then font(frame.TitleText, "header") end

    anyZoneBtn = CreateFrame("Button", NAME .. "AnyZoneButton", frame, "UIPanelButtonTemplate")
    anyZoneBtn:SetSize(92, 20)
    anyZoneBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -2)
    anyZoneBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    local smallFont = WFC.Fonts and WFC.Fonts:Get("small")
    if smallFont then anyZoneBtn:SetNormalFontObject(smallFont) end
    anyZoneBtn:SetScript("OnClick", function()
        Questing.settings.anyZone = not Questing.settings.anyZone
        updateAnyZoneButton()
        Panel:Refresh()
        Questing:RequestScore("anyZone", 0)
    end)
    anyZoneBtn:SetScript("OnEnter", function(self)
        local _, _, zName = Questing:CurrentZoneInfo()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Quest Search Scope", 1, 1, 1)
        if Questing.settings.anyZone then
            GameTooltip:AddLine("Mode: Any Zone (searching all zones)", 0.25, 1.0, 0.25)
        else
            GameTooltip:AddLine("Mode: Current Zone only (" .. (zName or "Current Zone") .. ")", 1.0, 0.82, 0.0)
        end
        GameTooltip:AddLine("Click to toggle between your current zone and all zones.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    anyZoneBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    updateAnyZoneButton()

    local tabsBelow = createTabs()
    local top = tabsBelow and 32 or 54
    scrollTop = top

    scroll = CreateFrame("ScrollFrame", NAME .. "Scroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -top)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, 34)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth(), 1)
    scroll:SetScrollChild(content)

    -- Dungeons toolbar: dungeon picker and its own map (Atlas-style view).
    bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", PAD, -top)
    bar:SetPoint("RIGHT", -PAD, 0)
    bar:SetHeight(BAR - 4)
    bar:Hide()
    local function barButton(label, width, tooltip, onClick)
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tooltip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    bar.picker = barButton("Dungeon", 190, "Choose a dungeon", function(self) ns.Menu:Show(self, ns.Dungeons:MenuItems()) end)
    bar.picker:SetPoint("LEFT", 0, 0)
    bar.map = barButton("Map", 50, "The dungeon's map, floors, bosses and your quests", function() ns.Dungeons:ShowMap() end)
    bar.map:SetPoint("RIGHT", 0, 0)
    Panel.bar = bar

    status = frame:CreateFontString(nil, "OVERLAY")
    font(status, "small")
    status:SetPoint("BOTTOMLEFT", PAD + 2, 12)

    ignoredCheck = CreateFrame("CheckButton", NAME .. "ShowIgnored", frame, "UICheckButtonTemplate")
    ignoredCheck:SetSize(22, 22)
    ignoredCheck:SetPoint("BOTTOMRIGHT", -PAD - 70, 6)
    ignoredCheck.label = ignoredCheck:CreateFontString(nil, "OVERLAY")
    font(ignoredCheck.label, "small")
    ignoredCheck.label:SetPoint("LEFT", ignoredCheck, "RIGHT", 0, 1)
    ignoredCheck.label:SetText("Show ignored")
    ignoredCheck:SetScript("OnClick", function(self)
        Questing.settings.showIgnored = self:GetChecked() == true
        Questing:RequestScore("showIgnored", 0)
    end)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        local w = Questing.settings.window
        w.w, w.h = frame:GetWidth(), frame:GetHeight()
        savePosition()
        Panel:Refresh()
    end)

    frame:SetScript("OnShow", function()
        if Panel.UpdateOpenButton then Panel:UpdateOpenButton() end
        Panel:Refresh()
    end)
    frame:SetScript("OnHide", function()
        if Questing.Rewards then Questing.Rewards:Hide() end
        if Panel.docked and not Panel.closingFromMap then
            Questing.settings.autoShow = false
            userHidden = true
        end
        if Panel.UpdateOpenButton then Panel:UpdateOpenButton() end
    end)
    Panel.frame = frame
    local initialTab = Questing.settings and Questing.settings.lastTab
    if initialTab == "skip" then initialTab = nil end -- that tab was removed
    if not initialTab then
        local activeCount = 0
        for _ in pairs(WFC.Player.active) do activeCount = activeCount + 1 end
        initialTab = (activeCount == 0) and "next" or "active"
    end
    selectTab(initialTab)
end

local function applySize()
    local w = Questing.settings.window
    frame:SetSize(w.w or WIDTH, w.h or HEIGHT)
end

function Panel:ResetPosition()
    if not frame then return end
    applySize()
    self:UpdateDock()
end

--- Anchors to the visible quest log (dock mode), or to the saved standalone position.
local openButton

--- A prominent "Quests »" button at the dock position (right edge of the map / quest log) that
--- reopens the panel. Only visible while the panel is closed and a log or the map is open.
function Panel:UpdateOpenButton()
    if not frame then return end
    local host = Compat.GetQuestLogFrame()
    if not host and WorldMapFrame and WorldMapFrame.IsVisible and WorldMapFrame:IsVisible() then
        host = WorldMapFrame
    end
    if not host or (frame and frame:IsShown()) or not host:IsShown() then
        if openButton then openButton:Hide() end
        return
    end
    if not openButton then
        openButton = CreateFrame("Button", "WFC_QuestOpenButton", UIParent, "UIPanelButtonTemplate")
        openButton:SetSize(72, 24)
        openButton:SetText("Quests »")
        local f = WFC.Fonts and WFC.Fonts:Get("small")
        if f then openButton:SetNormalFontObject(f) end
        openButton:SetFrameStrata("HIGH")
        openButton:SetFrameLevel(600)
        openButton:SetScript("OnClick", function() Panel:Show() end)
        openButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("WFC Quests", 1, 1, 1)
            GameTooltip:AddLine("Click to open the quest panel (also /wfc quests).", 0.75, 0.75, 0.75)
            GameTooltip:Show()
        end)
        openButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    openButton:ClearAllPoints()
    openButton:SetPoint("TOPLEFT", host, "TOPRIGHT", 2, -2)
    openButton:Show()
end

--- Anchors to the visible quest log (dock mode), or to the saved standalone position.
function Panel:UpdateDock()
    if not frame then return end
    local s = Questing.settings
    local log = s.dock and Compat.GetQuestLogFrame() or nil
    frame:ClearAllPoints()
    if log then
        frame:SetPoint("TOPLEFT", log, "TOPRIGHT", 4, 0)
        Panel.docked = true
        if s.autoShow and not userHidden and not frame:IsShown() then
            autoShown = true
            frame:Show()
        end
    else
        Panel.docked = false
        if s.dock then
            -- In dock mode, if there is no visible log/map, the panel must not float on screen.
            if frame:IsShown() then
                Panel.closingFromMap = true
                frame:Hide()
                Panel.closingFromMap = false
            end
            autoShown = false
        else
            -- Standalone mode (undocked)
            local w = s.window
            frame:SetPoint(w.point or "CENTER", UIParent, w.point or "CENTER", w.x or 0, w.y or 0)
        end
    end
    self:UpdateOpenButton()
end

function Panel:Show()
    if not frame then return end
    userHidden = false
    autoShown = false
    local s = Questing.settings
    if s.dock and not Compat.GetQuestLogFrame() then
        Compat.OpenWorldMap()
    end
    self:UpdateDock()
    frame:Show()
    if openButton then openButton:Hide() end
end

function Panel:Hide()
    if not frame then return end
    if Panel.docked and not Panel.closingFromMap then
        Questing.settings.autoShow = false
    end
    userHidden = true
    autoShown = false
    frame:Hide()
    self:UpdateOpenButton()
end

function Panel:Toggle()
    if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function Panel:SetTab(key) selectTab(key) end

function Panel:UpdateDungeonBar()
    local D = ns.Dungeons
    local id = D:Selected()
    local card = id and WFC.DB:GetDungeon(id)
    bar.picker:SetText(card and D.Title(card, (WFC.DB:GetDungeonDetails(id))) or "Dungeon")
end
function Panel:GetTab() return tab end
function Panel:Rows() return rows end

---------------------------------------------------------------------------
-- Row interaction
---------------------------------------------------------------------------
function Panel:OnRowEnter(row)
    row.hover:Show()
    if row.kind == "boss" then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(row.item.title)
        GameTooltip:AddLine("Dungeon boss", P.TEXT_MUTED.r, P.TEXT_MUTED.g, P.TEXT_MUTED.b)
        GameTooltip:Show()
        return
    end
    if row.kind == "circuit" then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(row.item.title)
        GameTooltip:AddLine("Optimized quest circuit in visiting order.", 1, 1, 1)
        GameTooltip:AddLine("Click to start routing with WFC Travel.", P.NEW.r, P.NEW.g, P.NEW.b)
        GameTooltip:Show()
        return
    end
    local c = row.entry and row.entry.candidate
    if not c then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Panel.QuestName(c, true))

    if c.state == "available" then
        local rankStr = row.rank and ("Recommended Next Quest · Rank #" .. row.rank) or "Recommended Next Quest"
        GameTooltip:AddLine(rankStr, P.EASY.r, P.EASY.g, P.EASY.b)
        local giver, coords = Panel.GetQuestGiver(c.id)
        if giver then
            GameTooltip:AddDoubleLine("Quest Giver:", giver, P.TEXT_MUTED.r, P.TEXT_MUTED.g, P.TEXT_MUTED.b, 1, 1, 1)
        end
        local zone = Compat.GetAreaName(c.area) or ""
        if zone ~= "" or coords then
            local locStr = zone .. (coords and (" (" .. coords .. ")") or "")
            GameTooltip:AddDoubleLine("Location:", locStr, P.TEXT_MUTED.r, P.TEXT_MUTED.g, P.TEXT_MUTED.b, 1, 1, 1)
        end
    elseif c.state == "complete" then
        GameTooltip:AddLine("Ready to turn in!", P.EASY.r, P.EASY.g, P.EASY.b)
    end

    local card = WFC.DB:GetQuest(c.id)
    local description = card and card.description
    if type(description) == "table" then description = table.concat(description, " ") end
    if description and description ~= "" then GameTooltip:AddLine(description, 1, 1, 1, true) end
    local e = row.entry
    if e.xp and e.xp > 0 then
        local scoreStr = ("%d xp · ~%d min (%d xp/min)"):format(math.floor(e.xp + 0.5), math.floor((e.minutes or 0) + 0.5), math.floor((e.score or 0) + 0.5))
        GameTooltip:AddDoubleLine("Reward:", scoreStr, P.TEXT_MUTED.r, P.TEXT_MUTED.g, P.TEXT_MUTED.b, 1, 1, 1)
    end
    if c.chainXp and c.chainXp > 0 then
        GameTooltip:AddLine(("Part of a chain: next quest gives +%d XP"):format(c.chainXp), P.NEW.r, P.NEW.g, P.NEW.b)
    end
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Shift-click to show on map / place waypoint", P.NEW.r, P.NEW.g, P.NEW.b)
    GameTooltip:AddLine("Right-click for options", P.TEXT_MUTED.r, P.TEXT_MUTED.g, P.TEXT_MUTED.b)
    GameTooltip:Show()
end

function Panel:OnRowClick(row, button)
    if row.kind == "header" then
        ns.Dungeons:Toggle(row.group)
        return
    end
    if row.kind == "circuit" then
        Questing:StartCircuit()
        return
    end
    local questId = row.questId
    if not questId then return end
    Panel.selected = questId
    if button == "RightButton" then
        ns.Menu:Open(row, questId)
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        Bridge:ShowQuestOnMap(questId)
    elseif WFC.Player.active[questId] and Compat.OpenQuestInLog(questId) then
        -- opened in the native log
    else
        Questing.Rewards:Show(questId, row)
    end
    self:Refresh()
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local hooked = {}
local mapToggleBtn

local function hookMapButton()
    if mapToggleBtn or not (WFC.UI and WFC.UI.AddMapHeaderButton) then return end
    mapToggleBtn = WFC.UI:AddMapHeaderButton("Quests", {
        text = "Quests",
        width = 54,
        tooltipTitle = "WFC Quests",
        tooltipText = function()
            return (frame and frame:IsShown()) and "Click to close quest panel." or "Click to open quest panel."
        end,
        onClick = function()
            Panel:Toggle()
        end,
    })
end

local function hookLogs()
    local names = { "WorldMapFrame" }
    for _, name in ipairs(Compat.QUEST_LOG_FRAMES) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        local f = _G[name]
        if f and not hooked[f] and f.HookScript then
            hooked[f] = true
            f:HookScript("OnShow", function()
                C_Timer.After(0, function() Panel:UpdateDock() end)
            end)
            f:HookScript("OnHide", function()
                Panel.closingFromMap = true
                Panel:UpdateDock()
                Panel.closingFromMap = false
            end)
        end
    end
    hookMapButton()
end

WFC:RegisterEvent("PLAYER_LOGIN", function()
    create()
    applySize()
    ignoredCheck:SetChecked(Questing.settings.showIgnored)
    hookLogs()
    Panel:UpdateDock()
end)

-- Quest log addons (e.g. Kerzo's ClassicQuestLog) may load after us.
WFC:RegisterEvent("ADDON_LOADED", function()
    if frame then hookLogs() end
end)

WFC:On("WFC_QUESTS_SCORED", function() Panel:Refresh() end)
WFC:On("WFC_QUEST_IGNORED", function() Panel:Refresh() end)
WFC:On("WFC_DB_READY", function() Panel:Refresh() end)
