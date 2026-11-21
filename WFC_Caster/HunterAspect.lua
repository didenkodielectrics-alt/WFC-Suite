local ADDON_NAME, ns = ...
local WFC = WFC
local Caster = ns.Caster

-- HunterAspect: Taint-free Hunter Aspect manager & top-left toggle button.
-- Swaps from Aspect of the Cheetah to Aspect of the Hawk upon entering combat.
-- Features:
--   1. Reliable 28x28 top-left toggle button with clear On/Off feedback.
--   2. In-combat secure click action to swap to Hawk directly from the button.
--   3. Center-screen emergency swap button that automatically appears in combat when Cheetah is active.
--   4. Auto-generated smart macro "WFC_Hawk".

local _, playerClass = UnitClass("player")
if playerClass ~= "HUNTER" then return end

local HunterAspect = {}
ns.HunterAspect = HunterAspect

local CHEETAH_SPELL_ID = 5118
-- Cast by name with no rank: the client then uses your HIGHEST known rank of Aspect of the Hawk
-- (a spell ID would pin one rank and miss ranks trained later).
local HAWK_SPELL = "Aspect of the Hawk"
local HAWK_ICON = "Interface\\Icons\\Spell_Nature_RavenForm"
local CHEETAH_ICON = "Interface\\Icons\\Ability_Mount_JungleTiger"

---------------------------------------------------------------------------
-- Buff Checks
---------------------------------------------------------------------------
local function isSecret(v) return WFC.Compat and WFC.Compat.IsSecret and WFC.Compat.IsSecret(v) end

--- Forever's spell IDs can differ from Classic's: resolve the real one from the spellbook by name.
local resolvedIds = {}
local function spellIdFor(spellName)
    if resolvedIds[spellName] ~= nil then return resolvedIds[spellName] or nil end
    local id = false
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellName)
        if ok and type(info) == "table" and info.spellID and not isSecret(info.spellID) then id = info.spellID end
    end
    resolvedIds[spellName] = id
    return id or nil
end

local function hasPlayerAura(spellName, spellId)
    -- 1. By the spell's real (runtime) ID, then the Classic ID we were given.
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, id in ipairs({ spellIdFor(spellName), spellId }) do
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok and aura ~= nil then return true end -- a secret aura table still means "present"
        end
    end
    -- 2. By name (Retail-style API, present on Forever).
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", spellName, "HELPFUL")
        if ok and aura ~= nil then return true end
    end
    if AuraUtil and AuraUtil.FindAuraByName then
        local ok, name = pcall(AuraUtil.FindAuraByName, spellName, "player", "HELPFUL")
        if ok and name then return true end
    end
    if UnitAura then
        for i = 1, 40 do
            local ok, name, _, _, _, _, _, _, _, _, id = pcall(UnitAura, "player", i, "HELPFUL")
            if ok and name then
                if (spellId and id == spellId) or name == spellName then
                    return true
                end
            elseif not ok or not name then
                break
            end
        end
    end
    return false
end

-- In combat Forever (Midnight model) usually hides the player's auras from addons, so a buff
-- check there says "no Hawk" even right after the swap. The player's own aspect casts still
-- arrive in combat (UNIT_SPELLCAST_SUCCEEDED), so the last aspect cast is the in-combat answer.
-- Only one aspect can be active at a time, so the last one cast is the one that's on.
-- Out of combat it is re-read from the buffs (syncFromAuras), so an aspect cast before the pull
-- is known when combat starts; death clears it.
local ASPECTS = {
    ["Aspect of the Hawk"] = "hawk",
    ["Aspect of the Cheetah"] = "cheetah",
    ["Aspect of the Pack"] = "cheetah", -- dazes the same way
    ["Aspect of the Monkey"] = "other",
    ["Aspect of the Beast"] = "other",
    ["Aspect of the Wild"] = "other",
}
local castAspect -- "hawk" | "cheetah" | "other" | nil

