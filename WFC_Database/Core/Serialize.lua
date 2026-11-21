local _, ns = ...
local WFC = ns.WFC

-- Compact, safe serializer for plain data (numbers, strings, booleans, nested tables).
-- Used for /wfc export|import and harvest flushes. Decoding never executes code.
--
-- Format:  n<number>;   s<len>:<bytes>   T   F   { key value key value ... }

local Serialize = {}
WFC.Serialize = Serialize

local tostring, tonumber, type, pairs = tostring, tonumber, type, pairs
local sub, find, format = string.sub, string.find, string.format

local function encode(value, out)
    local t = type(value)
    if t == "number" then
        out[#out + 1] = "n" .. (value % 1 == 0 and format("%d", value) or format("%.17g", value)) .. ";"
    elseif t == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif t == "boolean" then
        out[#out + 1] = value and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, v in pairs(value) do
            local kt = type(k)
            if (kt == "number" or kt == "string") and type(v) ~= "function" and type(v) ~= "userdata" then
                encode(k, out)
                encode(v, out)
            end
        end
        out[#out + 1] = "}"
    else
        error("WFC.Serialize: cannot encode " .. t)
    end
end

function Serialize.Encode(value)
    local out = {}
    encode(value, out)
    return table.concat(out)
end

-- Returns value, nextPos  or  nil, errorMessage
local function decode(str, pos, depth)
    if depth > 64 then return nil, "too deep" end
    local c = sub(str, pos, pos)
    if c == "n" then
        local stop = find(str, ";", pos + 1, true)
        if not stop then return nil, "bad number" end
        local n = tonumber(sub(str, pos + 1, stop - 1))
        if not n then return nil, "bad number" end
        return n, stop + 1
    elseif c == "s" then
        local colon = find(str, ":", pos + 1, true)
        local len = colon and tonumber(sub(str, pos + 1, colon - 1))
        if not len or colon + len > #str then return nil, "bad string" end
        return sub(str, colon + 1, colon + len), colon + len + 1
    elseif c == "T" then
        return true, pos + 1
    elseif c == "F" then
        return false, pos + 1
    elseif c == "{" then
        local t = {}
        pos = pos + 1
        while sub(str, pos, pos) ~= "}" do
            if pos > #str then return nil, "unterminated table" end
            local k, v
            k, pos = decode(str, pos, depth + 1)
            if k == nil then return nil, pos end
            v, pos = decode(str, pos, depth + 1)
            if v == nil then return nil, pos end
            t[k] = v
        end
        return t, pos + 1
    end
    return nil, "unexpected '" .. c .. "' at " .. pos
end

--- Returns value or nil, error.
function Serialize.Decode(str)
    if type(str) ~= "string" or str == "" then return nil, "empty" end
    local value, pos = decode(str, 1, 0)
    if value == nil then return nil, pos end
    if pos <= #str then return nil, "trailing data" end
    return value
end
