local ADDON_NAME, ns = ...
local WFC = WFC

-- WFC_OverlayRevamp (design.md §7): restyles Forever's windows and fonts with a flat,
-- race-flavoured theme. Namespace, SavedVariables, theme choice, the GetTheme() API for the
-- WFC addons, the options page and /wfcui.

local Themes = ns.Themes

local Overlay = { ADDON = ADDON_NAME }
WFC.OverlayRevamp = Overlay
ns.Overlay = Overlay

Overlay.DEFAULTS = {
    tutorialOnLaunch = true, -- show the quick tutorial popup in the top-left on game launch
    style = nil,             -- "original" | "originalplus" | "modern" | "futuristic" (nil: from `theme`)
    theme = "auto",          -- Original+ colours: "auto" (by race), a theme key, or "blizzard" (skinning off)
    ambience = true,         -- Futuristic/Modern screen ambience (haze, motes, vignette)
    music = true,            -- play a theme's own track if its file is installed (Panelka)
    themeButton = true,      -- the THEMES button with the top-left launchers
    themeButtonPos = nil,    -- saved position once dragged
    ornaments = 0.55,        -- 0 off, 0.35 subtle, 0.55 normal
    wfcHeaderFonts = false,  -- WFC windows keep their Teko/Barlow pair unless this is on
    glockFireBlast = true,   -- Easter egg: pull out a Glock 19 when casting Fire Blast
    modules = { fonts = true, tooltips = true, core = true, economy = true, wfc = true, chrome = true },
    disabled = {},           -- [frameName] = true: skins switched off one by one (/wfcui skin)
}

Overlay.ORNAMENT_LEVELS = { off = 0, subtle = 0.35, normal = 0.55 }

--- The active style: "original" | "originalplus" | "modern" | "futuristic".
function Overlay:Style()
    local s = self.settings
    if not s then return "original" end
    local st = s.style
    if st and (st == "original" or st == "originalplus" or (ns.Styles and ns.Styles.packs[st])) then return st end
    return s.theme == "blizzard" and "original" or "originalplus"
end

--- Switches the whole UI look and restyles everything live.
function Overlay:SetStyle(id)
    local s = self.settings
    if not s then return end
    s.style = id
    if id == "original" then
        s.theme = "blizzard"
    elseif s.theme == "blizzard" then
        s.theme = "auto"
    end
    self:Restyle()
    WFC:Fire("WFC_OVERLAY_STYLE", id)
end

--- The active theme table, or nil when the Blizzard look is chosen.
function Overlay:Theme()
    local s = self.settings
    if not s then return nil end
    local style = self:Style()
    if style == "original" then return nil end
    if style ~= "originalplus" then return ns.Styles.Theme(style) end
    if s.theme == "blizzard" then return nil end
    local key = s.theme
    if key == "auto" or not Themes.list[key] then
        local P = WFC.Player
        key = Themes.Pick(P.raceFile, P.faction, P.raceId)
    end
    return Themes.list[key]
end

--- Public API (design §7.6): the active token table, or nil (Blizzard look / not loaded yet).
function Overlay.GetTheme()
    return Overlay:Theme()
end
WFC_OverlayRevamp = { GetTheme = Overlay.GetTheme }

function Overlay:ModuleOn(module)
    local s = self.settings
    return s ~= nil and s.theme ~= "blizzard" and s.modules[module] ~= false and not (self.blocked and self.blocked[module])
end

