local _, ns = ...
local WFC = WFC
local Caster = ns.Caster

-- HunterRange: ranged dead-zone indicator for WoW Forever.
--
-- Forever keeps the Classic dead zone: melee reaches ~5 yd, Auto Shot works from 8 to 35 yd
-- (41 with Hawk Eye), and nothing hits in between. Forever gives addons no distance to other
-- units (UnitPosition(target) returns nil) and no world->screen projection, so instead of a
-- fake-scaled 3D bubble this shows the zone the game itself reports:
--   C_Spell.IsSpellInRange(Auto Shot / Shoot Bow ...)  -> inside shooting range?
--   C_Spell.IsSpellInRange(Raptor Strike / Wing Clip)  -> in melee?
--   CheckInteractDistance(target, 3) (~10 yd)          -> close but not shootable = dead zone
-- All three return plain values in combat on Forever.
--
-- Visuals (all our own frames; Blizzard frames are only used as SetPoint anchors):
--   * HUD: icon + zone label + hint + a segmented ruler (melee | dead zone | in range | far)
--     with a marker that glides to the active segment. Fades with the target, pulses red
--     in the dead zone. Click-through unless unlocked (/wfc caster unlock).
--   * Target marker: a slim glowing bar under the target's nameplate in the zone colour.

local HunterRange = {}
ns.HunterRange = HunterRange

local P = WFC.Colors and WFC.Colors.palette or {}
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function rgb(c, fr, fg, fb) return c and c.r or fr, c and c.g or fg, c and c.b or fb end

-- Zones, left to right on the ruler. `w` is the segment's share of the ruler width
-- (stylised, not to scale: true yards would make the dead zone a sliver).
local ZONES = {
    { key = "MELEE", label = "MELEE",     hint = "in melee reach",          tick = "5",  w = 0.18, color = { rgb(P.DIFFICULT, 1, 0.5, 0.25) } },
    { key = "DEAD",  label = "DEAD ZONE", hint = "too close to shoot",       tick = "8",  w = 0.22, color = { rgb(P.IMPOSSIBLE, 1, 0.1, 0.1) } },
    { key = "SHOOT", label = "IN RANGE",  hint = "clear to shoot",           tick = "35", w = 0.42, color = { rgb(P.EASY, 0.25, 0.75, 0.25) } },
    { key = "FAR",   label = "TOO FAR",   hint = "close in to shoot",                    w = 0.18, color = { rgb(P.FAIR, 1, 1, 0) } },
}
local ZONE_BY_KEY = {}
for i, z in ipairs(ZONES) do z.index = i; ZONE_BY_KEY[z.key] = z end

local RANGED_SPELLS = { "Auto Shot", "Shoot Bow", "Shoot Gun", "Shoot Crossbow", "Throw" }
local MELEE_SPELLS  = { "Raptor Strike", "Wing Clip", "Mongoose Bite" }

local HUD_W, HUD_H, ICON = 236, 50, 38
local TRACK_H = 6
local SOUND_COOLDOWN = 2.0

local hud, marker
local rangedSpell, meleeSpell, rangedIcon
local current            -- current zone table or nil
local markerX, targetX   -- ruler marker position (px), animated
local alpha, wantAlpha = 0, 0
local flash = 0          -- 1 -> 0 burst of glow on zone change
local lastSound = 0
local unlocked = false

---------------------------------------------------------------------------
-- Spells & range
---------------------------------------------------------------------------
local function isSecret(v)
    return WFC.Compat and WFC.Compat.IsSecret and WFC.Compat.IsSecret(v) or false
end

local function knownSpell(name)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    local id = ok and type(info) == "table" and info.spellID
    if not id or isSecret(id) then return nil end
    local known = (IsPlayerSpell and IsPlayerSpell(id))
        or (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id))
    if not known then return nil end
    return id, info.iconID
end

