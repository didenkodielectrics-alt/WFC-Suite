local ADDON_NAME, ns = ...
local WFC = ns.WFC

-- Startup order:
--   ADDON_LOADED  bind SavedVariables -> bind QuestieDB -> section Init()     -> WFC_STORE_READY
--   PLAYER_LOGIN  player snapshot     -> section Login() -> background indexes -> WFC_DB_READY

local DB, Store = WFC.DB, WFC.Store

local GLOBAL_DEFAULTS = {
    settings = {
        debug = false,
        harvest = true,
        prewarmDrops = true,
        priceProviders = { "auctionator", "tsm" },
        showNew = true,
        fontScale = 1,
    },
    chars = {},
    harvest = { loot = {}, corpses = {}, vendors = {}, recipes = {}, questGivers = {}, questEnders = {} },
}

local function onAddonLoaded(event, name)
    if name ~= ADDON_NAME then return end
    WFC:UnregisterEvent(event, onAddonLoaded)

    Store:Bind("WFC_DB_Global", GLOBAL_DEFAULTS, 1)
    Store:Bind("WFC_DB_Char", {}, 1)
    Store:Bind("WFC_DB_Cache", { indexes = {} }, 1)
    WFC.version = WFC.Compat.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

    Store:RegisterExport("dbSettings",
        function() return WFC_DB_Global.settings end,
        function(value)
            if type(value) == "table" then
                for k, v in pairs(value) do WFC_DB_Global.settings[k] = v end
            end
        end)
    Store:RegisterRebuild("player", function() WFC.Player:RefreshAll() end)

    if DB.Source:Init() then
        DB:Call("Init")
    else
        WFC:Print("|cffff1a1a" .. tostring(DB.Source.reason) .. "|r - WFC database features are disabled.")
    end
    WFC:Fire("WFC_STORE_READY")
end

WFC:RegisterEvent("ADDON_LOADED", onAddonLoaded)

WFC:RegisterEvent("PLAYER_LOGIN", function()
    WFC.Player:RefreshAll()
    if not DB.Source.available then return end
    DB:Call("Login")
    DB.Indexes:Start()
    DB.ready = true
    WFC:Fire("WFC_DB_READY")
end)
