local _, ns = ...
local WFC = WFC

-- The "WFC Travel" box on the world map (plan.md §5.7, design.md §5.3): crosshair button
-- (click the map to place a target), clear button, ETA and the step list.
-- Our own non-secure frame anchored to WorldMapFrame (never Krowi_WorldMapButtons). The
-- click-capture overlay exists only while the crosshair is armed, so normal map clicks
-- are untouched; we never hook the map's own click handlers (CoreRules R10).

local Travel, Drawer, Flights = ns.Travel, ns.Drawer, ns.Flights
local Colors = WFC.Colors
local P = Colors.palette

local MapUI = {}
ns.MapUI = MapUI

local MAX_STEPS = 6
local LEG_DOT = {
    walk = P.TEXT, flight = P.NEW, boat = Drawer.STYLE.boat.color, zeppelin = Drawer.STYLE.zeppelin.color,
    tram = Drawer.STYLE.tram.color, portal = Drawer.STYLE.portal.color, hearth = Drawer.rgb("ffd100"),
}

local box, overlay, armButton, clearButton, eta, steps, hint, riskText, safeButton, deathButton
MapUI.armed = false

local function font(fs, key)
    local f = WFC.Fonts:Get(key)
    if f then fs:SetFontObject(f) end
end

---------------------------------------------------------------------------
-- Text (also used by specs and /wfc travel route)
---------------------------------------------------------------------------
--- Safe/Deathrun risk line for the current route, or nil.
local function riskLine(route)
    local risk = route.risk
    if Travel.fallback then return Colors.Wrap("No safe way found: showing the direct route", P.IMPOSSIBLE) end
    if not risk then return nil end
    if risk.pending then return Colors.Wrap("Danger data still loading", P.TEXT_MUTED) end
    local text
    if risk.stretches > 0 then
        text = Colors.Wrap("Risk: " .. (risk.text or (risk.stretches .. " risky stretches")), P.DIFFICULT)
    else
        text = Colors.Wrap("No risky stretches", P.EASY)
    end
    if risk.incomplete then text = text .. Colors.Wrap(" · danger data incomplete here", P.TEXT_MUTED) end
    return text
end

