local _, ns = ...
local WFC = WFC

-- THEMES: a 28 px launcher next to the WFC launchers in the top-left (after Professions /
-- Inventory value / Aspect), drawn as a 2x2 swatch of the four looks with the active one lit.
--   left-click   open the picker          right-click  next theme
--   drag         move (saved)             shift-right  put it back next to the others
-- The picker shows a card per theme with a live mini preview built from that theme's own art;
-- it is a registered window, so it wears whichever theme is active.

local Overlay, Styles, Themes = ns.Overlay, ns.Styles, ns.Themes
local Slice, SliceColor, Gradient = Styles.Slice, Styles.SliceColor, Styles.Gradient

local TB = {}
ns.ThemeButton = TB

local SIZE = 28
local PICK_W, CARD_H, PAD, GAP = 352, 56, 14, 6
local FRAME_MEDIA = "Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Frame\\"
local NEIGHBORS = { "WFC_AspectLauncher", "WFC_ItemTipsValueLauncher", "WFC_ValueLauncher", "WFC_ProfessionsLauncher" }

local launcher, picker

local function styleColor(id)
    if id == "original" then return 0.78, 0.16, 0.10 end
    if id == "originalplus" then
        local P = WFC.Player or {}
        local key = Overlay.settings and Overlay.settings.theme
        if not key or key == "auto" or key == "blizzard" or not Themes.list[key] then
            key = Themes.Pick(P.raceFile, P.faction, P.raceId)
        end
        return Themes.RGB(Themes.list[key].accent)
    end
    local c = Styles.packs[id] and Styles.packs[id].spec.tokens.swatch
    if c then return c[1], c[2], c[3] end
    return 0.5, 0.5, 0.5
end

local function activeAccent()
    local r, g, b = styleColor(Overlay:Style())
    return r, g, b
end

local function font(fs, header, size)
    local theme = Overlay:Theme()
    local obj = theme and ns.Fonts and ns.Fonts:Object(theme, header)
    if obj then
        fs:SetFontObject(obj)
    else
        fs:SetFontObject(header and "GameFontNormalLarge" or "GameFontHighlightSmall")
    end
    if size then
        local f, _, flags = fs:GetFont()
        if f then fs:SetFont(f, size, flags) end
    end
end

---------------------------------------------------------------------------
-- Launcher
---------------------------------------------------------------------------
local hookedNeighbors = {}

local function place()
    if not launcher then return end
    local s = Overlay.settings
    launcher:ClearAllPoints()
    local p = s and s.themeButtonPos
    if p and p.point then
        launcher:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
        return
    end
    for _, name in ipairs(NEIGHBORS) do
        local f = _G[name]
        if f and f ~= launcher and f:IsShown() then
            launcher:SetPoint("LEFT", f, "RIGHT", 4, 0)
            return
        end
    end
    launcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 14, -60)
end

local function hookNeighbors()
    for _, name in ipairs(NEIGHBORS) do
        local f = _G[name]
        if f and not hookedNeighbors[f] and f.HookScript then
            hookedNeighbors[f] = true
            for _, script in ipairs({ "OnShow", "OnHide", "OnDragStop" }) do
                pcall(f.HookScript, f, script, function() C_Timer.After(0, place) end)
            end
        end
    end
end

