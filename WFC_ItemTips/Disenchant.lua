local _, ns = ...

-- Classic disenchanting (plan.md §3.3, DISENCHANT row). PURE: tables and arithmetic only.
-- Results follow the Classic 1.12 disenchant tables (approximate chances): uncommon armor
-- mostly gives dust, uncommon weapons mostly essence, rares a shard, epics shards or a
-- Nexus Crystal. Prices come in through a function, so the Advisor stays testable.

local Disenchant = {}
ns.Disenchant = Disenchant

local DUST = { 10940, 10940, 10940, 11083, 11083, 11137, 11137, 11176, 11176, 16204, 16204 }
local ESSENCE = { 10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203, 16203 }
local SHARD = { nil, 10978, 10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 14344 }
-- Uncommon dust/essence counts per band: { dustMin, dustMax, essMin, essMax }
local COUNTS = {
    { 1, 2, 1, 2 }, { 2, 3, 1, 2 }, { 4, 6, 1, 2 }, { 1, 2, 1, 2 }, { 2, 5, 1, 2 }, { 1, 2, 1, 2 },
    { 2, 5, 1, 2 }, { 1, 2, 1, 2 }, { 2, 5, 1, 2 }, { 1, 2, 1, 2 }, { 2, 5, 2, 3 },
}
local NEXUS = 20725

Disenchant.ARMOR, Disenchant.WEAPON = 4, 2 -- item class IDs
Disenchant.ENCHANTING = 333

--- Item-level band 1-11: 5-15, 16-20, 21-25, ... 61-65 (higher levels count as the last band).
local function band(ilvl)
    if ilvl <= 15 then return 1 end
    return math.min(11, math.floor((ilvl - 16) / 5) + 2)
end

--- Enchanting skill needed to disenchant an item of this level.
function Disenchant.Skill(ilvl)
    if ilvl <= 20 then return 1 end
    return math.min(300, (math.floor((ilvl - 21) / 5) + 1) * 25)
end

--- True for items that can be disenchanted: uncommon to epic armor and weapons.
function Disenchant.Can(client)
    return client ~= nil and (client.quality or 0) >= 2 and client.quality <= 4
        and (client.classId == Disenchant.ARMOR or client.classId == Disenchant.WEAPON)
        and (client.ilvl or 0) >= 5
end

--- { { itemId, chance, min, max }, ... } for an item.
function Disenchant.Results(quality, ilvl, isWeapon)
    local b = band(ilvl)
    if quality == 2 then
        local c = COUNTS[b]
        local dust, essence = isWeapon and 0.20 or 0.75, isWeapon and 0.75 or 0.20
        local shardChance = b == 1 and 0 or (b == 3 and 0.10 or 0.05)
        if b == 1 then dust, essence = isWeapon and 0.20 or 0.80, isWeapon and 0.80 or 0.20 end
        local out = {
            { DUST[b], dust, c[1], c[2] },
            { ESSENCE[b], essence, c[3], c[4] },
        }
        if SHARD[b] and shardChance > 0 then
            -- The shard replaces some of the dust/essence chance (they add up to 1).
            out[1][2] = out[1][2] - (b == 3 and 0.05 or 0)
            out[#out + 1] = { SHARD[b], shardChance, 1, 1 }
        end
        return out
    elseif quality == 3 then
        local out = { { SHARD[math.max(2, b)], b >= 10 and 0.995 or 1, 1, 1 } }
        if b >= 10 then out[2] = { NEXUS, 0.005, 1, 1 } end
        return out
    elseif quality == 4 then
        if ilvl >= 56 then return { { NEXUS, 1, 1, ilvl >= 61 and 2 or 1 } } end
        return { { SHARD[math.max(7, b)], 1, 2, 4 } }
    end
    return {}
end

--- Expected copper from disenchanting, priced by price(itemId) -> copper|nil.
--- nil when no result has a price (the advice would be a guess).
function Disenchant.Value(results, price)
    local total, priced, best, bestValue = 0, false, nil, 0
    for _, r in ipairs(results) do
        local p = price(r[1])
        if p and p > 0 then
            local value = r[2] * (r[3] + r[4]) / 2 * p
            total, priced = total + value, true
            if value > bestValue then best, bestValue = r[1], value end
        end
    end
    if not priced then return nil end
    return total, best
end

-- Shared with The Plan (gear advice: disenchant vs save vs sell).
if WFC and WFC.ItemTips then WFC.ItemTips.Disenchant = Disenchant end

return Disenchant
