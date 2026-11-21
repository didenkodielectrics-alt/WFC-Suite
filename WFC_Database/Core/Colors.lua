local _, ns = ...
local WFC = ns.WFC

-- The suite's colour language (design.md §1). The difficulty palette is copied
-- exactly from Questie (QuestieLib.lua) so WFC and Questie read as one UI.

local Compat = WFC.Compat
local floor, format = math.floor, string.format

local Colors = {}
WFC.Colors = Colors

local function color(r, g, b)
    local hex = format("ff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
    return { r = r, g = g, b = b, hex = hex, code = "|c" .. hex }
end

local P = {
    TRIVIAL    = color(0.753, 0.753, 0.753), -- grey   C0C0C0
    EASY       = color(0.251, 0.753, 0.251), -- green  40C040
    FAIR       = color(1, 1, 0),             -- yellow FFFF00
    DIFFICULT  = color(1, 0.502, 0.251),     -- orange FF8040
    IMPOSSIBLE = color(1, 0.102, 0.102),     -- red    FF1A1A
    NEW        = color(0.302, 0.851, 1),     -- cyan   4DD9FF
    HORDE      = color(0.855, 0.267, 0.314), -- DA4450 (Questie)
    ALLIANCE   = color(0.118, 0.565, 1),     -- 1E90FF (Questie)
    TEXT       = color(0.933, 0.933, 0.933), -- EEEEEE
    TEXT_MUTED = color(0.659, 0.659, 0.659), -- A8A8A8
}
Colors.palette = P

-- Enum.RelativeContentDifficulty value -> palette colour
local byDifficulty = {}
if Enum and Enum.RelativeContentDifficulty then
    local E = Enum.RelativeContentDifficulty
    byDifficulty[E.Trivial or -1] = P.TRIVIAL
    byDifficulty[E.Easy or -1] = P.EASY
    byDifficulty[E.Fair or -1] = P.FAIR
    byDifficulty[E.Difficult or -1] = P.DIFFICULT
    byDifficulty[E.Impossible or -1] = P.IMPOSSIBLE
end

--- Level-difference colour (mobs, zones, anything level based).
function Colors.ForLevel(level, playerLevel)
    playerLevel = playerLevel or UnitLevel("player")
    if not level or level <= 0 then return P.FAIR end
    local diff = level - playerLevel
    if diff >= 5 then
        return P.IMPOSSIBLE
    elseif diff >= 3 then
        return P.DIFFICULT
    elseif diff >= -2 then
        return P.FAIR
    elseif -diff <= Compat.GetGreenRange(playerLevel) then
        return P.EASY
    end
    return P.TRIVIAL
end

--- Quest colour: the client's own quest difficulty when available, else the level estimate.
--- (Do not use the generic GetQuestDifficultyColor: its thresholds differ on Forever.)
function Colors.ForQuest(questId, questLevel, playerLevel)
    local difficulty = questId and Compat.GetQuestDifficulty(questId)
    local c = difficulty and byDifficulty[difficulty]
    if c then return c end
    return Colors.ForLevel(questLevel, playerLevel)
end

local bySkill = { orange = P.DIFFICULT, yellow = P.FAIR, green = P.EASY, grey = P.TRIVIAL, gray = P.TRIVIAL }

--- Recipe skill-up colour name ("orange", "yellow", "green", "grey") -> palette colour.
function Colors.ForSkill(name)
    return bySkill[name] or P.TEXT
end

--- Questie's "red to green" objective progress gradient. Returns a |cAARRGGBB code.
function Colors.Progress(have, need)
    if not have or not need or need <= 0 then return P.TEXT.code end
    if have >= need then return "|cff28ff28" end
    local p = have / need
    local r, g, b
    if p <= 0.5 then
        r, g, b = 1, p * 2, 0
    else
        r, g, b = 1.843 - p / 0.593, 1, (p * 2 - 1) * 0.157
    end
    return color(math.min(r, 1), math.min(g, 1), math.min(b, 1)).code
end

--- Colours text with a palette colour. A missing colour (typo, or a plain {r,g,b} table)
--- degrades to uncoloured / computed text instead of erroring, so one bad colour can't
--- blank a whole window.
function Colors.Wrap(text, c)
    if type(c) ~= "table" then return tostring(text) end
    if c.code then return c.code .. tostring(text) .. "|r" end
    if c.r and c.g and c.b then
        return format("|cff%02x%02x%02x%s|r", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5), tostring(text))
    end
    return tostring(text)
end