WFC:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    local g = WFC.Store:Bind("WFC_OverlayRevamp_Global", { settings = Overlay.DEFAULTS }, 1)
    Overlay.settings = g.settings
    WFC.Store:RegisterExport("overlaySettings",
        function() return g.settings end,
        function(value)
            if type(value) == "table" then
                for k, v in pairs(value) do g.settings[k] = v end
            end
        end)
    Overlay.category = WFC.UI:AddSettingsPage("OverlayRevamp", g.settings, Overlay.DEFAULTS, {
        { key = "tutorialOnLaunch", label = "Tutorial on launch",
            tooltip = "Show the quick feature tutorial popup in the top-left when the game opens." },
        { key = "themeButton", label = "Show THEMES button (top-left)",
            tooltip = "A button next to the WFC launchers that opens the theme picker: Original, Original+, Modern, Futuristic. /wfcui themes also opens it." },
        { key = "ambience", label = "Theme ambience",
            tooltip = "Modern: a soft cinematic vignette. Futuristic: amber sky haze and drifting golden motes. Purely visual; never takes the mouse." },
        { key = "music", label = "Theme music",
            tooltip = "Panelka plays Media\\Music\\toska.mp3 (your own copy) in place of zone music while it's the active theme. A newly added file needs a full WoW restart." },
        { key = "wfcHeaderFonts", label = "Use theme header fonts in WFC windows",
            tooltip = "Off: WFC windows keep their own fonts on every character." },
        { key = "ornaments", label = "Ornament intensity", kind = "slider", min = 0, max = 0.55, step = 0.05,
            tooltip = "0 turns the corner and title ornaments off." },
        { key = "glockFireBlast", label = "Easter egg: Glock 19 Fire Blast",
            tooltip = "Pull out a Glock 19 when casting Fire Blast — fires a high-velocity round with a smoke trail and smoky impact explosion." },
    }, function() Overlay:Restyle() end)
    if WFC.UI and WFC.UI.RegisterTutorial then
        WFC.UI:RegisterTutorial({
            id = "OverlayRevamp",
            order = 4,
            title = "WFC Overlay · Themes",
            icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01",
            accent = { 0.95, 0.55, 0.20 },
            store = g.settings,
            settingKey = "tutorialOnLaunch",
            rows = {
                { icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01", pill = "THEMES", style = "amber",
                    text = "Pick a look from the |cffffa840THEMES|r button (top-left)" },
                { icon = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02", pill = "Modern", style = "cyan",
                    text = "|cff8c9bffModern|r graphite glass or |cffe9b44cFuturistic|r amber holo-city" },
                { icon = "Interface\\Icons\\Trade_Engineering", pill = "/wfcui", style = "gold",
                    text = "Right-click the button to cycle · |cffffd100/wfcui themes|r" },
            },
        })
    end
end)

---------------------------------------------------------------------------
-- /wfcui
---------------------------------------------------------------------------
local STYLE_ALIASES = { original = "original", blizzard = "original", ["original+"] = "originalplus",
    originalplus = "originalplus", plus = "originalplus", modern = "modern", futuristic = "futuristic", future = "futuristic",
    nightdrive = "nightdrive", synthwave = "nightdrive", wildwood = "wildwood", forest = "wildwood",
    frostbound = "frostbound", frost = "frostbound", ice = "frostbound",
    panelka = "panelka", soviet = "panelka", postpunk = "panelka" }

local function status()
    local t = Overlay:Theme()
    local style = Overlay:Style()
    local info = ns.Styles and ns.Styles.INFO[style]
    WFC:Print(("OverlayRevamp: %s%s · ornaments %.2f · ambience %s · glock %s%s"):format(info and info.name or style,
        style == "originalplus" and t and (" (" .. t.name .. ")") or "",
        Overlay.settings.ornaments, Overlay.settings.ambience ~= false and "on" or "off",
        Overlay.settings.glockFireBlast and "ON" or "off",
        Overlay.blockedBy and (" · limited by " .. Overlay.blockedBy) or ""))
end