--- The cast's spell name, or nil when the client hides it.
local function castName(spellId)
    if WFC.Safe then spellId = WFC.Safe(spellId) end
    if type(spellId) ~= "number" then return nil end
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId))
        or (GetSpellInfo and GetSpellInfo(spellId))
    if WFC.Safe then name = WFC.Safe(name) end
    return type(name) == "string" and name or nil
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

--- Cheetah, or Pack (it dazes in combat the same way).
local function hasCheetah()
    if inCombat() and castAspect then return castAspect == "cheetah" end
    return hasPlayerAura("Aspect of the Cheetah", CHEETAH_SPELL_ID) or hasPlayerAura("Aspect of the Pack", 13159)
end

local function hasHawk()
    if inCombat() and castAspect then return castAspect == "hawk" end
    return hasPlayerAura("Aspect of the Hawk", nil)
end

--- Out of combat only: the buffs are readable, so they are the truth.
local function syncFromAuras()
    if inCombat() then return end
    if hasPlayerAura("Aspect of the Hawk", nil) then
        castAspect = "hawk"
    elseif hasPlayerAura("Aspect of the Cheetah", CHEETAH_SPELL_ID) or hasPlayerAura("Aspect of the Pack", 13159) then
        castAspect = "cheetah"
    else
        castAspect = nil -- another aspect or none: the buff check decides
    end
end

---------------------------------------------------------------------------
-- Emergency In-Combat Swap Button
-- Uses Blizzard's C++ StateDriver for 100% taint-free visibility in combat.
---------------------------------------------------------------------------
local emergencyBtn
local function getEmergencyButton()
    if emergencyBtn then return emergencyBtn end

    emergencyBtn = CreateFrame("Button", "WFC_CheetahEmergencySwap", UIParent, "SecureActionButtonTemplate, BackdropTemplate")
    emergencyBtn:SetSize(220, 42)
    emergencyBtn:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
    emergencyBtn:SetFrameStrata("HIGH")
    emergencyBtn:SetClampedToScreen(true)
    emergencyBtn:EnableMouse(true)
    -- Both: Retail-based clients act on key DOWN by default (ActionButtonUseKeyDown), and an
    -- "AnyUp"-only secure button then silently does nothing.
    emergencyBtn:RegisterForClicks("AnyUp", "AnyDown")

    -- Secure action: cast your highest rank of Hawk (casting it replaces Cheetah/Pack).
    -- "!" = never toggle Hawk OFF: after the swap the button only fades (a secure button can't be
    -- hidden from addon code in combat), so a stray click on the faded button must be harmless.
    emergencyBtn:SetAttribute("type", "macro")
    emergencyBtn:SetAttribute("macrotext", "/cast !" .. HAWK_SPELL)

    -- No instant hide on click: 1.5s later we check that Hawk really took (see checkSwap below).

    if emergencyBtn.SetBackdrop then
        emergencyBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        emergencyBtn:SetBackdropColor(0.14, 0.03, 0.03, 0.95)
        emergencyBtn:SetBackdropBorderColor(1.0, 0.20, 0.20, 1)
    end

    local icon = emergencyBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture(HAWK_ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local title = emergencyBtn:CreateFontString(nil, "OVERLAY")
    title:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -3)
    title:SetText("|cffff2020CHEETAH IN COMBAT!|r")

    local sub = emergencyBtn:CreateFontString(nil, "OVERLAY")
    sub:SetFont(STANDARD_TEXT_FONT, 10, "")
    sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 4)
    sub:SetText("|cffffff00Click to Swap to Hawk|r")
    emergencyBtn.sub = sub

    local hl = emergencyBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)

    -- After a click, check that Hawk is really on once no ability has been cast for a GCD.
    emergencyBtn:HookScript("OnClick", function() HunterAspect:ScheduleCheck() end)

    emergencyBtn:Hide()
    return emergencyBtn
end

