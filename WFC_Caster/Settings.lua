local ADDON_NAME, ns = ...
local WFC = WFC

-- WFC_Caster: combat helpers for WoW Forever.
--   * Hunter (and any ranged-weapon user): dead-zone range indicator + target nameplate marker
--   * Hunter: Cheetah -> Hawk emergency swap launcher
--   * Mage: compact AoE cooldown tracker
-- (The Left-Ctrl 180° kite flip was removed in 5.0: Forever gives addons no reliable way to set
-- character facing, and it fought the player's own mouselook.)

local Caster = { ADDON = ADDON_NAME }
WFC.Caster = Caster
ns.Caster = Caster

Caster.DEFAULTS = {
    tutorialOnLaunch = true,  -- show the quick tutorial popup in the top-left on game launch
    showMageBar = true,       -- show compact Frost Nova / Cone of Cold / Blink AoE tracker
    hunterRangeBubble = true, -- dead-zone range indicator (key name kept for saved settings)
    hunterPlateMarker = true, -- coloured range marker under the target's nameplate
    hunterAudioWarn = true,   -- sound when the target enters the dead zone
    hunterOnlyClass = false,  -- if false, also shows for other classes with a ranged weapon equipped
    autoHawkOnCombat = true,  -- auto change Cheetah -> Hawk in combat
    hawkQuietSeconds = 1.5,   -- the Hawk "did it take?" check waits until no ability was cast for this long (GCD)
    aspectLauncherPos = nil,  -- saved position of top-left aspect launcher
    rangeHudPos = nil,        -- saved position of the range indicator
    mageBarPos = nil,         -- saved position of the Mage AoE bar
}

-- Saved keys from the removed kite flip; cleared on load.
local OBSOLETE = { "enabled", "requireRightClick", "flipSpeed", "showHud", "rearviewMode", "turnaroundDisabledV48" }

local CONTROLS = {
    { key = "tutorialOnLaunch", label = "Tutorial on launch",
        tooltip = "Show the quick feature tutorial popup in the top-left when the game opens." },
    { key = "hunterRangeBubble", label = "Hunter: dead-zone range indicator",
        tooltip = "Shows whether your target is in melee, in the dead zone (too close to shoot), in shooting range, or too far, using the game's own range checks. Move it with /wfc caster unlock." },
    { key = "hunterPlateMarker", label = "Hunter: range marker under target nameplate",
        tooltip = "A slim bar under your target's nameplate in the range colour; pulses red in the dead zone. Needs enemy nameplates turned on." },
    { key = "hunterAudioWarn", label = "Hunter: sound when target enters the dead zone",
        tooltip = "Plays a warning when your target moves inside your minimum shooting range." },
    { key = "hunterOnlyClass", label = "Range indicator for Hunters only",
        tooltip = "When off, the range indicator also shows for other classes with a bow, gun, crossbow or thrown weapon equipped." },
    { key = "autoHawkOnCombat", label = "Hunter: Auto Hawk in combat",
        tooltip = "Automatically changes to Aspect of the Hawk when you enter combat with Aspect of the Cheetah active to avoid getting dazed. Also toggleable via the top-left button." },
    { key = "showMageBar", label = "Mage: AoE cooldown tracker",
        tooltip = "Compact tracker for Frost Nova, Cone of Cold, Blink, and Ice Block / Ice Barrier. In combat it shows ready / on cooldown (Forever hides cooldown timers from addons in combat)." },
}

function Caster:SettingsChanged()
    if ns.HunterRange and ns.HunterRange.Sync then ns.HunterRange:Sync(Caster.unlocked) end
    if ns.MageBar and ns.MageBar.Sync then ns.MageBar:Sync(Caster.unlocked) end
    if ns.HunterAspect and ns.HunterAspect.CreateLauncher then ns.HunterAspect:CreateLauncher() end
end

WFC:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    local g = WFC.Store:Bind("WFC_Caster_Global", { settings = Caster.DEFAULTS }, 1)
    for _, k in ipairs(OBSOLETE) do g.settings[k] = nil end
    Caster.settings = g.settings
    WFC.Store:RegisterExport("casterSettings",
        function() return g.settings end,
        function(value)
            if type(value) == "table" then
                for k, v in pairs(value) do g.settings[k] = v end
                Caster:SettingsChanged()
            end
        end)
    Caster.category = WFC.UI:AddSettingsPage("Caster", g.settings, Caster.DEFAULTS, CONTROLS,
        function() Caster:SettingsChanged() end)
    if WFC.UI and WFC.UI.RegisterTutorial then
        WFC.UI:RegisterTutorial({
            id = "Caster",
            order = 2,
            title = "WFC Caster · Range & Cooldowns",
            icon = "Interface\\Icons\\Ability_Hunter_RunningShot",
            accent = { 0.35, 0.85, 1.00 },
            store = g.settings,
            settingKey = "tutorialOnLaunch",
            rows = {
                { icon = "Interface\\Icons\\Ability_Hunter_RunningShot", pill = "Hunter", style = "green",
                    text = "Range HUD: |cff40c040in range|r, |cffff1a1adead zone|r, too far" },
                { icon = "Interface\\Icons\\Ability_Mount_JungleTiger", pill = "Aspect", style = "gold",
                    text = "Swap |cffffd100Cheetah → Hawk|r with one click" },
                { icon = "Interface\\Icons\\Spell_Frost_FrostNova", pill = "Mage", style = "cyan",
                    text = "Track |cff4dd9ffNova, Cone, Blink|r cooldowns" },
            },
        })
    end
end)

