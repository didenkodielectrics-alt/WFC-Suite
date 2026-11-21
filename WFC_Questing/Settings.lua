local ADDON_NAME, ns = ...
local WFC = WFC

-- WFC_Questing: namespace, SavedVariables, /wfc quests and the options page.
-- Public surface for other addons (Travel, M6): WFC.Questing:GetRanked(), :GetNextUp(n),
-- :IsIgnored(id), :SetIgnored(id, on), and the WFC_QUESTS_SCORED message.

local Questing = { ADDON = ADDON_NAME }
WFC.Questing = Questing
ns.Questing = Questing

Questing.DEFAULTS = {
    dock = true,             -- dock next to the visible quest log
    autoShow = true,         -- open/close together with the quest log while docked
    lastTab = nil,           -- remember the last selected tab ("active", "next", "dungeons", "skip")
    anyZone = false,         -- false = search current zone only; true = search all zones
    quickKeys = true,        -- Space to accept/complete quests, F1-F10 to select rewards
    tutorialOnLaunch = true, -- show the quick tutorial popup in the top-left on game launch
    nextUpCount = 10,
    below = 0,               -- levels below you to consider (0 = up to grey)
    above = 3,               -- levels above you to consider
    includeDungeons = false, -- dungeon quests otherwise live in the Dungeons tab (M7)
    hideGrey = true,
    hideElite = false,       -- elite/group quests are only down-weighted unless this is on
    xpPerGold = 20,          -- how much 1g of rewards is worth, in XP, when ranking
    xpPerRep = 0,            -- how much 1 reputation point is worth, in XP (0 = ignore reputation)
    killSeconds = 20,        -- average time per kill
    assumeMount = true,      -- use mount speed from level 40/60
    showIgnored = false,
    showCircuit = true,      -- a suggested batch of nearby quests at the top of Next Up
    window = {},             -- saved position and size of the standalone panel
}

--- Scorer settings for the current character (speed from level, group state).
function Questing:ScorerSettings(level, inGroup)
    local s = self.settings
    local speed = 7 -- running, yards per second
    if s.assumeMount and level >= 60 then
        speed = 14
    elseif s.assumeMount and level >= 40 then
        speed = 11.2
    end
    return {
        below = s.below > 0 and s.below or nil, above = s.above,
        includeDungeons = s.includeDungeons, hideGrey = s.hideGrey, hideElite = s.hideElite, inGroup = inGroup,
        eliteFactor = 0.3, redFactor = 0.5, xpPerGold = s.xpPerGold, xpPerRep = s.xpPerRep, speed = speed, killSeconds = s.killSeconds,
    }
end

---------------------------------------------------------------------------
-- Ignore list (per character, exported with /wfc export)
---------------------------------------------------------------------------
function Questing:IsIgnored(questId)
    return self.char ~= nil and self.char.ignored[questId] == true
end

function Questing:SetIgnored(questId, on)
    self.char.ignored[questId] = on and true or nil
    WFC:Fire("WFC_QUEST_IGNORED", questId, on)
    self:RequestScore("ignore", 0)
end

function Questing:SettingsChanged()
    if ns.QuickDialog and ns.QuickDialog.Sync then ns.QuickDialog:Sync() end
    self:RequestScore("settings", 0)
end

local CONTROLS = {
    { key = "tutorialOnLaunch", label = "Tutorial on launch",
        tooltip = "Show the quick feature tutorial popup in the top-left when the game opens." },
    { key = "dock", label = "Dock next to the quest log", tooltip = "Attach the panel to whichever quest log is open." },
    { key = "autoShow", label = "Open with the quest log",
        tooltip = "While docked, automatically show the panel whenever the quest log or world map opens. Closing the panel while docked turns this off." },
    { key = "anyZone", label = "Any Zone mode (search all zones)",
        tooltip = "When off, Next Up only searches available quests in your current zone. Toggle anytime with the Any Zone button on the quest panel." },
    { key = "quickKeys", label = "Space to accept/complete & F1-F10 to pick rewards",
        tooltip = "While a quest window is open: press Space to accept, continue, or complete the quest, and press F1, F2, F3... to select between quest reward choices." },
    { key = "above", label = "Levels above you", kind = "slider", min = 0, max = 6, step = 1,
        tooltip = "How far above your level a quest may be and still be suggested." },
    { key = "below", label = "Levels below you (0 = until grey)", kind = "slider", min = 0, max = 15, step = 1,
        tooltip = "How far below your level a quest may be. 0 uses the grey (no XP) cutoff." },
    { key = "hideGrey", label = "Hide grey quests", tooltip = "Never suggest quests that give little or no XP." },
    { key = "hideElite", label = "Hide elite and group quests while solo",
        tooltip = "Otherwise they are kept but ranked lower while you are not in a group." },
    { key = "showCircuit", label = "Suggest a circuit of nearby quests",
        tooltip = "Top of Next Up: the zone where your best quests cluster, in visiting order. Click it to start." },
    { key = "includeDungeons", label = "Include dungeon quests", tooltip = "Suggest quests inside dungeons in Next Up." },
    { key = "xpPerGold", label = "XP value of 1 gold in rewards", kind = "slider", min = 0, max = 200, step = 10,
        tooltip = "How much reward money and items count when ranking quests." },
    { key = "xpPerRep", label = "XP value of 1 reputation", kind = "slider", min = 0, max = 20, step = 1,
        tooltip = "Count reputation rewards when ranking quests (0 ignores them). Useful for repeatable turn-ins." },
}

