local _, ns = ...
local WFC = WFC

-- Music bar: three small buttons in the top-left, right of the THEMES button, while a theme's
-- playlist is running (Panelka): previous song, pause / play, next song. Hovering shows what's
-- playing. Pause stops the song (WoW can't resume a sound midway); play starts it again from the
-- top. Hidden whenever no playlist is active.

local Overlay, Themes = ns.Overlay, ns.Themes

local MusicBar = {}
ns.MusicBar = MusicBar

local H, BTN = 28, 26
local bar

local function accent()
    local theme = Overlay:Theme()
    if theme and theme.accent then return Themes.RGB(theme.accent) end
    return 0.3, 0.85, 1
end

local function status()
    if not ns.Chrome then return nil end
    return ns.Chrome:MusicStatus()
end

local function tooltip(owner, action)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
    local r, g, b = accent()
    local track, found, _, _, paused = status()
    GameTooltip:AddLine("Theme music", r, g, b)
    GameTooltip:AddLine((paused and "Paused: " or "Now playing: ") .. (track or "nothing"), 1, 1, 1)
    GameTooltip:AddLine(("%d song(s) found · shuffled"):format(found or 0), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(action, 0.85, 0.85, 0.85)
    GameTooltip:Show()
end

local function makeButton(parent, x, label, action, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(BTN, H - 4)
    b:SetPoint("LEFT", parent, "LEFT", x, 0)
    b:RegisterForClicks("LeftButtonUp")
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.14)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    b.action = action
    b:SetScript("OnClick", function(self)
        onClick()
        MusicBar:Refresh()
        if GameTooltip:IsOwned(self) then tooltip(self, self.action) end
    end)
    b:SetScript("OnEnter", function(self) tooltip(self, self.action) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function build()
    if bar then return bar end
    bar = CreateFrame("Frame", "WFC_MusicBar", UIParent)
    bar:SetSize(BTN * 3 + 6, H)
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.08, 0.09, 0.12, 0.95)
    bar.edge = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = bar:CreateTexture(nil, "BORDER")
        if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        bar.edge[#bar.edge + 1] = t
    end
    -- "|" is WoW's escape character: "||" prints one bar.
    bar.prev = makeButton(bar, 3, "||<", "Previous song", function() ns.Chrome:MusicPrev() end)
    bar.play = makeButton(bar, 3 + BTN, "||||", "Pause", function() ns.Chrome:MusicPause() end)
    bar.next = makeButton(bar, 3 + BTN * 2, ">||", "Next song", function() ns.Chrome:MusicNext() end)
    bar:Hide()
    return bar
end

local function place()
    bar:ClearAllPoints()
    local launcher = _G.WFC_ThemeLauncher
    if launcher and launcher:IsShown() then
        bar:SetPoint("LEFT", launcher, "RIGHT", 4, 0)
    else
        bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 14, -60)
    end
end

function MusicBar:Refresh()
    local track, _, _, active, paused = status()
    if not active then
        if bar then bar:Hide() end
        return
    end
    build()
    place()
    local r, g, b = accent()
    for _, t in ipairs(bar.edge) do t:SetColorTexture(r, g, b, 0.9) end
    for _, btn in ipairs({ bar.prev, bar.play, bar.next }) do btn.text:SetTextColor(r * 0.4 + 0.6, g * 0.4 + 0.6, b * 0.4 + 0.6) end
    bar.play.text:SetText(paused and ">" or "||||")
    bar.play.action = paused and ("Play (starts " .. (track or "the song") .. " again)") or "Pause"
    bar:Show()
end

WFC:On("WFC_MUSIC_CHANGED", function() MusicBar:Refresh() end)
WFC:On("WFC_OVERLAY_STYLE", function() C_Timer.After(0.2, function() MusicBar:Refresh() end) end)
