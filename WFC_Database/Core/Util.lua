local _, ns = ...
local WFC = ns.WFC

local floor = math.floor

local Util = {}
WFC.Util = Util

-- Shared read-only empty table: return this instead of allocating `{}` on hot paths.
Util.EMPTY = setmetatable({}, {
    __newindex = function() error("WFC.Util.EMPTY is read-only", 2) end,
    __metatable = false,
})

--- QuestieDB returns 0 for "no value" in numeric fields; turn that into nil.
function Util.Nz(v)
    if v == 0 then return nil end
    return v
end

--- Bit test that stays exact above 32 bits (Skyborne race bits are 2^32 / 2^33).
--- `bitValue` must be a power of two.
function Util.HasBit(mask, bitValue)
    return mask % (bitValue * 2) >= bitValue
end

--- True when two masks share any set bit. Arithmetic, so it is safe above 32 bits.
function Util.MaskIntersects(a, b)
    local bitValue = 1
    while bitValue <= a and bitValue <= b do
        if a % (bitValue * 2) >= bitValue and b % (bitValue * 2) >= bitValue then
            return true
        end
        bitValue = bitValue * 2
    end
    return false
end

--- Binary search in a flat, sorted list of inclusive ranges: {a1, b1, a2, b2, ...}.
function Util.InRanges(ranges, id)
    local lo, hi = 1, #ranges / 2
    while lo <= hi do
        local mid = floor((lo + hi) / 2)
        local a, b = ranges[mid * 2 - 1], ranges[mid * 2]
        if id < a then
            hi = mid - 1
        elseif id > b then
            lo = mid + 1
        else
            return true
        end
    end
    return false
end

function Util.ToSet(list)
    local set = {}
    if list then
        for i = 1, #list do set[list[i]] = true end
    end
    return set
end

function Util.Count(t)
    local n = 0
    if t then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

--- Appends `value` to `t[key]`, creating the list on first use. Used by index builders.
function Util.Push(t, key, value)
    local list = t[key]
    if list then
        list[#list + 1] = value
    else
        t[key] = { value }
    end
end

function Util.CopyDeep(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = Util.CopyDeep(v) end
    return dst
end

--- Cache whose values the GC may collect; for large per-entity data such as spawns.
function Util.WeakCache()
    return setmetatable({}, { __mode = "v" })
end

function Util.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