--- Swap done (Hawk on, Cheetah/Pack gone): get the button out of the way. Out of combat it's
--- hidden; in combat a secure button can't be hidden by addon code, so it fades to invisible
--- (its "/cast !Hawk" makes any stray click harmless) and is hidden properly when combat ends.
local function retireButton()
    if not emergencyBtn then return end
    if InCombatLockdown() then
        emergencyBtn:SetAlpha(0)
    else
        emergencyBtn:Hide()
    end
end

local function reviveButton(text)
    if not emergencyBtn then return end
    emergencyBtn:SetAlpha(1)
    if text then emergencyBtn.sub:SetText(text) end
end

function HunterAspect:CheckSwap()
    if not emergencyBtn or not emergencyBtn:IsShown() then return end
    if hasHawk() and not hasCheetah() then
        retireButton()
    else
        reviveButton("|cffff8040Still no Hawk, click again|r")
    end
end

---------------------------------------------------------------------------
-- Quiet-window check: a Hawk click while another ability's global cooldown is running is
-- simply dropped by the game. So the "did it take?" verdict waits until no ability has been
-- cast for a full GCD (settings.hawkQuietSeconds, default 1.5s), counted from the later of
-- the click and the player's last cast. Auto Shot / wand shots are off the GCD and ignored.
-- A hard cap (QUIET_MAX after the click) stops a long cast chain from postponing it forever.
---------------------------------------------------------------------------
local DEFAULT_QUIET, QUIET_MAX = 1.5, 8
local OFF_GCD = { ["Auto Shot"] = true, ["Shoot"] = true, ["Shoot Bow"] = true, ["Shoot Gun"] = true,
    ["Shoot Crossbow"] = true, ["Throw"] = true, ["Auto Attack"] = true, ["Attack"] = true }
local lastCastAt = -1e9
local checkSerial = 0

local function quietSeconds()
    local q = Caster.settings and tonumber(Caster.settings.hawkQuietSeconds)
    return (q and q >= 0) and q or DEFAULT_QUIET
end

function HunterAspect:ScheduleCheck()
    checkSerial = checkSerial + 1 -- key down + key up / repeat clicks: only the latest counts
    local serial, clickedAt = checkSerial, GetTime()
    local function try()
        if serial ~= checkSerial then return end
        local now = GetTime()
        local quietUntil = math.max(clickedAt, lastCastAt) + quietSeconds()
        if now < quietUntil and now - clickedAt < QUIET_MAX then
            C_Timer.After(math.max(0.05, quietUntil - now), try)
            return
        end
        HunterAspect:CheckSwap()
    end
    C_Timer.After(quietSeconds(), try)
end

--- Any GCD ability the player casts (Hawk included) restarts the quiet window.
function HunterAspect:NoteCast(name)
    if type(name) == "string" and OFF_GCD[name] then return end
    lastCastAt = GetTime()
end

local function syncEmergencyDriver()
    if InCombatLockdown and InCombatLockdown() then return end
    local btn = getEmergencyButton()
    local s = Caster.settings
    local shouldArm = (s and s.autoHawkOnCombat ~= false) and hasCheetah() and not hasHawk()

    if shouldArm then
        -- When combat begins, Blizzard's engine will securely reveal the button
        RegisterStateDriver(btn, "visibility", "[combat] show; hide")
    else
        UnregisterStateDriver(btn, "visibility")
        btn:Hide()
    end
end

---------------------------------------------------------------------------
-- Top-Left Launcher / Toggle Button
---------------------------------------------------------------------------
local launcher
local secureCombatOverlay
local hookedLaunchers = false

local function updateVisuals()
    if not launcher then return end
    local s = Caster.settings
    local enabled = (s and s.autoHawkOnCombat ~= false)

    if enabled then
        launcher.icon:SetDesaturated(false)
        launcher.icon:SetAlpha(1.0)
        launcher.dot:SetColorTexture(0.2, 1.0, 0.3, 1) -- Bright green
        if launcher.SetBackdropBorderColor then
            launcher:SetBackdropBorderColor(0.25, 0.75, 0.40, 0.90)
        end
    else
        launcher.icon:SetDesaturated(true)
        launcher.icon:SetAlpha(0.40)
        launcher.dot:SetColorTexture(0.7, 0.2, 0.2, 0.8) -- Dim red
        if launcher.SetBackdropBorderColor then
            launcher:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.70)
        end
    end
