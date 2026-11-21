local ADDON_NAME, ns = ...
local WFC = WFC

-- WFC_Travel: namespace, SavedVariables, /wfc travel and the options page.
-- Public API (plan.md §5.8) lives on WFC.Travel; see Travel.lua.

local Travel = { ADDON = ADDON_NAME }
WFC.Travel = Travel
ns.Travel = Travel

Travel.DEFAULTS = {
    tutorialOnLaunch = true, -- show the quick tutorial popup in the top-left on game launch
    allowHearth = true,   -- the hearthstone may be a leg when it is off cooldown
    assumeMount = true,   -- riding speed from level 40 (60%) and 60 (100%)
    detour = 1.3,         -- straight-line walking x this, for roads and terrain
    crossZoneDetour = 2.0, -- road/pass detour factor when walking between different zones
    zoneTransition = 120, -- extra seconds buffer for zone borders, passes, and elevation
    arrivalYards = 25,    -- the target clears itself within this distance
    waypoint = true,      -- pin the end of the current leg on the map (native pin / TomTom)
    showPopup = true,     -- the WFC Travel box on the world map
}

local CONTROLS = {
    { key = "tutorialOnLaunch", label = "Tutorial on launch",
        tooltip = "Show the quick feature tutorial popup in the top-left when the game opens." },
    { key = "showPopup", label = "Show the travel box on the world map" },
    { key = "allowHearth", label = "Use the hearthstone in routes", tooltip = "Only when it is off cooldown." },
    { key = "assumeMount", label = "Assume a mount from level 40", tooltip = "Riding speed for walking legs." },
    { key = "waypoint", label = "Pin the next stop on the map", tooltip = "Native map pin, or TomTom's arrow when loaded." },
    { key = "arrivalYards", label = "Arrival distance (yards)", kind = "slider", min = 10, max = 100, step = 5,
        tooltip = "The target clears itself once you are this close." },
    { key = "zoneTransition", label = "Cross-zone travel buffer (sec)", kind = "slider", min = 30, max = 300, step = 15,
        tooltip = "Extra seconds buffer added to cross-zone walking legs to account for mountain passes and zone transitions." },
}

function Travel:SettingsChanged()
    if self.Invalidate then self:Invalidate() end
end

WFC:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    local g = WFC.Store:Bind("WFC_Travel_Global", { settings = Travel.DEFAULTS, authored = { nodes = {}, links = {} },
        learned = { pairs = {}, factor = 1, samples = 0 } }, 1)
    local c = WFC.Store:Bind("WFC_Travel_Char", { knownTaxi = {}, bind = {}, mode = "safe" }, 1)
    Travel.settings, Travel.authored, Travel.char, Travel.learned = g.settings, g.authored, c, g.learned
    WFC.Store:RegisterExport("travelSettings",
        function() return g.settings end,
        function(value)
            if type(value) == "table" then
                for k, v in pairs(value) do g.settings[k] = v end
            end
        end)
    -- Known flight points are rebuilt by visiting any flight master (R8), so they are not exported.
    Travel.category = WFC.UI:AddSettingsPage("Travel", g.settings, Travel.DEFAULTS, CONTROLS,
        function() Travel:SettingsChanged() end)
    if WFC.UI and WFC.UI.RegisterTutorial then
        WFC.UI:RegisterTutorial({
            id = "Travel",
            order = 3,
            title = "WFC Travel · Route Planner",
            icon = "Interface\\Icons\\INV_Misc_Map_01",
            accent = { 0.30, 0.85, 1.00 },
            store = g.settings,
            settingKey = "tutorialOnLaunch",
            rows = {
                { icon = "Interface\\Icons\\INV_Misc_Map_01", pill = "Map [M]", style = "cyan",
                    text = "Draws fastest |cff4dd9ffFlight / Boat / Zep|r route" },
                { icon = "Interface\\GossipFrame\\AvailableQuestIcon", pill = "Click Quest", style = "gold",
                    text = "Click a quest in |cffffd100WFC Quests|r to route" },
                { icon = "Interface\\Icons\\INV_Misc_Rune_01", pill = "Waypoints", style = "green",
                    text = "Pins each leg & |cff40ff40Hearthstone|r shortcuts" },
            },
        })
    end
end)