---------------------------------------------------------------------------
-- /wfc caster
---------------------------------------------------------------------------
local USAGE = "[range on|off|marker on|off|sound on|off|aoe on|off|hawk on|off|test|wait <sec>|unlock|lock|reset|options]"

local function toggle(s, key, b)
    if b == "on" or b == "off" then s[key] = (b == "on") else s[key] = not s[key] end
    return s[key] and "on" or "off"
end

WFC:AddCommand("caster", USAGE, function(rest)
    local s = Caster.settings
    if not s then return end
    local a, b = strsplit(" ", (rest or ""):lower(), 2)
    if a == "range" or a == "bubble" or a == "hunter" then
        WFC:Print("Range indicator:", toggle(s, "hunterRangeBubble", b))
    elseif a == "marker" then
        WFC:Print("Nameplate range marker:", toggle(s, "hunterPlateMarker", b))
    elseif a == "sound" then
        WFC:Print("Dead-zone sound:", toggle(s, "hunterAudioWarn", b))
    elseif a == "aoe" then
        WFC:Print("Mage AoE tracker:", toggle(s, "showMageBar", b))
    elseif (a == "hawk" or a == "aspect") and b == "test" then
        if ns.HunterAspect and ns.HunterAspect.Test then ns.HunterAspect:Test() else WFC:Print("Hawk assist is Hunter-only.") end
        return
    elseif (a == "hawk" or a == "aspect") and b and b:match("^wait") then
        local sec = tonumber(b:match("^wait%s+([%d%.]+)"))
        if sec and sec >= 0 and sec <= 10 then s.hawkQuietSeconds = sec end
        WFC:Print(("Hawk check waits until no ability was cast for %.1fs (/wfc caster hawk wait <0-10>)"):format(
            tonumber(s.hawkQuietSeconds) or 1.5))
        return
    elseif a == "hawk" or a == "aspect" then
        WFC:Print("Auto Aspect of the Hawk in combat:", toggle(s, "autoHawkOnCombat", b))
    elseif a == "unlock" then
        Caster.unlocked = true
        WFC:Print("Caster frames unlocked: drag them, then /wfc caster lock")
    elseif a == "lock" then
        Caster.unlocked = false
        WFC:Print("Caster frames locked")
    elseif a == "reset" then
        s.rangeHudPos, s.mageBarPos = nil, nil
        WFC:Print("Caster frame positions reset")
    elseif a == "options" then
        if not WFC.UI:OpenSettings(Caster.category) then WFC:Print("options panel unavailable; use /wfc caster") end
        return
    else
        WFC:Print(("WFC Caster · range: %s · marker: %s · sound: %s · AoE: %s · auto-Hawk: %s"):format(
            s.hunterRangeBubble and "on" or "off", s.hunterPlateMarker ~= false and "on" or "off",
            s.hunterAudioWarn and "on" or "off", s.showMageBar and "on" or "off",
            s.autoHawkOnCombat and "on" or "off"))
        WFC:Print("Usage: /wfc caster " .. USAGE)
        return
    end
    Caster:SettingsChanged()
end)