local function nextStyle()
    local cur = Overlay:Style()
    for i, id in ipairs(Styles.ORDER) do
        if id == cur then return Styles.ORDER[i % #Styles.ORDER + 1] end
    end
    return "originalplus"
end

local function buildLauncher()
    if launcher then return launcher end
    local b = CreateFrame("Button", "WFC_ThemeLauncher", UIParent)
    launcher = b
    b:SetSize(SIZE, SIZE)
    b:SetFrameStrata("HIGH")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.08, 0.09, 0.12, 0.95)
    b.edge = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = b:CreateTexture(nil, "BORDER")
        if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        b.edge[#b.edge + 1] = t
    end
    -- Swatches, one per theme: 2x2 for up to four, 3x3 for up to nine.
    b.sw = {}
    local n = #Styles.ORDER
    local cols = n <= 4 and 2 or 3
    local cell = cols == 2 and 9 or 6
    local span = cols * cell + (cols - 1) * 2
    local x0 = math.floor((SIZE - span) / 2)
    for i, id in ipairs(Styles.ORDER) do
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetSize(cell, cell)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        t:SetPoint("TOPLEFT", x0 + col * (cell + 2), -x0 - row * (cell + 2))
        t.id = id
        b.sw[i] = t
    end
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.ring:SetSize(cell + 2, cell + 2)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.12)

    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        Overlay.settings.themeButtonPos = { point = point or "TOPLEFT", x = math.floor((x or 0) + 0.5), y = math.floor((y or 0) + 0.5) }
    end)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if IsShiftKeyDown() then
                Overlay.settings.themeButtonPos = nil
                place()
                return
            end
            local id = nextStyle()
            Overlay:SetStyle(id)
            WFC:Print("Theme:", Styles.INFO[id].name)
            if GameTooltip:IsOwned(launcher) then launcher:GetScript("OnEnter")(launcher) end
        else
            TB:TogglePicker()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        local r, g, bl = activeAccent()
        GameTooltip:AddLine("Themes", r, g, bl)
        GameTooltip:AddLine("Current: " .. Styles.INFO[Overlay:Style()].name, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: choose a theme", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: next theme", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move · Shift+right-click: put back", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function paintLauncher()
    local b = launcher
    if not b then return end
    local cur = Overlay:Style()
    local r, g, bl = activeAccent()
    for _, t in ipairs(b.edge) do t:SetColorTexture(r, g, bl, 0.9) end
    for _, t in ipairs(b.sw) do
        local sr, sg, sb = styleColor(t.id)
        local on = t.id == cur
        t:SetColorTexture(sr, sg, sb, on and 1 or 0.35)
        if on then
            b.ring:ClearAllPoints()
            b.ring:SetPoint("CENTER", t, "CENTER")
            b.ring:SetVertexColor(1, 1, 1, 0.9)
            t:SetDrawLayer("OVERLAY", 1)
        else
            t:SetDrawLayer("ARTWORK", 0)
        end
    end
    -- the white square sits under the lit swatch as a 1 px frame
    b.ring:SetDrawLayer("OVERLAY", 0)
end

---------------------------------------------------------------------------
-- Picker
---------------------------------------------------------------------------
-- Mini previews for the two looks that aren't style packs.
local function miniOriginal(parent)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    end
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 8, -9); bar:SetSize(26, 3); bar:SetColorTexture(1, 0.82, 0, 1)
    for i = 1, 2 do
        local l = f:CreateTexture(nil, "ARTWORK")
        l:SetPoint("TOPLEFT", 8, -13 - i * 6); l:SetSize(i == 1 and 40 or 30, 2); l:SetColorTexture(1, 1, 1, 0.5)
    end
    local btn = f:CreateTexture(nil, "ARTWORK")
    btn:SetPoint("BOTTOMRIGHT", -7, 6); btn:SetSize(22, 8); btn:SetColorTexture(0.55, 0.08, 0.05, 1)
    return f
end

local function miniOriginalPlus(parent)
    local f = CreateFrame("Frame", nil, parent)
    local fill = f:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetTexture(FRAME_MEDIA .. "stone", "REPEAT", "REPEAT")
    f.fill = fill
    local edge = Slice(f, "OVERLAY", 0, FRAME_MEDIA .. "border", 0.125, 4, 1)
    local corner = f:CreateTexture(nil, "OVERLAY", nil, 2)
    corner:SetTexture(FRAME_MEDIA .. "corner"); corner:SetSize(18, 18); corner:SetPoint("BOTTOMLEFT", -2, -2)
    corner:SetTexCoord(0, 1, 1, 0)
    local gem = f:CreateTexture(nil, "OVERLAY", nil, 3)
    gem:SetTexture(FRAME_MEDIA .. "crest"); gem:SetSize(40, 10); gem:SetPoint("CENTER", f, "TOP", 0, 0)
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 8, -10); bar:SetSize(26, 3)
    f.bar = bar
    for i = 1, 2 do
        local l = f:CreateTexture(nil, "ARTWORK")
        l:SetPoint("TOPLEFT", 8, -14 - i * 6); l:SetSize(i == 1 and 40 or 30, 2); l:SetColorTexture(0.93, 0.93, 0.93, 0.5)
    end
    function f:Paint()
        local r, g, b = styleColor("originalplus")
        local key = Overlay.settings.theme
        local P = WFC.Player or {}
        if not key or key == "auto" or key == "blizzard" or not Themes.list[key] then key = Themes.Pick(P.raceFile, P.faction, P.raceId) end
        local br, bg, bb = Themes.RGB(Themes.list[key].bg)
        fill:SetVertexColor(math.min(1, br * 1.3), math.min(1, bg * 1.3), math.min(1, bb * 1.3), 1)
        bar:SetColorTexture(r, g, b, 1)
        SliceColor(edge, { 1, 1, 1, 1 })
    end
    return f
