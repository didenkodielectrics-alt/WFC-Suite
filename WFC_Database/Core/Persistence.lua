local _, ns = ...
local WFC = ns.WFC

-- SavedVariables are a CACHE that can vanish on a cold start (CoreRules R8).
-- Every module must be able to rebuild from live APIs; user choices can be
-- exported to / imported from a string as a manual backup.

local Store = {}
WFC.Store = Store

local Serialize = WFC.Serialize
local CopyDeep = WFC.Util.CopyDeep
local EXPORT_PREFIX = "WFC1:"

local function applyDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            t[k] = CopyDeep(v)
        elseif type(v) == "table" and type(t[k]) == "table" then
            applyDefaults(t[k], v)
        end
    end
end

--- Validates/initializes a SavedVariables root and assigns it back to _G.
--- A root from a newer schema, or a non-table, is replaced. migrate(old, oldSchema) may upgrade.
function Store:Bind(globalName, defaults, schema, migrate)
    local t = _G[globalName]
    if type(t) ~= "table" or (type(t.schema) == "number" and t.schema > schema) then
        t = {}
    elseif type(t.schema) == "number" and t.schema < schema and migrate then
        t = migrate(t, t.schema) or {}
    end
    t.schema = schema
    applyDefaults(t, defaults or {})
    _G[globalName] = t
    return t
end

---------------------------------------------------------------------------
-- Rebuild registry
---------------------------------------------------------------------------
local rebuilders = {}

--- fn() reconstructs a module's state from live client APIs.
function Store:RegisterRebuild(name, fn)
    rebuilders[name] = fn
end

function Store:RebuildAll()
    for name, fn in pairs(rebuilders) do
        WFC:RunOutOfCombat("rebuild:" .. name, fn)
    end
end

---------------------------------------------------------------------------
-- Export / import of user choices
---------------------------------------------------------------------------
local exporters = {}

--- get() returns plain data to back up; set(data) restores it.
function Store:RegisterExport(key, get, set)
    exporters[key] = { get = get, set = set }
end

function Store:Export()
    local payload = {}
    for key, e in pairs(exporters) do
        payload[key] = e.get()
    end
    return EXPORT_PREFIX .. Serialize.Encode(payload)
end

--- Returns true, or false + error message.
function Store:Import(str)
    if type(str) ~= "string" or str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return false, "not a WFC export string"
    end
    local payload, err = Serialize.Decode(str:sub(#EXPORT_PREFIX + 1))
    if type(payload) ~= "table" then return false, err or "invalid data" end
    for key, value in pairs(payload) do
        local e = exporters[key]
        if e then e.set(value) end
    end
    return true
end
