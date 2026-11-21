local _, ns = ...
local WFC = ns.WFC

-- WFC.DB is split into SECTIONS (Zones, Quests, Items, Npcs, Objects, Recipes,
-- Drops, Prices, New). Each section:
--   * reads only the QuestieDB fields it needs, for the entity it was asked about;
--   * memoizes a normalized, denormalized "card" per entity, so the second call is
--     a single table lookup and callers never parse raw data;
--   * may hold small static indexes built at Init.
-- Whole-database reverse indexes (quests by zone, NPCs by area, ...) live in
-- DB/Indexes.lua and are built in the background, then cached in WFC_DB_Cache.
--
-- Section lifecycle hooks (all optional):
--   section:Init()        after QuestieDB is bound (ADDON_LOADED)
--   section:Login()       after the player snapshot exists (PLAYER_LOGIN)
--   section:Invalidate()  drop memoized cards (data changed)
--   section:Stats()       -> table of counters for /wfc db stats

local DB = {
    ready = false,
    sections = {},
    order = {},
}
WFC.DB = DB

--- Creates and registers a section. Sections are also reachable as WFC.DB.<Name>.
function DB:NewSection(name)
    local section = { name = name }
    self.sections[name] = section
    self.order[#self.order + 1] = name
    self[name] = section
    return section
end

function DB:Call(hook, ...)
    for i = 1, #self.order do
        local section = self.sections[self.order[i]]
        local fn = section[hook]
        if fn then
            local ok, err = pcall(fn, section, ...)
            if not ok then geterrorhandler()("WFC.DB." .. section.name .. ":" .. hook .. " - " .. tostring(err)) end
        end
    end
end

function DB:IsReady()
    return self.ready
end

--- Drops every memoized card (e.g. after corrections or harvest imports).
function DB:Invalidate()
    self:Call("Invalidate")
    WFC:Fire("WFC_DB_INVALIDATED")
end

function DB:Stats()
    local stats = {}
    for i = 1, #self.order do
        local section = self.sections[self.order[i]]
        if section.Stats then stats[section.name] = section:Stats() end
    end
    return stats
end