local function resolveSpells()
    rangedSpell, rangedIcon, meleeSpell = nil, nil, nil
    for _, n in ipairs(RANGED_SPELLS) do
        local id, icon = knownSpell(n)
        if id then rangedSpell, rangedIcon = id, icon; break end
    end
    for _, n in ipairs(MELEE_SPELLS) do
        local id = knownSpell(n)
        if id then meleeSpell = id; break end
    end
end

--- true / false / nil (unknown) for a spell against the target.
local function inRange(spellId, unit)
    if not spellId then return nil end
    local fn = C_Spell and C_Spell.IsSpellInRange
    if fn then
        local ok, r = pcall(fn, spellId, unit)
        if ok and not isSecret(r) and r ~= nil then return r == true or r == 1 end
        return nil
    end
    if IsSpellInRange then -- Classic Era (11509): 1 / 0 / nil
        local ok, r = pcall(IsSpellInRange, spellId, unit)
        if ok and r ~= nil then return r == 1 end
    end
    return nil
end

local function near(unit) -- ~10 yd (duel distance)
    if not CheckInteractDistance then return nil end
    local ok, r = pcall(CheckInteractDistance, unit, 3)
    if not ok or isSecret(r) then return nil end
    return r and true or false
end

local function hostileTarget()
    if not UnitExists("target") then return false end
    local canAttack = WFC.Safe(UnitCanAttack("player", "target"))
    local dead = WFC.Safe(UnitIsDeadOrGhost("target"))
    return canAttack == true and not dead
end

--- Zone table for the target, or nil when it can't be determined.
local function computeZone()
    if not rangedSpell then return nil end
    if inRange(meleeSpell, "target") then return ZONE_BY_KEY.MELEE end
    local shoot = inRange(rangedSpell, "target")
    if shoot == true then return ZONE_BY_KEY.SHOOT end
    local close = near("target")
    if shoot == false then return close and ZONE_BY_KEY.DEAD or ZONE_BY_KEY.FAR end
    if close then return ZONE_BY_KEY.DEAD end -- no range answer (e.g. out of line of sight)
    return nil
end

local function enabledForPlayer()
    local s = Caster.settings
    if not s or not s.hunterRangeBubble then return false end
    local _, class = UnitClass("player")
    if class == "HUNTER" then return true end
    if s.hunterOnlyClass then return false end
    return GetInventoryItemLink and GetInventoryItemLink("player", 18) ~= nil -- ranged slot
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
local function solid(parent, layer, sub, r, g, b, a)
    local t = parent:CreateTexture(nil, layer, nil, sub or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

--- Vertical gradient (top -> bottom alpha) when the client supports it, else flat.
local function gradient(tex, r, g, b, aTop, aBottom)
    if tex.SetGradient and CreateColor then
        -- (no SetVertexColor afterwards: it would overwrite the per-corner gradient colours)
        if pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r, g, b, aBottom), CreateColor(r, g, b, aTop)) then return end
    end
    tex:SetVertexColor(r, g, b, (aTop + aBottom) / 2)
end

