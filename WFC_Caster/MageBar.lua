local _, ns = ...
local WFC = WFC
local Caster = ns.Caster

-- MageBar: compact Mage AoE cooldown tracker (Frost Nova, Cone of Cold, Blink, Ice Block/Barrier).
--
-- Forever (Retail API, Midnight restrictions): C_Spell.GetSpellCooldown returns startTime and
-- duration as SECRET numbers in combat, but isActive as a plain boolean. So:
--   * out of combat: exact countdown numbers;
--   * in combat: "on cooldown" (dimmed icon) vs "ready", with no numbers. isActive is also true
--     during the global cooldown, so a short debounce keeps icons from flickering on every cast.
-- SetCooldownFromDurationObject is a protected function on Forever, so no cooldown swipe.

local MageBar = {}
ns.MageBar = MageBar

local SPELLS = {
    { name = "Frost Nova",   icon = "Interface\\Icons\\Spell_Frost_FrostNova" },
    { name = "Cone of Cold", icon = "Interface\\Icons\\Spell_Frost_Glacier" },
    { name = "Blink",        icon = "Interface\\Icons\\Spell_Arcane_Blink" },
    { name = "Ice Block",    icon = "Interface\\Icons\\Spell_Frost_Frost", fallback = "Ice Barrier" },
}
local GCD_DEBOUNCE = 1.6 -- isActive must stay true this long (in combat) to count as a real cooldown
local WHITE = "Interface\\Buttons\\WHITE8X8"

local frame
local resolved = {}      -- [slot index] = spellID or false
local activeSince = {}   -- [slot index] = GetTime() when isActive first turned true

local function isSecret(v)
    return WFC.Compat and WFC.Compat.IsSecret and WFC.Compat.IsSecret(v) or false
end

--- spellID of a spell this character knows, by name (nil when unknown).
local function knownSpellId(name)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    local id = ok and type(info) == "table" and info.spellID
    if not id or isSecret(id) then return nil end
    local known = (IsPlayerSpell and IsPlayerSpell(id))
        or (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id))
    return known and id or nil
end

local function resolveSpells()
    for i, sp in ipairs(SPELLS) do
        local id = knownSpellId(sp.name) or (sp.fallback and knownSpellId(sp.fallback))
        resolved[i] = id or false
    end
end

--- onCooldown, remainingSeconds|nil (nil = not readable right now)
local function cooldownState(i, spellId, now)
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellId)
    if not ok or type(info) ~= "table" then return false, nil end
    local start, dur, active = info.startTime, info.duration, info.isActive
    if not isSecret(start) and not isSecret(dur) and type(start) == "number" and type(dur) == "number" then
        activeSince[i] = nil
        if dur > 1.5 and start + dur > now then return true, start + dur - now end
        return false, nil
    end
    -- Secret numbers (combat): fall back to the plain isActive flag, debounced past the GCD.
    if active == true and not isSecret(active) then
        activeSince[i] = activeSince[i] or now
        return (now - activeSince[i]) >= GCD_DEBOUNCE, nil
    end
    activeSince[i] = nil
    return false, nil
end

local function savePosition(self)
    local s = Caster.settings
    if not s then return end
    local point, _, rel, x, y = self:GetPoint(1)
    s.mageBarPos = { point = point, rel = rel, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
end

local function build()
    if frame then return frame end
    frame = CreateFrame("Frame", "WFC_CasterMageBar", UIParent, "BackdropTemplate")
    frame:SetSize(4 + #SPELLS * 30, 34)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self) end)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(0.04, 0.05, 0.07, 0.86)
    frame:SetBackdropBorderColor(0.22, 0.27, 0.34, 1)

    local font = WFC.Fonts and WFC.Fonts:Get("small")
    frame.slots = {}
    for i, sp in ipairs(SPELLS) do
        local slot = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        slot:SetSize(26, 26)
        slot:SetPoint("LEFT", frame, "LEFT", 4 + (i - 1) * 30, 0)
        slot:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        slot:SetBackdropColor(0, 0, 0, 1)
        slot:SetBackdropBorderColor(0.28, 0.32, 0.38, 1)
        local tex = slot:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", -1, 1)
        tex:SetTexture(sp.icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local shade = slot:CreateTexture(nil, "OVERLAY")
        shade:SetAllPoints(tex)
        shade:SetColorTexture(0, 0, 0, 0.55)
        local cd = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if font then cd:SetFontObject(font) end
        cd:SetPoint("CENTER", 0, 0)
        cd:SetTextColor(1, 0.82, 0.2)
        slot.tex, slot.shade, slot.cd = tex, shade, cd
        frame.slots[i] = slot
    end

    local accum = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        accum = accum + elapsed
        if accum < 0.1 then return end
        accum = 0
        local now = GetTime()
        local anyOnCd = false
        for i, slot in ipairs(self.slots) do
            local id = resolved[i]
            if not id then
                slot:SetAlpha(0.25) -- not learned yet
                slot.shade:Hide()
                slot.cd:SetText("")
            else
                slot:SetAlpha(1)
                local onCd, rem = cooldownState(i, id, now)
                anyOnCd = anyOnCd or onCd
                slot.tex:SetDesaturated(onCd)
                slot.shade:SetShown(onCd)
                if onCd and rem then
                    slot.cd:SetText(rem >= 10 and ("%d"):format(rem + 0.5) or ("%.1f"):format(rem))
                else
                    slot.cd:SetText("")
                end
                slot:SetBackdropBorderColor(onCd and 0.20 or 0.30, onCd and 0.22 or 0.62, onCd and 0.26 or 0.85, 1)
            end
        end
        local inCombat = InCombatLockdown and InCombatLockdown()
        self:SetAlpha((inCombat or anyOnCd) and 1 or 0.3)
    end)
    return frame
end

function MageBar:ApplyPosition()
    if not frame then return end
    local p = Caster.settings and Caster.settings.mageBarPos
    frame:ClearAllPoints()
    if p and p.point then
        frame:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -135)
    end
end

--- Shows/hides from settings; `unlocked` makes it draggable.
function MageBar:Sync(unlocked)
    local s = Caster.settings
    local _, classFile = UnitClass("player")
    if not s or classFile ~= "MAGE" or not s.showMageBar then
        if frame then frame:Hide() end
        return
    end
    build()
    resolveSpells()
    self:ApplyPosition()
    frame:EnableMouse(unlocked == true)
    frame:Show()
end

WFC:RegisterEvent("PLAYER_LOGIN", function() MageBar:Sync() end)
WFC:RegisterEvent("SPELLS_CHANGED", function() if frame and frame:IsShown() then resolveSpells() end end)
