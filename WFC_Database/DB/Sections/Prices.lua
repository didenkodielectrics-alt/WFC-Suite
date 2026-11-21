local _, ns = ...
local WFC = ns.WFC

-- Prices come from OTHER addons' auction scanners: the WoW auction API is slow
-- and throttled, so WFC does not scan (an own scanner is deferred, plan.md M9).
-- Providers are tried in the user's preferred order; the first with a price wins.
--
-- Built-in providers: Auctionator (has a Forever build), TSM (dormant: no Forever
-- build yet). Any addon can add one:
--
--   WFC.DB.Prices:RegisterProvider({
--       key = "myscanner", label = "My Scanner",
--       IsAvailable = function() return MyScanner ~= nil end,
--       GetPrice = function(itemId) return copper or nil end,   -- required
--       GetAge = function(itemId) return days or nil end,       -- optional
--       Watch = function(onChange) ... end,                     -- optional: call onChange() when its data updates
--   })

local Util = WFC.Util

local Prices = WFC.DB:NewSection("Prices")

local CALLER = "WFC"
local CACHE_SECONDS = 300

local providers = {}  -- [key] = provider
local active = {}     -- ordered list of available providers
local cache = {}      -- [itemId] = { t, copper, key, age }

function Prices:RegisterProvider(provider)
    assert(type(provider) == "table" and provider.key and provider.GetPrice, "WFC Prices: invalid provider")
    providers[provider.key] = provider
    if WFC.DB.ready then self:Refresh() end
end

--- Re-detects available providers and orders them by settings.priceProviders.
function Prices:Refresh()
    active = {}
    local order = WFC_DB_Global.settings.priceProviders or {}
    local used = {}
    local function add(provider)
        if provider and not used[provider.key] then
            used[provider.key] = true
            local ok, available = pcall(provider.IsAvailable or function() return true end)
            if ok and available then
                active[#active + 1] = provider
                if provider.Watch and not provider.watching then
                    provider.watching = true
                    pcall(provider.Watch, function() Prices:Invalidate() end)
                end
            end
        end
    end
    for i = 1, #order do add(providers[order[i]]) end
    for _, provider in pairs(providers) do add(provider) end
    cache = {}
    local names = table.concat(self:Providers(), ", ")
    WFC:Log("INFO", "prices", "providers: " .. (names ~= "" and names or "none"))
end

function Prices:Login()
    self:Refresh()
end

function Prices:Invalidate()
    cache = {}
    WFC:Fire("WFC_PRICES_UPDATED")
end

--- Auction value in copper, provider key, and data age in days (age may be nil).
--- Returns nil when no provider has a price.
function Prices:Auction(itemId)
    local entry = cache[itemId]
    local now = GetTime()
    if entry and now - entry.t < CACHE_SECONDS then
        return entry.copper, entry.key, entry.age
    end
    entry = { t = now }
    for i = 1, #active do
        local p = active[i]
        local ok, copper = pcall(p.GetPrice, itemId)
        if ok and type(copper) == "number" and copper > 0 then
            entry.copper, entry.key = copper, p.key
            if p.GetAge then
                local ageOk, age = pcall(p.GetAge, itemId)
                entry.age = ageOk and age or nil
            end
            break
        end
    end
    cache[itemId] = entry
    return entry.copper, entry.key, entry.age
end

--- Vendor sell price in copper from the client, or nil until the item data loads.
function Prices:Vendor(itemId)
    local info = WFC.DB.Items:Client(itemId)
    return info and info.sellPrice or nil
end

function Prices:Providers()
    local list = {}
    for i = 1, #active do list[i] = active[i].key end
    return list
end

function Prices:Stats()
    return { providers = table.concat(self:Providers(), ","), cached = Util.Count(cache) }
end

---------------------------------------------------------------------------
-- Built-in providers
---------------------------------------------------------------------------
local function auctionatorApi()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

Prices:RegisterProvider({
    key = "auctionator",
    label = "Auctionator",
    IsAvailable = function()
        local api = auctionatorApi()
        return api ~= nil and api.GetAuctionPriceByItemID ~= nil
    end,
    GetPrice = function(itemId)
        return auctionatorApi().GetAuctionPriceByItemID(CALLER, itemId)
    end,
    GetAge = function(itemId)
        local api = auctionatorApi()
        if api.GetAuctionAgeByItemID then return api.GetAuctionAgeByItemID(CALLER, itemId) end
    end,
    Watch = function(onChange)
        local api = auctionatorApi()
        if api.RegisterForDBUpdate then api.RegisterForDBUpdate(CALLER, onChange) end
    end,
})

Prices:RegisterProvider({
    key = "tsm",
    label = "TradeSkillMaster",
    IsAvailable = function()
        return TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil
    end,
    GetPrice = function(itemId)
        return TSM_API.GetCustomPriceValue("dbminbuyout", "i:" .. itemId)
    end,
})
