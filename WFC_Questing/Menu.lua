local _, ns = ...
local WFC = WFC

-- Right-click menu (plan.md §4.4, design.md §4.3). Native MenuUtil context menu when
-- the client has it; otherwise a small flat menu of our own. Never EasyMenu or
-- UIDropDownMenu (they taint).

local Questing, Bridge, Panel = ns.Questing, ns.Bridge, ns.Panel
local Compat = WFC.Compat
local P = WFC.Colors.palette

local Menu = {}
ns.Menu = Menu

local function travel()
    local T = WFC.Travel
    return T and T.PathToQuest and T or nil
end

--- The menu as data: { {title=}, {text=, fn=, disabled=}, {divider=true}, ... }.
function Menu.Build(questId)
    local entry = Questing:GetEntry(questId)
    local brief = WFC.DB:GetQuestBrief(questId)
    local c = entry and entry.candidate or brief or { id = questId, name = "Quest " .. questId }
    local items = {
        { title = Panel.QuestName(c, true) },
        { text = "Show on map", fn = function() Bridge:ShowQuestOnMap(questId) end },
        { text = "Path", disabled = travel() == nil, tooltip = "Needs WFC Travel",
          fn = function() local T = travel() if T then T:PathToQuest(questId) end end },
        { text = "Show rewards", fn = function() Questing.Rewards:Show(questId) end },
    }
    local isActive = (WFC.Player and WFC.Player.active and WFC.Player.active[questId])
        or (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questId) ~= nil)
        or (GetQuestLogIndexByID and GetQuestLogIndexByID(questId) and GetQuestLogIndexByID(questId) > 0)

    if isActive then
        local watched = Compat.IsQuestWatched(questId)
        items[#items + 1] = { text = watched and "Untrack" or "Track",
            fn = function() Compat.SetQuestWatched(questId, not watched) end }
        items[#items + 1] = { text = "Abandon",
            fn = function()
                if Compat and Compat.AbandonQuest then
                    Compat.AbandonQuest(questId)
                end
            end }
    end
    items[#items + 1] = { divider = true }
    local ignored = Questing:IsIgnored(questId)
    items[#items + 1] = { text = ignored and "Unignore" or "Ignore", fn = function() Questing:SetIgnored(questId, not ignored) end }
    return items
end

---------------------------------------------------------------------------
-- Compact Scrollable Menu Frame (used for Dungeon List and fallback menus)
---------------------------------------------------------------------------
local fallback
local ROW_H = 16
local DIV_H = 6
local MAX_VISIBLE_H = 196 -- ~12 compact rows visible at once
local SCROLL_STEP = ROW_H * 3

local function setScrollOffset(f, offset)
    local maxScroll = f.maxScroll or 0
    if offset < 0 then offset = 0 elseif offset > maxScroll then offset = maxScroll end
    f.scrollOffset = offset
    f.scroll:SetVerticalScroll(offset)
    if f.track and f.thumb then
        if maxScroll > 0 then
            f.track:Show()
            local trackH = f.track:GetHeight()
            local thumbH = math.max(20, trackH * (f.visibleH / f.totalH))
            f.thumb:SetHeight(thumbH)
            local travel = math.max(0, trackH - thumbH)
            local yOff = (offset / maxScroll) * travel
            f.thumb:ClearAllPoints()
            f.thumb:SetPoint("TOP", f.track, "TOP", 0, -yOff)
        else
            f.track:Hide()
        end
    end
end

local function createFallback()
    local f = CreateFrame("Frame", "WFC_QuestMenu", UIParent, "BackdropTemplate")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0.06, 0.065, 0.075, 0.97)
        f:SetBackdropBorderColor(0.3, 0.32, 0.36, 1)
    end
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:Hide()
    f.lines = {}
    f.scrollOffset = 0
    f.maxScroll = 0
    tinsert(UISpecialFrames, "WFC_QuestMenu")

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 2, -4)
    scroll:SetPoint("BOTTOMRIGHT", -12, 4)
    scroll:EnableMouseWheel(true)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    f.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(170, 1)
    scroll:SetScrollChild(content)
    f.content = content

    local track = CreateFrame("Frame", nil, f)
    track:SetWidth(6)
    track:SetPoint("TOPRIGHT", -3, -4)
    track:SetPoint("BOTTOMRIGHT", -3, 4)
    track:EnableMouse(true)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    track.bg:SetColorTexture(1, 1, 1, 0.06)
    f.track = track

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(6)
    thumb:SetHeight(28)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()
    thumb.tex:SetColorTexture(0.45, 0.55, 0.68, 0.85)
    thumb:SetScript("OnEnter", function(self) self.tex:SetColorTexture(0.55, 0.72, 0.92, 1) end)
    thumb:SetScript("OnLeave", function(self)
        if not f.draggingThumb then self.tex:SetColorTexture(0.45, 0.55, 0.68, 0.85) end
    end)
    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or (f.maxScroll or 0) <= 0 then return end
        f.draggingThumb = true
        local _, cursorY = GetCursorPosition()
        local scale = f:GetEffectiveScale() or 1
        f.dragStartY = cursorY / scale
        f.dragStartScroll = f.scrollOffset or 0
    end)
    thumb:SetScript("OnMouseUp", function(self)
        f.draggingThumb = false
        if not self:IsMouseOver() then self.tex:SetColorTexture(0.45, 0.55, 0.68, 0.85) end
    end)
    f.thumb = thumb

    track:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or (f.maxScroll or 0) <= 0 then return end
        local _, cursorY = GetCursorPosition()
        local scale = f:GetEffectiveScale() or 1
        cursorY = cursorY / scale
        local top = self:GetTop() or cursorY
        local trackH = self:GetHeight()
        local thumbH = thumb:GetHeight()
        local ratio = math.max(0, math.min(1, ((top - cursorY) - thumbH * 0.5) / math.max(1, trackH - thumbH)))
        setScrollOffset(f, ratio * f.maxScroll)
    end)

    f:SetScript("OnUpdate", function(self)
        if not self.draggingThumb then return end
        if not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then
            self.draggingThumb = false
            thumb.tex:SetColorTexture(0.45, 0.55, 0.68, 0.85)
            return
        end
        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale() or 1
        cursorY = cursorY / scale
        local dy = (self.dragStartY or cursorY) - cursorY
        local trackH = track:GetHeight()
        local thumbH = thumb:GetHeight()
        local travel = math.max(1, trackH - thumbH)
        setScrollOffset(self, (self.dragStartScroll or 0) + (dy / travel) * (self.maxScroll or 0))
    end)

    local function onWheel(_, delta)
        if (f.maxScroll or 0) <= 0 then return end
        setScrollOffset(f, (f.scrollOffset or 0) - delta * SCROLL_STEP)
    end
    f:SetScript("OnMouseWheel", onWheel)
    scroll:SetScript("OnMouseWheel", onWheel)

    -- Close on any click elsewhere (event exists on modern clients; Esc always works).
    pcall(f.RegisterEvent, f, "GLOBAL_MOUSE_DOWN")
    f:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
            self:Hide()
        end
    end)
    return f
