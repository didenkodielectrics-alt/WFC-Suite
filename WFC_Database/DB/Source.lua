local _, ns = ...
local WFC = ns.WFC

-- The ONLY file that touches LibQuestieDB (CoreRules R12). Sections take the
-- entity tables from here (Source.Q/N/I/O) in their Init and call the named
-- getters directly, which is the fastest QuestieDB read path.
--
-- QuestieDB semantics the sections must respect:
--   * numeric fields return 0 (not nil) for "none"  -> WFC.Util.Nz
--   * every table read returns a fresh copy          -> memoize, never re-read in loops
--   * startedBy/finishedBy/objectives are {} not nil
--   * coordinates are 0-100 percentages keyed by AreaID
--   * GetAllIds() is shared and read-only

local Compat = WFC.Compat

local REQUIRED_CONTRACT = 4

local Source = {
    available = false,
    reason = nil,
}
WFC.DB.Source = Source

function Source:Init()
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" or type(lib.Quest) ~= "table" then
        self.reason = "QuestieDB is not loaded"
        return false
    end
    if lib.RequireContract then
        local ok, message = lib.RequireContract(REQUIRED_CONTRACT)
        if not ok then
            self.reason = "QuestieDB is too old: " .. tostring(message)
            return false
        end
    end
    self.lib = lib
    self.Q, self.N, self.I, self.O = lib.Quest, lib.Npc, lib.Item, lib.Object
    self.contract = lib.contractVersion
    self.mode = lib.readMode
    self.version = Compat.GetAddOnMetadata("QuestieDB", "Version") or "?"
    self.available = true
    return true
end

--- Identifies the provider data; part of the WFC_DB_Cache key.
function Source:VersionKey()
    return table.concat({ tostring(self.version), tostring(self.contract), tostring(self.mode) }, "/")
end

--- Support module by name ("ZoneDB", "QuestXP", "QuestieDB", "QuestieClassicItemDrops", ...).
function Source:Support(name)
    local support = self.lib and self.lib.Support
    if support and support.Get then
        local ok, value = pcall(support.Get, name)
        if ok then return value end
    end
end

--- Support values that ship as "return {...}" source strings are loaded once here.
--- Plain tables pass through. Never returns nil.
function Source.Materialize(value)
    if type(value) == "string" then
        local fn = loadstring(value)
        if fn then
            setfenv(fn, {})
            local ok, result = pcall(fn)
            if ok and type(result) == "table" then return result end
        end
        return {}
    end
    return type(value) == "table" and value or {}
end

function Source:Enum()
    return self.lib and self.lib.Enum or {}
end

function Source:RaceMask(raceId)
    local masks = self:Enum().raceMaskById
    return masks and raceId and masks[raceId] or nil
end

--- { Alliance = mask, Horde = mask } for the active flavor.
function Source:FactionRaceMasks()
    return self:Enum().factionRaceMasks or {}
end

function Source:ClassMask(classFile)
    local keys = self:Enum().classKeys
    local v = keys and classFile and keys[classFile]
    if type(v) == "number" and v > 0 then return v end
end

--- { flagName = bitValue } NPC function flags (vendor, trainer, flight master, ...).
function Source:NpcFlags()
    return self:Enum().npcFlags or {}
end

--- Converts an Era-framed point (0-100) to Forever. Never apply to QuestieDB data.
function Source:EraToForever(areaId, x, y)
    local lib = self.lib
    if lib and lib.EraToForever then return lib.EraToForever(areaId, x, y) end
    return x, y
end

--- Same as EraToForever, keyed by uiMapID (0-100 in and out). For hand-authored Era coordinates.
function Source:EraToForeverByUiMapId(uiMapId, x, y)
    local lib = self.lib
    if lib and lib.EraToForeverByUiMapId then return lib.EraToForeverByUiMapId(uiMapId, x, y) end
    return x, y
end

function Source:Status()
    if not self.available then return "unavailable: " .. tostring(self.reason) end
    return ("QuestieDB %s, contract %s, %s mode"):format(tostring(self.version), tostring(self.contract), tostring(self.mode))
end
