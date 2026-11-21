local ADDON_NAME, ns = ...
local WFC = WFC

-- WFC_Professions: Standalone multi-character profession & material manager for WoW Forever.
-- Tracks crafting materials across all alts (via BagBrother + live bag fallback),
-- scroll/pattern recipes (learned vs unlearned), craftable equippable gear for your
-- current character's level, and a skill-up planner using materials already on hand.

local Professions = { ADDON = ADDON_NAME }
WFC.Professions = Professions
ns.Professions = Professions

Professions.DEFAULTS = {
    tutorialOnLaunch = true,     -- show quick launch tutorial popup
    lastTab = "materials",       -- "materials" | "scrolls" | "gear" | "skillup"
    matProfFilter = 0,           -- 0 = All Crafting Materials, -1 = My Alts' Professions, or skillLineId
    matInStockOnly = true,       -- only show crafting materials with count > 0 across alts
    scrollProfFilter = -1,       -- -1 = My Alts' Professions, 0 = All Professions, or skillLineId
    scrollStateFilter = "all",   -- "all" | "unlearned" | "learned" | "owned"
    scrollAtLearnedLevel = false,-- only show scrolls at or below current learned skill level
    gearOnlyHaveMats = false,    -- checkbox: only show equippable gear you have materials to craft right now
    gearIncludeUnlearned = true, -- checkbox: include gear your alts could craft if they learn the recipe
    gearStatFilter = "all",      -- "all" | "agi" | "str" | "sta" | "int" | "spi" | "sp" | "ap" | "crit_hit" | "def" | "mp5" | "res"
    gearTargetChar = "player",   -- "player" | "all" | character key (filter equippable gear for specific alt)
    gearLevelSpan = 12,          -- how many levels below current player level to show (0 = no minimum)
    showSkillUpBanner = true,    -- show top "next best character to level" suggestion banner
    skillUpOnlyHaveMats = true,  -- checkbox: only show skill-up recommendations you have materials for
    skillUpSort = "current",     -- "current" (Current Char First) | "gain" (Most Gain) | "name" (A-Z)
    skillUpCharFilter = "all",   -- "all" | "player" | character key
    showLauncher = true,         -- show floating top-left quick launcher button
    launcherPos = { point = "TOPLEFT", x = 14, y = -60 }, -- saved launcher screen position
    collapsed = {},              -- [groupKey] = true for collapsed section headers
    window = {},                 -- saved standalone window position and size
}

local CONTROLS = {
    { key = "tutorialOnLaunch", label = "Tutorial on launch",
        tooltip = "Show the quick feature tutorial popup in the top-left when the game opens." },
    { key = "showLauncher", label = "Show quick launcher button in top-left",
        tooltip = "Displays a small floating icon in the top-left of the screen to quickly open WFC Professions at any time." },
    { key = "matInStockOnly", label = "Materials tab: only show materials in stock",
        tooltip = "When enabled, the Materials tab only lists crafting materials that at least one of your characters currently owns." },
    { key = "gearOnlyHaveMats", label = "Craftable Gear: only items I have materials for",
        tooltip = "Filter the Craftable Gear tab to items you can craft right now using materials across all your characters." },
    { key = "gearIncludeUnlearned", label = "Craftable Gear: include unlearned recipes",
        tooltip = "Also list equippable gear from recipes your alts have the profession for but haven't learned yet (marked as Needs Scroll or Trainer)." },
    { key = "gearLevelSpan", label = "Craftable Gear: level window below you (0 = all)", kind = "slider", min = 0, max = 30, step = 2,
        tooltip = "How many levels below your current level to include when listing equippable gear (0 shows all lower-level gear too)." },
    { key = "skillUpOnlyHaveMats", label = "Skill-Up Planner: only with materials I have",
        tooltip = "When enabled, the Skill-Up tab only shows characters and recipes you currently have crafting materials for." },
    { key = "showSkillUpBanner", label = "Show 'Next best character to level' skill-up banner",
        tooltip = "Highlights which alt can gain the most profession skill points right now using materials you already own." },
}

function Professions:SettingsChanged()
    if ns.Panel then
        if ns.Panel.UpdateLauncher then ns.Panel:UpdateLauncher() end
        if ns.Panel.Refresh then ns.Panel:Refresh() end
    end
end

WFC:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    local g = WFC.Store:Bind("WFC_Professions_Global", {
        settings = Professions.DEFAULTS,
        inventories = {},
    }, 1)
    local c = WFC.Store:Bind("WFC_Professions_Char", {}, 1)
    Professions.global = g
    Professions.settings = g.settings
    Professions.char = c

    WFC.Store:RegisterExport("professionsSettings",
        function() return g.settings end,
        function(value)
            if type(value) == "table" then
                for k, v in pairs(value) do g.settings[k] = v end
                Professions:SettingsChanged()
            end
        end)

    Professions.category = WFC.UI:AddSettingsPage("Professions", g.settings, Professions.DEFAULTS, CONTROLS,
        function() Professions:SettingsChanged() end)

    if WFC.UI and WFC.UI.RegisterTutorial then
        WFC.UI:RegisterTutorial({
            id = "Professions",
            order = 3,
            title = "WFC Professions · Alt & Mat Manager",
            icon = "Interface\\Icons\\Trade_BlackSmithing",
            accent = { 1.00, 0.78, 0.25 },
            store = g.settings,
            settingKey = "tutorialOnLaunch",
            rows = {
                { icon = "Interface\\Icons\\INV_Fabric_Linen_01", pill = "/wfc prof", style = "gold",
                    text = "Track |cffffd100crafting materials|r across all alts" },
                { icon = "Interface\\Icons\\INV_Scroll_03", pill = "Scrolls Tab", style = "cyan",
                    text = "See |cff4dd9fflearned & unlearned|r scroll recipes" },
                { icon = "Interface\\Icons\\INV_Chest_Chain_05", pill = "Gear Tab", style = "green",
                    text = "Find |cff40ff40craftable gear|r for your current level" },
            },
        })
    end
end)

---------------------------------------------------------------------------
-- /wfc prof & /wfc professions & /wfcprof
---------------------------------------------------------------------------
local function handleCommand(rest)
    local Panel = ns.Panel
    if not Panel then return end
    local a = strsplit(" ", (rest or ""):lower(), 2)
    if a == "" or a == nil then
        Panel:Toggle()
    elseif a == "show" then
        Panel:Show()
    elseif a == "hide" then
        Panel:Hide()
    elseif a == "materials" or a == "mats" then
        Panel:ShowTab("materials")
    elseif a == "scrolls" or a == "recipes" then
        Panel:ShowTab("scrolls")
    elseif a == "gear" or a == "equip" then
        Panel:ShowTab("gear")
    elseif a == "skillup" or a == "level" then
        Panel:ShowTab("skillup")
    elseif a == "reset" then
        if Professions.settings then Professions.settings.window = {} end
        Panel:ResetPosition()
    elseif a == "options" or a == "config" then
        if not WFC.UI:OpenSettings(Professions.category) then
            WFC:Print("options panel unavailable; use /wfc prof")
        end
    else
        WFC:Print("Usage: /wfc prof [show|hide|mats|scrolls|gear|skillup|reset|options]")
    end
end

WFC:AddCommand("prof", "[show|hide|mats|scrolls|gear|skillup|reset|options]", handleCommand)
WFC:AddCommand("professions", "[show|hide|mats|scrolls|gear|skillup|reset|options]", handleCommand)

SLASH_WFCPROF1 = "/wfcprof"
SlashCmdList["WFCPROF"] = handleCommand