WFC:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    local g = WFC.Store:Bind("WFC_Questing_Global", { settings = Questing.DEFAULTS }, 1)
    local c = WFC.Store:Bind("WFC_Questing_Char", { ignored = {} }, 1)
    Questing.settings, Questing.char = g.settings, c
    WFC.Store:RegisterExport("questingSettings",
        function() return g.settings end,
        function(value)
            if type(value) == "table" then
                for k, v in pairs(value) do g.settings[k] = v end
            end
        end)
    WFC.Store:RegisterExport("questingIgnored:" .. WFC.Util.CharKey(),
        function() return c.ignored end,
        function(value)
            if type(value) == "table" then
                for k, v in pairs(value) do c.ignored[tonumber(k) or k] = v and true or nil end
            end
        end)
    Questing.category = WFC.UI:AddSettingsPage("Questing", g.settings, Questing.DEFAULTS, CONTROLS,
        function() Questing:SettingsChanged() end)
    if WFC.UI and WFC.UI.RegisterTutorial then
        WFC.UI:RegisterTutorial({
            id = "Questing",
            order = 1,
            title = "WFC Questing · Quick Keys",
            icon = "Interface\\GossipFrame\\AvailableQuestIcon",
            accent = { 1.00, 0.82, 0.20 },
            store = g.settings,
            settingKey = "tutorialOnLaunch",
            rows = {
                { icon = "Interface\\GossipFrame\\AvailableQuestIcon", pill = "[ SPACE ]", style = "gold",
                    text = "|cff40ff40Accept|r or |cff40ff40Complete|r quests" },
                { icon = "Interface\\GossipFrame\\ActiveQuestIcon", pill = "F1 / F2...", style = "cyan",
                    text = "Pick |cffffd1001st, 2nd, 3rd...|r reward" },
                { icon = "Interface\\Icons\\INV_Misc_Map_01", pill = "Any Zone", style = "green",
                    text = "Toggle |cff4dd9ffZone|r vs |cff4dd9ffAll Zones|r" },
            },
        })
    end
end)

---------------------------------------------------------------------------
-- /wfc quests
---------------------------------------------------------------------------
WFC:AddCommand("quests", "[show|hide|dock|undock|autoshow [on|off]|reset|rescore|next|ignored|unignore <id>|options]", function(rest)
    local Panel = ns.Panel
    local a, b = strsplit(" ", (rest or ""):lower(), 2)
    local s = Questing.settings
    if a == "" or a == nil then
        Panel:Toggle()
    elseif a == "show" then
        Panel:Show()
    elseif a == "hide" then
        Panel:Hide()
    elseif a == "dock" or a == "undock" then
        s.dock = a == "dock"
        Panel:UpdateDock()
        WFC:Print("quest panel", s.dock and "docks to the quest log" or "is a standalone window")
    elseif a == "autoshow" then
        if b == "on" or b == "1" or b == "true" then
            s.autoShow = true
            WFC:Print("quest panel will open automatically with the map/quest log")
        elseif b == "off" or b == "0" or b == "false" then
            s.autoShow = false
            WFC:Print("quest panel will stay closed when opening the map/quest log")
        else
            s.autoShow = not s.autoShow
            WFC:Print("auto-show with map/log:", s.autoShow and "on" or "off")
        end
    elseif a == "reset" then
        s.window = {}
        Panel:ResetPosition()
    elseif a == "rescore" then
        Questing:RequestScore("command", 0)
    elseif a == "next" then
        local entries = Questing:GetNextUp(5)
        if #entries == 0 then
            WFC:Print("no recommended quests to pick up right now")
        else
            WFC:Print("Top recommended quests to pick up:")
            for i, entry in ipairs(entries) do
                local c = entry.candidate
                local giver = Panel.GetQuestGiver and Panel.GetQuestGiver(c.id)
                local giverStr = giver and (" (from " .. giver .. ")") or ""
                print(("  #%d. [%s] %s%s · ~%d min · %d xp/min"):format(i, tostring(c.level or c.minLevel), c.name or c.id,
                    giverStr, math.floor(entry.minutes + 0.5), math.floor(entry.score + 0.5)))
            end
        end
    elseif a == "ignored" then
        local n = 0
        for id in pairs(Questing.char.ignored) do
            n = n + 1
            local brief = WFC.DB:GetQuestBrief(id)
            print(("  %d %s"):format(id, brief and brief.name or "?"))
        end
        WFC:Print(n, "ignored quest(s)")
    elseif a == "unignore" and tonumber(b) then
        Questing:SetIgnored(tonumber(b), false)
    elseif a == "options" then
        if not WFC.UI:OpenSettings(Questing.category) then WFC:Print("options panel unavailable; use /wfc quests") end
    else
        WFC:Print("unknown option; try /wfc help")
    end
end)
