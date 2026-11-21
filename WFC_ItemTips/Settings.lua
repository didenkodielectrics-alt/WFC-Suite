local ADDON_NAME, ns = ...
local WFC = WFC

-- WFC_ItemTips: namespace, SavedVariables, /wfc tips and the options page (plan.md §3.6).

local Tips = { ADDON = ADDON_NAME }
WFC.ItemTips = Tips
ns.Tips = Tips

Tips.DEFAULTS = {
    tutorialOnLaunch = true, -- show the quick tutorial popup in the top-left on game launch
    enabled = true,
    showReasons = true,    -- reference lines under the verdict
    shiftOnly = false,     -- only add anything while Shift is held
    useAlts = true,        -- CRAFT advice may name same-faction alts
    minProfitSilver = 1,   -- AUCTION only when it beats vendoring by this much (was 5s in the 1s-deposit era)
    margin = 0.10,         -- ...and by this fraction of the vendor price
    depositRate = 0.15,    -- deposit estimate as a fraction of the vendor price
    learnWindow = 25,      -- recipes learnable within this many skill points count for CRAFT
    weaponEnchants = true, -- clarify temporary weapon imbues (Rockbiter, Windfury, etc.)
    aliveSkinning = true,  -- show skinning difficulty on alive beasts
    skinningDrops = true,  -- show expected skinning loot & percentages on skinnable units
    humanoidCloth = true,  -- show expected cloth type & drop % on humanoids
    mining = true,         -- show mining required skill and difficulty
    herbalism = true,      -- show herbalism required skill and difficulty
    nodeGlowRange = 60,    -- yards: how far away the sparkle finds a node (Interact Key range)
    nodeGlow = true,       -- sparkle + floating name above a mining vein while you hover it
    valueJunk = true,         -- value junk / autosold items in inventory by default
    valueCrafting = false,    -- value crafting materials in inventory
    valueGear = false,        -- value weapons & armor in inventory
    valueConsumables = false, -- value consumables in inventory
    showValueLauncher = true, -- show inventory value button next to professions
    valueLauncherPos = nil,   -- custom position if dragged
}

--- Advisor-ready settings snapshot (copper units).
function Tips:AdvisorSettings()
    local s = self.settings
    return {
        minProfit = (s.minProfitSilver or 0) * 100,
        margin = s.margin, depositRate = s.depositRate, learnWindow = s.learnWindow,
    }
end

function Tips:SettingsChanged()
    if self.Invalidate then self:Invalidate() end
    if ns.InventoryValue and ns.InventoryValue.OnSettingsChanged then
        ns.InventoryValue:OnSettingsChanged()
    end
    if ns.NodeGlow and ns.NodeGlow.Sync then ns.NodeGlow:Sync() end
end

local CONTROLS = {
    { key = "tutorialOnLaunch", label = "Tutorial on launch",
        tooltip = "Show the quick feature tutorial popup in the top-left when the game opens." },
    { key = "enabled", label = "Show item advice", tooltip = "Add a keep / craft / auction / vendor verdict to item tooltips." },
    { key = "showValueLauncher", label = "Show inventory value button",
        tooltip = "Show quick inventory valuation button and popup next to WFC Professions launcher." },
    { key = "valueJunk", label = "Value junk in inventory",
        tooltip = "Include vendor trash and Scrap auto-sold items in inventory value." },
    { key = "valueCrafting", label = "Value crafting materials in inventory",
        tooltip = "Include trade goods, cloth, herbs, ore, leather, etc." },
    { key = "valueGear", label = "Value gear in inventory",
        tooltip = "Include equipable weapons and armor." },
    { key = "valueConsumables", label = "Value consumables in inventory",
        tooltip = "Include potions, food, bandages, scrolls, etc." },
    { key = "weaponEnchants", label = "Clarify weapon imbues", tooltip = "Show attack power and effect details on Rockbiter, Windfury, stones, oils, etc." },
    { key = "aliveSkinning", label = "Skinning difficulty on beasts and corpses", tooltip = "Show if an animal can be skinned, the skill required and your current skill, on live beasts and on their corpses." },
    { key = "skinningDrops", label = "Skinning loot & drop rates", tooltip = "Show expected leather, hides, and special scales with approximate percentages on skinnable creatures." },
    { key = "humanoidCloth", label = "Humanoid cloth drop rates", tooltip = "Show which cloth types and approximate drop percentages a humanoid creature can drop." },
    { key = "mining", label = "Mining skill & difficulty", tooltip = "Show required skill and difficulty on mining nodes, minable creatures, and ores." },
    { key = "nodeGlow", label = "Gathering sparkle & floating name", tooltip = "A sparkle in the difficulty colour sits on the nearest vein, herb or skinnable corpse (the one your Interact Key would pick), only for professions you have,, with its name, your Mining skill and the ore price. Turns on the Interact Key settings while on; turning it off puts them back." },
    { key = "herbalism", label = "Herbalism skill & difficulty", tooltip = "Show required skill and difficulty on herb nodes, herbable creatures, and herbs." },
    { key = "showReasons", label = "Show reasons", tooltip = "List the quest, recipe and prices behind the verdict." },
    { key = "shiftOnly", label = "Only while Shift is held", tooltip = "Keep tooltips untouched unless Shift is down." },
    { key = "useAlts", label = "Include alts' professions", tooltip = "Suggest crafting with your other characters of the same faction." },
    { key = "minProfitSilver", label = "Minimum auction profit (silver)", kind = "slider", min = 0, max = 500, step = 5,
        tooltip = "Only recommend the auction house when it earns at least this much more than a vendor." },
}