end

local function updatePosition()
    if not launcher then return end
    local s = Caster.settings

    if not hookedLaunchers then
        hookedLaunchers = true
        local prof = _G.WFC_ProfessionsLauncher
        if prof and prof.HookScript then
            pcall(prof.HookScript, prof, "OnDragStop", function() updatePosition() end)
            pcall(prof.HookScript, prof, "OnShow", function() updatePosition() end)
            pcall(prof.HookScript, prof, "OnHide", function() updatePosition() end)
        end
        local val = _G.WFC_ItemTipsValueLauncher or _G.WFC_ValueLauncher
        if val and val.HookScript then
            pcall(val.HookScript, val, "OnDragStop", function() updatePosition() end)
            pcall(val.HookScript, val, "OnShow", function() updatePosition() end)
            pcall(val.HookScript, val, "OnHide", function() updatePosition() end)
        end
    end

    if s and s.aspectLauncherPos then
        local p = s.aspectLauncherPos
        launcher:ClearAllPoints()
        launcher:SetPoint(p.point or "TOPLEFT", UIParent, p.point or "TOPLEFT", p.x or 78, p.y or -60)
        return
    end

    local val = _G.WFC_ItemTipsValueLauncher or _G.WFC_ValueLauncher
    local prof = _G.WFC_ProfessionsLauncher

    launcher:ClearAllPoints()
    if val and val:IsShown() then
        launcher:SetPoint("LEFT", val, "RIGHT", 4, 0)
    elseif prof and prof:IsShown() then
        launcher:SetPoint("LEFT", prof, "RIGHT", 4, 0)
    else
        launcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 78, -60)
    end
end

