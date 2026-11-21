local _, ns = ...

-- Theme tokens (design.md §7.2/§7.3). PURE data and colour maths, no WoW API.
-- One table per theme; ornaments are white-on-transparent art tinted with `accent`.

local Themes = {}
ns.Themes = Themes

local HORDE_ACCENT, ALLIANCE_ACCENT = "DA4450", "1E90FF"
local TEXT, MUTED = "EEEEEE", "A8A8A8"

local function theme(name, faction, bg, surface, accent, ornament, band)
    return {
        name = name, faction = faction,
        bg = bg, surface = surface, border = nil, accent = accent,
        text = TEXT, textMuted = MUTED,
        -- 6.0: one engraved serif for titles (sits with Forever's Friz Quadrata), and body text
        -- stays Blizzard's own font so windows read like the rest of the game.
        headerFont = "MarcellusSC-Regular",
        bodyFont = nil,
        ornament = ornament and { set = ornament, corners = true, titleBand = band ~= false, alpha = 0.55 } or nil,
    }
end

Themes.list = {
    -- Horde
    Orc        = theme("Orc", "Horde", "17161A", "221F22", "B3261E", "orc"),
    Scourge    = theme("Forsaken", "Horde", "15171A", "1E2124", "7DBF5A", "undead"),
    Tauren     = theme("Tauren", "Horde", "1C1814", "27211B", "D08A3A", "tauren"),
    Troll      = theme("Troll", "Horde", "121A19", "1A2423", "2FB3A2", "troll"),
    SkyborneH  = theme("Skyborne (Horde)", "Horde", "141820", "1D2330", "5FB4E6", "skyhorde"),
    Horde      = theme("Horde", "Horde", "16181C", "1F2228", HORDE_ACCENT, "notch", false),
    -- Alliance
    Human      = theme("Human", "Alliance", "141A24", "1C2431", "D4AF37", "human"),
    Dwarf      = theme("Dwarf", "Alliance", "1A1917", "24221F", "C27C3A", "dwarf"),
    NightElf   = theme("Night Elf", "Alliance", "15142A", "1E1C33", "9C8CF0", "nightelf"),
    Gnome      = theme("Gnome", "Alliance", "16191B", "1F2427", "3FD0C9", "gnome"),
    SkyborneA  = theme("Skyborne (Alliance)", "Alliance", "161A22", "1F2530", "E8D27A", "skyalliance"),
    Alliance   = theme("Alliance", "Alliance", "161A22", "1F2530", ALLIANCE_ACCENT, "notch", false),
    -- Neither
    Neutral    = theme("Neutral", nil, "16181C", "1F2228", "4DD9FF", nil),
}
local PARCHMENT_BASE = {
    -- Horde
    Orc        = { bg = "ECE2D0", border = "3A2E22", header = "5C1D06", text = "1A1209", muted = "453220" },
    Scourge    = { bg = "E4E7DF", border = "2E3628", header = "2D4A18", text = "141A10", muted = "384232" },
    Tauren     = { bg = "EDE2CB", border = "3E2E1C", header = "6B3008", text = "1A1107", muted = "4A321A" },
    Troll      = { bg = "E0ECE7", border = "223834", header = "15544B", text = "0D1C19", muted = "2E4844" },
    SkyborneH  = { bg = "E2E8F0", border = "263445", header = "1A4D6B", text = "101821", muted = "324558" },
    Horde      = { bg = "ECE3D2", border = "3C2A24", header = "66181C", text = "1A100E", muted = "48302A" },
    -- Alliance
    Human      = { bg = "EFE8D6", border = "3A3222", header = "61400A", text = "1A150A", muted = "453C24" },
    Dwarf      = { bg = "EAE2D4", border = "3A3026", header = "5E3210", text = "1A120A", muted = "453525" },
    NightElf   = { bg = "E7E4F2", border = "2C2840", header = "3C3068", text = "13101C", muted = "39334F" },
    Gnome      = { bg = "E3ECEC", border = "233838", header = "145451", text = "0E1B1B", muted = "2A4646" },
    SkyborneA  = { bg = "EFEBD8", border = "3C3824", header = "5C4F18", text = "1A170B", muted = "474026" },
    Alliance   = { bg = "E5EAF2", border = "253245", header = "16456E", text = "0F1722", muted = "2F3E52" },
    -- Neutral
    Neutral    = { bg = "ECE5D8", border = "34322E", header = "1D5266", text = "121415", muted = "363C40" },
}

for key, t in pairs(Themes.list) do
    t.key = key
    t.border = "4D5460"
    t.buttonSurface = Themes.Lighten and Themes.Lighten(t.surface, 0.16) or t.surface
    t.buttonBorder = "6B7280"
    t.accentSoft = t.accent .. "33"
    t.titleBand = { from = nil, to = t.bg } -- `from` is the accent darkened, filled in below
    t.parchment = PARCHMENT_BASE[key] or PARCHMENT_BASE.Neutral
end

Themes.ORDER = { "Orc", "Scourge", "Tauren", "Troll", "SkyborneH", "Horde",
    "Human", "Dwarf", "NightElf", "Gnome", "SkyborneA", "Alliance", "Neutral" }

-- Skyborne (Forever's new race) by race ID; the race file token isn't known before launch.
local SKYBORNE = { [95] = true, [96] = true }

--- Theme key for a character: race theme, then faction theme, then neutral (design §7.1).
function Themes.Pick(raceFile, faction, raceId)
    if SKYBORNE[raceId] or (raceFile and raceFile:find("Skyborne")) then
        return faction == "Alliance" and "SkyborneA" or faction == "Horde" and "SkyborneH" or "Neutral"
    end
    if raceFile and Themes.list[raceFile] and Themes.list[raceFile].faction == faction then return raceFile end
    if faction == "Horde" or faction == "Alliance" then return faction end
    return "Neutral"
end

---------------------------------------------------------------------------
-- Colour maths
---------------------------------------------------------------------------
--- "RRGGBB" or "RRGGBBAA" -> r, g, b, a (0-1).
function Themes.RGB(hex)
    local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    local a = #hex >= 8 and tonumber(hex:sub(7, 8), 16) / 255 or 1
    return r / 255, g / 255, b / 255, a
end

local function linear(c)
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

function Themes.Luminance(hex)
    local r, g, b = Themes.RGB(hex)
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

--- WCAG contrast ratio between two colours (1-21).
function Themes.Contrast(a, b)
    local la, lb = Themes.Luminance(a), Themes.Luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

--- Lightens a colour toward white by `amount` (0-1). Returns hex.
function Themes.Lighten(hex, amount)
    local r, g, b = Themes.RGB(hex)
    local function l(c) return math.min(1, c + (1 - c) * amount) end
    return ("%02X%02X%02X"):format(math.floor(l(r) * 255 + 0.5), math.floor(l(g) * 255 + 0.5), math.floor(l(b) * 255 + 0.5))
end

--- Darkens a colour toward black by `amount` (0-1). Returns hex.
function Themes.Darken(hex, amount)
    local r, g, b = Themes.RGB(hex)
    local k = 1 - amount
    return ("%02X%02X%02X"):format(math.floor(r * k * 255 + 0.5), math.floor(g * k * 255 + 0.5), math.floor(b * k * 255 + 0.5))
end

for _, t in pairs(Themes.list) do
    t.titleBand.from = Themes.Darken(t.accent, 0.75)
    t.buttonSurface = Themes.Lighten(t.surface, 0.16)
end

return Themes