--- Soft outer glow: three stacked rings fading outward.
local function makeGlow(parent)
    local rings = {}
    for i, a in ipairs({ 0.55, 0.28, 0.12 }) do
        local o = i * 1.5
        local ring = {}
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = solid(parent, "BACKGROUND", -8 + i, 1, 1, 1, a)
            t.baseAlpha = a
            if side == "TOP" or side == "BOTTOM" then
                t:SetHeight(1.5)
                t:SetPoint(side .. "LEFT", parent, side .. "LEFT", -o, side == "TOP" and o or -o)
                t:SetPoint(side .. "RIGHT", parent, side .. "RIGHT", o, side == "TOP" and o or -o)
            else
                t:SetWidth(1.5)
                t:SetPoint("TOP" .. side, parent, "TOP" .. side, side == "LEFT" and -o or o, o)
                t:SetPoint("BOTTOM" .. side, parent, "BOTTOM" .. side, side == "LEFT" and -o or o, -o)
            end
            ring[#ring + 1] = t
        end
        rings[i] = ring
    end
    function rings:Set(r, g, b, strength)
        for _, ring in ipairs(self) do
            for _, t in ipairs(ring) do t:SetVertexColor(r, g, b, t.baseAlpha * strength) end
        end
    end
    return rings
end

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------
local function savePosition(self)
    local s = Caster.settings
    if not s then return end
    local point, _, rel, x, y = self:GetPoint(1)
    s.rangeHudPos = { point = point, rel = rel, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
end

local function buildHud()
    if hud then return hud end
    local f = CreateFrame("Frame", "WFC_HunterRangeHud", UIParent)
    hud = f
    f:SetSize(HUD_W, HUD_H)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self) end)
    f:SetAlpha(0)
    f:Hide()

    -- Glass panel: dark fill, faint top sheen, 1px border tinted by zone, soft outer glow.
    f.glow = makeGlow(f)
    f.bg = solid(f, "BACKGROUND", 0, 0.035, 0.045, 0.06, 0.88)
    f.bg:SetAllPoints()
    f.sheen = solid(f, "BACKGROUND", 1, 1, 1, 1, 1)
    f.sheen:SetPoint("TOPLEFT", 1, -1)
    f.sheen:SetPoint("TOPRIGHT", -1, -1)
    f.sheen:SetHeight(HUD_H * 0.45)
    gradient(f.sheen, 1, 1, 1, 0.07, 0)
    f.border = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = solid(f, "BORDER", 0, 1, 1, 1, 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else
            t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
        end
        f.border[#f.border + 1] = t
    end
    -- Accent strip on the left edge, in the zone colour.
    f.accent = solid(f, "ARTWORK", 0, 1, 1, 1, 1)
    f.accent:SetPoint("TOPLEFT", 1, -1)
    f.accent:SetPoint("BOTTOMLEFT", 1, 1)
    f.accent:SetWidth(3)

    -- Icon with its own 1px frame.
    local iconFrame = CreateFrame("Frame", nil, f)
    iconFrame:SetSize(ICON, ICON)
    iconFrame:SetPoint("LEFT", 10, 0)
    f.iconBorder = solid(iconFrame, "BACKGROUND", 0, 0, 0, 0, 1)
    f.iconBorder:SetAllPoints()
    f.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Label + hint.
    local textX = 10 + ICON + 10
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    local header = WFC.Fonts and WFC.Fonts:Get("header")
    if header then f.label:SetFontObject(header) end
    f.label:SetPoint("TOPLEFT", textX, -5)
    f.label:SetShadowOffset(1, -1)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local small = WFC.Fonts and WFC.Fonts:Get("small")
    if small then f.hint:SetFontObject(small) end
    f.hint:SetPoint("LEFT", f.label, "RIGHT", 8, -1)
    f.hint:SetTextColor(rgb(P.TEXT_MUTED, 0.66, 0.66, 0.66))

    -- Segmented ruler.
    local trackW = HUD_W - textX - 12
    f.track = CreateFrame("Frame", nil, f)
    f.track:SetSize(trackW, TRACK_H)
    f.track:SetPoint("BOTTOMLEFT", textX, 12)
    f.segments = {}
    local x = 0
    for i, z in ipairs(ZONES) do
        local w = math.floor(trackW * z.w + 0.5)
        if i == #ZONES then w = trackW - x end
        local seg = CreateFrame("Frame", nil, f.track)
        seg:SetSize(w - (i < #ZONES and 2 or 0), TRACK_H)
        seg:SetPoint("LEFT", x, 0)
        seg.fill = solid(seg, "ARTWORK", 0, z.color[1], z.color[2], z.color[3], 0.18)
        seg.fill:SetAllPoints()
        seg.lit = solid(seg, "ARTWORK", 1, 1, 1, 1, 1)
        seg.lit:SetAllPoints()
        gradient(seg.lit, z.color[1], z.color[2], z.color[3], 1, 0.65)
        seg.lit:SetAlpha(0)
        seg.center = x + (w - (i < #ZONES and 2 or 0)) / 2
        seg.zone = z
        f.segments[i] = seg
        if z.tick then
            local tick = f.track:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if small then tick:SetFontObject(small) end
            tick:SetPoint("TOP", f.track, "BOTTOMLEFT", x + w - 1, -1)
            tick:SetText(z.tick)
            tick:SetTextColor(0.5, 0.52, 0.56)
        end
        x = x + w
    end
    -- Marker: a bright notch with a soft halo, gliding over the ruler.
    f.marker = CreateFrame("Frame", nil, f.track)
    f.marker:SetSize(4, TRACK_H + 8)
    f.marker.halo = solid(f.marker, "OVERLAY", 0, 1, 1, 1, 0.25)
    f.marker.halo:SetPoint("CENTER")
    f.marker.halo:SetSize(10, TRACK_H + 10)
    f.marker.core = solid(f.marker, "OVERLAY", 1, 1, 1, 1, 1)
    f.marker.core:SetPoint("CENTER")
    f.marker.core:SetSize(2, TRACK_H + 6)

    return f
end

local function applyHudPosition()
    if not hud then return end
    local p = Caster.settings and Caster.settings.rangeHudPos
    hud:ClearAllPoints()
    if p and p.point then
        hud:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
    else
        hud:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    end
end

local function paintZone(z)
    local r, g, b = z.color[1], z.color[2], z.color[3]
    hud.label:SetText(z.label)
    hud.label:SetTextColor(r, g, b)
    hud.hint:SetText(z.hint)
    for _, t in ipairs(hud.border) do t:SetVertexColor(r * 0.55, g * 0.55, b * 0.55, 1) end
    hud.accent:SetVertexColor(r, g, b, 1)
    hud.iconBorder:SetVertexColor(r * 0.8, g * 0.8, b * 0.8, 1)
    hud.icon:SetDesaturated(z.key ~= "SHOOT")
    hud.marker.core:SetVertexColor(1, 1, 1, 1)
    hud.marker.halo:SetVertexColor(r, g, b, 0.45)
    for _, seg in ipairs(hud.segments) do
        seg.fill:SetAlpha(seg.zone == z and 0 or 1)
    end
    targetX = hud.segments[z.index].center
    if not markerX then markerX = targetX end
end

---------------------------------------------------------------------------
-- Nameplate marker
---------------------------------------------------------------------------
local function buildMarker()
    if marker then return marker end
    local m = CreateFrame("Frame", "WFC_HunterRangePlateMarker", UIParent)
    marker = m
    m:SetSize(64, 4)
    m:SetFrameStrata("LOW")
    m:Hide()
    m.glow = makeGlow(m)
    m.bar = solid(m, "ARTWORK", 0, 1, 1, 1, 1)
    m.bar:SetAllPoints()
    m.diamonds = {}
    for i, side in ipairs({ "LEFT", "RIGHT" }) do
        local d = solid(m, "OVERLAY", 0, 1, 1, 1, 1)
        d:SetSize(6, 6)
        d:SetPoint("CENTER", m, side, side == "LEFT" and -8 or 8, 0)
        if d.SetRotation then d:SetRotation(math.pi / 4) end
        m.diamonds[i] = d
    end
    return m
end

local function updateMarker(z, pulse)
    local s = Caster.settings
    if not (s and s.hunterPlateMarker ~= false and z) then
        if marker then marker:Hide() end
        return
    end
    local plate
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, "target", false)
        if ok and p and not isSecret(p) then plate = p end
    end
    if not plate then
        if marker then marker:Hide() end
        return
    end
    local m = buildMarker()
    if m.anchor ~= plate then
        m:ClearAllPoints()
        if not pcall(m.SetPoint, m, "TOP", plate, "BOTTOM", 0, 2) then m:Hide(); return end
        m.anchor = plate
    end
    local r, g, b = z.color[1], z.color[2], z.color[3]
    local dead = z.key == "DEAD"
    m.bar:SetVertexColor(r, g, b, dead and (0.65 + 0.35 * pulse) or 0.9)
    m.glow:Set(r, g, b, dead and (0.5 + 0.5 * pulse) or 0.45)
    for _, d in ipairs(m.diamonds) do
        d:SetShown(dead)
        d:SetVertexColor(r, g, b, 0.6 + 0.4 * pulse)
    end
    m:Show()
end

---------------------------------------------------------------------------
-- Update loop
---------------------------------------------------------------------------
local function playWarning()
    local s = Caster.settings
    if not (s and s.hunterAudioWarn and PlaySound) then return end
    local now = GetTime()
    if now - lastSound < SOUND_COOLDOWN then return end
    lastSound = now
    local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
    pcall(PlaySound, kit, "SFX")
end

local tickAccum = 0
local function onUpdate(self, elapsed)
    -- Zone check at 10 Hz; animation every frame.
    tickAccum = tickAccum + elapsed
    if tickAccum >= 0.1 then
        tickAccum = 0
        local z = (unlocked and (current or ZONE_BY_KEY.SHOOT))
            or (enabledForPlayer() and hostileTarget() and computeZone()) or nil
        if z then
            if z ~= current then
                if z.key == "DEAD" and current and current.key ~= "DEAD" then playWarning() end
                current = z
                flash = 1
                paintZone(z)
            end
            wantAlpha = 1
        else
            wantAlpha = 0
        end
    end

    -- The frame stays shown (click-through, alpha 0) so the 10 Hz check keeps running and the
    -- HUD comes back on its own, e.g. when the target re-enters line of sight.
    local k = math.min(1, elapsed * 12)
    alpha = alpha + (wantAlpha - alpha) * k
    if alpha < 0.01 and wantAlpha == 0 then
        if alpha > 0 then
            alpha = 0
            self:SetAlpha(0)
            current, markerX = nil, nil
            if marker then marker:Hide() end
        end
        return
    end
    self:SetAlpha(alpha)
    flash = math.max(0, flash - elapsed * 3)
    self.accent:SetWidth(3 + 3 * flash)

    if current then
        local pulse = 0.5 + 0.5 * math.sin(GetTime() * 7)
        local dead = current.key == "DEAD"
        local r, g, b = current.color[1], current.color[2], current.color[3]
        self.glow:Set(r, g, b, math.min(1, (dead and (0.45 + 0.55 * pulse) or 0.3) + flash * 0.7))
        for _, seg in ipairs(self.segments) do
            seg.lit:SetAlpha(seg.zone == current and (dead and (0.7 + 0.3 * pulse) or 1) or 0)
        end
        if targetX then
            markerX = (markerX or targetX) + (targetX - (markerX or targetX)) * math.min(1, elapsed * 14)
            self.marker:ClearAllPoints()
            self.marker:SetPoint("CENTER", self.track, "LEFT", markerX, 0)
        end
        updateMarker(not unlocked and current or nil, pulse)
    end
end

local function wake()
    if hud and not hud:IsShown() then
        hud:SetAlpha(alpha)
        hud:Show()
    end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
function HunterRange:Sync(isUnlocked)
    unlocked = isUnlocked == true
    local s = Caster.settings
    if not s or not s.hunterRangeBubble then
        if hud then hud:Hide() end
        if marker then marker:Hide() end
        return
    end
    buildHud()
    resolveSpells()
    hud.icon:SetTexture(rangedIcon or "Interface\\Icons\\Ability_Hunter_RunningShot")
    hud:SetScript("OnUpdate", onUpdate)
    applyHudPosition()
    hud:EnableMouse(unlocked)
    current = nil
    wake()
end

WFC:RegisterEvent("PLAYER_LOGIN", function() HunterRange:Sync() end)
WFC:RegisterEvent("SPELLS_CHANGED", function() if hud then resolveSpells(); hud.icon:SetTexture(rangedIcon or "Interface\\Icons\\Ability_Hunter_RunningShot") end end)
WFC:RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if not hud then return end
    if enabledForPlayer() and hostileTarget() then wake() end
end)
WFC:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() if hud then resolveSpells() end end)
