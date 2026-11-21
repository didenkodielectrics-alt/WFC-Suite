local ADDON_NAME, ns = ...

-- WFC is the only global the suite publishes (plus SavedVariables roots).
-- Other WFC addons extend it; private state stays on `ns`.
WFC = WFC or {}
local WFC = WFC

ns.WFC = WFC
ns.Data = ns.Data or {}

WFC.ADDON = ADDON_NAME
WFC.DATA_VERSION = 1 -- bump when Data/ or index formats change; invalidates WFC_DB_Cache
WFC.CHAT_PREFIX = "|cff4dd9ffWFC|r: "
WFC.NEW_TAG = "|cff4dd9ffnew!|r"

--- The new! tag, or "" when the user turned tags off (plan.md §6). `prefix` goes before a shown tag.
function WFC:NewTag(prefix)
    local g = WFC_DB_Global
    if g and g.settings and g.settings.showNew == false then return "" end
    return (prefix or "") .. WFC.NEW_TAG
end

function WFC:Print(...)
    print(WFC.CHAT_PREFIX .. strjoin(" ", tostringall(...)))
end

--- Structured log line: level "ERROR" | "WARN" | "INFO" | "DEBUG", source = short module name.
--- A no-op unless dev mode (Database\Dev) is installed; safe to leave calls in shipped code.
function WFC:Log(level, source, ...) end

function WFC:Debug(...)
    local g = WFC_DB_Global
    if g and g.settings and g.settings.debug then
        print("|cff808080WFC debug:|r " .. strjoin(" ", tostringall(...)))
    end
end