end

local function line(f, i)
    local b = f.lines[i]
    if b then return b end
    b = CreateFrame("Button", nil, f.content)
    b:SetHeight(ROW_H)
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(_, delta)
        if (f.maxScroll or 0) > 0 then
            setScrollOffset(f, (f.scrollOffset or 0) - delta * SCROLL_STEP)
        end
    end)
    b.text = b:CreateFontString(nil, "OVERLAY")
    local font = WFC.Fonts:Get("small") or WFC.Fonts:Get("body")
    if font then b.text:SetFontObject(font) end
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.10)
    b.hl:Hide()
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(0.30, 0.75, 1.00, 0.14)
    b.sel:Hide()
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then self.hl:Show() end end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    f.lines[i] = b
    return b
end

local function openFallback(owner, items)
    fallback = fallback or createFallback()
    if fallback:IsShown() and fallback.owner == owner then
        fallback:Hide()
        return
    end
    fallback.owner = owner

    local y = 0
    local maxTextW = 145
    local selectedCenterY = nil

    for i, item in ipairs(items) do
        local b = line(fallback, i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", fallback.content, "TOPLEFT", 0, -y)
        b.item = item
        b.sel:Hide()
        if item.divider then
            b:SetHeight(DIV_H)
            b.text:SetText("")
            b:Disable()
            y = y + DIV_H
        else
            b:SetHeight(ROW_H)
            local text = item.title or item.text or ""
            if item.title then
                text = WFC.Colors.Wrap(text, P.NEW)
            elseif item.disabled then
                text = WFC.Colors.Wrap(text, P.TEXT_MUTED)
            end
            b.text:SetText(text)
            local tw = b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth() or (b.text.GetStringWidth and b.text:GetStringWidth()) or 0
            if tw > maxTextW then maxTextW = tw end
            if item.selected then
                b.sel:Show()
                selectedCenterY = y + ROW_H * 0.5
            end
            if item.title or item.disabled then b:Disable() else b:Enable() end
            y = y + ROW_H
        end
        b:SetScript("OnClick", function()
            fallback:Hide()
            if item.fn and not item.disabled then item.fn() end
        end)
        b:Show()
    end
    for i = #items + 1, #fallback.lines do fallback.lines[i]:Hide() end

    local totalH = math.max(ROW_H, y)
    local visibleH = math.min(totalH, MAX_VISIBLE_H)
    local scrollable = totalH > visibleH
    local width = math.max(165, math.min(230, math.ceil(maxTextW) + (scrollable and 26 or 16)))
    local contentW = width - (scrollable and 14 or 4)

    fallback.totalH = totalH
    fallback.visibleH = visibleH
    fallback.maxScroll = math.max(0, totalH - visibleH)

    fallback.scroll:ClearAllPoints()
    fallback.scroll:SetPoint("TOPLEFT", 2, -4)
    fallback.scroll:SetPoint("BOTTOMRIGHT", scrollable and -11 or -2, 4)
    fallback.content:SetSize(contentW, totalH)

    for i = 1, #items do
        local b = fallback.lines[i]
        b:SetWidth(contentW)
        b.text:SetPoint("RIGHT", -4, 0)
    end

    fallback:SetSize(width, visibleH + 8)
    fallback:ClearAllPoints()
    local xOff = (owner and owner.GetHeight and owner:GetHeight() <= 24 and #items > 8) and 0 or 20
    fallback:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", xOff, -2)
    fallback:Show()

    if scrollable and selectedCenterY then
        setScrollOffset(fallback, selectedCenterY - visibleH * 0.5)
    else
        setScrollOffset(fallback, 0)
    end

    Menu.frame = fallback
end

function Menu:Open(owner, questId)
    self:Show(owner, Menu.Build(questId))
end

--- Shows any item list (see Menu.Build for the shape). Uses our compact scrollable dropdown
--- for long lists (such as the Dungeons picker) or when native MenuUtil is unavailable.
function Menu:Show(owner, items)
    if Compat.HasContextMenu() and #items <= 8 then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            for _, item in ipairs(items) do
                if item.title then
                    root:CreateTitle(item.title)
                elseif item.divider then
                    root:CreateDivider()
                else
                    local button = root:CreateButton(item.text, item.fn)
                    if item.disabled and button.SetEnabled then button:SetEnabled(false) end
                end
            end
        end)
    else
        openFallback(owner, items)
    end
end