end

local function card(parent, id, i)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(PICK_W - PAD * 2, CARD_H)
    c:SetPoint("TOPLEFT", PAD, -44 - (i - 1) * (CARD_H + GAP))
    c.id = id
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.edge = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = c:CreateTexture(nil, "BORDER")
        if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        c.edge[#c.edge + 1] = t
    end
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints()
    -- preview
    local pv
    if id == "original" then pv = miniOriginal(c)
    elseif id == "originalplus" then pv = miniOriginalPlus(c)
    else pv = Styles.packs[id]:Mini(c) end
    pv:SetSize(72, 42)
    pv:SetPoint("LEFT", 9, 0)
    c.preview = pv
    c.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    c.name:SetPoint("TOPLEFT", pv, "TOPRIGHT", 12, 2)
    c.desc = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.desc:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3)
    c.desc:SetPoint("RIGHT", c, "RIGHT", -10, 0)
    c.desc:SetJustifyH("LEFT")
    c.desc:SetJustifyV("TOP")
    c.desc:SetHeight(28)
    c.pill = c:CreateTexture(nil, "ARTWORK")
    c.pill:SetSize(50, 15)
    c.pill:SetPoint("TOPRIGHT", -8, -8)
    c.pillText = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.pillText:SetPoint("CENTER", c.pill, "CENTER", 0, 0)
    c:SetScript("OnClick", function(self)
        if Overlay:Style() ~= self.id then
            Overlay:SetStyle(self.id)
            if InCombatLockdown() then WFC:Print("Theme changes after combat.") end
        end
    end)
    return c
end

local function paintPicker()
    if not picker then return end
    local theme = Overlay:Theme()
    local cur = Overlay:Style()
    local ar, ag, ab = activeAccent()
    local surface = theme and theme.surface or "1E1E1E"
    local sr, sg, sb = Themes.RGB(surface)
    local tr, tg, tb = 1, 1, 1
    local mr, mg, mb = 0.66, 0.66, 0.66
    if theme then
        tr, tg, tb = Themes.RGB(theme.text)
        mr, mg, mb = Themes.RGB(theme.textMuted)
    end
    font(picker.TitleText, true)
    picker.TitleText:SetText(cur == "futuristic" and "THEMES" or "Themes")
    font(picker.foot, false, 11)
    picker.foot:SetTextColor(mr, mg, mb)
    picker.Bg:SetColorTexture(0.06, 0.065, 0.08, 0.96)
    for _, t in ipairs(picker.NineSlice.edge) do t:SetColorTexture(ar, ag, ab, 0.8) end
    picker.closeX1:SetVertexColor(ar, ag, ab, 1)
    picker.closeX2:SetVertexColor(ar, ag, ab, 1)
    for _, c in ipairs(picker.cards) do
        local on = c.id == cur
        local cr, cg, cb = styleColor(c.id)
        c.bg:SetColorTexture(math.min(1, sr * 1.25 + (on and ar * 0.10 or 0)), math.min(1, sg * 1.25 + (on and ag * 0.10 or 0)),
            math.min(1, sb * 1.25 + (on and ab * 0.10 or 0)), 0.92)
        for _, t in ipairs(c.edge) do t:SetColorTexture(on and cr or 1, on and cg or 1, on and cb or 1, on and 0.95 or 0.08) end
        c.hl:SetColorTexture(cr, cg, cb, 0.10)
        font(c.name, true, cur == "futuristic" and 14 or 16)
        c.name:SetText(Styles.INFO[c.id].name)
        c.name:SetTextColor(cr * 0.5 + 0.5, cg * 0.5 + 0.5, cb * 0.5 + 0.5)
        font(c.desc, false, 11)
        c.desc:SetText(Styles.INFO[c.id].desc)
        c.desc:SetTextColor(tr * 0.85, tg * 0.85, tb * 0.85)
        font(c.pillText, false, 10)
        if on then
            c.pill:SetColorTexture(cr, cg, cb, 0.9)
            c.pillText:SetText("ACTIVE")
            c.pillText:SetTextColor(0.05, 0.05, 0.05)
            c.pill:Show(); c.pillText:Show()
        else
            c.pill:Hide(); c.pillText:Hide()
        end
        if c.preview.Paint then c.preview:Paint() end
    end