--- { eta = "...", risk = "..."|nil, steps = { "...", ... } } for the current route.
function MapUI.Lines()
    local route, legIndex = Travel:GetRoute()
    local target = Travel:GetTarget()
    if not target then
        local known = Flights:KnownCount()
        return { eta = known == 0 and "Visit any flight master once so Travel knows your flight points."
            or "Click the crosshair, then the map, to set a target.", steps = {} }
    end
    if not route then
        return { eta = Colors.Wrap("No route: " .. tostring(Travel.reason or "unreachable"), P.DIFFICULT), steps = {} }
    end
    local legs = route.legs
    local remaining = 0
    for i = legIndex or 1, #legs do remaining = remaining + legs[i].seconds end
    local anyNew = false
    local out = {}
    for i = legIndex or 1, #legs do
        local leg = legs[i]
        anyNew = anyNew or leg.isNew
        if #out < MAX_STEPS then
            local dot = LEG_DOT[leg.mode] or P.TEXT
            out[#out + 1] = Colors.Wrap("• ", dot) .. Travel.StepText(leg, i == #legs, target.name)
                .. Colors.Wrap("  " .. Travel.FormatTime(leg.seconds), P.TEXT_MUTED)
                .. (leg.isNew and WFC:NewTag("  ") or "")
        end
    end
    local count = #legs - (legIndex or 1) + 1
    local etaText = ("ETA %s · %d leg%s"):format(Travel.FormatTime(remaining), count, count == 1 and "" or "s")
        .. (anyNew and WFC:NewTag(" · ") or "")
    return { eta = etaText, risk = riskLine(route), steps = out }
end

function MapUI:Refresh()
    if not box then return end
    local lines = MapUI.Lines()
    eta:SetText(lines.eta)
    riskText:SetText(lines.risk or "")
    steps:SetText(table.concat(lines.steps, "\n"))
    if Travel:GetTarget() then clearButton:Enable() else clearButton:Disable() end
    local mode = Travel:GetMode()
    safeButton.label:SetText(mode == "safe" and Colors.Wrap("• Safe", P.EASY) or Colors.Wrap("Safe", P.TEXT_MUTED))
    deathButton.label:SetText(mode == "deathrun" and Colors.Wrap("• Deathrun", P.DIFFICULT) or Colors.Wrap("Deathrun", P.TEXT_MUTED))
    box:SetHeight(64 + 14 * (#lines.steps + (lines.risk and 1 or 0)))
end

---------------------------------------------------------------------------
-- Crosshair placement
---------------------------------------------------------------------------
function MapUI:Disarm()
    MapUI.armed = false
    if overlay then overlay:Hide() end
    if armButton then armButton:UnlockHighlight() end
end

function MapUI:Arm()
    if WFC:InCombat() or not overlay then return false end
    MapUI.armed = true
    overlay:Show()
    armButton:LockHighlight()
    return true
end

local function placeFromCursor()
    local sc = WorldMapFrame.ScrollContainer
    local x, y = sc:GetNormalizedCursorPosition()
    local mapId = WorldMapFrame:GetMapID()
    MapUI:Disarm()
    if mapId and x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        Travel:SetTarget(mapId, x, y, "Map target")
    end
end

local function createOverlay()
    local sc = WorldMapFrame.ScrollContainer
    overlay = CreateFrame("Frame", nil, sc)
    overlay:SetAllPoints(sc)
    overlay:SetFrameLevel((sc:GetFrameLevel() or 1) + 50)
    overlay:EnableMouse(true)
    overlay:Hide()
    hint = overlay:CreateFontString(nil, "OVERLAY")
    font(hint, "mapLabel")
    hint:SetPoint("TOP", 0, -12)
    hint:SetText(Colors.Wrap("Click the map to set a target · right-click or Esc to cancel", P.NEW))
    overlay:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then placeFromCursor() else MapUI:Disarm() end
    end)
    -- Esc cancels; every other key passes through to the game.
    overlay:SetScript("OnKeyDown", function(self, key)
        if WFC:InCombat() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            MapUI:Disarm()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    overlay:SetScript("OnShow", function(self) self:EnableKeyboard(true) end)
    overlay:SetScript("OnHide", function(self) self:EnableKeyboard(false) end)
    MapUI.overlay = overlay
end

---------------------------------------------------------------------------
-- Box
---------------------------------------------------------------------------
local function iconButton(parent, texture, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(tooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function create()
    box = CreateFrame("Frame", "WFC_TravelBox", WorldMapFrame, "BackdropTemplate")
    if box.SetBackdrop then
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        box:SetBackdropColor(0.086, 0.094, 0.11, 0.92)
        box:SetBackdropBorderColor(0.23, 0.25, 0.28, 1)
    end
    box:SetSize(280, 64)
    box:SetPoint("TOPRIGHT", WorldMapFrame.ScrollContainer or WorldMapFrame, "TOPRIGHT", -8, -8)
    box:SetFrameLevel((WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer:GetFrameLevel() or 1) + 60)
    box:EnableMouse(true)

    local title = box:CreateFontString(nil, "OVERLAY")
    font(title, "subheader")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText(Colors.Wrap("WFC Travel", { code = "|cffffd100" }))

    local closeButton = iconButton(box, "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", "Close WFC Travel (reopen with the Travel map button)", function()
        MapUI:HideBox()
    end)
    closeButton:SetPoint("TOPRIGHT", -4, -4)

    clearButton = iconButton(box, "Interface\\Buttons\\UI-StopButton", "Clear the target and route", function()
        Travel:ClearTarget()
    end)
    clearButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)

    armButton = iconButton(box, "Interface\\CURSOR\\Crosshairs", "Set target: click a spot on the map", function()
        if MapUI.armed then MapUI:Disarm() else MapUI:Arm() end
    end)
    armButton:SetPoint("RIGHT", clearButton, "LEFT", -2, 0)

    -- Safe / Deathrun (design §5.3: a two-state toggle; Deathrun tinted orange).
    local function modeButton(mode, width)
        local b = CreateFrame("Button", nil, box)
        b:SetSize(width, 18)
        b.label = b:CreateFontString(nil, "OVERLAY")
        font(b.label, "small")
        b.label:SetPoint("LEFT")
        b:SetScript("OnClick", function() Travel:SetMode(mode) end)
        return b
    end
    safeButton = modeButton("safe", 40)
    safeButton:SetPoint("TOPLEFT", 92, -7)
    deathButton = modeButton("deathrun", 62)
    deathButton:SetPoint("LEFT", safeButton, "RIGHT", 4, 0)
    MapUI.safeButton, MapUI.deathButton = safeButton, deathButton

    eta = box:CreateFontString(nil, "OVERLAY")
    font(eta, "body")
    eta:SetPoint("TOPLEFT", 8, -28)
    eta:SetPoint("RIGHT", -8, 0)
    eta:SetJustifyH("LEFT")
    riskText = box:CreateFontString(nil, "OVERLAY")
    font(riskText, "small")
    riskText:SetPoint("TOPLEFT", eta, "BOTTOMLEFT", 0, -2)
    riskText:SetPoint("RIGHT", -8, 0)
    riskText:SetJustifyH("LEFT")
    steps = box:CreateFontString(nil, "OVERLAY")
    font(steps, "small")
    steps:SetPoint("TOPLEFT", riskText, "BOTTOMLEFT", 0, -4)
    steps:SetPoint("RIGHT", -8, 0)
    steps:SetJustifyH("LEFT")
    steps:SetJustifyV("TOP")

    createOverlay()
    box:SetScript("OnShow", function() MapUI:Refresh() end)
    MapUI.box = box
    MapUI:Refresh()
end

function MapUI:ShowBox()
    Travel.settings.showPopup = true
    if box then
        box:Show()
        MapUI:Refresh()
    end
end

function MapUI:HideBox()
    Travel.settings.showPopup = false
    if box then box:Hide() end
end

function MapUI:ToggleBox()
    if box and box:IsShown() then
        MapUI:HideBox()
    else
        MapUI:ShowBox()
    end
end

local function hookMapButton()
    if not WFC.UI or not WFC.UI.AddMapHeaderButton then return end
    WFC.UI:AddMapHeaderButton("Travel", {
        text = "Travel",
        width = 54,
        tooltipTitle = "WFC Travel",
        tooltipText = function()
            return (box and box:IsShown()) and "Click to close the travel box." or "Click to open the travel box."
        end,
        onClick = function()
            MapUI:ToggleBox()
        end,
    })
end

local function init()
    if not box and WorldMapFrame then
        create()
        Drawer:Init()
        WorldMapFrame:HookScript("OnHide", function() MapUI:Disarm() end)
        if not Travel.settings.showPopup then box:Hide() end
    end
    hookMapButton()
end

WFC:RegisterEvent("PLAYER_LOGIN", init)
WFC:RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then init() end
end)
WFC:On("WFC_COMBAT_START", function() MapUI:Disarm() end)
WFC:On("WFC_TRAVEL_ROUTE", function() MapUI:Refresh() end)
WFC:On("WFC_TRAVEL_TARGET", function() MapUI:Refresh() end)
WFC:On("WFC_FLIGHTPOINTS_CHANGED", function() MapUI:Refresh() end)
WFC:On("WFC_TRAVEL_MODE", function() MapUI:Refresh() end)
