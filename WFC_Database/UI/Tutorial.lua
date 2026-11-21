local _, ns = ...
local WFC = ns.WFC

-- Compact launch tutorial popups that stack on top of each other in the top-left corner.
-- Kept small (< 1/4 of the top-left screen quadrant: 248x152 px) with visual keycap/button
-- illustrations, a centered Close button at the bottom, and a "Show this every time"
-- checkbox synced two-way with each addon's "Tutorial on launch" setting.

WFC.UI = WFC.UI or {}
local UI = WFC.UI

local WIDTH, HEIGHT = 312, 152
local BASE_X, BASE_Y = 12, -12
local STACK_OFFSET = 4

local tutorials = {}      -- list of specs sorted by order
local tutorialsById = {}  -- [id] = spec
local shownOnce = false

local PALETTES = {
    gold  = { bg = { 0.22, 0.17, 0.05, 0.95 }, border = { 0.90, 0.72, 0.20, 1 }, text = { 1.00, 0.86, 0.30 } },
    cyan  = { bg = { 0.06, 0.18, 0.24, 0.95 }, border = { 0.30, 0.85, 1.00, 1 }, text = { 0.45, 0.90, 1.00 } },
    green = { bg = { 0.06, 0.20, 0.09, 0.95 }, border = { 0.25, 0.82, 0.35, 1 }, text = { 0.40, 0.95, 0.50 } },
    amber = { bg = { 0.22, 0.12, 0.05, 0.95 }, border = { 0.95, 0.55, 0.20, 1 }, text = { 1.00, 0.68, 0.35 } },
}

local function updateStackLayout()
    local visible = {}
    local maxW = WIDTH
    for _, spec in ipairs(tutorials) do
        if spec.frame and spec.frame:IsShown() then
            visible[#visible + 1] = spec
            if spec.neededWidth and spec.neededWidth > maxW then
                maxW = spec.neededWidth
            end
        end
    end
    local total = #visible
    for idx, spec in ipairs(visible) do
        local f = spec.frame
        f:SetWidth(maxW)
        -- idx == 1 is the top-most card in the stack; cards behind it sit at slightly lower frame levels
        local depth = idx - 1
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(math.max(10, 80 - depth * 10))
        if not f.userMoved then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", BASE_X + depth * STACK_OFFSET, BASE_Y - depth * STACK_OFFSET)
        end
        if f.stackBadge then
            if total > 1 then
                f.stackBadge:SetText(("%d/%d"):format(idx, total))
                f.stackBadge:Show()
            else
                f.stackBadge:Hide()
            end
        end
    end
end

local function bringToFront(targetSpec)
    if not targetSpec or tutorials[1] == targetSpec then return end
    for i, s in ipairs(tutorials) do
        if s == targetSpec then
            table.remove(tutorials, i)
            table.insert(tutorials, 1, targetSpec)
            break
        end
    end
    updateStackLayout()
end

local function createKeycapBadge(parent, pillText, styleName)
    local pal = PALETTES[styleName or "gold"] or PALETTES.gold
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    badge:SetSize(68, 18)
    if badge.SetBackdrop then
        badge:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        badge:SetBackdropColor(unpack(pal.bg))
        badge:SetBackdropBorderColor(unpack(pal.border))
    end
    -- Subtle top keycap highlight
    local hi = badge:CreateTexture(nil, "ARTWORK")
    hi:SetColorTexture(1, 1, 1, 0.12)
    hi:SetPoint("TOPLEFT", 1, -1)
    hi:SetPoint("TOPRIGHT", -1, -1)
    hi:SetHeight(4)

    -- Bottom keycap bevel shadow
    local lo = badge:CreateTexture(nil, "ARTWORK")
    lo:SetColorTexture(0, 0, 0, 0.35)
    lo:SetPoint("BOTTOMLEFT", 1, 1)
    lo:SetPoint("BOTTOMRIGHT", -1, 1)
    lo:SetHeight(3)

    local fs = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local fontObj = WFC.Fonts and WFC.Fonts:Get("small")
    if fontObj then fs:SetFontObject(fontObj) end
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(pillText or "")
    fs:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
    badge.label = fs
    return badge
end

local function buildFrame(spec)
    if spec.frame then return spec.frame end

    local f = CreateFrame("Frame", "WFC_Tutorial_" .. spec.id, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", BASE_X, BASE_Y)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseDown", function() bringToFront(spec) end)
    f:SetScript("OnDragStart", function(self)
        bringToFront(spec)
        self.userMoved = true
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.07, 0.08, 0.10, 0.96)
        f:SetBackdropBorderColor(0.32, 0.36, 0.42, 1)
    end

    -- Header band
    local headerBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    headerBg:SetColorTexture(0.13, 0.15, 0.19, 1)
    headerBg:SetPoint("TOPLEFT", 1, -1)
    headerBg:SetPoint("TOPRIGHT", -1, -1)
    headerBg:SetHeight(22)

    local accentLine = f:CreateTexture(nil, "ARTWORK")
    local accent = spec.accent or { 0.30, 0.85, 1.00 }
    accentLine:SetColorTexture(accent[1], accent[2], accent[3], 0.85)
    accentLine:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("TOPRIGHT", headerBg, "BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(1)

    if spec.icon then
        local hdrIcon = f:CreateTexture(nil, "OVERLAY")
        hdrIcon:SetSize(14, 14)
        hdrIcon:SetPoint("LEFT", headerBg, "LEFT", 7, 0)
        hdrIcon:SetTexture(spec.icon)
        if not tostring(spec.icon):find("GossipFrame") then
            hdrIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local subFont = WFC.Fonts and WFC.Fonts:Get("subheader")
    if subFont then title:SetFontObject(subFont) end
    title:SetPoint("LEFT", headerBg, "LEFT", spec.icon and 25 or 8, 0)
    title:SetText(spec.title or spec.id)
    title:SetTextColor(0.96, 0.96, 0.96)

    local stackBadge = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local smallFont = WFC.Fonts and WFC.Fonts:Get("small")
    if smallFont then stackBadge:SetFontObject(smallFont) end
    stackBadge:SetPoint("RIGHT", headerBg, "RIGHT", -8, 0)
    stackBadge:SetTextColor(0.68, 0.74, 0.82)
    f.stackBadge = stackBadge

    -- Illustrated feature rows (up to 3 rows)
    local rows = spec.rows or {}
    local maxTextW = 0
    for i = 1, math.min(3, #rows) do
        local r = rows[i]
        local rowY = -28 - (i - 1) * 24

        -- Icon illustration
        local iconFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
        iconFrame:SetSize(18, 18)
        iconFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, rowY)
        if iconFrame.SetBackdrop then
            iconFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            iconFrame:SetBackdropColor(0.04, 0.04, 0.05, 1)
            iconFrame:SetBackdropBorderColor(0.25, 0.28, 0.32, 1)
        end
        local tex = iconFrame:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", -1, 1)
        tex:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        if not tostring(r.icon or ""):find("GossipFrame") then
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end

        -- Keycap / Button illustration
        local badge = createKeycapBadge(f, r.pill, r.style)
        badge:SetPoint("LEFT", iconFrame, "RIGHT", 4, 0)

        -- Description text
        local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if smallFont then desc:SetFontObject(smallFont) end
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(false)
        desc:SetText(r.text or "")
        desc:SetTextColor(0.90, 0.90, 0.92)
        local w = (desc.GetUnboundedStringWidth and desc:GetUnboundedStringWidth())
            or (desc.GetStringWidth and desc:GetStringWidth()) or 0
        if w > maxTextW then maxTextW = w end
        desc:SetPoint("LEFT", badge, "RIGHT", 6, 0)
        desc:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    end

    spec.neededWidth = math.max(WIDTH, math.ceil(114 + maxTextW))
    f:SetWidth(spec.neededWidth)

    -- Footer divider
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(0.22, 0.25, 0.30, 0.9)
    div:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 49)
    div:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 49)
    div:SetHeight(1)

    -- "Show this every time" checkbox (enabled by default, tied to "Tutorial on launch" setting)
    local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    check:SetSize(20, 20)
    check:SetPoint("BOTTOM", f, "BOTTOM", -52, 26)

    local checkLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if smallFont then checkLabel:SetFontObject(smallFont) end
    checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)
    checkLabel:SetText("Show this every time")
    checkLabel:SetTextColor(0.82, 0.84, 0.88)

    check:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        UI:SetSettingValue(spec.id, spec.settingKey or "tutorialOnLaunch", on, spec.store)
    end)
    f.check = check

    -- Close button in the middle at the bottom
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(78, 20)
    closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
    closeBtn:SetText(CLOSE or "Close")
    if smallFont then closeBtn:SetNormalFontObject(smallFont) end
    closeBtn:SetScript("OnClick", function()
        f:Hide()
        updateStackLayout()
    end)
    f.closeBtn = closeBtn

    f:SetScript("OnShow", function()
        local key = spec.settingKey or "tutorialOnLaunch"
        local val = spec.store and spec.store[key]
        if val == nil then val = true end
        check:SetChecked(val and true or false)
    end)

    spec.frame = f
    return f
