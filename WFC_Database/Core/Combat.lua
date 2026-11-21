local _, ns = ...
local WFC = ns.WFC

-- Combat gate (CoreRules R4/R6): everything WFC does is out-of-combat work.
-- Work requested during combat is queued by key (latest request wins) and
-- flushed, in request order, when combat ends.

local InCombatLockdown = InCombatLockdown
local Compat = WFC.Compat

local queue, order = {}, {}

function WFC:InCombat()
    return InCombatLockdown()
end

--- Runs fn now when out of combat, otherwise once combat ends. Returns true if it ran now.
function WFC:RunOutOfCombat(key, fn)
    if not InCombatLockdown() then
        fn()
        return true
    end
    if not queue[key] then order[#order + 1] = key end
    queue[key] = fn
    return false
end

--- Returns v, or nil when v is a secret value that must not be compared or used as a key.
function WFC.Safe(v)
    if Compat.IsSecret(v) then return nil end
    return v
end

WFC:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    WFC:Fire("WFC_COMBAT_START")
end)

WFC:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    local keys = order
    order = {}
    for i = 1, #keys do
        local fn = queue[keys[i]]
        queue[keys[i]] = nil
        if fn then
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end
    WFC:Fire("WFC_COMBAT_END")
end)