end

local function buildPicker()
    if picker then return picker end
    local f = CreateFrame("Frame", "WFC_ThemePicker", UIParent)
    picker = f
    local n = #Styles.ORDER
    f:SetSize(PICK_W, 44 + n * (CARD_H + GAP) + 26)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    -- Fallback body for the Original look (the skins fade "Bg" / "NineSlice" like Blizzard's).
    f.Bg = f:CreateTexture(nil, "BACKGROUND")
    f.Bg:SetAllPoints()
    f.NineSlice = CreateFrame("Frame", nil, f)
    f.NineSlice:SetAllPoints()
    f.NineSlice.edge = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = f.NineSlice:CreateTexture(nil, "BORDER")
        if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        f.NineSlice.edge[#f.NineSlice.edge + 1] = t
    end
    -- Every FontString gets a font before any SetText (the client errors on "Font not set").
    f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.TitleText:SetPoint("TOP", 0, -8)
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.foot:SetPoint("BOTTOM", 0, 10)
    f.foot:SetText("Right-click the button to cycle · /wfcui themes")
    -- Our own close cross (Blizzard's red button clashes with the new looks).
    local close = CreateFrame("Button", nil, f)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -8, -8)
    f.closeX1 = close:CreateTexture(nil, "ARTWORK"); f.closeX1:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.closeX2 = close:CreateTexture(nil, "ARTWORK"); f.closeX2:SetTexture("Interface\\Buttons\\WHITE8X8")
    for i, t in ipairs({ f.closeX1, f.closeX2 }) do
        t:SetSize(14, 2); t:SetPoint("CENTER")
        if t.SetRotation then t:SetRotation(i == 1 and math.pi / 4 or -math.pi / 4) end
    end
    local chl = close:CreateTexture(nil, "HIGHLIGHT"); chl:SetAllPoints(); chl:SetColorTexture(1, 1, 1, 0.12)
    close:SetScript("OnClick", function() f:Hide() end)
    f.cards = {}
    for i, id in ipairs(Styles.ORDER) do f.cards[i] = card(f, id, i) end
    f:SetScript("OnShow", function() paintPicker() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "WFC_ThemePicker") end
    ns.Skin:Register("WFC_ThemePicker", "core", { noTopLeft = true, keepFonts = true })
    ns.Skin:Watch("WFC_ThemePicker")
    return f
end

function TB:TogglePicker()
    local f = buildPicker()
    if f:IsShown() then f:Hide() return end
    f:ClearAllPoints()
    if launcher and launcher:IsShown() then
        f:SetPoint("TOPLEFT", launcher, "BOTTOMLEFT", 0, -8)
    else
        f:SetPoint("CENTER")
    end
    f:Show()
end

function TB:Refresh()
    local s = Overlay.settings
    if not s then return end
    if s.themeButton == false then
        if launcher then launcher:Hide() end
    else
        buildLauncher()
        hookNeighbors()
        place()
        paintLauncher()
        launcher:Show()
    end
    if picker and picker:IsShown() then paintPicker() end
end

WFC:RegisterEvent("PLAYER_LOGIN", function()
    -- The other launchers are created at PLAYER_LOGIN too; settle after them.
    C_Timer.After(0.5, function() TB:Refresh() end)
    C_Timer.After(3, function() hookNeighbors(); place() end)
end)