end

--- Registers an addon's launch tutorial card.
--- spec = { id = "Questing", order = 1, title = "...", icon = "...", accent = {r,g,b},
---          store = table, settingKey = "tutorialOnLaunch", rows = { { icon, pill, style, text }, ... } }
function UI:RegisterTutorial(spec)
    if not spec or not spec.id then return end
    spec.order = spec.order or (#tutorials + 1)
    spec.settingKey = spec.settingKey or "tutorialOnLaunch"
    if not tutorialsById[spec.id] then
        tutorials[#tutorials + 1] = spec
    else
        for i, existing in ipairs(tutorials) do
            if existing.id == spec.id then
                tutorials[i] = spec
                break
            end
        end
    end
    tutorialsById[spec.id] = spec
    table.sort(tutorials, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

--- Syncs the popup checkbox when the setting is changed in Blizzard's Settings panel.
function UI:OnSettingChanged(id, key, value)
    local spec = tutorialsById[id]
    if spec and key == (spec.settingKey or "tutorialOnLaunch") and spec.frame and spec.frame.check then
        spec.frame.check:SetChecked(value and true or false)
    end
end

--- Shows all registered tutorials whose "Tutorial on launch" setting is enabled (or all if force == true).
function UI:ShowLaunchTutorials(force)
    for _, spec in ipairs(tutorials) do
        local key = spec.settingKey or "tutorialOnLaunch"
        local enabled = spec.store and spec.store[key]
        if enabled == nil then enabled = true end
        if force or enabled then
            local f = buildFrame(spec)
            f.userMoved = false
            f:Show()
            f.check:SetChecked(enabled and true or false)
        end
    end
    updateStackLayout()
end

WFC:RegisterEvent("PLAYER_LOGIN", function()
    if shownOnce then return end
    shownOnce = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.6, function() UI:ShowLaunchTutorials(false) end)
    else
        UI:ShowLaunchTutorials(false)
    end
end)

WFC:AddCommand("tutorial", "Reopen the WFC launch tutorial popups", function()
    UI:ShowLaunchTutorials(true)
end)