function HunterAspect:CreateLauncher()
    if launcher then
        updatePosition()
        updateVisuals()
        return launcher
    end

    launcher = CreateFrame("Button", "WFC_AspectLauncher", UIParent, "BackdropTemplate")
    launcher:SetSize(28, 28)
    launcher:SetFrameStrata("HIGH")
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(true)
    launcher:EnableMouse(true)
    launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if launcher.SetBackdrop then
        launcher:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        launcher:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
        launcher:SetBackdropBorderColor(0.25, 0.75, 0.40, 0.90)
    end

    local icon = launcher:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture(HAWK_ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    launcher.icon = icon

    local dot = launcher:CreateTexture(nil, "OVERLAY")
    dot:SetSize(6, 6)
    dot:SetPoint("BOTTOMRIGHT", -2, 2)
    launcher.dot = dot

    local hover = launcher:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.18)

    -- In-Combat Secure Overlay: When in combat, clicks on the launcher securely swap to Hawk!
    secureCombatOverlay = CreateFrame("Button", "WFC_AspectLauncherSecure", launcher, "SecureActionButtonTemplate")
    secureCombatOverlay:SetAllPoints()
    secureCombatOverlay:SetFrameLevel(launcher:GetFrameLevel() + 5)
    secureCombatOverlay:EnableMouse(true)
    secureCombatOverlay:RegisterForClicks("AnyUp", "AnyDown")
    secureCombatOverlay:SetAttribute("type", "macro")
    secureCombatOverlay:SetAttribute("macrotext", "/cast !" .. HAWK_SPELL) -- "!": never toggles Hawk off
    -- Swapping from this button too: check ~1.5s later and retire the centre button if Hawk took.
    secureCombatOverlay:HookScript("OnClick", function() HunterAspect:ScheduleCheck() end)
    RegisterStateDriver(secureCombatOverlay, "visibility", "[combat] show; hide")

    -- Dragging with Shift + Left Mouse
    local isDragging = false
    launcher:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and IsShiftKeyDown() then
            isDragging = true
            self:StartMoving()
        end
    end)

    launcher:SetScript("OnMouseUp", function(self, btn)
        if isDragging then
            isDragging = false
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint(1)
            if Caster.settings then
                Caster.settings.aspectLauncherPos = { point = point or "TOPLEFT", x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
            end
            self._justDragged = true
        end
    end)

    -- Normal Click: Toggle setting out of combat
    launcher:SetScript("OnClick", function(self, btn)
        if self._justDragged then
            self._justDragged = nil
            return
        end

        if btn == "RightButton" and not IsShiftKeyDown() then
            -- Snap back next to other launchers
            if Caster.settings then Caster.settings.aspectLauncherPos = nil end
            updatePosition()
            return
        end

        if btn == "LeftButton" then
            local s = Caster.settings
            s.autoHawkOnCombat = not (s.autoHawkOnCombat ~= false)
            updateVisuals()
            syncEmergencyDriver()
            if WFC and WFC.Print then
                WFC:Print("Hunter Aspect Helper: " .. (s.autoHawkOnCombat and "|cff40ff40Enabled|r" or "|cffff5555Disabled|r"))
            end
            pcall(PlaySound, s.autoHawkOnCombat and 856 or 857, "Master")
            self:RefreshTooltip()
        end
    end)

    function launcher:RefreshTooltip()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 4, -4)
        GameTooltip:AddLine("Hunter Aspect Helper", 0.30, 0.85, 1.0)
        local s = Caster.settings
        local enabled = (s and s.autoHawkOnCombat ~= false)
        if enabled then
            GameTooltip:AddLine("● Auto-Swap Enabled", 0.25, 1.0, 0.25)
            GameTooltip:AddLine("Presents an instant one-click swap to Aspect of the Hawk when you enter combat with Aspect of the Cheetah active to avoid getting dazed.", 0.85, 0.85, 0.85, true)
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("|cffffd100Controls:|r", 1, 0.82, 0)
            GameTooltip:AddLine("• Left-Click: Toggle On/Off", 0.80, 0.80, 0.80)
            GameTooltip:AddLine("• In Combat: Click to instantly swap to Hawk", 0.80, 0.80, 0.80)
            GameTooltip:AddLine("• Shift + Drag: Move button", 0.80, 0.80, 0.80)
            GameTooltip:AddLine("• Right-Click: Re-dock next to other buttons", 0.80, 0.80, 0.80)
        else
            GameTooltip:AddLine("○ Auto-Swap Disabled", 1.0, 0.30, 0.30)
            GameTooltip:AddLine("Click to enable Cheetah -> Hawk swap assist when entering combat.", 0.85, 0.85, 0.85, true)
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("• Left-Click: Toggle On", 0.80, 0.80, 0.80)
            GameTooltip:AddLine("• Shift + Drag: Move button", 0.80, 0.80, 0.80)
        end
        GameTooltip:Show()
    end

    launcher:SetScript("OnEnter", function(self) self:RefreshTooltip() end)
    launcher:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
    updateVisuals()
    return launcher
end

---------------------------------------------------------------------------
-- Auto-Create Smart Hunter Macro (/macro WFC_Hawk)
---------------------------------------------------------------------------
local function checkOrCreateMacro()
    if InCombatLockdown and InCombatLockdown() then return end
    if not (CreateMacro and GetMacroInfo) then return end

    local name = "WFC_Hawk"
    local body = "#showtooltip\n/cancelaura [combat] Aspect of the Cheetah\n/cast [combat] !Aspect of the Hawk; !Aspect of the Cheetah"
    local existing = GetMacroInfo(name)
    if not existing then
        local numAcc, numChar = GetNumMacros()
        if numChar < 18 then
            pcall(CreateMacro, name, "INV_Misc_QuestionMark", body, true)
        elseif numAcc < 120 then
            pcall(CreateMacro, name, "INV_Misc_QuestionMark", body, false)
        end
    end