WFC:RegisterEvent("ADDON_LOADED", function(event, name)
    if name ~= ADDON_NAME then return end
    local g = WFC.Store:Bind("WFC_ItemTips_Global", { settings = Tips.DEFAULTS }, 1)
    if g.settings.minProfitSilver == 5 and not g.settings.depositEra1c then g.settings.minProfitSilver = 1 end
    g.settings.depositEra1c = true
    Tips.settings = g.settings
    WFC.Store:RegisterExport("itemTipsSettings",
        function() return g.settings end,
        function(value)
            if type(value) == "table" then
                for k, v in pairs(value) do g.settings[k] = v end
                Tips:SettingsChanged()
            end
        end)
    Tips.category = WFC.UI:AddSettingsPage("ItemTips", g.settings, Tips.DEFAULTS, CONTROLS,
        function() Tips:SettingsChanged() end)
    if WFC.UI and WFC.UI.RegisterTutorial then
        WFC.UI:RegisterTutorial({
            id = "ItemTips",
            order = 2,
            title = "WFC ItemTips · Tooltip Verdicts",
            icon = "Interface\\Icons\\INV_Misc_Coin_01",
            accent = { 0.25, 0.85, 0.40 },
            store = g.settings,
            settingKey = "tutorialOnLaunch",
            rows = {
                { icon = "Interface\\Icons\\INV_Misc_Coin_01", pill = "KEEP / AH", style = "green",
                    text = "|cff40ff40Keep, Craft, AH|r or |cffffd100Vendor|r advice" },
                { icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", pill = "Gather", style = "amber",
                    text = "|cffff8040Skin, Mine & Herb|r skill on tooltips" },
                { icon = "Interface\\Icons\\Spell_Nature_RockBiter", pill = "Imbues", style = "cyan",
                    text = "Exact stats on |cff4dd9ffweapon imbues|r" },
            },
        })
    end
end)

---------------------------------------------------------------------------
-- /wfc tips
---------------------------------------------------------------------------
local TOGGLES = { reasons = "showReasons", shift = "shiftOnly", alts = "useAlts", glow = "nodeGlow" }

WFC:AddCommand("tips", "[on|off|reasons on|off|shift on|off|alts on|off|glow on|off|test|profit <silver>|why <itemId>|options]",
    function(rest)
        local s = Tips.settings
        local a, b = strsplit(" ", (rest or ""):lower(), 2)
        if a == "on" or a == "off" then
            s.enabled = a == "on"
            WFC:Print("item advice", a)
        elseif TOGGLES[a] and (b == "on" or b == "off") then
            s[TOGGLES[a]] = b == "on"
            WFC:Print(a, b)
        elseif a == "profit" and tonumber(b) then
            s.minProfitSilver = tonumber(b)
            WFC:Print("minimum auction profit:", WFC.Compat.FormatMoney(s.minProfitSilver * 100))
        elseif a == "glow" and b == "why" then
            WFC:Print("Node sparkle:", ns.NodeGlow and ns.NodeGlow:Why() or "not loaded")
            return
        elseif a == "glow" and b and b:match("^range") then
            local yd = tonumber(b:match("^range%s+(%d+)"))
            if yd and yd >= 5 and yd <= 100 then
                s.nodeGlowRange = yd
                if ns.NodeGlow then ns.NodeGlow:Sync() end
            end
            WFC:Print(("Gathering sparkle range: %d yd (game setting now %s) · /wfc tips glow range <5-100>"):format(
                tonumber(s.nodeGlowRange) or 60, tostring(GetCVar("SoftTargetInteractRange"))))
            return
        elseif a == "glow" and b == "test" then
            if ns.NodeGlow then ns.NodeGlow:Preview() end
            return
        elseif a == "why" and tonumber(b) then
            Tips:PrintWhy(tonumber(b))
            return
        elseif a == "options" then
            if not WFC.UI:OpenSettings(Tips.category) then WFC:Print("options panel unavailable; use /wfc tips") end
            return
        else
            WFC:Print(("item advice %s · reasons %s · shift-only %s · alts %s · min profit %s"):format(
                s.enabled and "on" or "off", s.showReasons and "on" or "off", s.shiftOnly and "on" or "off",
                s.useAlts and "on" or "off", WFC.Compat.FormatMoney((s.minProfitSilver or 0) * 100)))
            return
        end
        Tips:SettingsChanged()
    end)