local function command(msg)
    local a, b, c = strsplit(" ", (msg or ""):lower(), 3)
    local s = Overlay.settings
    if a == "" or a == nil then
        status()
    elseif (a == "style" or a == "theme") and b and STYLE_ALIASES[b] and b ~= "blizzard" then
        Overlay:SetStyle(STYLE_ALIASES[b])
        status()
    elseif a == "themes" or a == "picker" then
        if ns.ThemeButton then ns.ThemeButton:TogglePicker() end
    elseif a == "ambience" and (b == "on" or b == "off") then
        s.ambience = b == "on"
        Overlay:Restyle()
        status()
    elseif a == "music" and (b == "on" or b == "off") then
        s.music = b == "on"
        Overlay:Restyle()
        WFC:Print("Theme music:", b, "· your own track goes in Interface\\AddOns\\WFC_OverlayRevamp\\Media\\Music\\ (see README there)")
    elseif a == "theme" and b then
        local key = b
        for k in pairs(Themes.list) do
            if k:lower() == b then key = k end
        end
        if b ~= "auto" and b ~= "blizzard" and not Themes.list[key] then
            WFC:Print("styles: original, originalplus, modern, futuristic · Original+ colours: auto, "
                .. table.concat(Themes.ORDER, ", "))
            return
        end
        -- A race colour (or auto/blizzard) picks the Original+ / Original look.
        s.theme = key
        s.style = key == "blizzard" and "original" or "originalplus"
        Overlay:Restyle()
        status()
    elseif a == "ornaments" and Overlay.ORNAMENT_LEVELS[b or ""] then
        s.ornaments = Overlay.ORNAMENT_LEVELS[b]
        Overlay:Restyle()
        status()
    elseif a == "glock" then
        if b == "test" or b == "fire" then
            if ns.Glock then
                local ok, err = pcall(ns.Glock.Fire, ns.Glock)
                if not ok then WFC:Print("Glock error:", tostring(err)) end
            else
                WFC:Print("Glock module not loaded yet — try /reload")
            end
        elseif b == "on" or b == "off" then
            s.glockFireBlast = (b == "on")
            WFC:Print("Easter egg Glock Fire Blast:", s.glockFireBlast and "ON" or "off")
        else
            s.glockFireBlast = not s.glockFireBlast
            WFC:Print("Easter egg Glock Fire Blast:", s.glockFireBlast and "ON" or "off")
        end
    elseif a == "skin" and b and (c == "off" or c == "on") then
        -- Frame names are case-sensitive; match against the registry.
        local name = ns.Skin:FindRegistered(b)
        if not name then return WFC:Print("unknown frame", b, "- see /wfcui list") end
        s.disabled[name] = c == "off" or nil
        Overlay:Restyle()
        WFC:Print(name, c == "off" and "will keep Blizzard's look" or "skinned")
    elseif a == "module" and b and s.modules[b] ~= nil and (c == "off" or c == "on") then
        s.modules[b] = c == "on"
        Overlay:Restyle()
        WFC:Print("module", b, c)
    elseif a == "list" then
        for _, name in ipairs(ns.Skin:Registered()) do
            local e = ns.Skin.registry[name]
            print(("  %s (%s)%s%s"):format(name, e.group, ns.Skin:IsSkinned(name) and " · skinned" or "",
                s.disabled[name] and " · off" or ""))
        end
    elseif a == "debug" and b == "chrome" then
        if ns.Chrome then ns.Chrome:Debug() end
    elseif a == "debug" and b == "zones" then
        ns.Skin.debugZones = not ns.Skin.debugZones
        Overlay:Restyle()
        WFC:Print("ornament zones", ns.Skin.debugZones and "shown in magenta" or "hidden")
    elseif a == "options" then
        if not WFC.UI:OpenSettings(Overlay.category) then WFC:Print("options panel unavailable; use /wfcui") end
    else
        WFC:Print("/wfcui [style original|originalplus|modern|futuristic|nightdrive|wildwood|frostbound|panelka|themes|theme <race|auto|blizzard>"
            .. "|ornaments off|subtle|normal|ambience on|off|music on|off|glock [on|off|test]|skin <frame> off|on"
            .. "|module fonts|tooltips|core|economy|wfc|chrome off|on|list|debug zones|options]")
    end
end

SLASH_WFCUI1 = "/wfcui"
SlashCmdList.WFCUI = command
WFC:AddCommand("ui", "(same as /wfcui)", command)