end

---------------------------------------------------------------------------
-- Combat & Aura Events
---------------------------------------------------------------------------
local function onEnterCombat()
    reviveButton("|cffffff00Click to Swap to Hawk|r") -- fresh fight: fully visible again
    local s = Caster.settings
    if not s or s.autoHawkOnCombat == false then return end

    if hasCheetah() and PlaySound then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
end

local function onLeaveCombat()
    if emergencyBtn then emergencyBtn:SetAlpha(1) end
    syncFromAuras()
    syncEmergencyDriver()
    updateVisuals()
end

--- The player's own casts: restart the quiet window, and track the aspect (see castAspect).
local function onSpellCast(unit, spellId)
    if WFC.Safe then unit = WFC.Safe(unit) end
    if unit ~= "player" then return end
    local name = castName(spellId)
    HunterAspect:NoteCast(name)
    local aspect = name and ASPECTS[name]
    if not aspect then return end
    castAspect = aspect
    if inCombat() then
        if emergencyBtn and emergencyBtn:IsShown() then
            if aspect == "cheetah" then
                reviveButton("|cffffff00Click to Swap to Hawk|r")
            else
                retireButton() -- the game confirmed the Hawk cast: no need to wait for the check
            end
        end
    else
        syncEmergencyDriver()
        updateVisuals()
    end
end

local function onAuraChanged()
    syncFromAuras()
    -- In combat: Hawk from the action bar (or anywhere) retires the button too; Cheetah back on
    -- brings it back. Out of combat: re-arm the combat driver.
    if InCombatLockdown() and emergencyBtn and emergencyBtn:IsShown() then
        if hasHawk() and not hasCheetah() then
            retireButton()
        elseif hasCheetah() then
            reviveButton()
        end
    end
    syncEmergencyDriver()
    updateVisuals()
end

--- /wfc caster hawk test: prints what the swap assist detects and shows the button for 5s.
function HunterAspect:Test()
    local s = Caster.settings
    WFC:Print(("Hawk assist: %s · Cheetah/Pack detected: %s · Hawk detected: %s · last aspect cast: %s · quiet window %.1fs · Cheetah spell ID here: %s"):format(
        (s and s.autoHawkOnCombat ~= false) and "on" or "off",
        hasCheetah() and "yes" or "no", hasHawk() and "yes" or "no", tostring(castAspect or "-"),
        quietSeconds(), tostring(spellIdFor("Aspect of the Cheetah") or "not in spellbook")))
    -- The detection line works in combat; showing the button for 5s doesn't (secure frame).
    if InCombatLockdown() then return end
    local btn = getEmergencyButton()
    UnregisterStateDriver(btn, "visibility")
    btn:Show()
    C_Timer.After(5, function()
        if not InCombatLockdown() then btn:Hide(); syncEmergencyDriver() end
    end)
end

WFC:RegisterEvent("PLAYER_REGEN_DISABLED", onEnterCombat)
WFC:RegisterEvent("PLAYER_REGEN_ENABLED", onLeaveCombat)
WFC:RegisterEvent("UNIT_AURA", function(_, unit)
    if unit == "player" then onAuraChanged() end
end)
WFC:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellId) onSpellCast(unit, spellId) end)
WFC:RegisterEvent("PLAYER_DEAD", function() castAspect = nil end) -- death strips every aspect
WFC:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    HunterAspect:CreateLauncher()
    syncEmergencyDriver()
    updateVisuals()
    checkOrCreateMacro()
end)
WFC:RegisterEvent("SPELLS_CHANGED", function()
    wipe(resolvedIds) -- a newly trained rank has a new spell ID; look it up again
    syncEmergencyDriver()
    updateVisuals()
end)

C_Timer.After(0.5, function()
    HunterAspect:CreateLauncher()
    syncEmergencyDriver()
    updateVisuals()
    checkOrCreateMacro()
end)
