local _, ns = ...
local WFC = WFC

-- NodeGlow: a colour sparkle with a nameplate-style label that sits ON the mining vein.
--
-- How it stays on the rock (same technique as NodeSight): with the Interact Key on, the game
-- gives the object your Interact Key would pick (the "softinteract" unit) a nameplate, and
-- nameplates are positioned in the 3D world by the client. The sparkle is attached to that
-- nameplate. So it marks the nearest vein in front of / around you, no hovering needed.
--
-- While the sparkle is on, these CVars are set (old values saved and put back when it's
-- turned off or on logout): softTargetInteract 3, SoftTargetIconGameObject 1,
-- SoftTargetInteractArc 2 (all around you), SoftTargetInteractRange (nodeGlowRange, default 60 yd; the game may cap it lower).
-- Sprites (Media/*.tga) are white with brightness as alpha, so SetVertexColor tints them.

local NodeGlow = {}
ns.NodeGlow = NodeGlow

local MEDIA = "Interface\\AddOns\\WFC_ItemTips\\Media\\"
local FADE_IN, FADE_OUT = 8, 5
local LIFT = 10 -- px above the nameplate's bottom edge

local CVARS = {
    { "softTargetInteract", "3" },
    { "SoftTargetIconGameObject", "1" },
    { "SoftTargetInteractArc", "2" },
    { "SoftTargetInteractRange", function() local s = ns.Tips and ns.Tips.settings return tostring(s and tonumber(s.nodeGlowRange) or 60) end },
}

-- Vein name pattern -> ore item, for the price on the second line.
local ORES = {
    { "rich thorium", 10620 }, { "small thorium", 10620 }, { "thorium", 10620 },
    { "dark iron", 11370 }, { "truesilver", 7911 }, { "mithril", 3858 },
    { "gold", 2776 }, { "iron", 2772 }, { "silver", 2775 }, { "tin", 2771 }, { "copper", 2770 },
    { "incendicite", 3340 }, { "bloodstone", 4278 },
}

local function oreFor(name)
    local lower = name:lower()
    for _, o in ipairs(ORES) do
        if lower:find("%f[%a]" .. o[1] .. "%f[%A]") then return o[2] end
    end
end

local function settings() return ns.Tips and ns.Tips.settings end
local function enabled()
    local s = settings()
    return s and s.nodeGlow ~= false
end

local frame, alpha, want = nil, 0, 0
local plate, shownFor, previewing

local function build()
    if frame then return frame end
    local f = CreateFrame("Frame", "WFC_NodeGlow", UIParent)
    frame = f
    f:SetSize(160, 120)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:SetAlpha(0)
    f:Hide()

    local function tex(file, layer, size)
        local t = f:CreateTexture(nil, layer)
        t:SetTexture(MEDIA .. file)
        t:SetSize(size, size)
        t:SetPoint("CENTER", f, "BOTTOM", 0, 24)
        t:SetBlendMode("ADD")
        return t
    end
    f.glow = tex("glow", "BACKGROUND", 70)
    f.dust = tex("dust", "BORDER", 84)
    f.star = tex("sparkle", "ARTWORK", 54)
    f.star2 = tex("sparkle", "ARTWORK", 30)

    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    f.name:SetPoint("BOTTOM", f.star, "TOP", 0, -10)
    f.name:SetShadowOffset(1, -1)
    f.detail = f:CreateFontString(nil, "OVERLAY")
    f.detail:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    f.detail:SetPoint("TOP", f.name, "BOTTOM", 0, -1)
    f.detail:SetTextColor(0.85, 0.85, 0.85)

    f:SetScript("OnUpdate", function(self, elapsed)
        alpha = alpha + (want - alpha) * math.min(1, elapsed * (want > alpha and FADE_IN or FADE_OUT))
        if want == 0 and alpha < 0.02 then
            alpha = 0
            self:SetAlpha(0)
            self:Hide()
            return
        end
        self:SetAlpha(alpha)
        local t = GetTime()
        local pulse = 0.5 + 0.5 * math.sin(t * 5)
        self.star:SetSize(46 + 14 * pulse, 46 + 14 * pulse)
        if self.star.SetRotation then
            self.star:SetRotation(t * 0.6)
            self.star2:SetRotation(-t * 1.1 + 0.785)
            self.dust:SetRotation(t * 0.35)
        end
        self.star2:SetAlpha(0.5 + 0.5 * math.sin(t * 7 + 1))
        self.glow:SetAlpha(0.45 + 0.35 * pulse)
        self.dust:SetAlpha(0.55 + 0.25 * math.sin(t * 3))
    end)
    return f
end

local function paint(f, nodeName, profName, reqSkill, playerSkill, r, g, b)
    for _, t in ipairs({ f.glow, f.dust, f.star }) do t:SetVertexColor(r, g, b) end
    f.star2:SetVertexColor(1, 1, 1)
    f.name:SetText((nodeName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    f.name:SetTextColor(r, g, b)
    local parts = {}
    if reqSkill == 0 then parts[1] = profName
    else parts[1] = playerSkill and ("%s %d/%d"):format(profName, playerSkill, reqSkill) or (profName .. " " .. reqSkill) end
    local ore = oreFor(nodeName)
    if ore and WFC.DB and WFC.DB.GetPrice then
        local ok, ah, vendor = pcall(WFC.DB.GetPrice, WFC.DB, ore)
        local p = ok and (ah or vendor)
        if p and p > 0 and WFC.Compat and WFC.Compat.FormatMoney then
            local item = WFC.DB:GetItemClient(ore) or WFC.DB:GetItem(ore)
            parts[#parts + 1] = ("%s ~%s"):format(item and item.name or "ore", WFC.Compat.FormatMoney(p))
        end
    end
    f.detail:SetText(table.concat(parts, " · "))
end

-- Hide at once and detach: nameplates are recycled, so fading out on the old plate made the
-- sparkle flash on whatever mob got that plate next.
local function hide()
    want, alpha = 0, 0
    shownFor, plate = nil, nil
    if frame then
        frame:Hide()
        frame:SetAlpha(0)
        frame:ClearAllPoints()
        frame:SetParent(UIParent)
    end
end

---------------------------------------------------------------------------
-- The soft-interact nameplate
---------------------------------------------------------------------------
local function unitOf(p)
    return p and (p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit))
end

local function softPlate()
    if not C_NamePlate then return end
    local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, "softinteract")
    if ok and p then return p end
    if not C_NamePlate.GetNamePlates then return end
    for _, np in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local u = unitOf(np)
        local ok2, same = pcall(UnitIsUnit, u or "none", "softinteract")
        if ok2 and WFC.Safe(same) then return np end
    end
end

-- Forever doesn't report UnitExists("softinteract"), but the plate exists: read the object
-- through the plate's own unit token (nameplateN), its name text, then the interact icon.
local function plateName(p)
    local u = unitOf(p)
    if u then
        local n = WFC.Safe(UnitName(u))
        if type(n) == "string" and n ~= "" then return n, u end
    end
    local uf = p.UnitFrame
    local fs = uf and uf.name
    local n = fs and fs.GetText and WFC.Safe(fs:GetText())
    if type(n) == "string" and n ~= "" then return n, u end
    return nil, u
end

-- What the game's interact icon on the plate shows: "mining", "herb" or nil.
local function plateIconKind(p)
    local icon = p.UnitFrame and p.UnitFrame.SoftTargetFrame and p.UnitFrame.SoftTargetFrame.Icon
    if not icon then return end
    local tex = WFC.Safe(icon.GetTexture and icon:GetTexture())
    local atlas = WFC.Safe(icon.GetAtlas and icon:GetAtlas())
    local text = (type(tex) == "string" and tex:lower() or tostring(tex or "")) .. " "
        .. (type(atlas) == "string" and atlas:lower() or "")
    if text:find("herb") then return "herb" end
    if text:find("min") then return "mining" end
end

-- Corpses only get a soft-interact nameplate with SoftTargetNameplateInteract on. Put back
-- when the sparkle is turned off or on logout.
local corpseCvarSaved
local function setCorpsePlates(on)
    if InCombatLockdown() then return end
    if on and corpseCvarSaved == nil then
        local cur = GetCVar("SoftTargetNameplateInteract")
        if cur ~= nil and cur ~= "1" then
            corpseCvarSaved = cur
            pcall(SetCVar, "SoftTargetNameplateInteract", "1")
        end
    elseif not on and corpseCvarSaved ~= nil then
        pcall(SetCVar, "SoftTargetNameplateInteract", corpseCvarSaved)
        corpseCvarSaved = nil
    end
end
NodeGlow.RestoreCorpseCvar = function() setCorpsePlates(false) end

-- Forever does not report the "softinteract" unit reliably, so corpse plates are turned on only
-- for a short window after a fight (that's when there are corpses to skin), never in rest areas
-- (towns, where flight masters and trainers need their normal names and titles).
local CORPSE_WINDOW = 90 -- seconds after leaving combat
local lastFightEnd = -1000
local function softCorpse()
    local Tips = ns.Tips
    if not (Tips and Tips.HasProfession and Tips:HasProfession(393, "Skinning")) then return false end
    if IsResting() then return false end
    return GetTime() - lastFightEnd < CORPSE_WINDOW
end
NodeGlow.MarkFightEnded = function()
    lastFightEnd = GetTime()
    C_Timer.After(CORPSE_WINDOW + 1, function() setCorpsePlates(softCorpse()) end)
end

NodeGlow.lastInfo = "nothing seen yet"

local function refresh()
    if previewing then return end
    if not enabled() then return hide() end
    setCorpsePlates(softCorpse())
    local p = softPlate()
    if not p then NodeGlow.lastInfo = "no interact plate" return hide() end
    local name, unit = plateName(p)
    local Tips = ns.Tips
    if not Tips then return hide() end
    local prof, req, skill, r, g, b
    -- 1. A skinnable corpse (only if you have Skinning)
    if unit and Tips.SkinInfo then
        req, skill, r, g, b = Tips:SkinInfo(unit)
        if req then prof = "Skinning" end
    end
    -- 2. A mining vein / herb by name (only if you have that profession)
    if not req and name and Tips.MiningInfo then
        req, skill, r, g, b = Tips:MiningInfo(name)
        if req then prof = "Mining" end
    end
    if not req and name and Tips.HerbInfo then
        req, skill, r, g, b = Tips:HerbInfo(name)
        if req then prof = "Herbalism" end
    end
    -- 3. Unnamed node: go by the game's interact icon, neutral gold.
    if not req then
        local icon = plateIconKind(p)
        if icon == "mining" and Tips:HasProfession(186, "Mining") then prof = "Mining"
        elseif icon == "herb" and Tips:HasProfession(182, "Herbalism") then prof = "Herbalism" end
        if prof then
            name = name or (prof == "Mining" and "Mining node" or "Herb")
            req, skill, r, g, b = 0, nil, 1, 0.82, 0.2
        end
    end
    NodeGlow.lastInfo = ("plate unit %s · name %s · %s"):format(tostring(unit), tostring(name),
        prof or "nothing you can gather")
    if not req then return hide() end

    local f = build()
    if p ~= plate then
        plate = p
        f:SetParent(p)
        f:SetFrameStrata("HIGH")
        f:ClearAllPoints()
        f:SetPoint("BOTTOM", p, "BOTTOM", 0, LIFT - 24)
        f:SetScale(1)
    end
    local key = prof .. ":" .. name
    if shownFor ~= key then
        shownFor = key
        paint(f, name, prof, req, skill, r, g, b)
    end
    want = 1
    f:Show()
end

---------------------------------------------------------------------------
-- CVars: set while the sparkle is on, put back after
---------------------------------------------------------------------------
local pendingCvars
local function applyCvars(on)
    if InCombatLockdown() then pendingCvars = on and "on" or "off"; return end
    pendingCvars = nil
    local s = settings()
    if not s then return end
    if on then
        s.nodeGlowSaved = s.nodeGlowSaved or {}
        for _, c in ipairs(CVARS) do
            local cur = GetCVar(c[1])
            local want = type(c[2]) == "function" and c[2]() or c[2]
            if cur ~= nil and cur ~= want then
                if s.nodeGlowSaved[c[1]] == nil then s.nodeGlowSaved[c[1]] = cur end
                pcall(SetCVar, c[1], want)
            end
        end
    elseif s.nodeGlowSaved then
        for k, v in pairs(s.nodeGlowSaved) do pcall(SetCVar, k, v) end
        s.nodeGlowSaved = nil
    end
end

--- Called when the setting changes.
function NodeGlow:Sync()
    applyCvars(enabled())
    if not enabled() then setCorpsePlates(false); hide() else refresh() end
end

-- Kept for older callers (tooltip hover no longer drives the sparkle).
function NodeGlow:Show() end
function NodeGlow:Hide() if not previewing then hide() end end

--- /wfc tips glow test: preview over the cursor for 3 seconds.
function NodeGlow:Preview()
    local f = build()
    previewing = true
    plate = nil
    f:SetParent(UIParent)
    f:SetFrameStrata("TOOLTIP")
    local x, y = GetCursorPosition()
    local sc = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x / sc, y / sc + 20)
    shownFor = nil
    paint(f, "Tin Vein", "Mining", 65, 125, 0.30, 0.85, 0.30)
    want = 1
    f:Show()
    C_Timer.After(3, function()
        previewing = false
        hide()
        refresh()
    end)
end

--- One-line status for /wfc tips glow why.
function NodeGlow:Why()
    if not enabled() then return "off (/wfc tips glow on)" end
    local bits = {}
    for _, c in ipairs(CVARS) do bits[#bits + 1] = c[1] .. "=" .. tostring(GetCVar(c[1])) end
    refresh()
    return ("%s · shown: %s · %s"):format(NodeGlow.lastInfo, want == 1 and "yes" or "no", table.concat(bits, ", "))
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "SKILL_LINES_CHANGED", "PLAYER_UPDATE_RESTING" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "NAME_PLATE_UNIT_REMOVED" and plate and arg1 and unitOf(plate) == arg1 then
        hide() -- our plate is going back to the pool: leave it before another mob gets it
    end
    if event == "PLAYER_LOGOUT" then
        setCorpsePlates(false)
        applyCvars(false) -- leave the game's settings as they were; re-applied next login
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        applyCvars(enabled())
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingCvars then applyCvars(pendingCvars == "on") end
        NodeGlow.MarkFightEnded()
    elseif event == "SKILL_LINES_CHANGED" then
        shownFor = nil -- repaint with the new skill
    end
    refresh()
end)
if NamePlateDriverFrame and hooksecurefunc and NamePlateDriverFrame.OnSoftTargetUpdate then
    hooksecurefunc(NamePlateDriverFrame, "OnSoftTargetUpdate", function() refresh() end)
end

return NodeGlow
